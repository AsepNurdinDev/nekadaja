# Database Dictionary — Nekadaja

**Versi:** 1.1  
**Status:** Revised Draft  
**Database:** PostgreSQL  
**Backend:** Go + Gin  
**Data Access:** pgx + sqlc  
**Acuan:** `database-blueprint.md` (v1.2) dan `database-erd.md` (v1.1)

---

## 1. Konvensi Database

Sebelum membahas tabel, berikut standar yang digunakan dalam database Nekadaja.

| Konvensi | Standar |
|---|---|
| Naming table | `snake_case`, plural |
| Naming column | `snake_case` |
| Primary key | UUID, default `gen_random_uuid()` (atau UUID yang dibuat aplikasi) |
| Foreign key | Menggunakan nama `{entity}_id` |
| Timestamp | `TIMESTAMPTZ` |
| Currency | `CHAR(3)`, default `IDR` |
| Nominal uang | `BIGINT` dalam satuan terkecil mata uang (untuk IDR: rupiah) |
| Boolean | `BOOLEAN` |
| Structured data | `JSONB` |
| Soft delete | Digunakan hanya jika diperlukan |
| Created timestamp | `created_at`, default `now()` |
| Updated timestamp | `updated_at`, default `now()` |

### 1.1 Standar tipe data

| Tipe data | Kegunaan |
|---|---|
| `UUID` | Identitas unik setiap record |
| `VARCHAR(n)` | Teks dengan panjang maksimum |
| `CHAR(3)` | Kode mata uang |
| `TEXT` | Teks panjang |
| `INTEGER` | Bilangan bulat |
| `BIGINT` | Nominal uang dan bilangan besar |
| `BOOLEAN` | Nilai true/false |
| `TIMESTAMPTZ` | Tanggal dan waktu dengan zona waktu |
| `JSONB` | Data JSON terstruktur |
| `NUMERIC(p,s)` | Angka desimal dengan presisi |
| `INET` | Alamat IP |

### 1.2 Standar constraint

| Constraint | Kegunaan |
|---|---|
| `PRIMARY KEY` | Identitas unik record |
| `FOREIGN KEY` | Menjaga hubungan antar-tabel |
| `UNIQUE` | Mencegah duplikasi nilai |
| `NOT NULL` | Memastikan kolom wajib diisi |
| `CHECK` | Memvalidasi nilai berdasarkan kondisi |
| `DEFAULT` | Nilai otomatis jika tidak diberikan |
| Partial `UNIQUE` index | Keunikan yang hanya berlaku pada baris tertentu (`WHERE ...`) |
| `DEFERRABLE` | Constraint ditunda hingga akhir transaksi (dipakai untuk pengurutan `position`) |

### 1.3 Catatan membaca tabel

- Kolom `Constraint` yang berisi `FK` mengacu ke tabel pada kolom `Keterangan` atau pada bagian "Foreign key" di tiap tabel. Aksi `ON DELETE` setiap foreign key dirangkum di bagian 12.
- Kolom yang tidak mencantumkan `NULL` pada `Constraint` bersifat `NOT NULL`.

---

# 2. Identity & Access Management

Domain ini mengelola akun pengguna, role, autentikasi, dan keamanan akun.

## 2.1 `users`

Menyimpan data utama pengguna Nekadaja.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID pengguna |
| `name` | VARCHAR(150) | NOT NULL | Nama pengguna |
| `email` | VARCHAR(255) | UNIQUE, NOT NULL | Email pengguna (sudah dinormalisasi) |
| `password_hash` | TEXT | NULL | Hash Argon2id; NULL untuk akun OAuth-only |
| `avatar_url` | TEXT | NULL | URL foto profil |
| `status` | VARCHAR(30) | NOT NULL, DEFAULT `'active'` | `active`, `inactive`, atau `suspended` |
| `email_verified_at` | TIMESTAMPTZ | NULL | Waktu verifikasi email; NULL berarti belum terverifikasi |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

**Constraint:**
- `CHECK (email = lower(btrim(email)))` agar email selalu dinormalisasi.
- `CHECK (status IN ('active', 'inactive', 'suspended'))`.

**Index:**
- UNIQUE index pada `email`.

## 2.2 `roles`

Menyimpan daftar role pengguna.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID role |
| `name` | VARCHAR(50) | UNIQUE, NOT NULL | Nama role |
| `description` | TEXT | NULL | Deskripsi role |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |

Data awal (seed):
- `admin`
- `author`
- `student`

## 2.3 `user_roles`

Menghubungkan pengguna dengan role. Satu pengguna dapat memiliki beberapa role.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `user_id` | UUID | PK, FK | Referensi `users.id` |
| `role_id` | UUID | PK, FK | Referensi `roles.id` |
| `assigned_at` | TIMESTAMPTZ | NOT NULL | Waktu pemberian role |

**Constraint:**
- Composite primary key (`user_id`, `role_id`).

## 2.4 `user_oauth_accounts`

Menyimpan akun OAuth yang terhubung dengan pengguna.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID akun OAuth |
| `user_id` | UUID | FK, NOT NULL | Referensi `users.id` |
| `provider` | VARCHAR(50) | NOT NULL | Penyedia OAuth; awalnya `google` |
| `provider_user_id` | VARCHAR(255) | NOT NULL | ID pengguna dari provider |
| `provider_email` | VARCHAR(255) | NULL | Email akun pada provider |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

**Constraint:**
- UNIQUE (`provider`, `provider_user_id`).
- `CHECK (provider IN ('google'))` pada tahap awal; diperluas lewat migration saat provider baru ditambahkan.

Access token dan refresh token OAuth tidak disimpan.

## 2.5 `refresh_tokens`

Menyimpan hash refresh token untuk pengelolaan sesi autentikasi.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID token |
| `user_id` | UUID | FK, NOT NULL | Pemilik token |
| `token_hash` | TEXT | UNIQUE, NOT NULL | Hash token |
| `expires_at` | TIMESTAMPTZ | NOT NULL | Waktu kedaluwarsa |
| `revoked_at` | TIMESTAMPTZ | NULL | Waktu pencabutan |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |

## 2.6 `email_verification_tokens`

Menyimpan token untuk verifikasi email pengguna.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID token |
| `user_id` | UUID | FK, NOT NULL | Pemilik token |
| `token_hash` | TEXT | UNIQUE, NOT NULL | Hash token |
| `expires_at` | TIMESTAMPTZ | NOT NULL | Kedaluwarsa token |
| `used_at` | TIMESTAMPTZ | NULL | Waktu penggunaan |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |

## 2.7 `password_reset_tokens`

Menyimpan token untuk proses reset password.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID token |
| `user_id` | UUID | FK, NOT NULL | Pemilik token |
| `token_hash` | TEXT | UNIQUE, NOT NULL | Hash token |
| `expires_at` | TIMESTAMPTZ | NOT NULL | Kedaluwarsa token |
| `used_at` | TIMESTAMPTZ | NULL | Waktu penggunaan |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |

---

# 3. Product Catalog

Domain ini mengelola katalog produk Course dan Source Code.

## 3.1 `products`

Menyimpan informasi utama seluruh produk.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID produk |
| `product_type` | VARCHAR(30) | NOT NULL | `course` atau `source_code` |
| `title` | VARCHAR(255) | NOT NULL | Nama produk |
| `slug` | VARCHAR(255) | UNIQUE, NOT NULL | URL-friendly identifier |
| `description` | TEXT | NULL | Deskripsi produk |
| `thumbnail_url` | TEXT | NULL | URL thumbnail produk |
| `pricing_type` | VARCHAR(30) | NOT NULL | `free`, `fixed`, atau `pwyw` |
| `price_amount` | BIGINT | NOT NULL, DEFAULT 0 | Harga tetap (`fixed`) atau harga yang disarankan (`pwyw`) |
| `minimum_amount` | BIGINT | NOT NULL, DEFAULT 0 | Harga minimum PWYW |
| `currency` | CHAR(3) | NOT NULL, DEFAULT `'IDR'` | Mata uang, awalnya IDR |
| `status` | VARCHAR(30) | NOT NULL, DEFAULT `'draft'` | `draft`, `published`, atau `archived` |
| `created_by` | UUID | FK, NOT NULL | Referensi `users.id` (Author/Admin pembuat produk) |
| `published_at` | TIMESTAMPTZ | NULL | Waktu pertama kali dipublikasikan |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

**Constraint:**
- `UNIQUE (id, product_type)` untuk foreign key komposit dari `courses` dan `source_code_details`.
- `CHECK (product_type IN ('course', 'source_code'))`.
- `CHECK (pricing_type IN ('free', 'fixed', 'pwyw'))`.
- `CHECK (status IN ('draft', 'published', 'archived'))`.
- `CHECK (price_amount >= 0 AND minimum_amount >= 0)`.
- `CHECK` aturan harga per tipe:
  - `free`: `price_amount = 0` dan `minimum_amount = 0`.
  - `fixed`: `price_amount > 0` dan `minimum_amount = 0`.
  - `pwyw`: `minimum_amount > 0` dan (`price_amount = 0` atau `price_amount >= minimum_amount`).
- `CHECK (status <> 'published' OR published_at IS NOT NULL)`.
- `CHECK (currency = upper(currency))`; aplikasi membatasi nilai awal ke `IDR`.

**Foreign key:** `created_by` → `users(id)`.

## 3.2 `categories`

Menyimpan kategori produk.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID kategori |
| `name` | VARCHAR(100) | NOT NULL | Nama kategori |
| `slug` | VARCHAR(120) | UNIQUE, NOT NULL | Slug kategori |
| `description` | TEXT | NULL | Deskripsi kategori |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

Kategori bertingkat (`parent_id`) tidak termasuk dalam desain saat ini.

## 3.3 `product_categories`

Tabel penghubung produk dan kategori.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `product_id` | UUID | PK, FK | Referensi `products.id` |
| `category_id` | UUID | PK, FK | Referensi `categories.id` |

**Constraint:**
- Composite primary key (`product_id`, `category_id`).

---

# 4. Course Management

Domain ini mengelola struktur materi pembelajaran.

## 4.1 `courses`

Menyimpan detail khusus produk bertipe course.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID course |
| `product_id` | UUID | UNIQUE, NOT NULL | Referensi produk |
| `product_type` | VARCHAR(30) | NOT NULL, DEFAULT `'course'` | Selalu `course` |
| `level` | VARCHAR(30) | NULL | Tingkat kesulitan |
| `language` | VARCHAR(10) | NOT NULL, DEFAULT `'id'` | Bahasa course |
| `estimated_duration_minutes` | INTEGER | NULL | Estimasi durasi dalam menit |
| `requirements` | JSONB | NOT NULL, DEFAULT `'[]'` | Prasyarat course (array) |
| `learning_outcomes` | JSONB | NOT NULL, DEFAULT `'[]'` | Hasil pembelajaran (array) |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

**Constraint:**
- `CHECK (product_type = 'course')`.
- `FOREIGN KEY (product_id, product_type) REFERENCES products (id, product_type)` sehingga hanya produk bertipe course yang dapat memiliki detail course.
- `CHECK (estimated_duration_minutes IS NULL OR estimated_duration_minutes >= 0)`.
- `CHECK (jsonb_typeof(requirements) = 'array' AND jsonb_typeof(learning_outcomes) = 'array')`.
- Nilai `level` yang disarankan: `beginner`, `intermediate`, `advanced`.

## 4.2 `course_sections`

Menyimpan bagian atau modul dalam course.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID section |
| `course_id` | UUID | FK, NOT NULL | Referensi `courses.id` |
| `title` | VARCHAR(255) | NOT NULL | Judul section |
| `description` | TEXT | NULL | Deskripsi section |
| `position` | INTEGER | NOT NULL | Urutan section |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

**Constraint:**
- UNIQUE (`course_id`, `position`), `DEFERRABLE INITIALLY DEFERRED`.
- `CHECK (position >= 0)`.

## 4.3 `lessons`

Menyimpan materi pembelajaran.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID lesson |
| `section_id` | UUID | FK, NOT NULL | Referensi `course_sections.id` |
| `title` | VARCHAR(255) | NOT NULL | Judul materi |
| `slug` | VARCHAR(255) | NOT NULL | Slug materi |
| `content` | TEXT | NULL | Konten materi |
| `lesson_type` | VARCHAR(30) | NOT NULL | `text`, `video`, atau `mixed` |
| `video_url` | TEXT | NULL | URL video |
| `duration_seconds` | INTEGER | NULL | Durasi materi dalam detik |
| `is_preview` | BOOLEAN | NOT NULL, DEFAULT FALSE | Materi dapat dilihat tanpa membeli |
| `position` | INTEGER | NOT NULL | Urutan materi |
| `status` | VARCHAR(30) | NOT NULL, DEFAULT `'draft'` | `draft` atau `published` |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

**Constraint:**
- UNIQUE (`section_id`, `slug`).
- UNIQUE (`section_id`, `position`), `DEFERRABLE INITIALLY DEFERRED`.
- `CHECK (lesson_type IN ('text', 'video', 'mixed'))`.
- `CHECK (status IN ('draft', 'published'))`.
- `CHECK (duration_seconds IS NULL OR duration_seconds >= 0)`.
- `CHECK (status <> 'published' OR lesson_type = 'text' OR video_url IS NOT NULL)`.

---

# 5. Examination Management

Domain ini mengelola ujian dan penilaian peserta course.

## 5.1 `exams`

Menyimpan konfigurasi ujian.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID ujian |
| `course_id` | UUID | FK, NOT NULL | Course pemilik ujian |
| `title` | VARCHAR(255) | NOT NULL | Judul ujian |
| `description` | TEXT | NULL | Deskripsi ujian |
| `duration_minutes` | INTEGER | NOT NULL | Durasi ujian |
| `passing_score` | NUMERIC(5,2) | NOT NULL | Nilai minimum lulus (persentase 0–100) |
| `max_attempts` | INTEGER | NULL | Batas percobaan; NULL berarti tanpa batas |
| `shuffle_questions` | BOOLEAN | NOT NULL, DEFAULT FALSE | Acak urutan pertanyaan |
| `shuffle_options` | BOOLEAN | NOT NULL, DEFAULT FALSE | Acak urutan pilihan jawaban |
| `status` | VARCHAR(30) | NOT NULL, DEFAULT `'draft'` | `draft`, `published`, atau `archived` |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

**Constraint:**
- `CHECK (duration_minutes > 0)`.
- `CHECK (passing_score BETWEEN 0 AND 100)`.
- `CHECK (max_attempts IS NULL OR max_attempts > 0)`.
- `CHECK (status IN ('draft', 'published', 'archived'))`.

## 5.2 `exam_questions`

Menyimpan pertanyaan ujian.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID pertanyaan |
| `exam_id` | UUID | FK, NOT NULL | Referensi `exams.id` |
| `question_text` | TEXT | NOT NULL | Isi pertanyaan |
| `question_type` | VARCHAR(30) | NOT NULL | `single_choice`, `multiple_choice`, atau `true_false` |
| `image_url` | TEXT | NULL | Gambar pertanyaan |
| `points` | NUMERIC(8,2) | NOT NULL, DEFAULT 1 | Bobot nilai |
| `explanation` | TEXT | NULL | Pembahasan jawaban |
| `position` | INTEGER | NOT NULL | Urutan pertanyaan |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

**Constraint:**
- `CHECK (question_type IN ('single_choice', 'multiple_choice', 'true_false'))`.
- `CHECK (points > 0)`.
- UNIQUE (`exam_id`, `position`), `DEFERRABLE INITIALLY DEFERRED`.

## 5.3 `exam_answer_options`

Menyimpan pilihan jawaban setiap pertanyaan.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID pilihan |
| `question_id` | UUID | FK, NOT NULL | Referensi `exam_questions.id` |
| `option_text` | TEXT | NULL | Isi pilihan |
| `image_url` | TEXT | NULL | Gambar pilihan |
| `is_correct` | BOOLEAN | NOT NULL, DEFAULT FALSE | Penanda jawaban benar |
| `position` | INTEGER | NOT NULL | Urutan pilihan |

**Constraint:**
- `CHECK (option_text IS NOT NULL OR image_url IS NOT NULL)`.
- UNIQUE (`question_id`, `position`), `DEFERRABLE INITIALLY DEFERRED`.
- UNIQUE (`question_id`, `id`) untuk foreign key komposit dari `exam_answers` dan `exam_answer_options_selected`.

**Aturan aplikasi (saat ujian dipublikasikan):**
- `single_choice` dan `true_false`: tepat satu pilihan dengan `is_correct = true`.
- `multiple_choice`: minimal satu pilihan dengan `is_correct = true`.
- `is_correct` tidak boleh dikirim ke frontend sebelum ujian diselesaikan.

## 5.4 `exam_attempts`

Mencatat setiap percobaan ujian pengguna.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID percobaan |
| `exam_id` | UUID | FK, NOT NULL | Referensi `exams.id` |
| `user_id` | UUID | FK, NOT NULL | Referensi `users.id` |
| `attempt_number` | INTEGER | NOT NULL | Nomor percobaan (mulai dari 1) |
| `started_at` | TIMESTAMPTZ | NOT NULL | Waktu mulai |
| `submitted_at` | TIMESTAMPTZ | NULL | Waktu pengumpulan |
| `score` | NUMERIC(5,2) | NULL | Nilai akhir (persentase 0–100) |
| `is_passed` | BOOLEAN | NULL | Snapshot status kelulusan saat penilaian |
| `status` | VARCHAR(30) | NOT NULL, DEFAULT `'in_progress'` | `in_progress`, `submitted`, `graded`, atau `expired` |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |

**Constraint:**
- UNIQUE (`exam_id`, `user_id`, `attempt_number`).
- Partial UNIQUE index (`exam_id`, `user_id`) `WHERE status = 'in_progress'`: hanya satu attempt berjalan.
- `CHECK (attempt_number > 0)`.
- `CHECK (score IS NULL OR score BETWEEN 0 AND 100)`.
- `CHECK (submitted_at IS NULL OR submitted_at >= started_at)`.
- `CHECK (status IN ('in_progress', 'submitted', 'graded', 'expired'))`.

**Aturan aplikasi:** batas `max_attempts` dan kepemilikan entitlement atas course divalidasi saat attempt dibuat.

## 5.5 `exam_answers`

Menyimpan jawaban peserta untuk setiap pertanyaan.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID jawaban |
| `attempt_id` | UUID | FK, NOT NULL | Referensi `exam_attempts.id` |
| `question_id` | UUID | FK, NOT NULL | Referensi `exam_questions.id` |
| `selected_option_id` | UUID | NULL | Pilihan jawaban tunggal (`single_choice` dan `true_false`) |
| `is_correct` | BOOLEAN | NULL | Hasil penilaian |
| `earned_points` | NUMERIC(8,2) | NOT NULL, DEFAULT 0 | Nilai yang diperoleh |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

**Constraint:**
- UNIQUE (`attempt_id`, `question_id`).
- UNIQUE (`id`, `question_id`) untuk foreign key komposit dari `exam_answer_options_selected`.
- `FOREIGN KEY (question_id, selected_option_id) REFERENCES exam_answer_options (question_id, id)`: pilihan harus milik pertanyaan yang dijawab. Jika `selected_option_id` NULL, foreign key ini tidak diperiksa.
- `CHECK (earned_points >= 0)`.

**Catatan desain:** Untuk `multiple_choice`, `selected_option_id` bernilai NULL dan pilihan peserta disimpan di `exam_answer_options_selected`. Kolom jawaban teks bebas belum disediakan karena belum ada tipe pertanyaan berbasis teks.

## 5.6 `exam_answer_options_selected`

Menyimpan pilihan peserta untuk pertanyaan `multiple_choice`.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `answer_id` | UUID | PK, FK | Referensi `exam_answers.id` |
| `question_id` | UUID | NOT NULL | Pertanyaan yang dijawab |
| `option_id` | UUID | PK | Pilihan yang dipilih |

**Constraint:**
- Composite primary key (`answer_id`, `option_id`).
- `FOREIGN KEY (answer_id, question_id) REFERENCES exam_answers (id, question_id)`.
- `FOREIGN KEY (question_id, option_id) REFERENCES exam_answer_options (question_id, id)`.

---

# 6. Certificate Management

Domain ini mengelola template dan sertifikat peserta.

## 6.1 `certificate_templates`

Menyimpan template sertifikat. Template bersifat global dan dapat dipakai oleh banyak course.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID template |
| `name` | VARCHAR(150) | NOT NULL | Nama template |
| `template_file_url` | TEXT | NOT NULL | Lokasi file template |
| `configuration` | JSONB | NOT NULL, DEFAULT `'{}'` | Konfigurasi penempatan elemen pada template |
| `is_active` | BOOLEAN | NOT NULL, DEFAULT TRUE | Status aktif |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

## 6.2 `certificates`

Menyimpan sertifikat yang telah diterbitkan.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID sertifikat |
| `user_id` | UUID | FK, NOT NULL | Penerima sertifikat |
| `course_id` | UUID | FK, NOT NULL | Course yang diselesaikan |
| `template_id` | UUID | FK, NOT NULL | Template yang digunakan |
| `certificate_number` | VARCHAR(100) | UNIQUE, NOT NULL | Nomor sertifikat |
| `file_url` | TEXT | NULL | Lokasi file sertifikat (NULL sebelum file dibuat) |
| `issued_at` | TIMESTAMPTZ | NOT NULL | Waktu penerbitan |
| `revoked_at` | TIMESTAMPTZ | NULL | Waktu pencabutan |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |

**Constraint:**
- Partial UNIQUE index (`user_id`, `course_id`) `WHERE revoked_at IS NULL`: satu sertifikat aktif per course. Sertifikat yang telah dicabut tetap tersimpan dan dapat diterbitkan ulang.

---

# 7. Source Code Management

Domain ini mengelola detail produk source code, versi, dan file unduhan.

## 7.1 `source_code_details`

Menyimpan detail produk bertipe source code.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID detail |
| `product_id` | UUID | UNIQUE, NOT NULL | Referensi produk |
| `product_type` | VARCHAR(30) | NOT NULL, DEFAULT `'source_code'` | Selalu `source_code` |
| `programming_language` | VARCHAR(100) | NULL | Bahasa pemrograman |
| `framework` | VARCHAR(100) | NULL | Framework |
| `documentation` | TEXT | NULL | Dokumentasi produk |
| `installation_guide` | TEXT | NULL | Panduan instalasi |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

**Constraint:**
- `CHECK (product_type = 'source_code')`.
- `FOREIGN KEY (product_id, product_type) REFERENCES products (id, product_type)` sehingga hanya produk bertipe source_code yang dapat memiliki detail source code.

## 7.2 `source_code_versions`

Menyimpan versi source code.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID versi |
| `source_code_id` | UUID | FK, NOT NULL | Referensi `source_code_details.id` |
| `version` | VARCHAR(50) | NOT NULL | Nomor versi |
| `changelog` | TEXT | NULL | Catatan perubahan |
| `release_notes` | TEXT | NULL | Catatan rilis |
| `is_latest` | BOOLEAN | NOT NULL, DEFAULT FALSE | Penanda versi terbaru |
| `released_at` | TIMESTAMPTZ | NOT NULL | Waktu rilis |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |

**Constraint:**
- UNIQUE (`source_code_id`, `version`).
- Partial UNIQUE index (`source_code_id`) `WHERE is_latest`: hanya satu versi latest per source code. Saat berpindah versi latest, nonaktifkan versi lama lebih dulu dalam transaksi yang sama.

## 7.3 `product_files`

Menyimpan metadata file produk yang dapat diunduh.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID file |
| `product_id` | UUID | FK, NOT NULL | Referensi `products.id` |
| `source_code_version_id` | UUID | FK, NULL | Versi source code; NULL untuk file course |
| `file_name` | VARCHAR(255) | NOT NULL | Nama file |
| `storage_key` | TEXT | UNIQUE, NOT NULL | Kunci lokasi file di storage |
| `mime_type` | VARCHAR(150) | NOT NULL | Tipe file |
| `file_size` | BIGINT | NOT NULL | Ukuran file dalam byte |
| `checksum` | VARCHAR(128) | NULL | Checksum file (misalnya SHA-256) |
| `is_primary` | BOOLEAN | NOT NULL, DEFAULT FALSE | File utama |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu unggah |

**Constraint:**
- `CHECK (file_size >= 0)`.
- Partial UNIQUE index (`source_code_version_id`) `WHERE is_primary AND source_code_version_id IS NOT NULL`: satu file primary per versi.
- Partial UNIQUE index (`product_id`) `WHERE is_primary AND source_code_version_id IS NULL`: satu file primary per course.

**Aturan aplikasi:** `product_id` harus sama dengan produk pemilik `source_code_version_id` (melalui `source_code_details`); validasi dilakukan aplikasi atau trigger.

File aktual tidak disimpan di PostgreSQL. Database hanya menyimpan metadata dan lokasi file.

---

# 8. Order Management

Domain ini mengelola transaksi pembelian pengguna.

## 8.1 `orders`

Menyimpan data utama transaksi.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID order |
| `order_number` | VARCHAR(50) | UNIQUE, NOT NULL | Nomor transaksi |
| `user_id` | UUID | FK, NOT NULL | Pembeli |
| `subtotal_amount` | BIGINT | NOT NULL | Subtotal sebelum diskon |
| `discount_amount` | BIGINT | NOT NULL, DEFAULT 0 | Diskon (dicadangkan untuk sistem kupon) |
| `total_amount` | BIGINT | NOT NULL | Total yang harus dibayar |
| `currency` | CHAR(3) | NOT NULL, DEFAULT `'IDR'` | Mata uang |
| `status` | VARCHAR(30) | NOT NULL, DEFAULT `'pending_payment'` | Status order |
| `paid_at` | TIMESTAMPTZ | NULL | Waktu pembayaran berhasil |
| `expires_at` | TIMESTAMPTZ | NULL | Batas waktu pembayaran (order `pending_payment`) |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

**Constraint:**
- `UNIQUE (id, user_id)` untuk foreign key komposit dari `refunds`.
- `CHECK (status IN ('pending_payment', 'paid', 'cancelled', 'expired', 'partially_refunded', 'refunded'))`.
- `CHECK (subtotal_amount >= 0 AND discount_amount >= 0 AND total_amount >= 0)`.
- `CHECK (discount_amount <= subtotal_amount)`.
- `CHECK (total_amount = subtotal_amount - discount_amount)`.
- `CHECK (status NOT IN ('paid', 'partially_refunded', 'refunded') OR paid_at IS NOT NULL)`.

**Foreign key:** `user_id` → `users(id)`.

**Aturan aplikasi:** `subtotal_amount` harus sama dengan `order_items.subtotal_amount`. Order gratis dibuat dengan `total_amount = 0` dan status `paid` tanpa payment.

## 8.2 `order_items`

Menyimpan snapshot produk yang dibeli.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID item |
| `order_id` | UUID | FK, UNIQUE, NOT NULL | Referensi `orders.id` |
| `product_id` | UUID | FK, NOT NULL | Produk yang dibeli |
| `product_title` | VARCHAR(255) | NOT NULL | Nama produk saat transaksi |
| `product_type` | VARCHAR(30) | NOT NULL | Tipe produk saat transaksi |
| `unit_price` | BIGINT | NOT NULL | Harga saat transaksi (termasuk harga pilihan pengguna pada PWYW) |
| `quantity` | INTEGER | NOT NULL, DEFAULT 1 | Selalu 1 |
| `subtotal_amount` | BIGINT | NOT NULL | Subtotal item |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |

**Constraint:**
- UNIQUE (`order_id`): satu order hanya memiliki satu item.
- `UNIQUE (id, product_id)` untuk foreign key komposit dari `entitlements`.
- `CHECK (product_type IN ('course', 'source_code'))`.
- `CHECK (unit_price >= 0)`.
- `CHECK (quantity = 1)`.
- `CHECK (subtotal_amount = unit_price * quantity)`.

**Aturan aplikasi:** untuk produk PWYW, `unit_price >= products.minimum_amount` saat order dibuat.

---

# 9. Payment & Refund Management

Domain ini mengelola pembayaran dan pengembalian dana.

## 9.1 `payments`

Menyimpan percobaan pembayaran untuk order.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID pembayaran |
| `order_id` | UUID | FK, NOT NULL | Referensi `orders.id` |
| `provider` | VARCHAR(50) | NOT NULL | Payment gateway |
| `provider_reference` | VARCHAR(255) | NULL | ID transaksi dari provider |
| `payment_method` | VARCHAR(50) | NULL | Metode pembayaran |
| `amount` | BIGINT | NOT NULL | Nominal pembayaran |
| `currency` | CHAR(3) | NOT NULL, DEFAULT `'IDR'` | Mata uang |
| `status` | VARCHAR(30) | NOT NULL, DEFAULT `'pending'` | Status pembayaran |
| `paid_at` | TIMESTAMPTZ | NULL | Waktu pembayaran berhasil |
| `expired_at` | TIMESTAMPTZ | NULL | Batas waktu pembayaran |
| `raw_response` | JSONB | NULL | Respons mentah provider |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

**Constraint:**
- `CHECK (status IN ('pending', 'paid', 'failed', 'expired', 'cancelled', 'refunded', 'partially_refunded'))`.
- `CHECK (amount > 0)`: order gratis tidak memiliki payment.
- `CHECK (status NOT IN ('paid', 'partially_refunded', 'refunded') OR paid_at IS NOT NULL)`.
- UNIQUE (`provider`, `provider_reference`) `WHERE provider_reference IS NOT NULL`.
- Partial UNIQUE index (`order_id`) `WHERE status IN ('paid', 'partially_refunded', 'refunded')`: hanya satu pembayaran berhasil per order, sehingga total pembayaran berhasil tidak melebihi jumlah yang harus dibayar.
- `UNIQUE (id, order_id)` untuk foreign key komposit dari `refunds`.

**Aturan aplikasi:** `amount` harus sama dengan `orders.total_amount` dan dibuat dalam transaksi. `raw_response` tidak boleh berisi data sensitif seperti nomor kartu lengkap.

## 9.2 `payment_events`

Menyimpan riwayat event dari payment gateway.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID event |
| `payment_id` | UUID | FK, NOT NULL | Referensi `payments.id` |
| `provider` | VARCHAR(50) | NOT NULL | Provider pengirim event |
| `provider_event_id` | VARCHAR(255) | NULL | ID event dari provider |
| `event_type` | VARCHAR(100) | NOT NULL | Jenis event |
| `payload` | JSONB | NOT NULL | Payload webhook |
| `processed_at` | TIMESTAMPTZ | NULL | Waktu selesai diproses; NULL berarti belum diproses |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu diterima |

**Constraint:**
- UNIQUE (`provider`, `provider_event_id`) `WHERE provider_event_id IS NOT NULL`: keunikan event ID per provider.
- Jika provider tidak menyediakan event ID, aplikasi membuat kunci idempotensi deterministik dan menyimpannya di `provider_event_id`.
- Simpan payload yang diperlukan untuk audit dengan perlindungan terhadap data sensitif.

`provider` harus sama dengan `payments.provider` untuk `payment_id` terkait (diisi aplikasi).

## 9.3 `refunds`

Menyimpan permintaan dan proses refund.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID refund |
| `payment_id` | UUID | FK, NOT NULL | Referensi `payments.id` |
| `order_id` | UUID | FK, NOT NULL | Referensi `orders.id` |
| `user_id` | UUID | FK, NOT NULL | Pemilik order yang mengajukan refund |
| `refund_number` | VARCHAR(100) | UNIQUE, NOT NULL | Nomor refund |
| `amount` | BIGINT | NOT NULL | Nominal refund |
| `reason` | TEXT | NULL | Alasan refund |
| `status` | VARCHAR(30) | NOT NULL, DEFAULT `'requested'` | Status refund |
| `provider_reference` | VARCHAR(255) | NULL | ID refund dari provider |
| `requested_at` | TIMESTAMPTZ | NOT NULL | Waktu permintaan |
| `processed_at` | TIMESTAMPTZ | NULL | Waktu pemrosesan |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

**Constraint:**
- `CHECK (status IN ('requested', 'approved', 'rejected', 'processing', 'succeeded', 'failed'))`.
- `CHECK (amount > 0)`.
- `FOREIGN KEY (payment_id, order_id) REFERENCES payments (id, order_id)`.
- `FOREIGN KEY (order_id, user_id) REFERENCES orders (id, user_id)`.

**Aturan aplikasi:** jumlah refund berstatus aktif (`requested`, `approved`, `processing`) dan `succeeded` untuk satu payment tidak boleh melebihi `payments.amount`; dicek dalam transaksi dengan row lock pada payment. Persetujuan refund tidak otomatis berarti dana sudah dikembalikan.

## 9.4 `refund_events`

Menyimpan riwayat event dan perubahan refund.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID event |
| `refund_id` | UUID | FK, NOT NULL | Referensi `refunds.id` |
| `provider_event_id` | VARCHAR(255) | NULL | ID event dari provider |
| `event_type` | VARCHAR(100) | NOT NULL | Jenis event |
| `payload` | JSONB | NOT NULL, DEFAULT `'{}'` | Data event |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pencatatan |

**Constraint:**
- UNIQUE (`refund_id`, `provider_event_id`) `WHERE provider_event_id IS NOT NULL`.

---

# 10. Entitlement & Learning Progress

Domain ini mengelola hak akses pengguna terhadap produk dan progres belajar.

## 10.1 `entitlements`

Menyimpan hak akses permanen pengguna terhadap produk yang diperoleh.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID entitlement |
| `user_id` | UUID | FK, NOT NULL | Pemilik akses |
| `product_id` | UUID | FK, NOT NULL | Produk yang diakses |
| `order_item_id` | UUID | UNIQUE, NOT NULL | Order item sumber akses (termasuk order gratis) |
| `granted_at` | TIMESTAMPTZ | NOT NULL | Waktu pemberian akses |
| `revoked_at` | TIMESTAMPTZ | NULL | Waktu pencabutan akses |
| `revoked_reason` | TEXT | NULL | Alasan pencabutan |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |

**Constraint:**
- Partial UNIQUE index (`user_id`, `product_id`) `WHERE revoked_at IS NULL`: satu entitlement aktif per kombinasi user dan produk.
- `FOREIGN KEY (order_item_id, product_id) REFERENCES order_items (id, product_id)`: produk entitlement sama dengan produk yang dipesan.
- `CHECK (revoked_at IS NOT NULL OR revoked_reason IS NULL)`.

Hak akses bersifat permanen dan tidak memiliki tanggal kedaluwarsa. Entitlement aktif adalah entitlement dengan `revoked_at IS NULL`.

**Aturan aplikasi:** `user_id` harus sama dengan pemilik order dari `order_item_id`. Order gratis menghasilkan entitlement dengan cara yang sama dengan order berbayar.

## 10.2 `lesson_progress`

Mencatat progres pengguna pada setiap lesson.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID progres |
| `user_id` | UUID | FK, NOT NULL | Pengguna |
| `lesson_id` | UUID | FK, NOT NULL | Materi |
| `is_completed` | BOOLEAN | NOT NULL, DEFAULT FALSE | Status penyelesaian |
| `last_position_seconds` | INTEGER | NOT NULL, DEFAULT 0 | Posisi terakhir video |
| `completed_at` | TIMESTAMPTZ | NULL | Waktu selesai |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu pembuatan |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

**Constraint:**
- UNIQUE (`user_id`, `lesson_id`).
- `CHECK (last_position_seconds >= 0)`.
- `CHECK (NOT is_completed OR completed_at IS NOT NULL)`.

## 10.3 `course_progress`

Mencatat ringkasan progres pengguna pada course.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID progres |
| `user_id` | UUID | FK, NOT NULL | Pengguna |
| `course_id` | UUID | FK, NOT NULL | Course |
| `completed_lessons` | INTEGER | NOT NULL, DEFAULT 0 | Jumlah materi selesai |
| `total_lessons` | INTEGER | NOT NULL, DEFAULT 0 | Total materi |
| `progress_percentage` | NUMERIC(5,2) | NOT NULL, DEFAULT 0 | Persentase progres |
| `completed_at` | TIMESTAMPTZ | NULL | Waktu course selesai |
| `updated_at` | TIMESTAMPTZ | NOT NULL | Waktu pembaruan |

**Constraint:**
- UNIQUE (`user_id`, `course_id`).
- `CHECK (progress_percentage BETWEEN 0 AND 100)`.
- `CHECK (completed_lessons >= 0 AND total_lessons >= 0 AND completed_lessons <= total_lessons)`.

Tabel ini merupakan ringkasan dari `lesson_progress`, diperbarui dalam transaksi yang sama. `total_lessons` dihitung ulang saat lesson ditambah atau dihapus.

---

# 11. System & Audit

## 11.1 `audit_logs`

Mencatat aktivitas penting di dalam sistem. Tabel bersifat append-only.

| Kolom | Tipe Data | Constraint | Keterangan |
|---|---|---|---|
| `id` | UUID | PK | ID log |
| `user_id` | UUID | FK, NULL | Pengguna yang melakukan aktivitas; NULL untuk aktivitas sistem |
| `action` | VARCHAR(100) | NOT NULL | Nama aktivitas |
| `entity_type` | VARCHAR(100) | NULL | Jenis entitas |
| `entity_id` | UUID | NULL | ID entitas terkait |
| `metadata` | JSONB | NOT NULL, DEFAULT `'{}'` | Detail aktivitas, termasuk nilai sebelum/sesudah perubahan |
| `ip_address` | INET | NULL | Alamat IP |
| `user_agent` | TEXT | NULL | Informasi browser/client |
| `created_at` | TIMESTAMPTZ | NOT NULL | Waktu aktivitas |

---

# 12. Aksi Foreign Key (`ON DELETE`)

Prinsip: data konten turunan ikut terhapus bersama induknya (`CASCADE`), sedangkan data transaksi, akses, dan hasil ujian tidak boleh terhapus otomatis (`RESTRICT`).

| Tabel | Foreign key | Mengacu ke | ON DELETE |
|---|---|---|---|
| `user_roles` | `user_id` | `users` | CASCADE |
| `user_roles` | `role_id` | `roles` | RESTRICT |
| `user_oauth_accounts` | `user_id` | `users` | CASCADE |
| `refresh_tokens` | `user_id` | `users` | CASCADE |
| `email_verification_tokens` | `user_id` | `users` | CASCADE |
| `password_reset_tokens` | `user_id` | `users` | CASCADE |
| `products` | `created_by` | `users` | RESTRICT |
| `product_categories` | `product_id` | `products` | CASCADE |
| `product_categories` | `category_id` | `categories` | CASCADE |
| `courses` | `(product_id, product_type)` | `products` | CASCADE |
| `course_sections` | `course_id` | `courses` | CASCADE |
| `lessons` | `section_id` | `course_sections` | CASCADE |
| `exams` | `course_id` | `courses` | CASCADE |
| `exam_questions` | `exam_id` | `exams` | CASCADE |
| `exam_answer_options` | `question_id` | `exam_questions` | CASCADE |
| `exam_attempts` | `exam_id` | `exams` | RESTRICT |
| `exam_attempts` | `user_id` | `users` | RESTRICT |
| `exam_answers` | `attempt_id` | `exam_attempts` | RESTRICT |
| `exam_answers` | `question_id` | `exam_questions` | RESTRICT |
| `exam_answers` | `(question_id, selected_option_id)` | `exam_answer_options` | RESTRICT |
| `exam_answer_options_selected` | `(answer_id, question_id)` | `exam_answers` | RESTRICT |
| `exam_answer_options_selected` | `(question_id, option_id)` | `exam_answer_options` | RESTRICT |
| `certificates` | `user_id` | `users` | RESTRICT |
| `certificates` | `course_id` | `courses` | RESTRICT |
| `certificates` | `template_id` | `certificate_templates` | RESTRICT |
| `source_code_details` | `(product_id, product_type)` | `products` | CASCADE |
| `source_code_versions` | `source_code_id` | `source_code_details` | CASCADE |
| `product_files` | `product_id` | `products` | CASCADE |
| `product_files` | `source_code_version_id` | `source_code_versions` | CASCADE |
| `orders` | `user_id` | `users` | RESTRICT |
| `order_items` | `order_id` | `orders` | RESTRICT |
| `order_items` | `product_id` | `products` | RESTRICT |
| `payments` | `order_id` | `orders` | RESTRICT |
| `payment_events` | `payment_id` | `payments` | RESTRICT |
| `refunds` | `(payment_id, order_id)` | `payments` | RESTRICT |
| `refunds` | `(order_id, user_id)` | `orders` | RESTRICT |
| `refund_events` | `refund_id` | `refunds` | RESTRICT |
| `entitlements` | `user_id` | `users` | RESTRICT |
| `entitlements` | `(order_item_id, product_id)` | `order_items` | RESTRICT |
| `lesson_progress` | `user_id` | `users` | CASCADE |
| `lesson_progress` | `lesson_id` | `lessons` | CASCADE |
| `course_progress` | `user_id` | `users` | CASCADE |
| `course_progress` | `course_id` | `courses` | CASCADE |
| `audit_logs` | `user_id` | `users` | SET NULL |

Catatan: produk yang sudah memiliki order tidak dapat dihapus karena `order_items.product_id` bersifat `RESTRICT`; gunakan status `archived`. Penghapusan course, ujian, atau lesson yang sudah memiliki attempt atau sertifikat juga akan ditolak oleh `RESTRICT` pada tabel hasil.

---

# 13. Rekomendasi Index Database

Index dibuat untuk mempercepat query yang sering digunakan. Index untuk constraint UNIQUE dan PRIMARY KEY sudah otomatis dibuat PostgreSQL, sedangkan foreign key tidak otomatis mendapat index.

## 13.1 Index unik

| Tabel | Kolom | Jenis Index | Tujuan |
|---|---|---|---|
| `users` | `email` | UNIQUE | Login dan pencarian pengguna |
| `roles` | `name` | UNIQUE | Pencarian role |
| `user_oauth_accounts` | `provider`, `provider_user_id` | UNIQUE | Identifikasi akun OAuth |
| `refresh_tokens` | `token_hash` | UNIQUE | Validasi token |
| `email_verification_tokens` | `token_hash` | UNIQUE | Validasi token |
| `password_reset_tokens` | `token_hash` | UNIQUE | Validasi token |
| `products` | `slug` | UNIQUE | Pencarian produk berdasarkan URL |
| `products` | `id`, `product_type` | UNIQUE | Foreign key komposit tabel detail |
| `categories` | `slug` | UNIQUE | Pencarian kategori |
| `courses` | `product_id` | UNIQUE | Satu detail course per produk |
| `source_code_details` | `product_id` | UNIQUE | Satu detail source code per produk |
| `lessons` | `section_id`, `slug` | UNIQUE | Slug unik per section |
| `lesson_progress` | `user_id`, `lesson_id` | UNIQUE | Progres materi |
| `course_progress` | `user_id`, `course_id` | UNIQUE | Progres course |
| `exam_attempts` | `exam_id`, `user_id`, `attempt_number` | UNIQUE | Nomor percobaan |
| `exam_answers` | `attempt_id`, `question_id` | UNIQUE | Satu jawaban per pertanyaan |
| `certificates` | `certificate_number` | UNIQUE | Verifikasi sertifikat |
| `source_code_versions` | `source_code_id`, `version` | UNIQUE | Identifikasi versi |
| `product_files` | `storage_key` | UNIQUE | Lokasi file unik |
| `orders` | `order_number` | UNIQUE | Pencarian order |
| `order_items` | `order_id` | UNIQUE | Satu item per order |
| `refunds` | `refund_number` | UNIQUE | Pencarian refund |
| `entitlements` | `order_item_id` | UNIQUE | Satu entitlement per order item |

## 13.2 Partial unique index

| Tabel | Kolom | Kondisi | Tujuan |
|---|---|---|---|
| `entitlements` | `user_id`, `product_id` | `revoked_at IS NULL` | Satu entitlement aktif per user dan produk |
| `certificates` | `user_id`, `course_id` | `revoked_at IS NULL` | Satu sertifikat aktif per course |
| `source_code_versions` | `source_code_id` | `is_latest` | Satu versi latest |
| `product_files` | `source_code_version_id` | `is_primary AND source_code_version_id IS NOT NULL` | Satu file primary per versi |
| `product_files` | `product_id` | `is_primary AND source_code_version_id IS NULL` | Satu file primary per course |
| `exam_attempts` | `exam_id`, `user_id` | `status = 'in_progress'` | Satu attempt berjalan |
| `payments` | `order_id` | `status IN ('paid', 'partially_refunded', 'refunded')` | Satu pembayaran berhasil per order |
| `payments` | `provider`, `provider_reference` | `provider_reference IS NOT NULL` | Referensi provider unik |
| `payment_events` | `provider`, `provider_event_id` | `provider_event_id IS NOT NULL` | Idempotensi webhook payment |
| `refund_events` | `refund_id`, `provider_event_id` | `provider_event_id IS NOT NULL` | Idempotensi webhook refund |

## 13.3 Index pencarian dan foreign key

| Tabel | Kolom | Jenis Index | Tujuan |
|---|---|---|---|
| `products` | `product_type`, `status` | B-tree | Filter katalog |
| `products` | `created_by` | B-tree | Produk milik author |
| `product_categories` | `category_id` | B-tree | Produk berdasarkan kategori |
| `user_roles` | `role_id` | B-tree | Pengguna berdasarkan role |
| `user_oauth_accounts` | `user_id` | B-tree | Akun OAuth milik pengguna |
| `refresh_tokens` | `user_id` | B-tree | Sesi milik pengguna |
| `course_sections` | `course_id`, `position` | B-tree (via UNIQUE) | Urutan section |
| `lessons` | `section_id`, `position` | B-tree (via UNIQUE) | Urutan materi |
| `lesson_progress` | `lesson_id` | B-tree | Progres per materi |
| `course_progress` | `course_id` | B-tree | Progres per course |
| `exams` | `course_id` | B-tree | Ujian milik course |
| `exam_attempts` | `user_id`, `exam_id` | B-tree | Riwayat ujian |
| `exam_answers` | `question_id` | B-tree | Jawaban per pertanyaan |
| `certificates` | `course_id` | B-tree | Sertifikat per course |
| `orders` | `user_id`, `created_at` | B-tree | Riwayat transaksi |
| `orders` | `status`, `expires_at` | B-tree | Pembersihan order kedaluwarsa |
| `order_items` | `product_id` | B-tree | Penjualan per produk |
| `payments` | `order_id`, `status` | B-tree | Status pembayaran |
| `payment_events` | `payment_id` | B-tree | Event per pembayaran |
| `refunds` | `payment_id` | B-tree | Refund per pembayaran |
| `refunds` | `order_id` | B-tree | Refund per order |
| `refund_events` | `refund_id` | B-tree | Event per refund |
| `entitlements` | `product_id` | B-tree | Pengguna yang memiliki produk |
| `audit_logs` | `user_id`, `created_at` | B-tree | Audit aktivitas |
| `audit_logs` | `entity_type`, `entity_id` | B-tree | Riwayat per entitas |

Index tambahan dapat ditentukan berdasarkan hasil pengukuran query setelah aplikasi berjalan.

---

# 14. Aturan Integritas Data

Beberapa aturan penting yang harus diterapkan pada tingkat database maupun aplikasi:

1. Email pengguna harus unik dan dinormalisasi.
2. Setiap pengguna dapat memiliki lebih dari satu role.
3. Setiap produk harus memiliki satu jenis produk yang valid.
4. Produk course hanya memiliki detail course; produk source code hanya memiliki detail source code (dijaga foreign key komposit).
5. Satu order hanya boleh memiliki satu order item dengan quantity 1.
6. Harga transaksi harus disimpan sebagai snapshot agar perubahan harga produk tidak mengubah riwayat transaksi.
7. Satu produk hanya memberikan satu entitlement aktif untuk pengguna yang sama.
8. Entitlement bersifat permanen: tidak ada kolom kedaluwarsa, dan akses hanya berakhir jika `revoked_at` terisi.
9. Pembayaran harus mendukung lebih dari satu percobaan pembayaran, tetapi hanya satu yang berhasil per order.
10. Webhook pembayaran dan refund harus idempotent.
11. Refund yang belum berhasil tidak otomatis mencabut entitlement.
12. File source code disimpan di storage eksternal, bukan di database.
13. Data jawaban dan nilai ujian harus tetap konsisten dengan percobaan ujian yang telah dikumpulkan; pertanyaan dan pilihan yang sudah dijawab tidak dapat dihapus.
14. Sertifikat harus memiliki nomor unik dan dapat diverifikasi.
15. Semua perubahan status order, payment, dan refund yang memengaruhi entitlement dilakukan dalam satu database transaction.

---

# 15. Hal yang Masih Perlu Diputuskan

Sebelum migration SQL dibuat, beberapa detail masih perlu disepakati.

| No. | Keputusan | Status |
|---|---|---|
| 1 | Syarat penerbitan sertifikat (lulus ujian atau cukup menyelesaikan materi) | Belum diputuskan |
| 2 | Kebijakan refund, batas waktunya, dan kondisi pencabutan entitlement | Belum diputuskan |
| 3 | Bank soal untuk ujian | Belum diputuskan |
| 4 | Batas jumlah unduhan source code | Belum diputuskan |
| 5 | Apakah sistem menggunakan kupon diskon (`orders.discount_amount` sudah dicadangkan) | Belum diputuskan |
| 6 | Aturan penghapusan dan retensi data | Belum diputuskan |
| 7 | Apakah admin dapat memberikan entitlement tanpa order | Belum diputuskan |

Keputusan yang sudah ditetapkan di blueprint v1.2: ujian mendukung pilihan ganda multi-jawaban (`exam_answer_options_selected`), satu versi source code dapat memiliki beberapa file unduhan, update source code gratis, serta pengacakan soal dan pilihan jawaban didukung.

---

## 16. Status Dokumen

Dokumen ini merupakan rancangan data dictionary yang menjadi acuan implementasi database Nekadaja.

Perubahan struktur tabel, tipe data, constraint, atau relasi harus diperbarui pada dokumen ini serta diselaraskan dengan `database-blueprint.md` dan `database-erd.md`.

**Tahap berikutnya:** Database Schema Design dan SQL Migration menggunakan PostgreSQL dan golang-migrate.
