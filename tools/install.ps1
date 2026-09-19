# One-line installer for Remielle Astral on Windows (PowerShell)
#
# Usage:
#   irm https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/install.ps1 | iex
#
$ErrorActionPreference = "Stop"

$repo = if ($env:REMIELLE_REPO) { $env:REMIELLE_REPO } else { "thaxao/Remielle-Astral" }
$installDir = "$env:LOCALAPPDATA\Remielle-Astral"
$platform = "windows-x86_64"

Write-Host ""
Write-Host "  Remielle Astral - Windows Installer" -ForegroundColor Cyan
Write-Host "  ====================================" -ForegroundColor DarkGray

Write-Host "==> Fetching latest release information for $repo..." -ForegroundColor Cyan
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ "User-Agent" = "Remielle-Installer" }
    $tag = $release.tag_name
    $asset = $release.assets | Where-Object { $_.name -like "*$platform.zip" } | Select-Object -First 1
    if (-not $asset) {
        throw "Could not find asset for $platform in release $tag"
    }
    $assetUrl = $asset.browser_download_url
} catch {
    Write-Warning "Could not query GitHub API: $_. Trying fallback URL..."
    $tag = "latest"
    $assetUrl = "https://github.com/$repo/releases/latest/download/remielle-astral-windows-x86_64.zip"
}

$tempZip = Join-Path $env:TEMP "remielle-astral-$platform.zip"
$extractTemp = Join-Path $env:TEMP "remielle-extract-$([Guid]::NewGuid().ToString().Substring(0,8))"

Write-Host "==> Downloading Remielle Astral ($tag)..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $assetUrl -OutFile $tempZip -UseBasicParsing

Write-Host "==> Extracting files..." -ForegroundColor Cyan
if (Test-Path $extractTemp) { Remove-Item -Recurse -Force $extractTemp }
Expand-Archive -Path $tempZip -DestinationPath $extractTemp -Force

# Locate extracted contents
$extractedExe = Get-ChildItem -Path $extractTemp -Recurse -Filter "remielle-astral.exe" | Select-Object -First 1
if (-not $extractedExe) {
    throw "remielle-astral.exe was not found in the downloaded archive"
}
$sourceDir = $extractedExe.DirectoryName

Write-Host "==> Installing to $installDir..." -ForegroundColor Cyan
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

# Copy files
Copy-Item -Path "$sourceDir\*" -Destination $installDir -Recurse -Force

# Cleanup temp files
Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue
Remove-Item -Path $extractTemp -Recurse -Force -ErrorAction SilentlyContinue

$exePath = Join-Path $installDir "remielle-astral.exe"

# Create Desktop Shortcut
$wsh = New-Object -ComObject WScript.Shell
$desktopDir = [Environment]::GetFolderPath("Desktop")
$desktopLnk = Join-Path $desktopDir "Remielle Astral.lnk"
$shortcut = $wsh.CreateShortcut($desktopLnk)
$shortcut.TargetPath = $exePath
$shortcut.WorkingDirectory = $installDir
$shortcut.Description = "Remielle Astral - Zenless Zone Zero Launcher"
$shortcut.Save()

# Create Start Menu Shortcut
$startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$startLnk = Join-Path $startMenuDir "Remielle Astral.lnk"
$startShortcut = $wsh.CreateShortcut($startLnk)
$startShortcut.TargetPath = $exePath
$startShortcut.WorkingDirectory = $installDir
$startShortcut.Description = "Remielle Astral - Zenless Zone Zero Launcher"
$startShortcut.Save()

# Add to user PATH if not present
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$installDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$installDir", "User")
}

Write-Host ""
Write-Host "  Installation completed successfully!" -ForegroundColor Green
Write-Host "  - Installed at: $installDir"
Write-Host "  - Desktop and Start Menu shortcuts created"
Write-Host ""

$launch = Read-Host "Would you like to launch Remielle Astral now? (Y/n)"
if ($launch -ne "n" -and $launch -ne "N") {
    Start-Process -FilePath $exePath -WorkingDirectory $installDir
}
