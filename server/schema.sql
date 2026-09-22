-- ============================================================================
-- Dakhila Camera — সার্ভার স্কিমা (MySQL / MariaDB — XAMPP/phpMyAdmin-এর জন্য)
-- তারিখ: 2026-09-19 • ভিত্তি: SQLite v9 (lib/db/database_helper.dart)
--
-- চালানো: phpMyAdmin → "Import" → এই ফাইল সিলেক্ট → Go  (DB সিলেক্ট করার দরকার নেই)
--   অথবা SQL ট্যাবে পুরো কনটেন্ট পেস্ট → Go
--   অথবা কমান্ড-লাইন: mysql -u root < server/schema.sql
-- এই ফাইলটি **পুনরায় চালানো নিরাপদ** (idempotent) — টেবিল/ইনডেক্স সব
-- CREATE TABLE IF NOT EXISTS-এর ভেতরে, তাই দ্বিতীয়বার চালালেও কিছু ভাঙে না।
-- যাচাই করা প্ল্যাটফর্ম: MariaDB 10.4 (XAMPP-এর ডিফল্ট) — MySQL 5.7+/8-ও চলবে।
--
-- নিরাপত্তা:
--   * শিক্ষক-লগইন = ইমেইল + bcrypt পাসওয়ার্ড → সেশন-টোকেন (auth_tokens)
--   * API ছাড়া কেউ টেবিলে ঢুকতে পারবে না — DB-ইউজার dakhila_app-এর পাসওয়ার্ড
--     কেবল api/config.php-তে (ওয়েবরুটের বাইরে রাখা ভালো)
-- ============================================================================

CREATE DATABASE IF NOT EXISTS dakhila_camera
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE dakhila_camera;

-- ---------------------------------------------------------------------------
-- ০. ইউজার (শিক্ষক/admin) ও টোকেন
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id            CHAR(36)     NOT NULL PRIMARY KEY,   -- UUID টেক্সট
  email         VARCHAR(190) NOT NULL UNIQUE,
  full_name     VARCHAR(190) NOT NULL,
  role          ENUM('teacher','admin') NOT NULL DEFAULT 'teacher',
  password_hash VARCHAR(255) NOT NULL,               -- PHP password_hash() (bcrypt)
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS auth_tokens (
  token      CHAR(64)  NOT NULL PRIMARY KEY,         -- PHP bin2hex(random_bytes(32))
  user_id    CHAR(36)  NOT NULL,
  device_id  VARCHAR(190) NOT NULL DEFAULT '',
  created_at DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME  NOT NULL,
  CONSTRAINT fk_token_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- ১. students — লোকাল SQLite-এর হুবহু প্রতিচ্ছবি (dakhila = স্থায়ী পরিচয়)
--    একই দাখিলা ভিন্ন বছর = একই ব্যক্তি; বছর মাত্র তথ্য-কলাম
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS students (
  dakhila              VARCHAR(64)  NOT NULL PRIMARY KEY,
  stu_name             VARCHAR(190) NULL,
  class_name           VARCHAR(190) NULL,
  forik_no             VARCHAR(32)  NULL,
  father_name          VARCHAR(190) NULL,
  guardian_mobile      VARCHAR(32)  NULL,
  dakhila_year         VARCHAR(16)  NULL,
  class_level          VARCHAR(64)  NULL,
  marhala              VARCHAR(190) NULL,
  exam_year            VARCHAR(16)  NULL,
  mother_name          VARCHAR(190) NULL,
  birth_date           VARCHAR(32)  NULL,
  birth_certificate_no VARCHAR(64)  NULL,
  stu_name_en          VARCHAR(190) NULL,
  stu_name_ar          VARCHAR(190) NULL,
  father_name_en       VARCHAR(190) NULL,
  father_name_ar       VARCHAR(190) NULL,
  mother_name_en       VARCHAR(190) NULL,
  mother_name_ar       VARCHAR(190) NULL,
  is_edited            TINYINT      NOT NULL DEFAULT 0,
  avg_num_month        VARCHAR(32)  NULL,
  avg_num_1st          VARCHAR(32)  NULL,
  avg_num_2nd          VARCHAR(32)  NULL,
  avg_num_final        VARCHAR(32)  NULL,
  address_vill         VARCHAR(190) NULL,
  address_po           VARCHAR(190) NULL,
  address_ps           VARCHAR(190) NULL,
  address_dist         VARCHAR(190) NULL,
  is_captured          TINYINT      NOT NULL DEFAULT 0,
  total_docs           INT          NOT NULL DEFAULT 0,
  updated_at           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                     ON UPDATE CURRENT_TIMESTAMP,
  deleted_at           DATETIME     NULL,
  KEY idx_students_class (class_name),
  KEY idx_students_forik (class_name, forik_no),
  KEY idx_students_year  (dakhila_year)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- ২. documents — PHOTO/BIRTH/FORM স্লট (লোকাল UNIQUE(dakhila,doc_type) মতো)
--    ছবি-ফাইল সার্ভারের uploads/ ফোল্ডারে; DB-তে শুধু পথ
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS documents (
  id            BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
  dakhila       VARCHAR(64)  NOT NULL,
  doc_type      ENUM('PHOTO','BIRTH','FORM') NOT NULL,
  storage_path  VARCHAR(255) NOT NULL,               -- uploads/docs/554/BIRTH.jpg
  mime_type     VARCHAR(64)  NOT NULL DEFAULT 'image/jpeg',
  file_size     BIGINT       NULL,
  file_sha256   CHAR(64)     NULL,                  -- ডুপ্লিকেট-আপলোড এড়াতে
  captured_by   CHAR(36)     NULL,
  captured_at   DATETIME     NULL,
  is_verified   TINYINT      NOT NULL DEFAULT 0,    -- admin approve
  verified_by   CHAR(36)     NULL,
  updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
              ON UPDATE CURRENT_TIMESTAMP,
  deleted_at    DATETIME     NULL,
  UNIQUE KEY uq_doc (dakhila, doc_type),             -- push_doc-এর ON DUPLICATE KEY-র ভিত্তি
  KEY idx_doc_captured (captured_by),
  KEY idx_doc_verified (dakhila, is_verified),
  CONSTRAINT fk_doc_student FOREIGN KEY (dakhila) REFERENCES students(dakhila)
    ON DELETE CASCADE,
  CONSTRAINT fk_doc_captor FOREIGN KEY (captured_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- ৩. case_notes — কেস নোট (সংবেদনশীল)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS case_notes (
  id         BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
  dakhila    VARCHAR(64)  NOT NULL,
  note_date  VARCHAR(32)  NOT NULL,
  category   VARCHAR(64)  NULL,
  title      VARCHAR(190) NULL,
  details    TEXT         NOT NULL,
  created_by CHAR(36)     NULL,
  created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
           ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME     NULL,
  KEY idx_notes_dakhila (dakhila),
  CONSTRAINT fk_note_student FOREIGN KEY (dakhila) REFERENCES students(dakhila)
    ON DELETE CASCADE,
  CONSTRAINT fk_note_user FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- ৪. sync_log — প্রতি ডিভাইস-সিঙ্কের হিসাব
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sync_log (
  id            BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_id       CHAR(36)    NULL,
  device_id     VARCHAR(190) NOT NULL,
  students_rev  INT         NOT NULL DEFAULT 0,
  documents_rev INT         NOT NULL DEFAULT 0,
  failures      INT         NOT NULL DEFAULT 0,
  synced_at     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_sync_time (synced_at),
  CONSTRAINT fk_sync_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
