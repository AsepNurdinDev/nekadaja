-- Domain 9: Entitlement & Learning Progress

CREATE TABLE entitlements (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID        NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    product_id        UUID        NOT NULL,
    order_item_id     UUID        NOT NULL,
    granted_at        TIMESTAMPTZ NOT NULL,
    revoked_at        TIMESTAMPTZ,
    revoked_reason    TEXT,
    -- Diisi hanya jika pencabutan berasal dari refund; refund tersebut harus berstatus succeeded
    -- (diperiksa trigger di bawah). NULL pada pencabutan lain, misalnya kebijakan administratif.
    revoked_refund_id UUID        REFERENCES refunds (id) ON DELETE RESTRICT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT entitlements_order_item_id_key UNIQUE (order_item_id),
    -- Pemilik dan produk entitlement harus sama dengan pemilik order dan produk pada order item.
    CONSTRAINT entitlements_order_item_fk FOREIGN KEY (order_item_id, user_id, product_id)
        REFERENCES order_items (id, user_id, product_id) ON DELETE RESTRICT,
    CONSTRAINT entitlements_revoked_reason_chk CHECK (revoked_at IS NOT NULL OR revoked_reason IS NULL),
    CONSTRAINT entitlements_revoked_refund_chk CHECK (revoked_at IS NOT NULL OR revoked_refund_id IS NULL)
);
-- Satu entitlement aktif per kombinasi user dan produk. Hak akses permanen: tidak ada kolom
-- kedaluwarsa, akses hanya berakhir jika revoked_at terisi.
CREATE UNIQUE INDEX uq_entitlements_active_user_product
    ON entitlements (user_id, product_id) WHERE revoked_at IS NULL;
CREATE INDEX idx_entitlements_product_id ON entitlements (product_id);
CREATE INDEX idx_entitlements_revoked_refund_id
    ON entitlements (revoked_refund_id) WHERE revoked_refund_id IS NOT NULL;

-- Penjaga entitlement:
--   1. Akses hanya diberikan untuk order berstatus paid (termasuk order gratis).
--   2. user_id, product_id, dan order_item_id tidak boleh diubah setelah akses dibuat.
--   3. Pencabutan karena refund (revoked_refund_id terisi) hanya sah jika refund tersebut
--      berstatus succeeded dan milik order serta user yang sama. Refund yang masih requested,
--      approved, atau processing tidak dapat dijadikan dasar pencabutan.
-- Fungsi ini tidak mencabut akses secara otomatis; kebijakan refund (penuh/sebagian) diputuskan
-- bisnis dan dijalankan aplikasi dalam transaksi yang sama dengan penandaan refund succeeded.
CREATE OR REPLACE FUNCTION entitlements_enforce_rules()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_status  VARCHAR(30);
    v_item_order_id UUID;
    v_refund_status VARCHAR(30);
    v_refund_user   UUID;
    v_refund_order  UUID;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT o.status
          INTO v_order_status
          FROM order_items oi
          JOIN orders o ON o.id = oi.order_id
         WHERE oi.id = NEW.order_item_id;

        IF FOUND AND v_order_status <> 'paid' THEN
            RAISE EXCEPTION 'Entitlement hanya dapat diberikan untuk order berstatus paid (status order: %)',
                    v_order_status
                USING ERRCODE = 'check_violation',
                      CONSTRAINT = 'entitlements_order_must_be_paid',
                      TABLE = 'entitlements';
        END IF;
    ELSE
        IF NEW.user_id IS DISTINCT FROM OLD.user_id
           OR NEW.product_id IS DISTINCT FROM OLD.product_id
           OR NEW.order_item_id IS DISTINCT FROM OLD.order_item_id THEN
            RAISE EXCEPTION 'user_id, product_id, dan order_item_id entitlement tidak boleh diubah'
                USING ERRCODE = 'check_violation',
                      CONSTRAINT = 'entitlements_identity_immutable',
                      TABLE = 'entitlements';
        END IF;
    END IF;

    IF NEW.revoked_refund_id IS NOT NULL
       AND (TG_OP = 'INSERT' OR NEW.revoked_refund_id IS DISTINCT FROM OLD.revoked_refund_id) THEN
        SELECT r.status, r.user_id, r.order_id
          INTO v_refund_status, v_refund_user, v_refund_order
          FROM refunds r
         WHERE r.id = NEW.revoked_refund_id
           FOR SHARE;

        SELECT oi.order_id
          INTO v_item_order_id
          FROM order_items oi
         WHERE oi.id = NEW.order_item_id;

        IF v_refund_status IS DISTINCT FROM 'succeeded'
           OR v_refund_user IS DISTINCT FROM NEW.user_id
           OR v_refund_order IS DISTINCT FROM v_item_order_id THEN
            RAISE EXCEPTION 'Pencabutan karena refund membutuhkan refund berstatus succeeded milik order yang sama (status refund: %)',
                    COALESCE(v_refund_status, 'tidak ditemukan')
                USING ERRCODE = 'check_violation',
                      CONSTRAINT = 'entitlements_revoke_requires_succeeded_refund',
                      TABLE = 'entitlements';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_entitlements_enforce_rules
    BEFORE INSERT OR UPDATE OF user_id, product_id, order_item_id, revoked_at, revoked_refund_id ON entitlements
    FOR EACH ROW EXECUTE FUNCTION entitlements_enforce_rules();

CREATE TABLE lesson_progress (
    id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id               UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    lesson_id             UUID        NOT NULL REFERENCES lessons (id) ON DELETE CASCADE,
    is_completed          BOOLEAN     NOT NULL DEFAULT FALSE,
    last_position_seconds INTEGER     NOT NULL DEFAULT 0,
    completed_at          TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT lesson_progress_user_lesson_key UNIQUE (user_id, lesson_id),
    CONSTRAINT lesson_progress_position_chk CHECK (last_position_seconds >= 0),
    CONSTRAINT lesson_progress_completed_chk CHECK (NOT is_completed OR completed_at IS NOT NULL)
);
CREATE INDEX idx_lesson_progress_lesson_id ON lesson_progress (lesson_id);

CREATE TABLE course_progress (
    id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID         NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    course_id           UUID         NOT NULL REFERENCES courses (id) ON DELETE CASCADE,
    completed_lessons   INTEGER      NOT NULL DEFAULT 0,
    total_lessons       INTEGER      NOT NULL DEFAULT 0,
    progress_percentage NUMERIC(5,2) NOT NULL DEFAULT 0,
    completed_at        TIMESTAMPTZ,
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT course_progress_user_course_key UNIQUE (user_id, course_id),
    CONSTRAINT course_progress_percentage_chk CHECK (progress_percentage BETWEEN 0 AND 100),
    CONSTRAINT course_progress_counts_chk CHECK
        (completed_lessons >= 0 AND total_lessons >= 0 AND completed_lessons <= total_lessons)
);
CREATE INDEX idx_course_progress_course_id ON course_progress (course_id);

CREATE TRIGGER trg_lesson_progress_set_updated_at
    BEFORE UPDATE ON lesson_progress FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_course_progress_set_updated_at
    BEFORE UPDATE ON course_progress FOR EACH ROW EXECUTE FUNCTION set_updated_at();
