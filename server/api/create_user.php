<?php
/**
 * create_user.php — প্রথম সেটআপে admin/শিক্ষক বানানোর CLI স্ক্রিপ্ট।
 * চালান (XAMPP shell):  php create_user.php admin@example.com "আপনার নাম" pass123 admin
 * (শেষ আর্গুমেন্ট admin না দিলে teacher হবে)
 * শুধু CLI-তে চলে — ব্রাউজার থেকে নয়।
 */
if (PHP_SAPI !== 'cli') { http_response_code(403); exit('শুধু কমান্ড-লাইনে চালান'); }

require_once __DIR__ . '/config.php';

$email = strtolower(trim($argv[1] ?? ''));
$name  = trim($argv[2] ?? '');
$pass  = (string)($argv[3] ?? '');
$role  = strtolower(trim($argv[4] ?? 'teacher'));

if ($email === '' || $name === '' || strlen($pass) < 6) {
    fwrite(STDERR, "ব্যবহার: php create_user.php <email> <name> <password-6+> [teacher|admin]\n");
    exit(1);
}
if (!in_array($role, ['teacher', 'admin'], true)) $role = 'teacher';

$stmt = db()->prepare('SELECT id FROM users WHERE email = ? LIMIT 1');
$stmt->bind_param('s', $email);
$stmt->execute();
if ($stmt->get_result()->fetch_assoc()) {
    fwrite(STDERR, "এই ইমেইলে ইউজার আগেই আছে\n");
    exit(1);
}

$id    = uuid4();
$hash  = password_hash($pass, PASSWORD_DEFAULT);
$stmt = db()->prepare(
    'INSERT INTO users (id, email, full_name, role, password_hash) VALUES (?, ?, ?, ?, ?)');
$stmt->bind_param('sssss', $id, $email, $name, $role, $hash);
$stmt->execute();

echo "✓ তৈরি হয়েছে: $email ($role)\n";
