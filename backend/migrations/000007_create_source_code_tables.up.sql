-- Domain 6: Source Code Management

CREATE TABLE source_code_details (
    id                   UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id           UUID         NOT NULL,
    product_type         VARCHAR(30)  NOT NULL DEFAULT 'source_code',
    programming_language VARCHAR(100),
    framework            VARCHAR(100),
    documentation        TEXT,
    installation_guide   TEXT,
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT source_code_details_product_id_key UNIQUE (product_id),
    CONSTRAINT source_code_details_product_type_chk CHECK (product_type = 'source_code'),
    -- Hanya produk bertipe source_code yang dapat memiliki detail source code.
    CONSTRAINT source_code_details_product_fk FOREIGN KEY (product_id, product_type)
        REFERENCES products (id, product_type) ON DELETE CASCADE
);

CREATE TABLE source_code_versions (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    source_code_id UUID         NOT NULL REFERENCES source_code_details (id) ON DELETE CASCADE,
    version        VARCHAR(50)  NOT NULL,
    changelog      TEXT,
    release_notes  TEXT,
    is_latest      BOOLEAN      NOT NULL DEFAULT FALSE,
    released_at    TIMESTAMPTZ  NOT NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT source_code_versions_source_version_key UNIQUE (source_code_id, version)
);
-- Hanya satu versi latest per source code. Saat berpindah versi, nonaktifkan versi lama
-- terlebih dahulu dalam transaksi yang sama.
CREATE UNIQUE INDEX uq_source_code_versions_latest
    ON source_code_versions (source_code_id) WHERE is_latest;

CREATE TABLE product_files (
    id                     UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id             UUID         NOT NULL REFERENCES products (id) ON DELETE CASCADE,
    source_code_version_id UUID         REFERENCES source_code_versions (id) ON DELETE CASCADE,
    file_name              VARCHAR(255) NOT NULL,
    storage_key            TEXT         NOT NULL,
    mime_type              VARCHAR(150) NOT NULL,
    file_size              BIGINT       NOT NULL,
    checksum               VARCHAR(128),
    is_primary             BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT product_files_storage_key_key UNIQUE (storage_key),
    CONSTRAINT product_files_size_chk CHECK (file_size >= 0)
);
CREATE INDEX idx_product_files_product_id ON product_files (product_id);
CREATE INDEX idx_product_files_version_id ON product_files (source_code_version_id);
CREATE UNIQUE INDEX uq_product_files_primary_per_version
    ON product_files (source_code_version_id)
    WHERE is_primary AND source_code_version_id IS NOT NULL;
CREATE UNIQUE INDEX uq_product_files_primary_per_course
    ON product_files (product_id)
    WHERE is_primary AND source_code_version_id IS NULL;

CREATE TRIGGER trg_source_code_details_set_updated_at
    BEFORE UPDATE ON source_code_details FOR EACH ROW EXECUTE FUNCTION set_updated_at();
