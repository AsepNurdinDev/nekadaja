# Database Migration Planning — Nekadaja

**Versi:** 1.1  
**Status:** Implemented (SQL migration 000001–000012 sudah ditulis dan diuji pada PostgreSQL 16)  
**Migration Tool:** golang-migrate  
**Database:** PostgreSQL 13 atau lebih baru  
**Acuan:** `database-blueprint.md` (v1.2), `database-erd.md` (v1.1), `database-dictionary.md` (v1.1)

---

## 1. Tujuan

Dokumen ini mendefinisikan strategi, urutan, dan standar implementasi database migration untuk Nekadaja. Skema yang dihasilkan migration harus identik dengan Database Dictionary.

## 2. Migration Strategy

- Menggunakan golang-migrate dengan migration berformat SQL.
- Setiap migration memiliki file `up.sql` dan `down.sql`.
- Migration dikelompokkan berdasarkan domain dan diurutkan berdasarkan dependency tabel.
- Nomor migration bersifat berurutan (6 digit).
- Folder migration: `migrations/` pada root project.

**Kebijakan perubahan:**

- Sebelum deploy pertama ke environment bersama (staging atau production), migration boleh diedit atau di-squash.
- Setelah migration diterapkan pada environment bersama, migration tersebut tidak boleh diedit sama sekali. Setiap perubahan dilakukan lewat migration baru.

## 3. Migration Sequence

| Version | Name | Domain | Isi |
|---|---|---|---|
| 000001 | create_extensions_and_functions | Extensions | Pemeriksaan versi PostgreSQL (13+) dan fungsi `set_updated_at()` |
| 000002 | create_identity_tables | Identity | `users`, `roles`, `user_roles`, `user_oauth_accounts`, `refresh_tokens`, `email_verification_tokens`, `password_reset_tokens` |
| 000003 | create_catalog_tables | Catalog | `products`, `categories`, `product_categories` |
| 000004 | create_course_tables | Course | `courses`, `course_sections`, `lessons` |
| 000005 | create_examination_tables | Examination | `exams`, `exam_questions`, `exam_answer_options`, `exam_attempts`, `exam_answers`, `exam_answer_options_selected` |
| 000006 | create_certificate_tables | Certificate | `certificate_templates`, `certificates` |
| 000007 | create_source_code_tables | Source Code | `source_code_details`, `source_code_versions`, `product_files` |
| 000008 | create_order_tables | Orders | `orders`, `order_items` |
| 000009 | create_payment_and_refund_tables | Payments | `payments`, `payment_events`, `refunds`, `refund_events` |
| 000010 | create_entitlement_and_progress_tables | Entitlement | `entitlements`, `lesson_progress`, `course_progress` |
| 000011 | create_audit_tables | Audit | `audit_logs` |
| 000012 | seed_roles | Seed | Role `admin`, `author`, `student` |

Total 34 tabel. Urutan ini mengikuti dependency foreign key, bukan urutan prioritas pengembangan di blueprint.

## 4. Naming Convention

Format:

`{version}_{migration_name}.{direction}.sql`

Contoh:

- `000001_create_extensions_and_functions.up.sql`
- `000001_create_extensions_and_functions.down.sql`

Penamaan objek database:

| Objek | Pola | Contoh |
|---|---|---|
| Constraint unik | `{tabel}_{kolom}_key` | `users_email_key` |
| Constraint CHECK | `{tabel}_{aturan}_chk` | `products_pricing_rules_chk` |
| Foreign key komposit | `{tabel}_{tujuan}_fk` | `courses_product_fk` |
| Index biasa | `idx_{tabel}_{kolom}` | `idx_orders_user_created` |
| Partial unique index | `uq_{tabel}_{aturan}` | `uq_entitlements_active_user_product` |
| Trigger | `trg_{tabel}_set_updated_at` | `trg_users_set_updated_at` |

## 5. Standar Isi Migration

1. Setiap tabel mengikuti Database Dictionary: tipe, nullability, default, dan constraint.
2. Constraint, foreign key, dan index didefinisikan eksplisit dengan nama.
3. Foreign key mencantumkan aksi `ON DELETE` sesuai Dictionary bagian 12 (`CASCADE` untuk data konten turunan, `RESTRICT` untuk transaksi, akses, dan hasil ujian, `SET NULL` untuk `audit_logs.user_id`).
4. Unique constraint pendukung foreign key komposit dibuat di migration tabel induk, bukan belakangan:

   | Tabel induk | Unique constraint | Migration |
   |---|---|---|
   | `products` | `(id, product_type)` | 000003 |
   | `exam_answer_options` | `(question_id, id)` | 000005 |
   | `exam_answers` | `(id, question_id)` | 000005 |
   | `orders` | `(id, user_id)` | 000008 |
   | `order_items` | `(id, product_id)` | 000008 |
   | `payments` | `(id, order_id)` | 000009 |

   Constraint yang dirujuk foreign key tidak boleh `DEFERRABLE`.
5. Constraint `position` pada `course_sections`, `lessons`, `exam_questions`, dan `exam_answer_options` bersifat `DEFERRABLE INITIALLY DEFERRED` agar urutan dapat ditukar dalam satu transaksi.
6. Setiap tabel yang memiliki `updated_at` memiliki trigger `trg_{tabel}_set_updated_at` yang memakai fungsi `set_updated_at()` dari migration 000001.
7. Seed data hanya untuk data referensi (role) dan ditulis idempotent (`ON CONFLICT DO NOTHING`).

## 6. Migration Rules

1. Setiap perubahan schema harus melalui migration.
2. Setiap migration harus memiliki pasangan up dan down.
3. Foreign key harus mengikuti dependency order.
4. Constraint dan index harus didefinisikan secara eksplisit.
5. Migration harus lulus pengujian pada bagian 8 sebelum digunakan di production.
6. Migration yang sudah diterapkan pada environment bersama tidak boleh diedit (lihat kebijakan pada bagian 2).
7. `down.sql` men-drop tabel dalam urutan terbalik dari `up.sql`. `down.sql` untuk seed hanya menghapus data seed itu dan gagal (`RESTRICT`) jika role masih dipakai di `user_roles`.
8. Rollback pada database berisi data menghapus data tabel terkait secara permanen; lakukan backup lebih dulu.
9. Perubahan schema harus disinkronkan dengan blueprint, ERD, dan database dictionary.

## 7. Execution Strategy

Migration dijalankan secara berurutan menggunakan golang-migrate.

Proses:

1. Pastikan PostgreSQL aktif dan berversi 13 atau lebih baru.
2. Atur `DATABASE_URL`, misalnya `postgres://user:pass@localhost:5432/nekadaja?sslmode=disable`.
3. Jalankan migration.
4. Periksa status migration.
5. Verifikasi struktur tabel (bagian 8).
6. Jalankan pengujian database.

Perintah dasar:

```bash
# Terapkan semua migration
migrate -path migrations -database "$DATABASE_URL" up

# Lihat versi saat ini
migrate -path migrations -database "$DATABASE_URL" version

# Rollback satu langkah
migrate -path migrations -database "$DATABASE_URL" down 1

# Pulihkan status dirty setelah migration gagal sebagian (setelah memperbaiki masalah)
migrate -path migrations -database "$DATABASE_URL" force <versi_terakhir_yang_benar>
```

Catatan:

- Jika sebuah migration gagal, golang-migrate menandai database sebagai `dirty`. Periksa kondisi tabel secara manual, perbaiki, lalu gunakan `force`.
- Setiap file dijalankan sebagai satu eksekusi. Perintah yang tidak boleh berada di dalam transaksi, seperti `CREATE INDEX CONCURRENTLY`, tidak dipakai pada migration awal. Gunakan hanya pada migration berikutnya yang menambah index pada tabel berisi data, dalam file terpisah.

## 8. Pengujian Migration

Pengujian dijalankan di database kosong khusus uji, bukan database development.

| Pengujian | Tujuan |
|---|---|
| `up` → `down` → `up` | Semua migration dapat diterapkan, dibatalkan, dan diterapkan ulang; setelah `down` tidak ada tabel tersisa |
| Verifikasi struktur | Kolom, tipe, dan nullability di database sama dengan Database Dictionary (`information_schema`) |
| Uji constraint | Constraint menolak data yang melanggar aturan dan menerima data yang sah |

Skrip uji tersedia di folder `database/tests/`:

- `run_migration_tests.sh` menjalankan `up` → `down` → `up`, lalu uji constraint.
- `constraints_test.sql` berisi 111 pengujian, dijalankan dalam satu transaksi yang di-rollback.

Cara menjalankan (psql dibutuhkan; kredensial lewat variabel standar PostgreSQL):

```bash
PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=... \
  bash database/tests/run_migration_tests.sh
```

Cakupan uji constraint:

- Normalisasi dan keunikan email; status; provider OAuth.
- Aturan harga free, fixed, dan PWYW; `published_at` wajib untuk produk published.
- Foreign key komposit: `courses` hanya untuk produk `course`, `source_code_details` hanya untuk produk `source_code`.
- Penukaran `position` dalam satu transaksi (deferrable).
- Ujian: satu attempt `in_progress` per user dan exam, pilihan jawaban harus milik pertanyaan yang dijawab, multi-select, pertanyaan yang sudah dijawab tidak dapat dihapus.
- Sertifikat: satu sertifikat aktif per course dan penerbitan ulang setelah pencabutan.
- Source code: satu versi latest, satu file primary per versi atau course.
- Order: total, diskon, quantity 1, satu item per order.
- Payment: satu payment berhasil per order, keunikan referensi provider, idempotensi webhook payment dan refund.
- Refund: `order_id` dan `user_id` harus konsisten dengan payment dan order.
- Entitlement: satu entitlement aktif per user dan produk, produk harus sama dengan order item, beli ulang setelah pencabutan.
- Aksi `ON DELETE`: `RESTRICT`, `CASCADE`, dan `SET NULL`.
- Trigger `updated_at`.

### Hasil verifikasi awal

Dijalankan pada PostgreSQL 16 dengan psql (satu transaksi per file migration):

| Pengujian | Hasil |
|---|---|
| `up` (12 migration) | Berhasil; 34 tabel terbentuk |
| `down` (12 migration) | Berhasil; 0 tabel tersisa |
| `up` ulang | Berhasil |
| Kolom database vs Dictionary | 280 kolom, 0 selisih |
| Uji constraint | 111 dari 111 lulus |

golang-migrate sendiri belum dijalankan pada verifikasi ini. Jalankan `migrate ... up` dan `down` sekali pada environment Anda sebagai konfirmasi akhir.

## 9. Integrasi sqlc

sqlc dapat membaca folder `migrations/` sebagai sumber skema. Untuk migration berformat golang-migrate, sqlc mengabaikan file `.down.sql`.

Contoh `sqlc.yaml`:

```yaml
version: "2"
sql:
  - engine: "postgresql"
    schema: "migrations"
    queries: "internal/db/queries"
    gen:
      go:
        package: "db"
        out: "internal/db/sqlc"
        sql_package: "pgx/v5"
```

Jalankan `sqlc generate` setelah migration selesai dan pastikan tidak ada error parsing. Migration 000001 memakai blok `DO` dan fungsi PL/pgSQL; jika sqlc menolaknya, pindahkan bagian tersebut ke luar folder skema sqlc atau gunakan opsi `schema` yang menunjuk ke file tertentu.

## 10. Catatan Keputusan Desain yang Tercermin di Migration

- `entitlements.order_item_id` wajib dan unik; order gratis tetap membuat order item.
- Kategori tidak bertingkat (tidak ada `parent_id`).
- Tipe pertanyaan awal hanya pilihan, sehingga `exam_answers` tidak memiliki kolom jawaban teks.
- Validasi yang tidak dapat dinyatakan dengan constraint tetap dilakukan aplikasi: kesesuaian `product_files.product_id` dengan versi source code, `user_id` entitlement dengan pemilik order, `payments.amount` dengan `orders.total_amount`, total refund terhadap payment, dan batas `max_attempts`.

## 11. Next Step

1. Jalankan migration dengan golang-migrate pada database development dan konfirmasi hasilnya.
2. Siapkan `sqlc.yaml` dan mulai menulis query untuk domain pertama (Identity).
3. Putuskan item pada bagian Pending Decisions blueprint; saat keputusan memengaruhi skema, tambahkan sebagai migration baru (000013 dan seterusnya).
