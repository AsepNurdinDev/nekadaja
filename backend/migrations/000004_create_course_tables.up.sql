-- Domain 3: Course Management

CREATE TABLE courses (
    id                         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id                 UUID        NOT NULL,
    product_type               VARCHAR(30) NOT NULL DEFAULT 'course',
    level                      VARCHAR(30),
    language                   VARCHAR(10) NOT NULL DEFAULT 'id',
    estimated_duration_minutes INTEGER,
    requirements               JSONB       NOT NULL DEFAULT '[]'::jsonb,
    learning_outcomes          JSONB       NOT NULL DEFAULT '[]'::jsonb,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT courses_product_id_key UNIQUE (product_id),
    CONSTRAINT courses_product_type_chk CHECK (product_type = 'course'),
    -- Hanya produk bertipe course yang dapat memiliki detail course.
    CONSTRAINT courses_product_fk FOREIGN KEY (product_id, product_type)
        REFERENCES products (id, product_type) ON DELETE CASCADE,
    CONSTRAINT courses_duration_chk CHECK (estimated_duration_minutes IS NULL OR estimated_duration_minutes >= 0),
    CONSTRAINT courses_json_arrays_chk CHECK (
        jsonb_typeof(requirements) = 'array' AND jsonb_typeof(learning_outcomes) = 'array'
    )
);

CREATE TABLE course_sections (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id   UUID         NOT NULL REFERENCES courses (id) ON DELETE CASCADE,
    title       VARCHAR(255) NOT NULL,
    description TEXT,
    position    INTEGER      NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT course_sections_position_chk CHECK (position >= 0),
    CONSTRAINT course_sections_course_position_key UNIQUE (course_id, position)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE lessons (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    section_id       UUID         NOT NULL REFERENCES course_sections (id) ON DELETE CASCADE,
    title            VARCHAR(255) NOT NULL,
    slug             VARCHAR(255) NOT NULL,
    content          TEXT,
    lesson_type      VARCHAR(30)  NOT NULL,
    video_url        TEXT,
    duration_seconds INTEGER,
    is_preview       BOOLEAN      NOT NULL DEFAULT FALSE,
    position         INTEGER      NOT NULL,
    status           VARCHAR(30)  NOT NULL DEFAULT 'draft',
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT lessons_section_slug_key UNIQUE (section_id, slug),
    CONSTRAINT lessons_section_position_key UNIQUE (section_id, position)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT lessons_position_chk CHECK (position >= 0),
    CONSTRAINT lessons_type_chk CHECK (lesson_type IN ('text', 'video', 'mixed')),
    CONSTRAINT lessons_status_chk CHECK (status IN ('draft', 'published')),
    CONSTRAINT lessons_duration_chk CHECK (duration_seconds IS NULL OR duration_seconds >= 0),
    CONSTRAINT lessons_video_url_chk CHECK (
        status <> 'published' OR lesson_type = 'text' OR video_url IS NOT NULL
    )
);

CREATE TRIGGER trg_courses_set_updated_at
    BEFORE UPDATE ON courses FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_course_sections_set_updated_at
    BEFORE UPDATE ON course_sections FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_lessons_set_updated_at
    BEFORE UPDATE ON lessons FOR EACH ROW EXECUTE FUNCTION set_updated_at();
