<?php
/**
 * POST push_doc.php  (multipart/form-data)
 * হেডার: Authorization: Bearer <token>
 * ফিল্ড: dakhila, doc_type (PHOTO|BIRTH|FORM), file=<jpeg|png>
 *        sha256=<hex>  (ঐচ্ছিক — সার্ভার নিজেই ফাইল থেকে হিসাব করে, ক্লায়েন্টের মান বিশ্বাস করে না)
 * → {ok, storage_path, url}  |  {ok, skipped:true, ...} একই ছবি আগেই এলে
 */
require_once __DIR__ . '/config.php';

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') fail('METHOD', 'POST প্রয়োজন', 405);
$user = require_user();

$dakhila = trim((string)($_POST['dakhila'] ?? ''));
$docType = strtoupper(trim((string)($_POST['doc_type'] ?? '')));
$file    = $_FILES['file'] ?? null;

if ($dakhila === '') fail('ARGS', 'dakhila দিন');
if (!in_array($docType, ['PHOTO', 'BIRTH', 'FORM'], true)) {
    fail('ARGS', 'doc_type সঠিক নয়');
}
if (!$file || ($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
    fail('FILE', 'ফাইল পাওয়া যায়নি', 400);
}

// মাইম-যাচাই: শুধুই jpeg/png
$finfo = new finfo(FILEINFO_MIME_TYPE);
$mime  = $finfo->file($file['tmp_name']);
if (!in_array($mime, ['image/jpeg', 'image/png'], true)) {
    fail('TYPE', 'কেবল JPEG/PNG ছবি গ্রহণযোগ্য', 415);
}
if (($file['size'] ?? 0) > 10 * 1024 * 1024) {
    fail('SIZE', 'ফাইল ১০MB-র ছোট হতে হবে', 413);
}

// sha256 ফাইল-কনটেন্ট থেকেই (ক্লায়েন্ট যা পাঠায় তা শুধু ইঙ্গিত; বিশ্বাস করা হয় না)
$sha = hash_file('sha256', $file['tmp_name']);

// ছাত্র সার্ভারে আছে কি না (pull-পথে আসবে; না থাকলে আপলোড নেই)
$stmt = db()->prepare('SELECT dakhila FROM students WHERE dakhila = ? LIMIT 1');
$stmt->bind_param('s', $dakhila);
$stmt->execute();
if (!$stmt->get_result()->fetch_assoc()) {
    fail('NO_STUDENT', 'এই দাখিলার ছাত্র সার্ভারে নেই — আগে তালিকা সিঙ্ক করুন', 404);
}

// ডুপ্লিকেট-স্কিপ: একই doc-এ আগেই এই hash আপলোড হয়েছে?
$stmt = db()->prepare(
    'SELECT storage_path FROM documents
     WHERE dakhila = ? AND doc_type = ? AND file_sha256 = ? AND deleted_at IS NULL LIMIT 1');
$stmt->bind_param('sss', $dakhila, $docType, $sha);
$stmt->execute();
$existing = $stmt->get_result()->fetch_assoc();
if ($existing) {
    json_out([
        'ok' => true, 'skipped' => true,
        'storage_path' => $existing['storage_path'],
        'url' => 'uploads/' . ltrim($existing['storage_path'], '/'),
    ]);
}

// ফাইল সেভ: uploads/docs/<dakhila>/<TYPE>.<jpg|png>
$ext      = $mime === 'image/png' ? 'png' : 'jpg';
$relDir   = "docs/$dakhila";
$absDir   = UPLOAD_DIR . "/$relDir";
if (!is_dir($absDir) && !mkdir($absDir, 0755, true) && !is_dir($absDir)) {
    fail('IO', 'আপলোড-ফোল্ডার তৈরি ব্যর্থ', 500);
}
$relPath  = "$relDir/$docType.$ext";
$absPath  = UPLOAD_DIR . "/$relPath";
if (!move_uploaded_file($file['tmp_name'], $absPath)) {
    fail('IO', 'ফাইল সেভ ব্যর্থ', 500);
}

// DB upsert (একই dakhila+type হলে নতুনটা জেতে — আগের ফাইল মুছে)
$stmt = db()->prepare('SELECT storage_path FROM documents WHERE dakhila = ? AND doc_type = ?');
$stmt->bind_param('ss', $dakhila, $docType);
$stmt->execute();
$old = $stmt->get_result()->fetch_assoc();
if ($old && $old['storage_path'] !== $relPath) {
    $oldAbs = UPLOAD_DIR . '/' . $old['storage_path'];
    if (is_file($oldAbs)) @unlink($oldAbs);
}

$sql = 'INSERT INTO documents
          (dakhila, doc_type, storage_path, mime_type, file_size, file_sha256,
           captured_by, captured_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, NOW())
        ON DUPLICATE KEY UPDATE
          storage_path = VALUES(storage_path), mime_type = VALUES(mime_type),
          file_size = VALUES(file_size), file_sha256 = VALUES(file_sha256),
          captured_by = VALUES(captured_by), captured_at = VALUES(captured_at),
          deleted_at = NULL,
          is_verified = 0, verified_by = NULL';
// ↑ নতুন ছবি এলে আগের approve বাতিল হয়ে যায় (একই hash হলে উপরে skipped হয়ে বেরিয়ে যায়)
$stmt = db()->prepare($sql);
$stmt->bind_param('ssssiss', $dakhila, $docType, $relPath, $mime,
    $file['size'], $sha, $user['id']);
$stmt->execute();

// students.is_captured/total_docs সামঞ্জস্য — শুধু এই দাখিলার জন্য
$stmt = db()->prepare(
    "UPDATE students s SET
       s.is_captured = IF(EXISTS (SELECT 1 FROM documents d
           WHERE d.dakhila = s.dakhila AND d.doc_type = 'PHOTO' AND d.deleted_at IS NULL), 1, 0),
       s.total_docs = (SELECT COUNT(*) FROM documents d
           WHERE d.dakhila = s.dakhila AND d.deleted_at IS NULL)
     WHERE s.dakhila = ?");
$stmt->bind_param('s', $dakhila);
$stmt->execute();

json_out([
    'ok'           => true,
    'storage_path' => $relPath,
    'url'          => 'uploads/' . $relPath,
]);
