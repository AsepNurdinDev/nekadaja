# Nekadaja — Database Blueprint

**Version:** 1.2  
**Status:** Revised Draft  
**Database:** PostgreSQL  
**Architecture:** Modular Monolith  
**Backend:** Go + Gin + pgx + sqlc

---

## 1. Project Overview

Nekadaja merupakan platform digital yang menggabungkan Learning Management System (LMS) dan marketplace source code.

Platform menyediakan dua jenis produk utama:

1. **Course:** Produk pembelajaran digital yang terdiri dari section, lesson, materi, ujian, dan sertifikat.
2. **Source Code:** Produk digital berupa source code aplikasi, template, starter kit, dan aset pengembangan perangkat lunak.

Kedua jenis produk menggunakan satu sistem katalog, transaksi, pembayaran, dan entitlement.

Platform menggunakan sistem seller internal. Author dan Admin bertanggung jawab mengelola produk, bukan seller independen.

## 2. Confirmed Business Rules

### 2.1 User & Role

Terdapat tiga role utama:

- Admin: Mengelola seluruh sistem.
- Author: Mengelola course dan source code.
- Student: Membeli dan mengakses produk.

Satu pengguna dapat memiliki lebih dari satu role.

### 2.2 Product

Terdapat dua jenis produk:

- `course`
- `source_code`

Setiap produk memiliki judul, slug, deskripsi, thumbnail, kategori, harga, status publikasi, dan pembuat.

### 2.3 Pricing

Platform mendukung tiga model harga:

| Pricing Type | Aturan |
|---|---|
| Free | Produk dapat diperoleh tanpa pembayaran |
| Fixed | Harga ditentukan platform |
| PWYW | Pengguna menentukan harga dengan minimum wajib |

Mata uang awal adalah IDR.

Semua nilai uang disimpan menggunakan BIGINT dalam satuan terkecil mata uang. Untuk IDR, satuan tersebut adalah rupiah (tanpa desimal).

Harga pada transaksi harus menjadi snapshot sehingga perubahan harga produk tidak mengubah histori transaksi.

### 2.4 Order

- Satu order hanya dapat berisi satu produk, dengan quantity selalu 1.
- Satu pengguna dapat memiliki banyak order.
- Order menyimpan snapshot informasi produk dan harga.
- Order gratis tidak membutuhkan payment gateway. Order gratis dibuat dengan `total_amount = 0`, langsung berstatus `paid`, dan tidak memiliki record `payments`.
- Produk yang sudah dimiliki tidak dapat dibeli kembali selama entitlement masih aktif, kecuali terdapat kebijakan khusus.

### 2.5 Access Rights

- Hak akses produk bersifat permanen.
- Hak akses diberikan setelah pembayaran berhasil atau proses klaim produk gratis berhasil.
- Pengguna yang telah memiliki entitlement tidak perlu membeli produk yang sama kembali.
- Hak akses tidak memiliki tanggal kedaluwarsa.
- Pengguna tetap berhak mengakses update versi source code (update bersifat gratis).
- Pencabutan akses hanya dilakukan berdasarkan kebijakan administratif atau hasil proses refund yang memenuhi ketentuan.

### 2.6 Course

Course mendukung:

- Section dan lesson.
- Materi text, video, dan mixed.
- Ujian atau assessment.
- Exam attempts dan penilaian.
- Sertifikat penyelesaian course.

### 2.7 Source Code

Source code mendukung:

- Informasi teknologi dan framework.
- Dokumentasi dan panduan instalasi.
- Versioning.
- File download per versi (satu versi dapat memiliki lebih dari satu file).
- Riwayat perubahan versi.

### 2.8 Payment & Refund

- Payment gateway dapat menggunakan lebih dari satu provider.
- Pembayaran diverifikasi melalui webhook.
- Webhook harus diproses secara idempotent.
- Refund memiliki proses pengajuan dan pencatatan tersendiri.
- Refund tidak menghapus histori order dan payment.

### 2.9 Authentication

Metode autentikasi:

- Email dan password.
- Google OAuth.

Satu akun dapat menghubungkan beberapa identitas OAuth.

---

## 3. Database Domains

Database dibagi menjadi sepuluh domain:

1. Identity & Access Management
2. Product Catalog
3. Course Management
4. Examination Management
5. Certificate Management
6. Source Code Management
7. Order Management
8. Payment & Refund Management
9. Entitlement & Learning Progress
10. System & Audit

### 3.1 Konvensi Penulisan Tabel

- Kolom tanpa tanda `NULL` bersifat `NOT NULL`.
- Primary key bertipe UUID dengan default `gen_random_uuid()` (atau UUID yang dibuat aplikasi).
- Kolom `created_at` dan `updated_at` memiliki default `now()`. `updated_at` diperbarui oleh aplikasi atau trigger.
- Detail tipe, constraint, dan index lengkap ada di `database-dictionary.md`. Diagram relasi ada di `database-erd.md`.

---

## 4. Table Design

### 4.1 Identity & Access Management

#### `users`

Menyimpan informasi akun pengguna.

| Column | Type |
|---|---|
| id | UUID |
| name | VARCHAR(150) |
| email | VARCHAR(255) |
| password_hash | TEXT NULL |
| avatar_url | TEXT NULL |
| status | VARCHAR(30) |
| email_verified_at | TIMESTAMPTZ NULL |
| created_at | TIMESTAMPTZ |
| updated_at | TIMESTAMPTZ |

Email harus unik dan dinormalisasi (huruf kecil dan tanpa spasi di awal/akhir) sebelum disimpan. Normalisasi dijaga dengan CHECK constraint.

`password_hash` dapat NULL untuk akun yang hanya menggunakan OAuth.

`email_verified_at` NULL berarti email belum diverifikasi.

Status:

- active
- inactive
- suspended

#### `roles`

| Column | Type |
|---|---|
| id | UUID |
| name | VARCHAR(50) |
| description | TEXT NULL |
| created_at | TIMESTAMPTZ |

`name` harus unik. Data awal: `admin`, `author`, `student`.

#### `user_roles`

| Column | Type |
|---|---|
| user_id | UUID |
| role_id | UUID |
| assigned_at | TIMESTAMPTZ |

Primary key: `(user_id, role_id)`.

#### `user_oauth_accounts`

Menyimpan identitas akun eksternal.

| Column | Type |
|---|---|
| id | UUID |
| user_id | UUID |
| provider | VARCHAR(50) |
| provider_user_id | VARCHAR(255) |
| provider_email | VARCHAR(255) NULL |
| created_at | TIMESTAMPTZ |
| updated_at | TIMESTAMPTZ |

Unique constraint:

- `(provider, provider_user_id)`

Provider awal: `google`.

Jangan menyimpan access token atau refresh token OAuth jika tidak dibutuhkan untuk kebutuhan integrasi lanjutan.

#### `refresh_tokens`

| Column | Type |
|---|---|
| id | UUID |
| user_id | UUID |
| token_hash | TEXT |
| expires_at | TIMESTAMPTZ |
| revoked_at | TIMESTAMPTZ NULL |
| created_at | TIMESTAMPTZ |

`token_hash` harus unik.

#### `email_verification_tokens`

| Column | Type |
|---|---|
| id | UUID |
| user_id | UUID |
| token_hash | TEXT |
| expires_at | TIMESTAMPTZ |
| used_at | TIMESTAMPTZ NULL |
| created_at | TIMESTAMPTZ |

`token_hash` harus unik.

#### `password_reset_tokens`

| Column | Type |
|---|---|
| id | UUID |
| user_id | UUID |
| token_hash | TEXT |
| expires_at | TIMESTAMPTZ |
| used_at | TIMESTAMPTZ NULL |
| created_at | TIMESTAMPTZ |

`token_hash` harus unik.

---

### 4.2 Product Catalog

#### `products`

Tabel utama seluruh produk.

| Column | Type |
|---|---|
| id | UUID |
| product_type | VARCHAR(30) |
| title | VARCHAR(255) |
| slug | VARCHAR(255) |
| description | TEXT NULL |
| thumbnail_url | TEXT NULL |
| pricing_type | VARCHAR(30) |
| price_amount | BIGINT |
| minimum_amount | BIGINT |
| currency | CHAR(3) |
| status | VARCHAR(30) |
| created_by | UUID |
| published_at | TIMESTAMPTZ NULL |
| created_at | TIMESTAMPTZ |
| updated_at | TIMESTAMPTZ |

`price_amount` dan `minimum_amount` bernilai `NOT NULL DEFAULT 0`. `currency` default `IDR`.

Constraint:

- `product_type`: course atau source_code.
- `pricing_type`: free, fixed, atau pwyw.
- `status`: draft, published, atau archived.
- Free: `price_amount = 0` dan `minimum_amount = 0`.
- Fixed: `price_amount > 0` dan `minimum_amount = 0`.
- PWYW: `minimum_amount > 0`; `price_amount` adalah harga yang disarankan, bernilai 0 (tidak ada saran) atau minimal sama dengan `minimum_amount`.
- Produk berstatus `published` wajib memiliki `published_at`.
- `UNIQUE (id, product_type)` disediakan agar tabel detail produk dapat memvalidasi tipe produk melalui foreign key (lihat bagian 6).

Produk yang sudah dipublikasikan tidak boleh mengubah histori transaksi sebelumnya.

Produk yang pernah terjual tidak dihapus secara fisik; gunakan status `archived`.

#### `categories`

| Column | Type |
|---|---|
| id | UUID |
| name | VARCHAR(100) |
| slug | VARCHAR(120) |
| description | TEXT NULL |
| created_at | TIMESTAMPTZ |
| updated_at | TIMESTAMPTZ |

`slug` harus unik. Kategori bertingkat tidak termasuk dalam desain saat ini.

#### `product_categories`

| Column | Type |
|---|---|
| product_id | UUID |
| category_id | UUID |

Primary key: `(product_id, category_id)`.

---

### 4.3 Course Management

#### `courses`

| Column | Type |
|---|---|
| id | UUID |
| product_id | UUID |
| product_type | VARCHAR(30) |
| level | VARCHAR(30) NULL |
| language | VARCHAR(10) |
| estimated_duration_minutes | INTEGER NULL |
| requirements | JSONB |
| learning_outcomes | JSONB |
| created_at | TIMESTAMPTZ |
| updated_at | TIMESTAMPTZ |

`product_id` harus unik dan mengacu pada produk bertipe course.

`product_type` bernilai tetap `course` (CHECK) dan bersama `product_id` menjadi foreign key komposit ke `products (id, product_type)`.

`requirements` dan `learning_outcomes` bertipe JSONB array, default `[]`.

#### `course_sections`

| Column | Type |
|---|---|
| id | UUID |
| course_id | UUID |
| title | VARCHAR(255) |
| description | TEXT NULL |
| position | INTEGER |
| created_at | TIMESTAMPTZ |
| updated_at | TIMESTAMPTZ |

Unique constraint: `(course_id, position)` (deferrable agar urutan dapat ditukar dalam satu transaksi).

#### `lessons`

| Column | Type |
|---|---|
| id | UUID |
| section_id | UUID |
| title | VARCHAR(255) |
| slug | VARCHAR(255) |
| content | TEXT NULL |
| lesson_type | VARCHAR(30) |
| video_url | TEXT NULL |
| duration_seconds | INTEGER NULL |
| is_preview | BOOLEAN |
| position | INTEGER |
| status | VARCHAR(30) |
| created_at | TIMESTAMPTZ |
| updated_at | TIMESTAMPTZ |

Lesson type:

- text
- video
- mixed

Status:

- draft
- published

Unique constraint: `(section_id, slug)` dan `(section_id, position)` (deferrable).

Lesson `video` atau `mixed` yang berstatus `published` wajib memiliki `video_url`.

`duration_seconds` menggunakan satuan detik agar konsisten dengan `lesson_progress.last_position_seconds`.

---

### 4.4 Examination Management

#### `exams`

Menyimpan konfigurasi ujian dalam course.

| Column | Type |
|---|---|
| id | UUID |
| course_id | UUID |
| title | VARCHAR(255) |
| description | TEXT NULL |
| duration_minutes | INTEGER |
| passing_score | NUMERIC(5,2) |
| max_attempts | INTEGER NULL |
| shuffle_questions | BOOLEAN |
| shuffle_options | BOOLEAN |
| status | VARCHAR(30) |
| created_at | TIMESTAMPTZ |
| updated_at | TIMESTAMPTZ |

`max_attempts = NULL` berarti percobaan tidak dibatasi; jika terisi harus lebih dari 0.

`passing_score` adalah persentase 0–100.

`duration_minutes` harus lebih dari 0.

Status:

- draft
- published
- archived

#### `exam_questions`

| Column | Type |
|---|---|
| id | UUID |
| exam_id | UUID |
| question_text | TEXT |
| question_type | VARCHAR(30) |
| image_url | TEXT NULL |
| points | NUMERIC(8,2) |
| explanation | TEXT NULL |
| position | INTEGER |
| created_at | TIMESTAMPTZ |
| updated_at | TIMESTAMPTZ |

Question type awal:

- single_choice
- multiple_choice
- true_false

`points` harus lebih dari 0 (default 1). Unique constraint: `(exam_id, position)` (deferrable).

#### `exam_answer_options`

| Column | Type |
|---|---|
| id | UUID |
| question_id | UUID |
| option_text | TEXT NULL |
| image_url | TEXT NULL |
| is_correct | BOOLEAN |
| position | INTEGER |

Setiap pilihan wajib memiliki `option_text` atau `image_url`.

Unique constraint: `(question_id, position)` (deferrable) dan `(question_id, id)` (untuk foreign key komposit dari jawaban).

Aturan jumlah jawaban benar (divalidasi aplikasi saat ujian dipublikasikan):

- `single_choice` dan `true_false`: tepat satu pilihan benar.
- `multiple_choice`: minimal satu pilihan benar.

Jawaban benar tidak boleh dikirimkan ke frontend sebelum ujian diselesaikan.

#### `exam_attempts`

| Column | Type |
|---|---|
| id | UUID |
| exam_id | UUID |
| user_id | UUID |
| attempt_number | INTEGER |
| started_at | TIMESTAMPTZ |
| submitted_at | TIMESTAMPTZ NULL |
| score | NUMERIC(5,2) NULL |
| is_passed | BOOLEAN NULL |
| status | VARCHAR(30) |
| created_at | TIMESTAMPTZ |

Status:

- in_progress
- submitted
- graded
- expired

`score` adalah persentase 0–100 (skala yang sama dengan `exams.passing_score`). `is_passed` disimpan sebagai snapshot saat penilaian sehingga perubahan `passing_score` di kemudian hari tidak mengubah hasil lama.

Unique constraint: `(exam_id, user_id, attempt_number)`.

Hanya satu attempt `in_progress` yang boleh ada untuk kombinasi `(exam_id, user_id)` (partial unique index).

#### `exam_answers`

| Column | Type |
|---|---|
| id | UUID |
| attempt_id | UUID |
| question_id | UUID |
| selected_option_id | UUID NULL |
| is_correct | BOOLEAN NULL |
| earned_points | NUMERIC(8,2) |
| created_at | TIMESTAMPTZ |
| updated_at | TIMESTAMPTZ |

Unique constraint: `(attempt_id, question_id)`; `(id, question_id)` (untuk foreign key komposit dari `exam_answer_options_selected`).

`selected_option_id` dipakai untuk `single_choice` dan `true_false`, dan harus merupakan pilihan dari pertanyaan yang sama (foreign key komposit `(question_id, selected_option_id)` ke `exam_answer_options (question_id, id)`).

Untuk `multiple_choice`, `selected_option_id` bernilai NULL dan pilihan disimpan di `exam_answer_options_selected`.

Karena tipe pertanyaan awal hanya pilihan, kolom jawaban teks bebas tidak disediakan. Kolom tersebut ditambahkan lewat migration ketika tipe pertanyaan berbasis teks (misalnya essay) dibuat.

#### `exam_answer_options_selected`

Menghubungkan jawaban pertanyaan `multiple_choice` dengan pilihan yang dipilih peserta.

| Column | Type |
|---|---|
| answer_id | UUID |
| question_id | UUID |
| option_id | UUID |

Primary key: `(answer_id, option_id)`.

Foreign key komposit `(answer_id, question_id)` ke `exam_answers (id, question_id)` dan `(question_id, option_id)` ke `exam_answer_options (question_id, id)` memastikan pilihan yang dipilih berasal dari pertanyaan yang dijawab.

Jawaban dan skor yang sudah tersimpan harus tetap konsisten. Pertanyaan dan pilihan yang sudah dijawab tidak boleh dihapus (foreign key `RESTRICT`), dan perubahan pada ujian yang sudah memiliki attempt harus diblokir atau dibuat sebagai ujian baru.

---

### 4.5 Certificate Management

#### `certificate_templates`

Menyimpan template sertifikat.

| Column | Type |
|---|---|
| id | UUID |
| name | VARCHAR(150) |
| template_file_url | TEXT |
| configuration | JSONB |
| is_active | BOOLEAN |
| created_at | TIMESTAMPTZ |
| updated_at | TIMESTAMPTZ |

Template bersifat global dan dapat dipakai oleh banyak course.

#### `certificates`

Menyimpan sertifikat yang diterbitkan.

| Column | Type |
|---|---|
| id | UUID |
| user_id | UUID |
| course_id | UUID |
| template_id | UUID |
| certificate_number | VARCHAR(100) |
| file_url | TEXT NULL |
| issued_at | TIMESTAMPTZ |
| revoked_at | TIMESTAMPTZ NULL |
| created_at | TIMESTAMPTZ |

Unique constraint:

- `certificate_number`
- `(user_id, course_id)` hanya untuk sertifikat yang belum dicabut (partial unique index `WHERE revoked_at IS NULL`), sehingga satu sertifikat aktif per course dan sertifikat yang telah dicabut tetap dapat diterbitkan ulang.

Sertifikat hanya diterbitkan setelah persyaratan penyelesaian course terpenuhi.

---

### 4.6 Source Code Management

#### `source_code_details`

| Column | Type |
|---|---|
| id | UUID |
| product_id | UUID |
| product_type | VARCHAR(30) |
| programming_language | VARCHAR(100) NULL |
| framework | VARCHAR(100) NULL |
| documentation | TEXT NULL |
| installation_guide | TEXT NULL |
| created_at | TIMESTAMPTZ |
| updated_at | TIMESTAMPTZ |

`product_id` harus unik dan mengacu pada produk bertipe source_code.

`product_type` bernilai tetap `source_code` (CHECK) dan bersama `product_id` menjadi foreign key komposit ke `products (id, product_type)`.

#### `source_code_versions`

Menyimpan versi source code.

| Column | Type |
|---|---|
| id | UUID |
| source_code_id | UUID |
| version | VARCHAR(50) |
| changelog | TEXT NULL |
| release_notes | TEXT NULL |
| is_latest | BOOLEAN |
| released_at | TIMESTAMPTZ |
| created_at | TIMESTAMPTZ |

`source_code_id` mengacu pada `source_code_details.id`.

Unique constraint: `(source_code_id, version)`.

Hanya satu versi yang boleh menjadi latest untuk setiap source code (partial unique index `WHERE is_latest`). Saat berpindah versi latest, nonaktifkan versi lama terlebih dahulu dalam transaksi yang sama.

#### `product_files`

Menyimpan file digital produk.

| Column | Type |
|---|---|
| id | UUID |
| product_id | UUID |
| source_code_version_id | UUID NULL |
| file_name | VARCHAR(255) |
| storage_key | TEXT |
| mime_type | VARCHAR(150) |
| file_size | BIGINT |
| checksum | VARCHAR(128) NULL |
| is_primary | BOOLEAN |
| created_at | TIMESTAMPTZ |

Untuk file course, `source_code_version_id` bernilai NULL. Untuk file source code, kolom tersebut mengacu pada versi terkait.

`storage_key` harus unik. `file_size` tidak boleh negatif.

Satu versi (atau satu course) dapat memiliki beberapa file, tetapi hanya satu file `is_primary` untuk setiap versi (atau untuk setiap course tanpa versi), dijaga dengan partial unique index.

Kesesuaian `product_id` dengan produk pemilik versi dijaga oleh aplikasi atau trigger, karena melibatkan tiga tabel.

File disimpan di object storage atau file storage, bukan langsung di PostgreSQL.

---

### 4.7 Order Management

#### `orders`

| Column | Type |
|---|---|
| id | UUID |
| order_number | VARCHAR(50) |
| user_id | UUID |
| subtotal_amount | BIGINT |
| discount_amount | BIGINT |
| total_amount | BIGINT |
| currency | CHAR(3) |
| status | VARCHAR(30) |
| paid_at | TIMESTAMPTZ NULL |
| expires_at | TIMESTAMPTZ NULL |
| created_at | TIMESTAMPTZ |
| updated_at | TIMESTAMPTZ |

Status:

- pending_payment
- paid
- cancelled
- expired
- partially_refunded
- refunded

Constraint:

- `order_number` unik.
- Semua nominal tidak boleh negatif.
- `discount_amount <= subtotal_amount` dan `total_amount = subtotal_amount - discount_amount`.
- `paid_at` wajib terisi untuk status `paid`, `partially_refunded`, dan `refunded`.

`discount_amount` default 0 dan dicadangkan untuk sistem kupon/diskon (belum diputuskan, lihat bagian 10).

`expires_at` dipakai untuk order `pending_payment`. Order gratis tidak memiliki `expires_at`.

#### `order_items`

| Column | Type |
|---|---|
| id | UUID |
| order_id | UUID |
| product_id | UUID |
| product_title | VARCHAR(255) |
| product_type | VARCHAR(30) |
| unit_price | BIGINT |
| quantity | INTEGER |
| subtotal_amount | BIGINT |
| created_at | TIMESTAMPTZ |

Unique constraint: `order_id`.

Dengan demikian, satu order hanya dapat memiliki satu produk.

`quantity` selalu 1 (CHECK) dan `subtotal_amount = unit_price * quantity`.

`unit_price` menyimpan harga transaksi, termasuk harga yang dipilih pengguna pada model PWYW. Untuk PWYW, aplikasi memastikan `unit_price >= products.minimum_amount` saat order dibuat.

`UNIQUE (id, product_id)` disediakan agar `entitlements` dapat memvalidasi produk melalui foreign key komposit.

---

### 4.8 Payment & Refund Management

#### `payments`

| Column | Type |
|---|---|
| id | UUID |
| order_id | UUID |
| provider | VARCHAR(50) |
| provider_reference | VARCHAR(255) NULL |
| payment_method | VARCHAR(50) NULL |
| amount | BIGINT |
| currency | CHAR(3) |
| status | VARCHAR(30) |
| paid_at | TIMESTAMPTZ NULL |
| expired_at | TIMESTAMPTZ NULL |
| raw_response | JSONB NULL |
| created_at | TIMESTAMPTZ |
| updated_at | TIMESTAMPTZ |

Status:

- pending
- paid
- failed
- expired
- cancelled
- refunded
- partially_refunded

Satu order dapat memiliki lebih dari satu record payment jika pengguna melakukan percobaan pembayaran ulang. Namun, total pembayaran yang berhasil tidak boleh melebihi jumlah yang harus dibayar.

Aturan ini dijaga dengan:

- Partial unique index `(order_id) WHERE status IN ('paid', 'partially_refunded', 'refunded')`, sehingga hanya satu pembayaran berhasil per order.
- `amount > 0` (order gratis tidak memiliki payment) dan kesesuaian `amount` dengan `orders.total_amount` divalidasi aplikasi dalam transaksi.
- `paid_at` wajib terisi untuk status `paid`, `partially_refunded`, dan `refunded`.
- `UNIQUE (provider, provider_reference)` jika `provider_reference` tidak NULL.
- `UNIQUE (id, order_id)` disediakan untuk foreign key komposit dari `refunds`.

#### `payment_events`

| Column | Type |
|---|---|
| id | UUID |
| payment_id | UUID |
| provider | VARCHAR(50) |
| provider_event_id | VARCHAR(255) NULL |
| event_type | VARCHAR(100) |
| payload | JSONB |
| processed_at | TIMESTAMPTZ NULL |
| created_at | TIMESTAMPTZ |

Event ID harus unik per provider jika provider menyediakannya: `UNIQUE (provider, provider_event_id)` untuk baris yang `provider_event_id`-nya tidak NULL.

Jika provider tidak menyediakan event ID, aplikasi menurunkan kunci idempotensi yang deterministik (misalnya dari referensi transaksi dan status) dan menyimpannya di `provider_event_id`.

`processed_at` NULL berarti event belum selesai diproses.

#### `refunds`

Menyimpan pengajuan dan hasil refund.

| Column | Type |
|---|---|
| id | UUID |
| payment_id | UUID |
| order_id | UUID |
| user_id | UUID |
| refund_number | VARCHAR(100) |
| amount | BIGINT |
| reason | TEXT NULL |
| status | VARCHAR(30) |
| provider_reference | VARCHAR(255) NULL |
| requested_at | TIMESTAMPTZ |
| processed_at | TIMESTAMPTZ NULL |
| created_at | TIMESTAMPTZ |
| updated_at | TIMESTAMPTZ |

Status:

- requested
- approved
- rejected
- processing
- succeeded
- failed

Constraint:

- `refund_number` unik.
- `amount > 0`.
- Foreign key komposit `(payment_id, order_id)` ke `payments (id, order_id)` dan `(order_id, user_id)` ke `orders (id, user_id)` menjaga `order_id` dan `user_id` tetap konsisten dengan payment.
- Total refund aktif dan berhasil untuk satu payment tidak boleh melebihi `payments.amount`; divalidasi aplikasi dalam transaksi dengan row lock pada payment.

`UNIQUE (id, user_id)` pada `orders` disediakan untuk foreign key komposit di atas.

#### `refund_events`

Mencatat setiap perubahan dan event refund.

| Column | Type |
|---|---|
| id | UUID |
| refund_id | UUID |
| provider_event_id | VARCHAR(255) NULL |
| event_type | VARCHAR(100) |
| payload | JSONB |
| created_at | TIMESTAMPTZ |

`UNIQUE (refund_id, provider_event_id)` untuk baris yang `provider_event_id`-nya tidak NULL, agar webhook refund yang dikirim ulang tidak tercatat ganda.

Refund harus diproses melalui workflow yang terkontrol. Persetujuan refund tidak otomatis berarti uang sudah berhasil dikembalikan.

---

### 4.9 Entitlement & Learning Progress

#### `entitlements`

Menyimpan hak akses permanen pengguna.

| Column | Type |
|---|---|
| id | UUID |
| user_id | UUID |
| product_id | UUID |
| order_item_id | UUID |
| granted_at | TIMESTAMPTZ |
| revoked_at | TIMESTAMPTZ NULL |
| revoked_reason | TEXT NULL |
| created_at | TIMESTAMPTZ |

Satu entitlement aktif untuk setiap kombinasi user dan product.

Gunakan partial unique index `(user_id, product_id) WHERE revoked_at IS NULL` untuk mencegah entitlement aktif ganda. Setelah entitlement dicabut, pengguna dapat membeli atau mengklaim produk yang sama kembali.

Setiap entitlement berasal dari satu order item (termasuk order gratis), sehingga `order_item_id` wajib terisi dan unik. Foreign key komposit `(order_item_id, product_id)` ke `order_items (id, product_id)` memastikan produk entitlement sama dengan produk yang dipesan.

`revoked_reason` hanya boleh terisi jika `revoked_at` terisi.

Entitlement tetap berlaku selama tidak dicabut. Refund yang disetujui dan berhasil dapat memicu pencabutan sesuai kebijakan refund platform.

#### `lesson_progress`

| Column | Type |
|---|---|
| id | UUID |
| user_id | UUID |
| lesson_id | UUID |
| is_completed | BOOLEAN |
| last_position_seconds | INTEGER |
| completed_at | TIMESTAMPTZ NULL |
| created_at | TIMESTAMPTZ |
| updated_at | TIMESTAMPTZ |

Unique constraint: `(user_id, lesson_id)`.

`last_position_seconds` default 0 dan tidak boleh negatif. `completed_at` wajib terisi jika `is_completed = true`.

#### `course_progress`

| Column | Type |
|---|---|
| id | UUID |
| user_id | UUID |
| course_id | UUID |
| completed_lessons | INTEGER |
| total_lessons | INTEGER |
| progress_percentage | NUMERIC(5,2) |
| completed_at | TIMESTAMPTZ NULL |
| updated_at | TIMESTAMPTZ |

Unique constraint: `(user_id, course_id)`.

Constraint: `completed_lessons <= total_lessons` dan `progress_percentage` antara 0 dan 100.

Progres dapat dihitung dari lesson_progress. Tabel ini digunakan sebagai ringkasan yang diperbarui secara konsisten dalam transaksi yang sama dengan perubahan `lesson_progress`. `total_lessons` perlu dihitung ulang ketika lesson ditambah atau dihapus.

---

### 4.10 System & Audit

#### `audit_logs`

| Column | Type |
|---|---|
| id | UUID |
| user_id | UUID NULL |
| action | VARCHAR(100) |
| entity_type | VARCHAR(100) NULL |
| entity_id | UUID NULL |
| metadata | JSONB |
| ip_address | INET NULL |
| user_agent | TEXT NULL |
| created_at | TIMESTAMPTZ |

Digunakan untuk mencatat aktivitas penting, seperti perubahan role, publikasi produk, dan proses refund.

`user_id` NULL untuk aktivitas sistem atau aktivitas tanpa pengguna terautentikasi. `metadata` default `{}` dan dapat menyimpan nilai sebelum/sesudah perubahan (misalnya `{"old": {...}, "new": {...}}`).

Tabel ini bersifat append-only.

---

## 5. Main Database Relationships

### Identity

- users → user_roles → roles
- users → user_oauth_accounts
- users → refresh_tokens
- users → email_verification_tokens
- users → password_reset_tokens

### Product

- products → product_categories → categories
- users → products (created_by)
- products → courses
- products → source_code_details
- products → product_files

### Course

- courses → course_sections → lessons
- courses → exams → exam_questions → exam_answer_options
- exams → exam_attempts → exam_answers
- exam_answers → exam_answer_options_selected → exam_answer_options
- exam_answers → exam_questions
- users → exam_attempts

### Certificate

- courses → certificates
- users → certificates
- certificate_templates → certificates

### Source Code

- source_code_details → source_code_versions
- source_code_versions → product_files

### Commerce

- users → orders → order_items
- products → order_items
- orders → payments → payment_events
- payments → refunds → refund_events
- orders → refunds
- users → refunds

### Access & Learning

- users → entitlements → products
- order_items → entitlements
- users → lesson_progress → lessons
- users → course_progress → courses

### System

- users → audit_logs

---

## 6. Important Database Constraints

1. Email user harus unik dan dinormalisasi.
2. Provider OAuth dan provider_user_id harus unik.
3. Product slug harus unik.
4. Satu order hanya memiliki satu order item dengan quantity 1.
5. Satu user hanya memiliki satu entitlement aktif untuk satu product.
6. Satu course hanya memiliki satu detail course.
7. Satu source code hanya memiliki satu detail source code.
8. Versi source code unik untuk setiap source code.
9. Hanya satu versi source code yang boleh menjadi latest.
10. Satu user tidak boleh memiliki sertifikat aktif ganda untuk course yang sama.
11. Attempt number harus unik per user dan exam.
12. Lesson progress harus unik per user dan lesson.
13. Nilai harga, nominal order, dan nominal payment tidak boleh negatif; nominal refund harus lebih dari nol.
14. Hanya satu payment berhasil per order.
15. Event webhook payment unik per provider; event refund unik per refund.
16. Foreign key dan CHECK constraint harus digunakan untuk menjaga integritas data.

### Kesesuaian `product_type` dengan tabel detail

Kesesuaian `product_type` dengan tabel detail dijaga langsung di database tanpa trigger:

1. `products` memiliki `UNIQUE (id, product_type)`.
2. `courses` dan `source_code_details` memiliki kolom `product_type` dengan CHECK bernilai tetap (`'course'` dan `'source_code'`).
3. Keduanya memakai foreign key komposit `(product_id, product_type)` ke `products (id, product_type)`.

Dengan demikian, `courses` hanya dapat mengacu pada produk bertipe `course`, dan `source_code_details` hanya pada produk bertipe `source_code`. `products.product_type` tidak boleh diubah setelah detail produk dibuat (diblokir oleh foreign key komposit).

Validasi lintas tabel lain yang tidak dapat dinyatakan dengan constraint, seperti kesesuaian `product_files.product_id` dengan versi source code dan kesesuaian `user_id` pada entitlement dengan pemilik order, dijaga pada application service atau trigger yang dirancang secara eksplisit.

### Referential Action

- Data konten turunan dihapus bersama induknya (`ON DELETE CASCADE`): token milik user, section dan lesson dari course, pertanyaan dan pilihan dari ujian, `lesson_progress` dari lesson.
- Data transaksi, akses, dan hasil ujian tidak boleh terhapus otomatis (`ON DELETE RESTRICT`): `orders`, `order_items`, `payments`, `refunds`, `entitlements`, `exam_attempts`, `exam_answers`, `certificates`, serta produk yang pernah dipesan.
- `audit_logs.user_id` menggunakan `ON DELETE SET NULL`.

Daftar lengkap per foreign key ada di `database-dictionary.md`.

---

## 7. Transaction & Data Integrity

Operasi berikut harus menggunakan database transaction:

- Pembuatan order.
- Pemberian entitlement untuk produk gratis.
- Konfirmasi pembayaran dan pemberian entitlement.
- Pemrosesan refund dan pencabutan entitlement.
- Penyimpanan jawaban ujian dan penilaian.
- Penerbitan sertifikat.
- Perpindahan versi latest source code.
- Pembaruan `lesson_progress` bersama `course_progress`.

Webhook payment dan refund harus idempotent agar event yang dikirim berulang tidak menghasilkan transaksi ganda.

---

## 8. Security Standards

- Password disimpan dalam bentuk hash Argon2id.
- Refresh token dan token verifikasi disimpan sebagai hash.
- OAuth identity diidentifikasi berdasarkan provider dan provider user ID.
- File source code hanya dapat diunduh oleh pengguna yang memiliki entitlement aktif.
- Download menggunakan signed URL yang memiliki masa berlaku singkat.
- Credential payment gateway disimpan melalui environment atau secret management.
- Data webhook harus diverifikasi sebelum diproses.
- Jawaban benar ujian tidak boleh diekspos sebelum penilaian.
- Aktivitas administratif penting dicatat melalui audit_logs.

---

## 9. Development Priority

1. Identity & Access Management.
2. Product Catalog.
3. Course Management.
4. Source Code Management.
5. Order Management.
6. Payment Management.
7. Refund Management.
8. Entitlement Management.
9. Examination Management.
10. Certificate Management.
11. Learning Progress.
12. System & Audit.

---

## 10. Pending Decisions

Beberapa hal masih perlu diputuskan sebelum database implementation:

- Kebijakan detail refund (termasuk batas waktu) dan kondisi pencabutan entitlement.
- Apakah sertifikat membutuhkan kelulusan ujian atau cukup penyelesaian materi.
- Apakah ujian mendukung bank soal (pengacakan soal dan pilihan sudah didukung oleh `shuffle_questions` dan `shuffle_options`).
- Apakah terdapat sistem kupon dan diskon (kolom `discount_amount` sudah dicadangkan).
- Apakah source code memiliki batas jumlah download.
- Aturan penghapusan dan retensi data.
- Apakah admin dapat memberikan entitlement tanpa order (saat ini setiap entitlement wajib berasal dari order item).

---

## 11. Revision Notes

### v1.2

Perbaikan hasil audit terhadap v1.1 dan penyelarasan dengan ERD dan Dictionary:

- Konvensi NULL/NOT NULL dinyatakan eksplisit pada seluruh tabel.
- `products`: aturan harga dilengkapi (nilai default dan aturan per `pricing_type`), `published_at` wajib untuk produk published.
- `lessons`: `duration_minutes` diganti `duration_seconds`; status lesson didefinisikan.
- `exams`/`exam_attempts`: skala skor diseragamkan menjadi persentase `NUMERIC(5,2)`, ditambahkan `is_passed`, status `exams` didefinisikan, satu attempt `in_progress` per user dan exam.
- `exam_answers`: kolom `answer_text` dihapus (tipe pertanyaan awal hanya pilihan); tabel `exam_answer_options_selected` didefinisikan karena `multiple_choice` sudah menjadi tipe pertanyaan yang didukung; ditambahkan unique `(attempt_id, question_id)`.
- `certificates`: unique `(user_id, course_id)` menjadi partial index agar sertifikat yang dicabut dapat diterbitkan ulang.
- `payments`: ditambahkan aturan satu payment berhasil per order dan unique `(provider, provider_reference)`.
- `payment_events`: ditambahkan kolom `provider` agar keunikan event ID berlaku per provider.
- `refund_events`: ditambahkan `provider_event_id` agar webhook refund idempotent.
- `refunds`: konsistensi `order_id` dan `user_id` dijaga foreign key komposit.
- `entitlements`: `order_item_id` wajib dan unik; produk dijaga foreign key komposit.
- `product_files`: pengelolaan banyak file per versi dan satu file primary didefinisikan.
- `courses` dan `source_code_details`: kesesuaian `product_type` dijaga foreign key komposit.
- Pending Decisions dirapikan: update source code gratis dan pengacakan soal dinyatakan sudah diputuskan; ditambahkan retensi data dan entitlement tanpa order.
- Ditambahkan bagian Referential Action dan perluasan daftar transaksi.

---

**End of Database Blueprint v1.2**
