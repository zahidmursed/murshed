<?php
/**
 * GET pull.php?since=YYYY-MM-DD HH:MM:SS
 * হেডার: Authorization: Bearer <token>
 * → {ok, now, students:[...], documents:[...]}  (deleted_at-সহ soft-delete প্রচার)
 * `since` না দিলে সব সক্রিয় রেকর্ড (প্রথম সিঙ্ক)।
 */
require_once __DIR__ . '/config.php';

$user = require_user();

$since = $_GET['since'] ?? null;
$students  = [];
$documents = [];

if ($since && preg_match('/^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}/', $since)) {
    // delta: শুধু `since`-এর পরে বদলানো রেকর্ড (মুছে-ফেলা/soft-delete-ও ধরা পড়ে)
    $ts = str_replace('T', ' ', substr($since, 0, 19));
    $stmt = db()->prepare('SELECT * FROM students WHERE updated_at > ? ORDER BY updated_at');
    $stmt->bind_param('s', $ts);
    $stmt->execute();
    $students = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);

    $stmt = db()->prepare('SELECT * FROM documents WHERE updated_at > ? ORDER BY updated_at');
    $stmt->bind_param('s', $ts);
    $stmt->execute();
    $documents = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
} else {
    // প্রথম সিঙ্ক: সব (deleted_at NULL হোক বা না হোক — ফোনে মুছে-ফেলার প্রচার দরকার)
    $students = db()->query('SELECT * FROM students ORDER BY dakhila')
        ->fetch_all(MYSQLI_ASSOC);
    $documents = db()->query('SELECT * FROM documents ORDER BY dakhila, doc_type')
        ->fetch_all(MYSQLI_ASSOC);
}

// সার্ভারের সময় — পরের pull-এর since হিসেবে
$now = db()->query('SELECT NOW() AS n')->fetch_assoc()['n'];

json_out([
    'ok'        => true,
    'now'       => $now,
    'students'  => $students,
    'documents' => $documents,
]);
