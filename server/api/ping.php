<?php
/**
 * GET ping.php  (লগইন ছাড়া — শুধু \"সার্ভার আছে কি না\" যাচাই)
 * → {ok, app, api, db, time}
 * অ্যাপের সেটিংসে \"সংযোগ পরীক্ষা\" বোতাম এই endpoint ডাকে।
 */
require_once __DIR__ . '/config.php';

$dbOk = true;
$count = 0;
try {
    $row = db()->query('SELECT COUNT(*) AS c FROM students')->fetch_assoc();
    $count = (int)($row['c'] ?? 0);
} catch (Throwable $e) {
    $dbOk = false;
}

json_out([
    'ok'      => true,
    'app'     => 'dakhila-camera',
    'api'     => 1,
    'db'      => $dbOk,
    'students'=> $count,
    'time'    => date('Y-m-d H:i:s'),
]);
