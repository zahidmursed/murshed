<?php
/** POST {email, password, device_id?} → {ok, token, user{...}, expires_at} */
require_once __DIR__ . '/config.php';

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') fail('METHOD', 'POST প্রয়োজন', 405);

$b = body();
$email = trim((string)($b['email'] ?? ''));
$pass  = (string)($b['password'] ?? '');
$dev   = substr(trim((string)($b['device_id'] ?? '')), 0, 180);

if ($email === '' || $pass === '') fail('ARGS', 'ইমেইল ও পাসওয়ার্ড দিন');

$stmt = db()->prepare('SELECT * FROM users WHERE email = ? LIMIT 1');
$stmt->bind_param('s', $email);
$stmt->execute();
$user = $stmt->get_result()->fetch_assoc();

// ভুল ইমেইল/পাসওয়ার্ড — একই বার্তা (ইনুমারেশন এড়াতে) + brute-force ধীর করতে সামান্য দেরি
if (!$user || !password_verify($pass, $user['password_hash'])) {
    usleep(400000);   // ০.৪ সেকেন্ড
    fail('BAD_LOGIN', 'ইমেইল বা পাসওয়ার্ড ভুল', 401);
}

// পুরনো/মেয়াদোত্তীর্ণ টোকেন পরিষ্কার (হালকা হাউসকিপিং)
db()->query('DELETE FROM auth_tokens WHERE expires_at < NOW()');

$token  = new_token();
$days   = TOKEN_DAYS;
$stmt = db()->prepare(
    'INSERT INTO auth_tokens (token, user_id, device_id, expires_at)
     VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL ? DAY))');
$stmt->bind_param('sssi', $token, $user['id'], $dev, $days);
$stmt->execute();

unset($user['password_hash']);
json_out([
    'ok'         => true,
    'token'      => $token,
    'expires_at' => gmdate('Y-m-d\TH:i:s\Z', strtotime("+$days days")),
    'user'       => $user,
]);
