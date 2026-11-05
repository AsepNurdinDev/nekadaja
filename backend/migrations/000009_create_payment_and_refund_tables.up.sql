-- Domain 8: Payment & Refund Management

CREATE TABLE payments (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id           UUID         NOT NULL,
    provider           VARCHAR(50)  NOT NULL,
    provider_reference VARCHAR(255),
    payment_method     VARCHAR(50),
    amount             BIGINT       NOT NULL,
    currency           CHAR(3)      NOT NULL DEFAULT 'IDR',
    status             VARCHAR(30)  NOT NULL DEFAULT 'pending',
    paid_at            TIMESTAMPTZ,
    expired_at         TIMESTAMPTZ,
    raw_response       JSONB,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- Target foreign key komposit.
    CONSTRAINT payments_id_order_id_key UNIQUE (id, order_id),   -- refunds
    CONSTRAINT payments_id_provider_key UNIQUE (id, provider),   -- payment_events
    -- Nominal dan mata uang payment harus sama dengan total order. Order gratis (total 0)
    -- otomatis tidak dapat memiliki payment karena amount > 0. Total order tidak dapat
    -- diubah selama masih ada payment yang merujuknya.
    CONSTRAINT payments_order_amount_fk FOREIGN KEY (order_id, amount, currency)
        REFERENCES orders (id, total_amount, currency) ON DELETE RESTRICT,
    CONSTRAINT payments_status_chk CHECK (status IN
        ('pending', 'paid', 'failed', 'expired', 'cancelled', 'refunded', 'partially_refunded')),
    CONSTRAINT payments_amount_chk CHECK (amount > 0),
    CONSTRAINT payments_paid_at_chk CHECK
        (status NOT IN ('paid', 'partially_refunded', 'refunded') OR paid_at IS NOT NULL),
    CONSTRAINT payments_currency_chk CHECK (currency = upper(currency))
);
CREATE UNIQUE INDEX uq_payments_provider_reference
    ON payments (provider, provider_reference) WHERE provider_reference IS NOT NULL;
-- Maksimal satu payment "aktif" per order: pending atau sudah berhasil. Percobaan baru (retry)
-- hanya dapat dibuat setelah payment sebelumnya failed, expired, atau cancelled. Ini sekaligus
-- menjamin total pembayaran berhasil tidak melebihi tagihan.
CREATE UNIQUE INDEX uq_payments_one_live_per_order
    ON payments (order_id) WHERE status IN ('pending', 'paid', 'partially_refunded', 'refunded');
CREATE INDEX idx_payments_order_status ON payments (order_id, status);

CREATE TABLE payment_events (
    id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id        UUID         NOT NULL,
    provider          VARCHAR(50)  NOT NULL,
    provider_event_id VARCHAR(255),
    event_type        VARCHAR(100) NOT NULL,
    payload           JSONB        NOT NULL,
    processed_at      TIMESTAMPTZ,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- provider event harus sama dengan provider payment, agar keunikan event ID per provider valid.
    CONSTRAINT payment_events_payment_provider_fk FOREIGN KEY (payment_id, provider)
        REFERENCES payments (id, provider) ON DELETE RESTRICT
);
-- Idempotensi webhook: event ID unik per provider.
CREATE UNIQUE INDEX uq_payment_events_provider_event
    ON payment_events (provider, provider_event_id) WHERE provider_event_id IS NOT NULL;
CREATE INDEX idx_payment_events_payment_id ON payment_events (payment_id);

CREATE TABLE refunds (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id         UUID         NOT NULL,
    order_id           UUID         NOT NULL,
    user_id            UUID         NOT NULL,
    refund_number      VARCHAR(100) NOT NULL,
    amount             BIGINT       NOT NULL,
    reason             TEXT,
    status             VARCHAR(30)  NOT NULL DEFAULT 'requested',
    provider_reference VARCHAR(255),
    requested_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    processed_at       TIMESTAMPTZ,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT refunds_refund_number_key UNIQUE (refund_number),
    CONSTRAINT refunds_status_chk CHECK (status IN
        ('requested', 'approved', 'rejected', 'processing', 'succeeded', 'failed')),
    CONSTRAINT refunds_amount_chk CHECK (amount > 0),
    CONSTRAINT refunds_payment_order_fk FOREIGN KEY (payment_id, order_id)
        REFERENCES payments (id, order_id) ON DELETE RESTRICT,
    CONSTRAINT refunds_order_user_fk FOREIGN KEY (order_id, user_id)
        REFERENCES orders (id, user_id) ON DELETE RESTRICT
);
CREATE INDEX idx_refunds_payment_id ON refunds (payment_id);
CREATE INDEX idx_refunds_order_id ON refunds (order_id);

CREATE TABLE refund_events (
    id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    refund_id         UUID         NOT NULL REFERENCES refunds (id) ON DELETE RESTRICT,
    provider_event_id VARCHAR(255),
    event_type        VARCHAR(100) NOT NULL,
    payload           JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_refund_events_provider_event
    ON refund_events (refund_id, provider_event_id) WHERE provider_event_id IS NOT NULL;
CREATE INDEX idx_refund_events_refund_id ON refund_events (refund_id);

-- Penjaga refund: total refund tidak melebihi nominal payment, aman terhadap refund bersamaan.
--
-- Mekanisme: baris payment dikunci (FOR NO KEY UPDATE) sebelum total refund dihitung, sehingga
-- refund bersamaan untuk payment yang sama diproses bergantian. Kunci ini tidak memblokir insert
-- anak lain (payment_events dll). Refund berstatus requested, approved, processing, dan succeeded
-- dihitung sebagai "terpakai"; rejected dan failed membebaskan kuota.
-- Syarat: transaksi berjalan pada READ COMMITTED (default PostgreSQL dan pgx) atau SERIALIZABLE.
-- Fungsi ini TIDAK mengubah entitlement: pencabutan akses dilakukan terpisah setelah refund succeeded.
CREATE OR REPLACE FUNCTION refunds_enforce_limits()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_active          CONSTANT TEXT[] := ARRAY['requested', 'approved', 'processing', 'succeeded'];
    v_payment_amount  BIGINT;
    v_payment_status  VARCHAR(30);
    v_reserved        NUMERIC;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.payment_id IS DISTINCT FROM OLD.payment_id
           OR NEW.order_id IS DISTINCT FROM OLD.order_id
           OR NEW.user_id IS DISTINCT FROM OLD.user_id THEN
            RAISE EXCEPTION 'payment_id, order_id, dan user_id refund tidak boleh diubah'
                USING ERRCODE = 'check_violation',
                      CONSTRAINT = 'refunds_identity_immutable',
                      TABLE = 'refunds';
        END IF;

        -- Kuota hanya perlu diperiksa ulang jika refund menjadi aktif atau nominalnya naik.
        IF NOT (NEW.status = ANY (v_active))
           OR (OLD.status = ANY (v_active) AND NEW.amount <= OLD.amount) THEN
            RETURN NEW;
        END IF;
    END IF;

    SELECT p.amount, p.status
      INTO v_payment_amount, v_payment_status
      FROM payments p
     WHERE p.id = NEW.payment_id
       FOR NO KEY UPDATE;

    IF NOT FOUND THEN
        RETURN NEW;  -- biarkan foreign key yang menolak payment yang tidak ada
    END IF;

    IF TG_OP = 'INSERT'
       AND v_payment_status NOT IN ('paid', 'partially_refunded', 'refunded') THEN
        RAISE EXCEPTION 'Refund hanya dapat diajukan untuk payment yang sudah berhasil (status payment: %)',
                v_payment_status
            USING ERRCODE = 'check_violation',
                  CONSTRAINT = 'refunds_payment_must_be_successful',
                  TABLE = 'refunds';
    END IF;

    IF NEW.status = ANY (v_active) THEN
        SELECT COALESCE(SUM(r.amount), 0)
          INTO v_reserved
          FROM refunds r
         WHERE r.payment_id = NEW.payment_id
           AND r.id <> NEW.id
           AND r.status = ANY (v_active);

        IF v_reserved + NEW.amount > v_payment_amount THEN
            RAISE EXCEPTION 'Total refund aktif (%) melebihi nominal payment (%)',
                    v_reserved + NEW.amount, v_payment_amount
                USING ERRCODE = 'check_violation',
                      CONSTRAINT = 'refunds_total_within_payment_chk',
                      TABLE = 'refunds';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_refunds_enforce_limits
    BEFORE INSERT OR UPDATE OF payment_id, order_id, user_id, amount, status ON refunds
    FOR EACH ROW EXECUTE FUNCTION refunds_enforce_limits();

CREATE TRIGGER trg_payments_set_updated_at
    BEFORE UPDATE ON payments FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_refunds_set_updated_at
    BEFORE UPDATE ON refunds FOR EACH ROW EXECUTE FUNCTION set_updated_at();
