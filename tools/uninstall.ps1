# One-line uninstaller for Remielle Astral on Windows (PowerShell)
#
# Usage:
#   irm https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/uninstall.ps1 | iex
#
$ErrorActionPreference = "Stop"

# 1. Safety Guard: Validate LOCALAPPDATA environment variable
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    Write-Error "Safety Guard: LOCALAPPDATA environment variable is empty. Aborting to protect system."
    exit 1
}

$installDir = Join-Path $env:LOCALAPPDATA "Remielle-Astral"

# 2. Safety Guard: Path verification check
if (-not $installDir.EndsWith("\Remielle-Astral")) {
    Write-Error "Safety Guard: Target install path does not match expected folder. Aborting."
    exit 1
}

$desktopPath = [Environment]::GetFolderPath("Desktop")
$desktopLnk = if (-not [string]::IsNullOrWhiteSpace($desktopPath)) { Join-Path $desktopPath "Remielle Astral.lnk" } else { $null }

$startProgramsPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$startLnk = if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) { Join-Path $startProgramsPath "Remielle Astral.lnk" } else { $null }

Write-Host ""
Write-Host "  Remielle Astral - Windows Uninstaller" -ForegroundColor Cyan
Write-Host "  ======================================" -ForegroundColor DarkGray
Write-Host ""

# Stop running launcher process safely
Write-Host "==> Stopping running launcher instances..." -ForegroundColor Cyan
Get-Process -Name "remielle-astral" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Ask user if they want to wipe configuration / settings
Write-Host ""
Write-Host "ต้องการลบการตั้งค่า (Settings/Config, โฟลเดอร์เซิร์ฟเวอร์/ไคลเอนต์, แคช) ด้วยหรือไม่?" -ForegroundColor Yellow
Write-Host "• หากลบ: ครั้งหน้าเมื่อติดตั้งใหม่ จะต้องผ่านขั้นตอนตั้งค่าเริ่มต้นใหม่ทั้งหมด" -ForegroundColor DarkGray
Write-Host "• หากไม่ลบ: จะเก็บการตั้งค่าไว้ ทำให้ติดตั้งใหม่แล้วใช้งานต่อได้ทันที" -ForegroundColor DarkGray
$removeConfig = Read-Host "ลบการตั้งค่าและแคชด้วยหรือไม่? [y/N]"

Write-Host "==> Removing installed files..." -ForegroundColor Cyan
if (Test-Path -LiteralPath $installDir) {
    if ($removeConfig -match "^[Yy]$") {
        Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [+] Removed all installation files and configuration" -ForegroundColor Green
    } else {
        # Remove executables and assets, keep settings.json and mods/
        Get-ChildItem -LiteralPath $installDir | Where-Object { $_.Name -ne "settings.json" -and $_.Name -ne "mods" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [+] Removed binaries and assets (preserved settings.json for future reinstall)" -ForegroundColor Green
    }
}

# Remove desktop shortcut if it exists
if ($desktopLnk -and (Test-Path -LiteralPath $desktopLnk)) {
    Remove-Item -LiteralPath $desktopLnk -Force -ErrorAction SilentlyContinue
    Write-Host "  [+] Removed Desktop shortcut" -ForegroundColor Green
}

# Remove start menu shortcut if it exists
if ($startLnk -and (Test-Path -LiteralPath $startLnk)) {
    Remove-Item -LiteralPath $startLnk -Force -ErrorAction SilentlyContinue
    Write-Host "  [+] Removed Start Menu shortcut" -ForegroundColor Green
}

# Clean PATH safely without altering other programs
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -and $userPath -like "*$installDir*") {
    $parts = $userPath.Split(';') | Where-Object { $_ -ne $installDir -and -not [string]::IsNullOrWhiteSpace($_) }
    $newPath = $parts -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "  [+] Cleaned up User PATH" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Remielle Astral has been uninstalled successfully." -ForegroundColor Green
Write-Host ""
