-- Domain 5: Certificate Management

CREATE TABLE certificate_templates (
    id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name              VARCHAR(150) NOT NULL,
    template_file_url TEXT         NOT NULL,
    configuration     JSONB        NOT NULL DEFAULT '{}'::jsonb,
    is_active         BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE certificates (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            UUID         NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    course_id          UUID         NOT NULL REFERENCES courses (id) ON DELETE RESTRICT,
    template_id        UUID         NOT NULL REFERENCES certificate_templates (id) ON DELETE RESTRICT,
    certificate_number VARCHAR(100) NOT NULL,
    file_url           TEXT,
    issued_at          TIMESTAMPTZ  NOT NULL,
    revoked_at         TIMESTAMPTZ,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT certificates_number_key UNIQUE (certificate_number)
);
-- Satu sertifikat aktif per course; sertifikat yang dicabut dapat diterbitkan ulang.
CREATE UNIQUE INDEX uq_certificates_active_user_course
    ON certificates (user_id, course_id) WHERE revoked_at IS NULL;
CREATE INDEX idx_certificates_course_id ON certificates (course_id);

CREATE TRIGGER trg_certificate_templates_set_updated_at
    BEFORE UPDATE ON certificate_templates FOR EACH ROW EXECUTE FUNCTION set_updated_at();
