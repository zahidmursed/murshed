<?php
/**
 * GET download_file.php?path=docs/554/BIRTH.jpg
 * হেডার: Authorization: Bearer <token>
 * লোকাল uploads/ থেকে ফাইল স্ট্রিম — পথ-ট্রাভার্সাল আটকায়।
 */
require_once __DIR__ . '/config.php';

$user = require_user();

$rel = ltrim((string)($_GET['path'] ?? ''), '/');
// পথ-ট্রাভার্সাল আটকায় (PHP 7.4-সামঞ্জস্য — str_contains/str_starts_with PHP 8-only)
if ($rel === '' || strpos($rel, '..') !== false || $rel[0] === '/' || $rel[0] === '\\') {
    fail('ARGS', 'পথ সঠিক নয়', 400);
}
// শুধুমাত্র uploads/ থেকে
$stmt = db()->prepare(
    'SELECT id FROM documents WHERE storage_path = ? AND deleted_at IS NULL LIMIT 1');
$stmt->bind_param('s', $rel);
$stmt->execute();
if (!$stmt->get_result()->fetch_assoc()) {
    fail('NOT_FOUND', 'ফাইল নিবন্ধিত নয়', 404);
}

$abs  = realpath(UPLOAD_DIR . '/' . $rel);
$root = realpath(UPLOAD_DIR);
$prefix = $root === false ? '' : $root . DIRECTORY_SEPARATOR;
if (!$abs || $root === false || strncmp($abs, $prefix, strlen($prefix)) !== 0) {
    fail('NOT_FOUND', 'ফাইল নেই', 404);
}

$ext = strtolower(pathinfo($abs, PATHINFO_EXTENSION));
header('Content-Type: ' . ($ext === 'png' ? 'image/png' : 'image/jpeg'));
header('Content-Length: ' . (string)filesize($abs));
header('X-Content-Type-Options: nosniff');
readfile($abs);
exit;
