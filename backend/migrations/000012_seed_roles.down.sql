-- Hanya menghapus data seed ini. Gagal (RESTRICT) jika role masih dipakai di user_roles.
DELETE FROM roles WHERE name IN ('admin', 'author', 'student');
