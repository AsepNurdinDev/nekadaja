-- Data awal role. Idempotent.
INSERT INTO roles (name, description) VALUES
    ('admin',   'Mengelola seluruh sistem'),
    ('author',  'Mengelola course dan source code'),
    ('student', 'Membeli dan mengakses produk')
ON CONFLICT (name) DO NOTHING;
