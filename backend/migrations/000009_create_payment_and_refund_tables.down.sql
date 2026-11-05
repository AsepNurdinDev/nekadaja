-- Urutan: anak sebelum induk. Trigger ikut terhapus bersama tabelnya; fungsi dihapus terakhir
-- karena fungsi tidak ikut terhapus saat tabel di-drop.
-- Tanpa CASCADE: jika migration yang lebih baru (000010) masih terpasang, DROP TABLE refunds
-- ditolak oleh foreign key entitlements.revoked_refund_id. Jalankan down 000010 lebih dulu.
DROP TABLE IF EXISTS refund_events;
DROP TABLE IF EXISTS refunds;
DROP TABLE IF EXISTS payment_events;
DROP TABLE IF EXISTS payments;
DROP FUNCTION IF EXISTS refunds_enforce_limits();
