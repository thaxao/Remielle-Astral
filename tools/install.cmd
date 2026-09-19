@echo off
:: Remielle Astral installer for Windows: runs install.ps1 from this folder, or
:: the published copy when this file was downloaded on its own.  Arguments
:: pass through, for example:  install.cmd -Version v1.1.2.b3.3.2-alpha
setlocal
if "%REMIELLE_REPO%"=="" (set "REPO=thaxao/Remielle-Astral") else (set "REPO=%REMIELLE_REPO%")
where powershell >nul 2>nul
if errorlevel 1 (
    echo PowerShell is needed ^(it comes with Windows 10 and 11^).
    exit /b 1
)
if exist "%~dp0install.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; & ([scriptblock]::Create((Invoke-RestMethod -UseBasicParsing 'https://raw.githubusercontent.com/%REPO%/main/tools/install.ps1'))) %*"
)
set "CODE=%ERRORLEVEL%"
:: Opened by a double click: keep the window until the result is read.
echo %CMDCMDLINE% | find /i "%~0" >nul && pause
exit /b %CODE%
