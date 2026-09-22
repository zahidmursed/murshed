<?php
/**
 * Dakhila Camera API — সাধারণ কনফিগ (XAMPP)
 * এই ফাইলেই DB-পাসওয়ার্ড; প্রোডাকশনে ওয়েবরুটের বাইরে রাখা ভালো।
 */

// ▼▼▼ আপনার পরিবেশ অনুযায়ী বদলান ▼▼▼
const DB_HOST = '127.0.0.1';
const DB_NAME = 'dakhila_camera';
const DB_USER = 'root';          // XAMPP ডিফল্ট; প্রোডাকশনে আলাদা ইউজার বানান
const DB_PASS = '';              // XAMPP-এ খালি; প্রোডাকশনে অবশ্যই পাসওয়ার্ড
// ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲

/** ছবি-ফাইল রাখার ফোল্ডার (এই api/ ফোল্ডারের পাশে) */
const UPLOAD_DIR = __DIR__ . '/../uploads';

/** টোকেন কত দিন বৈধ (দিন) */
const TOKEN_DAYS = 60;

/** JSON রেসপন্স + বন্ধ */
function json_out(array $data, int $code = 200): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function fail(string $code, string $message, int $http = 400): void {
    json_out(['ok' => false, 'error' => $code, 'message' => $message], $http);
}

/** MySQLi সংযোগ (utf8mb4) */
function db(): mysqli {
    static $db = null;
    if ($db === null) {
        mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
        try {
            $db = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);
            $db->set_charset('utf8mb4');
        } catch (mysqli_sql_exception $e) {
            fail('DB_ERROR', 'ডাটাবেজ সংযোগ ব্যর্থ — config.php যাচাই করুন', 500);
        }
    }
    return $db;
}

/** POST-বডি JSON পড়া */
function body(): array {
    $raw = file_get_contents('php://input');
    if ($raw === '' || $raw === false) return [];
    $j = json_decode($raw, true);
    return is_array($j) ? $j : [];
}

/** Authorization: Bearer <token> → users-রো (না মিললে 401) */
function require_user(): array {
    $hdr = $_SERVER['HTTP_AUTHORIZATION'] ?? ($_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '');
    if (!preg_match('/Bearer\s+(\S+)/i', $hdr, $m)) {
        fail('NO_TOKEN', 'লগইন প্রয়োজন', 401);
    }
    $token = $m[1];
    $stmt = db()->prepare(
        'SELECT u.* FROM auth_tokens t JOIN users u ON u.id = t.user_id
         WHERE t.token = ? AND t.expires_at > NOW() LIMIT 1');
    $stmt->bind_param('s', $token);
    $stmt->execute();
    $user = $stmt->get_result()->fetch_assoc();
    if (!$user) fail('BAD_TOKEN', 'সেশন শেষ — আবার লগইন করুন', 401);
    return $user;
}

/** admin না হলে 403 */
function require_admin(array $user): void {
    if (($user['role'] ?? '') !== 'admin') {
        fail('FORBIDDEN', 'কেবল admin-এর অনুমতি আছে', 403);
    }
}

function uuid4(): string {
    $b = random_bytes(16);
    $b[6] = chr((ord($b[6]) & 0x0f) | 0x40);
    $b[8] = chr((ord($b[8]) & 0x3f) | 0x80);
    return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($b), 4));
}

function new_token(): string {
    return bin2hex(random_bytes(32));
}
