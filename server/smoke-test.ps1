<#
  Dakhila Camera — সার্ভার স্মোক-টেস্ট (XAMPP / cPanel)
  ---------------------------------------------------------------
  কী যাচাই করে: লগইন (সফল+ব্যর্থ), টোকেন-গার্ড, তালিকা-pull,
  ছবি-আপলোড (sha256-dedup সহ), ছবি-ডাউনলোড (hash মিলিয়ে), admin পরিসংখ্যান,
  আর পথ-ট্রাভার্সাল/অননুমোদিত অ্যাক্সেস আটকানো।

  চালান (Apache চালু থাকলে):
    pwsh -File server\smoke-test.ps1 -Email admin@madrasa.com -Password 'StrongPass123'
  PHP-বিল্ট-ইন সার্ভার দিয়ে:
    php -S 127.0.0.1:8123 -t server      # আলাদা টার্মিনালে
    pwsh -File server\smoke-test.ps1 -Base http://127.0.0.1:8123/api -Email ... -Password ...

  ছবি-আপলোডও পরীক্ষা করতে:  -Dakhila TEST-001 -Photo C:\path\a.jpg [-DocType BIRTH]
  (ওই দাখিলা সার্ভারের students টেবিলে থাকতে হবে)
#>
param(
  [string]$Base = 'http://localhost/dakhila/api',
  [Parameter(Mandatory = $true)][string]$Email,
  [Parameter(Mandatory = $true)][string]$Password,
  [string]$Dakhila = '',
  [string]$Photo   = '',
  [string]$DocType = 'PHOTO'
)

$ErrorActionPreference = 'Stop'
$Base = $Base.TrimEnd('/')
$pass = 0
$fail = 0

function Check([string]$name, [bool]$cond, $extra = '') {
  if ($cond) { $script:pass++; Write-Host "  [OK]   $name" -ForegroundColor Green }
  else       { $script:fail++; Write-Host "  [FAIL] $name  $extra" -ForegroundColor Red }
}

# JSON কল → @{status; data}; HTTP এররও ধরা পড়ে (PS 5.1 ও 7 দুটোতেই চলে)
function Call([string]$method, [string]$url, [string]$token = '', [string]$json = '') {
  $headers = @{}
  if ($token) { $headers['Authorization'] = "Bearer $token" }
  try {
    $a = @{ Method = $method; Uri = $url; Headers = $headers }
    if ($json) { $a['Body'] = $json; $a['ContentType'] = 'application/json' }
    return @{ status = 200; data = (Invoke-RestMethod @a) }
  } catch {
    $code = 0
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    return @{ status = $code; data = $null; error = $_.Exception.Message }
  }
}

# multipart ছবি-আপলোড (PS 5.1 ও 7 দুটোতেই কাজ করে)
function Send-Photo([string]$url, [string]$token, [string]$dakhila, [string]$docType, [string]$path) {
  Add-Type -AssemblyName System.Net.Http
  $client = New-Object System.Net.Http.HttpClient
  $client.DefaultRequestHeaders.Authorization =
    New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $token)
  $content = New-Object System.Net.Http.MultipartFormDataContent
  $content.Add((New-Object System.Net.Http.StringContent($dakhila)), 'dakhila')
  $content.Add((New-Object System.Net.Http.StringContent($docType)), 'doc_type')
  $mime = if ([IO.Path]::GetExtension($path) -match '(?i)\.png$') { 'image/png' } else { 'image/jpeg' }
  $bytes = [IO.File]::ReadAllBytes($path)
  $part = New-Object System.Net.Http.ByteArrayContent(, $bytes)
  $part.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue($mime)
  $content.Add($part, 'file', [IO.Path]::GetFileName($path))
  $resp = $client.PostAsync($url, $content).GetAwaiter().GetResult()
  $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  $json = $null
  try { $json = $body | ConvertFrom-Json } catch { }
  return @{ status = [int]$resp.StatusCode; data = $json; raw = $body }
}

Write-Host "`n=== Dakhila Camera সার্ভার-পরীক্ষা — $Base ===" -ForegroundColor Cyan

# ১. লগইন
$r = Call 'POST' "$Base/login.php" '' (@{ email = $Email; password = $Password; device_id = 'smoke-test' } | ConvertTo-Json)
Check 'লগইন সফল' ($r.status -eq 200 -and $r.data.ok) "status=$($r.status)"
$token = $r.data.token
$role = $r.data.user.role
Write-Host "         ইউজার: $($r.data.user.full_name)  ($role)"

$r = Call 'POST' "$Base/login.php" '' (@{ email = $Email; password = 'wrong-password-xyz' } | ConvertTo-Json)
Check 'ভুল পাসওয়ার্ডে 401' ($r.status -eq 401)

# ২. টোকেন ছাড়া/ভুল টোকেনে কিছুই নয়
$r = Call 'GET' "$Base/pull.php"
Check 'টোকেন ছাড়া pull → 401' ($r.status -eq 401)
$r = Call 'GET' "$Base/pull.php" 'not-a-real-token'
Check 'ভুয়া টোকেনে pull → 401' ($r.status -eq 401)
$r = Call 'GET' "$Base/admin_stats.php" $token
Check 'শিক্ষক-টোকেনে admin_stats → 403' ($role -eq 'admin' -or $r.status -eq 403)

# ৩. তালিকা pull
$r = Call 'GET' "$Base/pull.php" $token
Check 'pull (পূর্ণ তালিকা) সফল' ($r.status -eq 200 -and $r.data.ok)
if ($r.data) {
  Write-Host "         ছাত্র: $($r.data.students.Count) • ডকুমেন্ট: $($r.data.documents.Count) • সার্ভার-সময়: $($r.data.now)"
}
$r = Call 'GET' "$Base/pull.php?since=2000-01-01%2000:00:00" $token
Check 'pull (since delta) সফল' ($r.status -eq 200 -and $r.data.ok)

# ৪. admin পরিসংখ্যান
if ($role -eq 'admin') {
  $r = Call 'GET' "$Base/admin_stats.php" $token
  Check 'admin_stats সফল' ($r.status -eq 200 -and $r.data.ok)
  if ($r.data) { Write-Host "         মোট ছাত্র: $($r.data.total_students) • ছবি-তোলা: $($r.data.captured) • ডক: $($r.data.documents)" }
}

# ৫. নিরাপত্তা-প্রাচীর: পথ-ট্রাভার্সাল ও অনিবন্ধিত ফাইল
$r = Call 'GET' "$Base/download_file.php?path=../../api/config.php" $token
Check 'path traversal → 400/404' ($r.status -eq 400 -or $r.status -eq 404)
$r = Call 'GET' "$Base/download_file.php?path=docs/naikhai.jpg" $token
Check 'অনিবন্ধিত ফাইল → 404' ($r.status -eq 404)

# ৬. ছবি-আপলোড → ডাউনলোড → হুবহু মিল (ছবি দেওয়া থাকলে)
if ($Photo -and $Dakhila) {
  if (-not (Test-Path $Photo)) {
    Check "ছবি-ফাইল পাওয়া গেছে ($Photo)" $false
  } else {
    $localHash = (Get-FileHash $Photo -Algorithm SHA256).Hash.ToLower()

    $u = Send-Photo "$Base/push_doc.php" $token $Dakhila $DocType $Photo
    Check 'ছবি আপলোড সফল' ($u.status -eq 200 -and $u.data.ok) "status=$($u.status) $($u.raw)"
    $rel = $u.data.storage_path
    Write-Host "         storage_path: $rel"

    $u2 = Send-Photo "$Base/push_doc.php" $token $Dakhila $DocType $Photo
    Check 'একই ছবি দ্বিতীয়বার → skipped (sha256 dedup)' ($u2.data.skipped -eq $true)

    $tmp = Join-Path $env:TEMP ("dakhila-dl-" + [IO.Path]::GetFileName($Photo))
    Invoke-WebRequest -Uri "$Base/download_file.php?path=$rel" `
      -Headers @{ Authorization = "Bearer $token" } -OutFile $tmp
    $dlHash = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
    Check 'ডাউনলোড করা ছবি হুবহু একই (sha256)' ($dlHash -eq $localHash)
    Remove-Item $tmp -Force

    $r = Call 'GET' "$Base/pull.php?since=2000-01-01%2000:00:00" $token
    $doc = $r.data.documents | Where-Object { $_.dakhila -eq $Dakhila -and $_.doc_type -eq $DocType } | Select-Object -First 1
    Check 'push-এর রেকর্ড pull-এ দেখা যাচ্ছে' ($null -ne $doc)
    if ($doc) {
      Check 'কে তুলেছে তা সংরক্ষিত (captured_by)' ($null -ne $doc.captured_by)
      Check 'is_verified ডিফল্ট 0 (admin approve বাকি)' ($doc.is_verified -eq 0)
    }

    $r = Call 'POST' "$Base/push_doc.php" $token ''
    Check 'ভুল doc_type → 400/METHOD' ($r.status -eq 400 -or $r.status -eq 405 -or $r.status -eq 415)
  }
} else {
  Write-Host "`n  (ছবি-আপলোড পরীক্ষা বাদ — -Photo ও -Dakhila দিন)" -ForegroundColor DarkGray
}

Write-Host "`n=== ফল: $pass পাস • $fail ফেল ===" -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 } else { exit 0 }