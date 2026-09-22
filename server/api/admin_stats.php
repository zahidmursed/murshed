<?php
/**
 * GET admin_stats.php  (হেডার: admin টোকেন)
 * → {ok, total_students, captured, docs, by_class:[{class_name, total, captured}], recent_syncs}
 */
require_once __DIR__ . '/config.php';

$user = require_user();
require_admin($user);

$db = db();
$total = (int)$db->query(
    'SELECT COUNT(*) c FROM students WHERE deleted_at IS NULL')->fetch_assoc()['c'];
$captured = (int)$db->query(
    'SELECT COUNT(*) c FROM students WHERE deleted_at IS NULL AND is_captured = 1')->fetch_assoc()['c'];
$docs = (int)$db->query(
    'SELECT COUNT(*) c FROM documents WHERE deleted_at IS NULL')->fetch_assoc()['c'];

$byClass = $db->query(
    "SELECT class_name, COUNT(*) total,
            SUM(is_captured = 1) captured
     FROM students WHERE deleted_at IS NULL
     GROUP BY class_name ORDER BY class_name")->fetch_all(MYSQLI_ASSOC);

$recent = $db->query(
    'SELECT s.full_name, s.role, l.device_id, l.students_rev, l.documents_rev,
            l.failures, l.synced_at
     FROM sync_log l LEFT JOIN users s ON s.id = l.user_id
     ORDER BY l.synced_at DESC LIMIT 20')->fetch_all(MYSQLI_ASSOC);

json_out([
    'ok'             => true,
    'total_students' => $total,
    'captured'       => $captured,
    'documents'      => $docs,
    'by_class'       => $byClass,
    'recent_syncs'   => $recent,
]);
