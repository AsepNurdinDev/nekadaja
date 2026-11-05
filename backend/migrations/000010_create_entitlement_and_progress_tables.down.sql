-- Urutan: tabel progres (tanpa dependensi), lalu entitlements (merujuk order_items dan refunds),
-- lalu fungsi trigger. Trigger ikut terhapus bersama tabelnya; fungsi harus dihapus eksplisit.
-- Down ini harus dijalankan sebelum down 000009 dan 000008.
DROP TABLE IF EXISTS course_progress;
DROP TABLE IF EXISTS lesson_progress;
DROP TABLE IF EXISTS entitlements;
DROP FUNCTION IF EXISTS entitlements_enforce_rules();
