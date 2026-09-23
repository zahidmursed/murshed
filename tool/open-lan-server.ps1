#Requires -RunAsAdministrator
<#
Apache-কে LAN-এ খুলে দেয় যাতে একই ওয়াইফাইয়ের ফোন থেকে API পৌঁছানো যায়।
চালান: ডান-ক্লিক → Run with PowerShell (Administrator), অথবা
       powershell -ExecutionPolicy Bypass -File tool\open-lan-server.ps1

ব্যাকআপ না রেখে কনফিগ ছোঁয় না; বদল ইতিমধ্যে করা থাকলে দ্বিতীয়বার চালানো নিরাপদ।
#>
param(
    [switch]$SkipFirewall,
    [switch]$SkipSync
)

$ErrorActionPreference = 'Stop'
$Conf    = 'D:\xampp\apache\conf\httpd.conf'
$SrcDir  = 'D:\dakhila_camera\server'
$WebDir  = 'D:\xampp\htdocs\dakhila_camera'
$RuleName = 'XAMPP Apache HTTP 80'

Write-Host "`n=== ১. httpd.conf ব্যাকআপ ও Listen বদল ===" -ForegroundColor Cyan
$Backup = "$Conf.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $Conf $Backup
Write-Host "ব্যাকআপ: $Backup"

$Original = Get-Content $Conf
$Updated  = $Original | ForEach-Object {
    if ($_ -match '^\s*Listen\s+127\.0\.0\.1:80\s*$') { 'Listen 80' } else { $_ }
}

if (($Updated -join "`n") -eq ($Original -join "`n")) {
    Write-Host "Listen ইতিমধ্যে 127.0.0.1-এ সীমিত নয় — কিছু বদলাল না।" -ForegroundColor Yellow
} else {
    Set-Content -Path $Conf -Value $Updated -Encoding Ascii
    Write-Host "Listen 127.0.0.1:80  ->  Listen 80" -ForegroundColor Green
}

Write-Host "`n=== ২. সার্ভার ফাইল htdocs-এ কপি ===" -ForegroundColor Cyan
if ($SkipSync) {
    Write-Host "বাদ দেওয়া হলো (-SkipSync)" -ForegroundColor Yellow
} else {
    # /XD uploads — আপলোড হওয়া ছাত্র-ছবি/ডকুমেন্ট যেন মুছে বা বদলে না যায়
    robocopy $SrcDir $WebDir /E /XD "$SrcDir\uploads" "$WebDir\uploads" /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy ব্যর্থ (কোড $LASTEXITCODE)" }
    Write-Host "সিঙ্ক সম্পন্ন (robocopy কোড $LASTEXITCODE; uploads অক্ষুণ্ণ)।" -ForegroundColor Green
}

Write-Host "`n=== ৩. ফায়ারওয়াল (শুধু Private নেটওয়ার্ক) ===" -ForegroundColor Cyan
if ($SkipFirewall) {
    Write-Host "বাদ দেওয়া হলো (-SkipFirewall)" -ForegroundColor Yellow
} elseif (Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue) {
    Write-Host "নিয়ম আগে থেকেই আছে।" -ForegroundColor Yellow
} else {
    New-NetFirewallRule -DisplayName $RuleName -Direction Inbound -Protocol TCP `
        -LocalPort 80 -Action Allow -Profile Private | Out-Null
    Write-Host "ইনবাউন্ড TCP 80 খোলা হলো (Private প্রোফাইল)।" -ForegroundColor Green
}

Write-Host "`n=== ৪. Apache সার্ভিস রিস্টার্ট ===" -ForegroundColor Cyan
Restart-Service Apache2.4
Start-Sleep -Seconds 4
Write-Host "অবস্থা: $((Get-Service Apache2.4).Status)"

Write-Host "`n=== ৫. যাচাই ===" -ForegroundColor Cyan
$IPs = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -ExpandProperty IPAddress

foreach ($Target in (@('127.0.0.1') + $IPs)) {
    $Url = "http://$Target/dakhila_camera/api/ping.php"
    try {
        $R = Invoke-WebRequest $Url -UseBasicParsing -TimeoutSec 8
        Write-Host "OK   $Url`n     $($R.Content)" -ForegroundColor Green
    } catch {
        Write-Host "FAIL $Url  ($($_.Exception.Message))" -ForegroundColor Red
    }
}

Write-Host @"

--- শেষ ---
ফোনের অ্যাপে Settings > সিঙ্ক-এ এই ঠিকানা লিখুন (http:// ছাড়াও চলে):

$(if ($IPs) { "    $($IPs[0])/dakhila_camera" } else { '    <পিসির IP>/dakhila_camera' })

ঠিকানাটি রাউটার থেকে DHCP-তে আসে, তাই পাল্টে যেতে পারে। বদলালে
ipconfig চালিয়ে নতুন IPv4 দেখে নিন।

ফিরিয়ে নিতে: ব্যাকআপ ফাইলটি httpd.conf-এ কপি করে Apache2.4 রিস্টার্ট করুন,
এবং নিয়ম মুছতে  Remove-NetFirewallRule -DisplayName '$RuleName'
"@
