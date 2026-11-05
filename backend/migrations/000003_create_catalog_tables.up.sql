-- Domain 2: Product Catalog

CREATE TABLE products (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    product_type   VARCHAR(30)  NOT NULL,
    title          VARCHAR(255) NOT NULL,
    slug           VARCHAR(255) NOT NULL,
    description    TEXT,
    thumbnail_url  TEXT,
    pricing_type   VARCHAR(30)  NOT NULL,
    price_amount   BIGINT       NOT NULL DEFAULT 0,
    minimum_amount BIGINT       NOT NULL DEFAULT 0,
    currency       CHAR(3)      NOT NULL DEFAULT 'IDR',
    status         VARCHAR(30)  NOT NULL DEFAULT 'draft',
    created_by     UUID         NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    published_at   TIMESTAMPTZ,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT products_slug_key UNIQUE (slug),
    -- Dipakai foreign key komposit dari courses dan source_code_details.
    CONSTRAINT products_id_product_type_key UNIQUE (id, product_type),
    CONSTRAINT products_product_type_chk CHECK (product_type IN ('course', 'source_code')),
    CONSTRAINT products_pricing_type_chk CHECK (pricing_type IN ('free', 'fixed', 'pwyw')),
    CONSTRAINT products_status_chk CHECK (status IN ('draft', 'published', 'archived')),
    CONSTRAINT products_amounts_non_negative_chk CHECK (price_amount >= 0 AND minimum_amount >= 0),
    CONSTRAINT products_pricing_rules_chk CHECK (
        (pricing_type = 'free'  AND price_amount = 0 AND minimum_amount = 0)
        OR (pricing_type = 'fixed' AND price_amount > 0 AND minimum_amount = 0)
        OR (pricing_type = 'pwyw'  AND minimum_amount > 0
            AND (price_amount = 0 OR price_amount >= minimum_amount))
    ),
    CONSTRAINT products_published_at_chk CHECK (status <> 'published' OR published_at IS NOT NULL),
    CONSTRAINT products_currency_chk CHECK (currency = upper(currency))
);
CREATE INDEX idx_products_type_status ON products (product_type, status);
CREATE INDEX idx_products_created_by ON products (created_by);

CREATE TABLE categories (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(100) NOT NULL,
    slug        VARCHAR(120) NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT categories_slug_key UNIQUE (slug)
);

CREATE TABLE product_categories (
    product_id  UUID NOT NULL REFERENCES products (id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES categories (id) ON DELETE CASCADE,
    PRIMARY KEY (product_id, category_id)
);
CREATE INDEX idx_product_categories_category_id ON product_categories (category_id);

CREATE TRIGGER trg_products_set_updated_at
    BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_categories_set_updated_at
    BEFORE UPDATE ON categories FOR EACH ROW EXECUTE FUNCTION set_updated_at();
