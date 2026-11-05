# Database Entity Relationship Diagram (ERD) — Nekadaja

**Versi:** 1.1  
**Status:** Revised Draft  
**Database:** PostgreSQL  
**Acuan:** `database-blueprint.md` (v1.2)

Dokumen ini menggambarkan struktur dan hubungan antar-entitas pada database platform Nekadaja. Diagram dibagi berdasarkan sepuluh domain pada blueprint agar lebih mudah dibaca, dikembangkan, dan dipelihara.

Keterangan notasi: `PK` primary key, `FK` foreign key, `UK` kolom unik. Kolom unik komposit, partial unique index, CHECK, dan aturan nullability dijelaskan di `database-dictionary.md`. Tabel dari domain lain yang hanya menjadi referensi ditampilkan dengan kolom `id` saja.

---

## 1. Identity & Access Management

Domain ini mengelola identitas pengguna, role, autentikasi, serta token yang dibutuhkan untuk proses keamanan akun.

```mermaid
erDiagram
    users ||--o{ user_roles : has
    roles ||--o{ user_roles : assigned
    users ||--o{ user_oauth_accounts : connects
    users ||--o{ refresh_tokens : owns
    users ||--o{ email_verification_tokens : receives
    users ||--o{ password_reset_tokens : requests

    users {
        uuid id PK
        varchar name
        varchar email UK
        text password_hash
        text avatar_url
        varchar status
        timestamptz email_verified_at
        timestamptz created_at
        timestamptz updated_at
    }

    roles {
        uuid id PK
        varchar name UK
        text description
        timestamptz created_at
    }

    user_roles {
        uuid user_id PK, FK
        uuid role_id PK, FK
        timestamptz assigned_at
    }

    user_oauth_accounts {
        uuid id PK
        uuid user_id FK
        varchar provider
        varchar provider_user_id
        varchar provider_email
        timestamptz created_at
        timestamptz updated_at
    }

    refresh_tokens {
        uuid id PK
        uuid user_id FK
        text token_hash UK
        timestamptz expires_at
        timestamptz revoked_at
        timestamptz created_at
    }

    email_verification_tokens {
        uuid id PK
        uuid user_id FK
        text token_hash UK
        timestamptz expires_at
        timestamptz used_at
        timestamptz created_at
    }

    password_reset_tokens {
        uuid id PK
        uuid user_id FK
        text token_hash UK
        timestamptz expires_at
        timestamptz used_at
        timestamptz created_at
    }
```

Catatan: `user_oauth_accounts` memiliki unique komposit `(provider, provider_user_id)`.

---

## 2. Product Catalog

Domain ini mengelola produk yang tersedia di Nekadaja. Setiap produk memiliki kategori dan dapat berupa Course atau Source Code.

```mermaid
erDiagram
    users ||--o{ products : creates
    products ||--o{ product_categories : categorized
    categories ||--o{ product_categories : contains

    users {
        uuid id PK
    }

    products {
        uuid id PK
        varchar product_type
        varchar title
        varchar slug UK
        text description
        text thumbnail_url
        varchar pricing_type
        bigint price_amount
        bigint minimum_amount
        char currency
        varchar status
        uuid created_by FK
        timestamptz published_at
        timestamptz created_at
        timestamptz updated_at
    }

    categories {
        uuid id PK
        varchar name
        varchar slug UK
        text description
        timestamptz created_at
        timestamptz updated_at
    }

    product_categories {
        uuid product_id PK, FK
        uuid category_id PK, FK
    }
```

Catatan: `products` memiliki unique komposit `(id, product_type)` yang dipakai oleh foreign key komposit dari `courses` dan `source_code_details` (lihat domain 3 dan 6).

---

## 3. Course Management

Domain ini mengelola struktur pembelajaran: course, section, dan lesson.

```mermaid
erDiagram
    products ||--o| courses : has_course_detail
    courses ||--o{ course_sections : contains
    course_sections ||--o{ lessons : contains

    products {
        uuid id PK
        varchar product_type
    }

    courses {
        uuid id PK
        uuid product_id FK, UK
        varchar product_type FK
        varchar level
        varchar language
        integer estimated_duration_minutes
        jsonb requirements
        jsonb learning_outcomes
        timestamptz created_at
        timestamptz updated_at
    }

    course_sections {
        uuid id PK
        uuid course_id FK
        varchar title
        text description
        integer position
        timestamptz created_at
        timestamptz updated_at
    }

    lessons {
        uuid id PK
        uuid section_id FK
        varchar title
        varchar slug
        text content
        varchar lesson_type
        text video_url
        integer duration_seconds
        boolean is_preview
        integer position
        varchar status
        timestamptz created_at
        timestamptz updated_at
    }
```

Catatan:
- `courses (product_id, product_type)` adalah foreign key komposit ke `products (id, product_type)`. Kolom `product_type` pada `courses` selalu bernilai `course` (CHECK), sehingga course hanya dapat mengacu pada produk bertipe course.
- `course_sections` memiliki unique `(course_id, position)`; `lessons` memiliki unique `(section_id, slug)` dan `(section_id, position)`.

---

## 4. Examination Management

Domain ini mengelola ujian, pertanyaan, pilihan jawaban, percobaan ujian, dan jawaban peserta.

```mermaid
erDiagram
    courses ||--o{ exams : provides
    exams ||--o{ exam_questions : contains
    exam_questions ||--o{ exam_answer_options : has
    users ||--o{ exam_attempts : takes
    exams ||--o{ exam_attempts : attempted
    exam_attempts ||--o{ exam_answers : contains
    exam_questions ||--o{ exam_answers : answered
    exam_answer_options |o--o{ exam_answers : selected_single
    exam_answers ||--o{ exam_answer_options_selected : has
    exam_answer_options ||--o{ exam_answer_options_selected : chosen

    courses {
        uuid id PK
    }

    users {
        uuid id PK
    }

    exams {
        uuid id PK
        uuid course_id FK
        varchar title
        text description
        integer duration_minutes
        numeric passing_score
        integer max_attempts
        boolean shuffle_questions
        boolean shuffle_options
        varchar status
        timestamptz created_at
        timestamptz updated_at
    }

    exam_questions {
        uuid id PK
        uuid exam_id FK
        text question_text
        varchar question_type
        text image_url
        numeric points
        text explanation
        integer position
        timestamptz created_at
        timestamptz updated_at
    }

    exam_answer_options {
        uuid id PK
        uuid question_id FK
        text option_text
        text image_url
        boolean is_correct
        integer position
    }

    exam_attempts {
        uuid id PK
        uuid exam_id FK
        uuid user_id FK
        integer attempt_number
        timestamptz started_at
        timestamptz submitted_at
        numeric score
        boolean is_passed
        varchar status
        timestamptz created_at
    }

    exam_answers {
        uuid id PK
        uuid attempt_id FK
        uuid question_id FK
        uuid selected_option_id FK
        boolean is_correct
        numeric earned_points
        timestamptz created_at
        timestamptz updated_at
    }

    exam_answer_options_selected {
        uuid answer_id PK, FK
        uuid question_id FK
        uuid option_id PK, FK
    }
```

Catatan:
- `question_type` mendukung `single_choice`, `multiple_choice`, dan `true_false`.
- `exam_answers.selected_option_id` dipakai untuk `single_choice` dan `true_false`. Untuk `multiple_choice`, pilihan peserta disimpan di `exam_answer_options_selected`.
- Foreign key komposit `(question_id, selected_option_id)` dan `(question_id, option_id)` memastikan pilihan jawaban berasal dari pertanyaan yang dijawab.
- `exam_attempts` unik pada `(exam_id, user_id, attempt_number)`; `exam_answers` unik pada `(attempt_id, question_id)`.
- `score` dan `passing_score` sama-sama berskala persentase 0–100. `is_passed` disimpan sebagai snapshot saat penilaian.
- Penilaian dan penyimpanan jawaban harus konsisten agar hasil ujian tidak berubah ketika soal diperbarui. Pertanyaan dan pilihan yang sudah dijawab tidak dapat dihapus.

---

## 5. Certificate Management

Domain ini mengelola template sertifikat dan sertifikat yang diterbitkan kepada pengguna setelah memenuhi persyaratan course.

```mermaid
erDiagram
    courses ||--o{ certificates : awards
    users ||--o{ certificates : receives
    certificate_templates ||--o{ certificates : generates

    courses {
        uuid id PK
    }

    users {
        uuid id PK
    }

    certificate_templates {
        uuid id PK
        varchar name
        text template_file_url
        jsonb configuration
        boolean is_active
        timestamptz created_at
        timestamptz updated_at
    }

    certificates {
        uuid id PK
        uuid user_id FK
        uuid course_id FK
        uuid template_id FK
        varchar certificate_number UK
        text file_url
        timestamptz issued_at
        timestamptz revoked_at
        timestamptz created_at
    }
```

Catatan:
- Template sertifikat bersifat global dan tidak terikat pada satu course.
- Satu sertifikat aktif per `(user_id, course_id)`, dijaga partial unique index `WHERE revoked_at IS NULL`.

---

## 6. Source Code Management

Domain ini mengelola detail source code, versi produk, dan file yang dapat diunduh oleh pengguna.

```mermaid
erDiagram
    products ||--o| source_code_details : has_source_detail
    source_code_details ||--o{ source_code_versions : has
    products ||--o{ product_files : owns
    source_code_versions |o--o{ product_files : contains

    products {
        uuid id PK
        varchar product_type
    }

    source_code_details {
        uuid id PK
        uuid product_id FK, UK
        varchar product_type FK
        varchar programming_language
        varchar framework
        text documentation
        text installation_guide
        timestamptz created_at
        timestamptz updated_at
    }

    source_code_versions {
        uuid id PK
        uuid source_code_id FK
        varchar version
        text changelog
        text release_notes
        boolean is_latest
        timestamptz released_at
        timestamptz created_at
    }

    product_files {
        uuid id PK
        uuid product_id FK
        uuid source_code_version_id FK
        varchar file_name
        text storage_key UK
        varchar mime_type
        bigint file_size
        varchar checksum
        boolean is_primary
        timestamptz created_at
    }
```

Catatan:
- `source_code_details (product_id, product_type)` adalah foreign key komposit ke `products (id, product_type)`; `product_type` pada tabel ini selalu bernilai `source_code`.
- `source_code_versions.source_code_id` mengacu pada `source_code_details.id` dan unik bersama `version`. Hanya satu versi `is_latest` per source code.
- `product_files.source_code_version_id` bernilai NULL untuk file course dan terisi untuk file source code. Satu versi dapat memiliki beberapa file, dengan satu file primary.
- File disimpan di object storage atau file storage, bukan sebagai binary di PostgreSQL. Database hanya menyimpan metadata dan lokasi penyimpanannya.

---

## 7. Order Management

Domain ini mengelola transaksi pembelian. Satu order hanya berisi satu produk.

```mermaid
erDiagram
    users ||--o{ orders : creates
    orders ||--|| order_items : contains
    products ||--o{ order_items : purchased

    users {
        uuid id PK
    }

    products {
        uuid id PK
    }

    orders {
        uuid id PK
        varchar order_number UK
        uuid user_id FK
        bigint subtotal_amount
        bigint discount_amount
        bigint total_amount
        char currency
        varchar status
        timestamptz paid_at
        timestamptz expires_at
        timestamptz created_at
        timestamptz updated_at
    }

    order_items {
        uuid id PK
        uuid order_id FK, UK
        uuid product_id FK
        varchar product_title
        varchar product_type
        bigint unit_price
        integer quantity
        bigint subtotal_amount
        timestamptz created_at
    }
```

Catatan:
- `order_items.order_id` unik sehingga satu order hanya memiliki satu item, dan `quantity` selalu 1.
- `product_title`, `product_type`, dan `unit_price` adalah snapshot saat transaksi.
- Order gratis bernilai `total_amount = 0`, berstatus `paid`, dan tidak memiliki `payments`.

---

## 8. Payment & Refund Management

Domain ini mengelola pembayaran dan proses pengembalian dana.

```mermaid
erDiagram
    orders ||--o{ payments : paid_by
    payments ||--o{ payment_events : records
    payments ||--o{ refunds : has
    orders ||--o{ refunds : refunded_in
    users ||--o{ refunds : requests
    refunds ||--o{ refund_events : records

    orders {
        uuid id PK
    }

    users {
        uuid id PK
    }

    payments {
        uuid id PK
        uuid order_id FK
        varchar provider
        varchar provider_reference
        varchar payment_method
        bigint amount
        char currency
        varchar status
        timestamptz paid_at
        timestamptz expired_at
        jsonb raw_response
        timestamptz created_at
        timestamptz updated_at
    }

    payment_events {
        uuid id PK
        uuid payment_id FK
        varchar provider
        varchar provider_event_id
        varchar event_type
        jsonb payload
        timestamptz processed_at
        timestamptz created_at
    }

    refunds {
        uuid id PK
        uuid payment_id FK
        uuid order_id FK
        uuid user_id FK
        varchar refund_number UK
        bigint amount
        text reason
        varchar status
        varchar provider_reference
        timestamptz requested_at
        timestamptz processed_at
        timestamptz created_at
        timestamptz updated_at
    }

    refund_events {
        uuid id PK
        uuid refund_id FK
        varchar provider_event_id
        varchar event_type
        jsonb payload
        timestamptz created_at
    }
```

Catatan:
- Satu order dapat memiliki beberapa percobaan pembayaran, tetapi hanya satu payment berhasil (partial unique index pada `order_id`).
- `payment_events` unik pada `(provider, provider_event_id)` dan `refund_events` unik pada `(refund_id, provider_event_id)` untuk menjamin webhook idempotent.
- `refunds` memakai foreign key komposit `(payment_id, order_id)` ke `payments` dan `(order_id, user_id)` ke `orders` agar `order_id` dan `user_id` selalu konsisten dengan payment.
- Refund yang masih dalam proses tidak otomatis mencabut hak akses pengguna.

---

## 9. Entitlement & Learning Progress

Domain ini menentukan hak akses pengguna terhadap produk yang telah diperoleh (pembelian atau klaim gratis) serta mencatat progres belajar.

```mermaid
erDiagram
    users ||--o{ entitlements : owns
    products ||--o{ entitlements : grants
    order_items ||--o| entitlements : originates_from
    users ||--o{ lesson_progress : tracks
    lessons ||--o{ lesson_progress : tracked_in
    users ||--o{ course_progress : has
    courses ||--o{ course_progress : measured_in

    users {
        uuid id PK
    }

    products {
        uuid id PK
    }

    order_items {
        uuid id PK
        uuid product_id
    }

    lessons {
        uuid id PK
    }

    courses {
        uuid id PK
    }

    entitlements {
        uuid id PK
        uuid user_id FK
        uuid product_id FK
        uuid order_item_id FK, UK
        timestamptz granted_at
        timestamptz revoked_at
        text revoked_reason
        timestamptz created_at
    }

    lesson_progress {
        uuid id PK
        uuid user_id FK
        uuid lesson_id FK
        boolean is_completed
        integer last_position_seconds
        timestamptz completed_at
        timestamptz created_at
        timestamptz updated_at
    }

    course_progress {
        uuid id PK
        uuid user_id FK
        uuid course_id FK
        integer completed_lessons
        integer total_lessons
        numeric progress_percentage
        timestamptz completed_at
        timestamptz updated_at
    }
```

Catatan:
- Hak akses produk bersifat permanen dan tidak memiliki tanggal kedaluwarsa. Entitlement aktif adalah entitlement dengan `revoked_at IS NULL`.
- Satu entitlement aktif per `(user_id, product_id)` dijaga partial unique index.
- Foreign key komposit `(order_item_id, product_id)` ke `order_items (id, product_id)` memastikan produk entitlement sama dengan produk yang dipesan.
- Jika terjadi refund yang disetujui dan berhasil, entitlement dapat dicabut sesuai kebijakan refund.
- `lesson_progress` unik pada `(user_id, lesson_id)`; `course_progress` unik pada `(user_id, course_id)`.

---

## 10. System & Audit

Domain ini mencatat aktivitas penting untuk kebutuhan keamanan, pelacakan, dan audit sistem.

```mermaid
erDiagram
    users ||--o{ audit_logs : performs

    users {
        uuid id PK
    }

    audit_logs {
        uuid id PK
        uuid user_id FK
        varchar action
        varchar entity_type
        uuid entity_id
        jsonb metadata
        inet ip_address
        text user_agent
        timestamptz created_at
    }
```

`user_id` dapat bernilai `NULL` untuk aktivitas sistem atau aktivitas yang tidak memiliki pengguna terautentikasi. Nilai sebelum dan sesudah perubahan disimpan di `metadata`.

---

## 11. Ringkasan Relasi Utama

| Domain | Relasi utama |
|---|---|
| Identity | Users ↔ Roles |
| Catalog | Products ↔ Categories |
| Course | Courses → Sections → Lessons |
| Examination | Exams → Questions → Answer Options |
| Certificate | Users → Certificates |
| Source Code | Source Code → Versions → Files |
| Commerce | Users → Orders → Order Items |
| Payment | Orders → Payments → Events |
| Refund | Payments → Refunds → Events |
| Access | Users → Entitlements → Products |
| Learning | Users → Lesson Progress / Course Progress |
| Audit | Users → Audit Logs |

---

## 12. Catatan Implementasi

Dokumen ERD ini merupakan representasi konseptual dan logis berdasarkan Database Blueprint v1.2. Poin-poin berikut sudah diputuskan di blueprint dan perlu dipertahankan saat membuat migration SQL:

1. Konsistensi `product_type` dengan tabel detail dijaga foreign key komposit `(product_id, product_type)`.
2. Pertanyaan ujian `multiple_choice` didukung melalui tabel `exam_answer_options_selected`.
3. File produk mendukung banyak file per versi (satu primary); `product_files.product_id` dan versi harus sejalan, divalidasi aplikasi atau trigger.
4. Sertifikat aktif ganda dicegah partial unique index pada `(user_id, course_id)`.
5. Pembayaran berulang dibatasi satu payment berhasil per order; idempotensi webhook dijaga unique event ID.
6. Aturan pencabutan entitlement setelah refund berhasil masih menunggu keputusan kebijakan refund.
7. Entitlement aktif ganda dan progres belajar duplikat dicegah constraint unik.

**Prinsip:** ERD menjadi acuan hubungan data, sedangkan aturan bisnis dan constraint database dijelaskan di blueprint dan data dictionary, lalu diterapkan pada tahap implementasi schema dan migration.
