-- Domain 7: Order Management
--
-- Integritas yang dijaga langsung oleh database (tanpa trigger) melalui foreign key komposit:
--   * order_items.product_type  = products.product_type         (snapshot tipe produk valid)
--   * order_items.user_id       = orders.user_id                 (pemilik order, dipakai entitlements)
--   * order_items.subtotal      = orders.subtotal_amount         (item dan order konsisten)
--   * payments.amount/currency  = orders.total_amount/currency   (lihat 000009)

CREATE TABLE orders (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    order_number    VARCHAR(50) NOT NULL,
    user_id         UUID        NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    subtotal_amount BIGINT      NOT NULL,
    discount_amount BIGINT      NOT NULL DEFAULT 0,
    total_amount    BIGINT      NOT NULL,
    currency        CHAR(3)     NOT NULL DEFAULT 'IDR',
    status          VARCHAR(30) NOT NULL DEFAULT 'pending_payment',
    paid_at         TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT orders_order_number_key UNIQUE (order_number),
    -- Target foreign key komposit. Kolom yang dirujuk tidak dapat diubah selama masih ada
    -- baris yang merujuknya (perilaku NO ACTION), sehingga snapshot tetap konsisten.
    CONSTRAINT orders_id_user_id_key UNIQUE (id, user_id),                          -- order_items, refunds
    CONSTRAINT orders_id_subtotal_amount_key UNIQUE (id, subtotal_amount),          -- order_items
    CONSTRAINT orders_id_total_currency_key UNIQUE (id, total_amount, currency),    -- payments
    CONSTRAINT orders_status_chk CHECK (status IN
        ('pending_payment', 'paid', 'cancelled', 'expired', 'partially_refunded', 'refunded')),
    CONSTRAINT orders_amounts_non_negative_chk CHECK
        (subtotal_amount >= 0 AND discount_amount >= 0 AND total_amount >= 0),
    CONSTRAINT orders_discount_chk CHECK (discount_amount <= subtotal_amount),
    CONSTRAINT orders_total_chk CHECK (total_amount = subtotal_amount - discount_amount),
    CONSTRAINT orders_paid_at_chk CHECK
        (status NOT IN ('paid', 'partially_refunded', 'refunded') OR paid_at IS NOT NULL),
    -- Order gratis (total 0) tidak memerlukan payment: dibuat langsung berstatus paid.
    -- Order bernilai 0 tidak boleh menunggu pembayaran atau berstatus refund karena
    -- payment (yang harus bernilai > 0) tidak mungkin ada untuknya.
    CONSTRAINT orders_free_order_status_chk CHECK
        (total_amount > 0 OR status IN ('paid', 'cancelled', 'expired')),
    CONSTRAINT orders_currency_chk CHECK (currency = upper(currency))
);
CREATE INDEX idx_orders_user_created ON orders (user_id, created_at);
CREATE INDEX idx_orders_status_expires ON orders (status, expires_at);

CREATE TABLE order_items (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id        UUID         NOT NULL,
    -- Salinan pemilik order (denormalisasi terkontrol, dijaga foreign key komposit di bawah).
    user_id         UUID         NOT NULL,
    product_id      UUID         NOT NULL,
    product_title   VARCHAR(255) NOT NULL,
    product_type    VARCHAR(30)  NOT NULL,
    unit_price      BIGINT       NOT NULL,
    quantity        INTEGER      NOT NULL DEFAULT 1,
    subtotal_amount BIGINT       NOT NULL,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- Satu order hanya memiliki satu item.
    CONSTRAINT order_items_order_id_key UNIQUE (order_id),
    -- Dipakai foreign key komposit dari entitlements (user dan produk harus sama dengan order item).
    CONSTRAINT order_items_id_user_product_key UNIQUE (id, user_id, product_id),
    CONSTRAINT order_items_order_owner_fk FOREIGN KEY (order_id, user_id)
        REFERENCES orders (id, user_id) ON DELETE RESTRICT,
    CONSTRAINT order_items_order_subtotal_fk FOREIGN KEY (order_id, subtotal_amount)
        REFERENCES orders (id, subtotal_amount) ON DELETE RESTRICT,
    -- Snapshot product_type harus sama dengan tipe produk sebenarnya. Tipe produk juga tidak
    -- dapat diubah setelah produk pernah dipesan.
    CONSTRAINT order_items_product_fk FOREIGN KEY (product_id, product_type)
        REFERENCES products (id, product_type) ON DELETE RESTRICT,
    CONSTRAINT order_items_product_type_chk CHECK (product_type IN ('course', 'source_code')),
    CONSTRAINT order_items_unit_price_chk CHECK (unit_price >= 0),
    CONSTRAINT order_items_quantity_chk CHECK (quantity = 1),
    CONSTRAINT order_items_subtotal_chk CHECK (subtotal_amount = unit_price * quantity)
);
CREATE INDEX idx_order_items_product_id ON order_items (product_id);
CREATE INDEX idx_order_items_user_product ON order_items (user_id, product_id);

CREATE TRIGGER trg_orders_set_updated_at
    BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION set_updated_at();
