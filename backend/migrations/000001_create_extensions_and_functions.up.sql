-- Nekadaja: persyaratan versi PostgreSQL dan fungsi bersama.
-- gen_random_uuid() bawaan PostgreSQL 13+, sehingga tidak membutuhkan extension pgcrypto.

DO $$
BEGIN
    IF current_setting('server_version_num')::int < 130000 THEN
        RAISE EXCEPTION 'PostgreSQL 13 atau lebih baru dibutuhkan (gen_random_uuid bawaan)';
    END IF;
END
$$;

-- Trigger function untuk memperbarui kolom updated_at.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;
