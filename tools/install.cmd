@echo off
setlocal enabledelayedexpansion

echo.
echo   Remielle Astral - Windows Installer (CMD)
echo   =========================================
echo.

:: Check for repository environment variable override
if "%REMIELLE_REPO%"=="" (
    set "REPO=thaxao/Remielle-Astral"
) else (
    set "REPO=%REMIELLE_REPO%"
)

set "POWERSHELL_CMD=powershell -NoProfile -ExecutionPolicy Bypass"

:: Check if local install.ps1 exists in the same directory
if exist "%~dp0install.ps1" (
    echo [INFO] Running local install.ps1...
    %POWERSHELL_CMD% -File "%~dp0install.ps1"
    goto :done
)

:: Otherwise fetch and run install.ps1 from GitHub
where powershell >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo [INFO] Downloading and launching installer via PowerShell...
    %POWERSHELL_CMD% -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $env:REMIELLE_REPO='%REPO%'; [ScriptBlock]::Create((Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/%REPO%/main/tools/install.ps1').Content).Invoke()"
    goto :done
)

:: Fallback if PowerShell is somehow not available
echo [INFO] PowerShell not detected, attempting fallback installation via curl/tar...
set "INSTALL_DIR=%LOCALAPPDATA%\Remielle-Astral"
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

set "ZIP_URL=https://github.com/%REPO%/releases/latest/download/remielle-astral-windows-x86_64.zip"
set "ZIP_FILE=%TEMP%\remielle-astral-windows-x86_64.zip"

echo [INFO] Downloading %ZIP_URL%...
curl -fSL "%ZIP_URL%" -o "%ZIP_FILE%"
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to download package from GitHub.
    exit /b 1
)

echo [INFO] Extracting to %INSTALL_DIR%...
tar -xf "%ZIP_FILE%" -C "%INSTALL_DIR%"
del "%ZIP_FILE%" >nul 2>nul

echo.
echo   Installation completed successfully!
echo   Location: %INSTALL_DIR%
echo.

:done
exit /b 0
