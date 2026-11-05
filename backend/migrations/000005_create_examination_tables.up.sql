-- Domain 4: Examination Management

CREATE TABLE exams (
    id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id         UUID         NOT NULL REFERENCES courses (id) ON DELETE CASCADE,
    title             VARCHAR(255) NOT NULL,
    description       TEXT,
    duration_minutes  INTEGER      NOT NULL,
    passing_score     NUMERIC(5,2) NOT NULL,
    max_attempts      INTEGER,
    shuffle_questions BOOLEAN      NOT NULL DEFAULT FALSE,
    shuffle_options   BOOLEAN      NOT NULL DEFAULT FALSE,
    status            VARCHAR(30)  NOT NULL DEFAULT 'draft',
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT exams_duration_chk CHECK (duration_minutes > 0),
    CONSTRAINT exams_passing_score_chk CHECK (passing_score BETWEEN 0 AND 100),
    CONSTRAINT exams_max_attempts_chk CHECK (max_attempts IS NULL OR max_attempts > 0),
    CONSTRAINT exams_status_chk CHECK (status IN ('draft', 'published', 'archived'))
);
CREATE INDEX idx_exams_course_id ON exams (course_id);

CREATE TABLE exam_questions (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    exam_id       UUID         NOT NULL REFERENCES exams (id) ON DELETE CASCADE,
    question_text TEXT         NOT NULL,
    question_type VARCHAR(30)  NOT NULL,
    image_url     TEXT,
    points        NUMERIC(8,2) NOT NULL DEFAULT 1,
    explanation   TEXT,
    position      INTEGER      NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT exam_questions_type_chk CHECK (question_type IN ('single_choice', 'multiple_choice', 'true_false')),
    CONSTRAINT exam_questions_points_chk CHECK (points > 0),
    CONSTRAINT exam_questions_exam_position_key UNIQUE (exam_id, position)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE exam_answer_options (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    question_id UUID    NOT NULL REFERENCES exam_questions (id) ON DELETE CASCADE,
    option_text TEXT,
    image_url   TEXT,
    is_correct  BOOLEAN NOT NULL DEFAULT FALSE,
    position    INTEGER NOT NULL,
    CONSTRAINT exam_answer_options_content_chk CHECK (option_text IS NOT NULL OR image_url IS NOT NULL),
    -- Tidak boleh DEFERRABLE karena dirujuk foreign key komposit.
    CONSTRAINT exam_answer_options_question_id_id_key UNIQUE (question_id, id),
    CONSTRAINT exam_answer_options_question_position_key UNIQUE (question_id, position)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE exam_attempts (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    exam_id        UUID         NOT NULL REFERENCES exams (id) ON DELETE RESTRICT,
    user_id        UUID         NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    attempt_number INTEGER      NOT NULL,
    started_at     TIMESTAMPTZ  NOT NULL,
    submitted_at   TIMESTAMPTZ,
    score          NUMERIC(5,2),
    is_passed      BOOLEAN,
    status         VARCHAR(30)  NOT NULL DEFAULT 'in_progress',
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT exam_attempts_exam_user_number_key UNIQUE (exam_id, user_id, attempt_number),
    CONSTRAINT exam_attempts_number_chk CHECK (attempt_number > 0),
    CONSTRAINT exam_attempts_score_chk CHECK (score IS NULL OR score BETWEEN 0 AND 100),
    CONSTRAINT exam_attempts_submitted_chk CHECK (submitted_at IS NULL OR submitted_at >= started_at),
    CONSTRAINT exam_attempts_status_chk CHECK (status IN ('in_progress', 'submitted', 'graded', 'expired'))
);
CREATE INDEX idx_exam_attempts_user_exam ON exam_attempts (user_id, exam_id);
-- Hanya satu attempt berjalan untuk setiap kombinasi exam dan user.
CREATE UNIQUE INDEX uq_exam_attempts_in_progress
    ON exam_attempts (exam_id, user_id) WHERE status = 'in_progress';

CREATE TABLE exam_answers (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    attempt_id         UUID         NOT NULL REFERENCES exam_attempts (id) ON DELETE RESTRICT,
    question_id        UUID         NOT NULL REFERENCES exam_questions (id) ON DELETE RESTRICT,
    selected_option_id UUID,
    is_correct         BOOLEAN,
    earned_points      NUMERIC(8,2) NOT NULL DEFAULT 0,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT exam_answers_attempt_question_key UNIQUE (attempt_id, question_id),
    CONSTRAINT exam_answers_id_question_id_key UNIQUE (id, question_id),
    -- Pilihan harus milik pertanyaan yang dijawab (tidak diperiksa jika NULL).
    CONSTRAINT exam_answers_selected_option_fk FOREIGN KEY (question_id, selected_option_id)
        REFERENCES exam_answer_options (question_id, id) ON DELETE RESTRICT,
    CONSTRAINT exam_answers_earned_points_chk CHECK (earned_points >= 0)
);
CREATE INDEX idx_exam_answers_question_id ON exam_answers (question_id);

CREATE TABLE exam_answer_options_selected (
    answer_id   UUID NOT NULL,
    question_id UUID NOT NULL,
    option_id   UUID NOT NULL,
    PRIMARY KEY (answer_id, option_id),
    CONSTRAINT exam_answer_options_selected_answer_fk FOREIGN KEY (answer_id, question_id)
        REFERENCES exam_answers (id, question_id) ON DELETE RESTRICT,
    CONSTRAINT exam_answer_options_selected_option_fk FOREIGN KEY (question_id, option_id)
        REFERENCES exam_answer_options (question_id, id) ON DELETE RESTRICT
);

CREATE TRIGGER trg_exams_set_updated_at
    BEFORE UPDATE ON exams FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_exam_questions_set_updated_at
    BEFORE UPDATE ON exam_questions FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_exam_answers_set_updated_at
    BEFORE UPDATE ON exam_answers FOR EACH ROW EXECUTE FUNCTION set_updated_at();
