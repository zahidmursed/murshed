<?php
/**
 * POST push_students.php   (JSON বডি)
 * হেডার: Authorization: Bearer <token>   — **admin--only**
 * বডি: {"students":[{"dakhila":"554","stu_name":"...","class_name":"...", ...}, ...],
 *        "replace":false}
 * → {ok, upserted, skipped, failed:[{dakhila,error}]}
 *
 * কাজ: অ্যাপের লোকাল তালিকা (JSON/Excel ইমপোর্ট করার পর) সার্ভারে তুলে দেয় —
 * তাই phpMyAdmin-এ CSV না ঢুকিয়েও শিক্ষকদের ফোনে তালিকা পৌঁছানো যায়।
 * দাখিলা = PRIMARY KEY; একই দাখিলা আবার এলে আপডেট হয় (নতুন বছর = একই ব্যক্তি)।
 * `deleted_at` সেট করা হয় না — মুছে-ফেলা সার্ভার থেকে আলাদা কল দরকার (নিরাপত্তা)।
 */
require_once __DIR__ . '/config.php';

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') fail('METHOD', 'POST প্রয়োজন', 405);
$user = require_user();
require_admin($user);

// সার্ভার students টেবিলের হুবহু কলাম-তালিকা — এই তালিকার বাইরের কী উপেক্ষা হয়
const STUDENT_COLUMNS = [
    'stu_name', 'class_name', 'forik_no', 'father_name', 'guardian_mobile',
    'dakhila_year', 'class_level', 'marhala', 'exam_year', 'mother_name',
    'birth_date', 'birth_certificate_no', 'stu_name_en', 'stu_name_ar',
    'father_name_en', 'father_name_ar', 'mother_name_en', 'mother_name_ar',
    'avg_num_month', 'avg_num_1st', 'avg_num_2nd', 'avg_num_final',
    'address_vill', 'address_po', 'address_ps', 'address_dist',
];

$b        = body();
$rows     = $b['students'] ?? null;
$replace  = !empty($b['replace']);

// replace=true → সার্ভারের তালিকা সম্পূর্ণ এই অ্যাপের তালিকায় বদলে যায়
// (সার্ভারে থাকা কিন্তু অ্যাপে না-থাকা দাখিলা deleted_at দিয়ে নিষ্ক্রিয় হয়)।
$keepSet  = [];

if (!is_array($rows)) fail('ARGS', 'students অ্যারে দিন');
if (count($rows) > 5000) fail('ARGS', 'একবারে সর্বোচ্চ ৫০০০ রেকর্ড', 413);

$upserted = 0;
$skipped  = 0;
$failed   = [];

$cols   = array_merge(['dakhila'], STUDENT_COLUMNS);
$ph     = implode(', ', array_fill(0, count($cols), '?'));
$update = implode(', ', array_map(fn($c) => "$c = VALUES($c)", STUDENT_COLUMNS));
$sql    = 'INSERT INTO students (' . implode(', ', $cols) . ") VALUES ($ph)
           ON DUPLICATE KEY UPDATE $update";

$stmt = db()->prepare($sql);

foreach ($rows as $r) {
    if (!is_array($r)) { $skipped++; continue; }
    $dakhila = trim((string)($r['dakhila'] ?? ''));
    if ($dakhila === '') { $skipped++; continue; }

    $keepSet[$dakhila] = true;
    $values = [$dakhila];
    foreach (STUDENT_COLUMNS as $c) {
        $v = $r[$c] ?? null;
        // MySQLi টাইপ-স্ট্রিং: সংখ্যা/খালি সব স্ট্রিং হিসেবেই যায় (utf8mb4)
        $values[] = $v === null ? null : (string)$v;
    }

    try {
        $types = str_repeat('s', count($values));
        $stmt->bind_param($types, ...$values);
        $stmt->execute();
        $upserted++;
    } catch (Throwable $e) {
        $failed[] = ['dakhila' => $dakhila, 'error' => 'DB'];
    }
}

// replace=true: অ্যাপে নেই এমন দাখিলা নিষ্ক্রিয় (soft delete — ডেটা মুছে যায় না)
$deactivated = 0;
if ($replace && $keepSet) {
    $all = db()->query('SELECT dakhila FROM students WHERE deleted_at IS NULL')
        ->fetch_all(MYSQLI_ASSOC);
    $upd = db()->prepare('UPDATE students SET deleted_at = NOW() WHERE dakhila = ?');
    foreach ($all as $a) {
        if (isset($keepSet[$a['dakhila']])) continue;
        $upd->bind_param('s', $a['dakhila']);
        $upd->execute();
        $deactivated++;
    }
}

json_out([
    'ok'          => true,
    'upserted'    => $upserted,
    'skipped'     => $skipped,
    'failed'      => $failed,
    'deactivated' => $deactivated,
]);
