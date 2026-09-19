# ============================================================
# increment_build_number.ps1 - bumps the build number (+N) in
# pubspec.yaml by 1, saves it, and prints the new number.
# Called by build_*.bat via for /f.
# NOTE: ASCII-only messages (Windows PowerShell 5.1 parses
# non-BOM UTF-8 files as ANSI and chokes on Bangla strings).
# ============================================================
$ErrorActionPreference = "Stop"
$pubspec = Join-Path $PSScriptRoot "pubspec.yaml"

try {
    $content = Get-Content $pubspec -Raw
    if ($content -match '(?m)^(version:\s*(\d+\.\d+\.\d+)\+(\d+))\s*$') {
        $newBuild = [int]$Matches[3] + 1
        $newLine = "version: $($Matches[2])+$newBuild"
        $content = $content -replace [regex]::Escape($Matches[1]), $newLine
        Set-Content -Path $pubspec -Value $content -NoNewline -Encoding UTF8
        Write-Host "pubspec.yaml build number incremented: $($Matches[3]) -> $newBuild"
        Write-Output $newBuild
    } else {
        Write-Error "Pattern 'version: x.y.z+N' not found in pubspec.yaml"
        exit 1
    }
} catch {
    Write-Error "Failed to increment build number: $_"
    exit 1
}
