# Remielle Astral installer for Windows (PowerShell 5.1 or 7).
#
#   irm https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/install.ps1 | iex
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/install.ps1))) -Version v1.1.2.b3.3.2-alpha
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Zip .\remielle-astral-1.1.2.b3.3.2-alpha-windows-x86_64.zip
#
#   -Version TAG    install that release instead of the newest ("v" optional)
#   -Zip FILE       install a zip already downloaded; a SHA256SUMS beside it is checked
#   -Dir DIR        install folder (default %LOCALAPPDATA%\Remielle-Astral)
#   -Check          only show what is installed and what the newest release is
#   -Rollback       put back the version the last install replaced
#   -Force          reinstall even when that version is already installed
#   -NoShortcuts    no Desktop / Start menu shortcuts and no Apps & features entry
#   -NoLaunch       do not offer to start it afterwards
#   -Yes            answer every question with its default
#
# Only the program's own files (the release's MANIFEST) are replaced:
# settings.json, the saves, the Custom server, the mod library and the caches
# in the same folder are never touched.  The version being replaced is kept
# for -Rollback.  The install is listed in Settings > Apps, whose Uninstall
# button runs tools\uninstall.ps1.
#
# Environment: REMIELLE_REPO=owner/name (default thaxao/Remielle-Astral),
# REMIELLE_RELEASES_URL=<a releases list in the GitHub shape> for a mirror.
#
# The file is plain ASCII on purpose: Windows PowerShell 5.1 reads a script
# without a byte-order mark in the ANSI code page, so the Thai messages are
# written as \u escapes and decoded when shown.

param(
    [string]$Version = $env:REMIELLE_VERSION,
    [string]$Zip = "",
    [string]$Dir = "",
    [switch]$Check,
    [switch]$Rollback,
    [switch]$Force,
    [switch]$NoShortcuts,
    [switch]$NoLaunch,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # the progress bar slows downloads tenfold in 5.1

$Repo = if ($env:REMIELLE_REPO) { $env:REMIELLE_REPO } else { "thaxao/Remielle-Astral" }
$Platform = "windows-x86_64"
$AppKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\RemielleAstral"
$LegacyFiles = @(
    "remielle-astral.exe", "Remielle Astral.exe", "remielle-astral.exe.old", "README.md", "LICENSE", "icon.png", "MANIFEST",
    "tools/remielle-update", "tools/build-official-patch", "tools/import-patch",
    "tools/install.sh", "tools/install.ps1", "tools/install.cmd",
    "tools/uninstall.sh", "tools/uninstall.ps1", "tools/uninstall.cmd",
    "patch/Pryce.exe", "patch/Armorer.dll"
)
$script:Thai = $false
$script:Sha = ""

# ------------------------------------------------------------------ output --
# T "english {0}" "thai {0}" args...: the message in the user's language.
function T([string]$En, [string]$Th) {
    $text = if ($script:Thai -and $Th) { [regex]::Unescape($Th) } else { $En }
    if ($args.Count -gt 0) { return $text -f $args }
    return $text
}
function Say([string]$m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok([string]$m) { Write-Host "  [+] $m" -ForegroundColor Green }
function Note([string]$m) { Write-Host "  [.] $m" -ForegroundColor DarkGray }
function Warn([string]$m) { Write-Host "  [!] $m" -ForegroundColor Yellow }
function Fail([string]$m) { throw $m }

function Ask([string]$Question, [bool]$Default) {
    if ($Yes -or -not [Environment]::UserInteractive) { return $Default }
    $hint = if ($Default) { "[Y/n]" } else { "[y/N]" }
    try { $answer = Read-Host "$Question $hint" } catch { return $Default }
    if ($answer -match '^[Yy]') { return $true }
    if ($answer -match '^[Nn]') { return $false }
    return $Default
}

# ---------------------------------------------------------------- versions --
# Is $A newer than $B?  The launcher's rules: LAUNCHER.bGAME numbers first
# (the "b" is skipped), then a release beats a pre-release, then pre-release
# names in order.  Anything after a space is a label.
function Test-Newer([string]$A, [string]$B) {
    $a = ($A.Trim() -replace '^[vV]', '').Split(' ')[0]
    $b = ($B.Trim() -replace '^[vV]', '').Split(' ')[0]
    $an, $ap = $a.Split('-', 2)
    $bn, $bp = $b.Split('-', 2)
    $as = $an.Split('.'); $bs = $bn.Split('.')
    for ($i = 0; $i -lt 8; $i++) {
        $x = 0; $y = 0
        if ($i -lt $as.Count) { [void][int]::TryParse(($as[$i] -replace '^[A-Za-z]+', ''), [ref]$x) }
        if ($i -lt $bs.Count) { [void][int]::TryParse(($bs[$i] -replace '^[A-Za-z]+', ''), [ref]$y) }
        if ($x -ne $y) { return $x -gt $y }
    }
    if (-not $ap -and $bp) { return $true }
    if ($ap -and -not $bp) { return $false }
    return [string]::CompareOrdinal([string]$ap, [string]$bp) -gt 0
}

function Get-ExeIn([string]$Folder) {
    foreach ($n in @("remielle-astral.exe", "Remielle Astral.exe")) {
        $p = Join-Path $Folder $n
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

# The version of the launcher in $Folder, or "".  A build that knows
# --version says so in its usage text; an older one would open its window
# instead, so it is only asked when it can answer.
function Get-VersionIn([string]$Folder) {
    $exe = Get-ExeIn $Folder
    if ($exe) {
        try {
            $bytes = [IO.File]::ReadAllBytes($exe)
            $text = [Text.Encoding]::ASCII.GetString($bytes)
            if ($text.Contains("usage: remielle-astral [--version")) {
                $psi = New-Object Diagnostics.ProcessStartInfo
                $psi.FileName = $exe
                $psi.Arguments = "--version"
                $psi.UseShellExecute = $false
                $psi.RedirectStandardOutput = $true
                $psi.CreateNoWindow = $true
                $p = [Diagnostics.Process]::Start($psi)
                $out = $p.StandardOutput.ReadToEnd()
                if (-not $p.WaitForExit(5000)) { $p.Kill() }
                $v = ($out -split "`r?`n")[0].Trim()
                if ($v) { return $v }
            }
        } catch { }
    }
    $info = Join-Path $Folder ".install-info"
    if (Test-Path -LiteralPath $info) {
        foreach ($line in Get-Content -LiteralPath $info) {
            if ($line -like "version=*") { return $line.Substring(8) }
        }
    }
    return ""
}

# ------------------------------------------------------------------- files --
function Get-SafePaths([string[]]$Lines) {
    $Lines | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -and -not $_.StartsWith("/") -and -not $_.StartsWith("\") -and $_ -notmatch '(^|[/\\])\.\.([/\\]|$)' -and $_ -notmatch '^[A-Za-z]:'
    }
}

# The program's own files in $Folder: its MANIFEST, else the known list.
function Get-ProgramFiles([string]$Folder) {
    $m = Join-Path $Folder "MANIFEST"
    if (Test-Path -LiteralPath $m) { return @(Get-SafePaths (Get-Content -LiteralPath $m)) }
    return $LegacyFiles
}

function Get-Tree([string]$Folder) {
    $root = (Resolve-Path -LiteralPath $Folder).Path.TrimEnd('\', '/')
    Get-ChildItem -LiteralPath $Folder -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($root.Length + 1).Replace('\', '/')
    } | Sort-Object
}

# Launcher processes started from $Folder (by their path, so nothing else is
# touched; the servers keep running).
function Get-LauncherProcesses([string]$Folder) {
    $names = @((Join-Path $Folder "remielle-astral.exe"), (Join-Path $Folder "Remielle Astral.exe"))
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and ($names -contains $_.Path) } catch { $false }
    }
}

function Stop-Launcher([string]$Folder) {
    $procs = @(Get-LauncherProcesses $Folder)
    if ($procs.Count -eq 0) { return }
    $ids = ($procs | ForEach-Object { $_.Id }) -join ", "
    if (-not (Ask (T "Remielle Astral is open (pid {0}). Close it to continue?" "Remielle Astral \u0e40\u0e1b\u0e34\u0e14\u0e2d\u0e22\u0e39\u0e48 (pid {0}) \u0e1b\u0e34\u0e14\u0e40\u0e1e\u0e37\u0e48\u0e2d\u0e17\u0e33\u0e15\u0e48\u0e2d\u0e44\u0e2b\u0e21?" $ids) $true)) {
        Fail (T "Close Remielle Astral and run this again." "\u0e1b\u0e34\u0e14 Remielle Astral \u0e41\u0e25\u0e49\u0e27\u0e23\u0e31\u0e19\u0e43\u0e2b\u0e21\u0e48\u0e2d\u0e35\u0e01\u0e04\u0e23\u0e31\u0e49\u0e07")
    }
    foreach ($p in $procs) { try { [void]$p.CloseMainWindow() } catch { } }
    for ($i = 0; $i -lt 50 -and @(Get-LauncherProcesses $Folder).Count -gt 0; $i++) { Start-Sleep -Milliseconds 100 }
    Get-LauncherProcesses $Folder | ForEach-Object { try { $_.Kill() } catch { } }
    Start-Sleep -Milliseconds 300
    Ok (T "Closed Remielle Astral (running servers keep going)" "\u0e1b\u0e34\u0e14 Remielle Astral \u0e41\u0e25\u0e49\u0e27 (\u0e40\u0e0b\u0e34\u0e23\u0e4c\u0e1f\u0e17\u0e35\u0e48\u0e23\u0e31\u0e19\u0e2d\u0e22\u0e39\u0e48\u0e22\u0e31\u0e07\u0e17\u0e33\u0e07\u0e32\u0e19\u0e15\u0e48\u0e2d)")
}

# Copies the program in $From over $Dir.  What it replaces goes to
# .remielle-cache\previous for -Rollback, and files the old version had and
# the new one does not are removed.  Everything else in $Dir stays.
function Install-From([string]$From) {
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    $manifest = Join-Path $From "MANIFEST"
    if (-not (Test-Path -LiteralPath $manifest)) {
        $list = @(Get-Tree $From) + "MANIFEST" | Sort-Object -Unique
        Set-Content -LiteralPath $manifest -Value $list -Encoding ASCII
    }
    $newList = @(Get-ProgramFiles $From)
    $prev = Join-Path $Dir ".remielle-cache/previous"

    if (Get-ExeIn $Dir) {
        $oldList = @(Get-ProgramFiles $Dir)
        $stage = "$prev.new"
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        foreach ($f in $oldList) {
            $src = Join-Path $Dir $f
            if (Test-Path -LiteralPath $src -PathType Leaf) {
                $dst = Join-Path $stage $f
                New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
                Copy-Item -LiteralPath $src -Destination $dst -Force
            }
        }
        $kept = @(Get-Tree $stage | Where-Object { $_ -ne "MANIFEST" }) + "MANIFEST" | Sort-Object -Unique
        Set-Content -LiteralPath (Join-Path $stage "MANIFEST") -Value $kept -Encoding ASCII
        if (Test-Path -LiteralPath $prev) { Remove-Item -LiteralPath $prev -Recurse -Force }
        Move-Item -LiteralPath $stage -Destination $prev
        foreach ($f in $oldList) {
            if ($newList -notcontains $f) {
                $p = Join-Path $Dir $f
                if (Test-Path -LiteralPath $p -PathType Leaf) { Remove-Item -LiteralPath $p -Force }
            }
        }
    }

    foreach ($f in $newList) {
        $src = Join-Path $From $f
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { continue }
        $dst = Join-Path $Dir $f
        New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
        Copy-Item -LiteralPath $src -Destination "$dst.astral-new" -Force
        Move-Item -LiteralPath "$dst.astral-new" -Destination $dst -Force
    }
    foreach ($sub in @("tools", "patch")) {
        $p = Join-Path $Dir $sub
        if ((Test-Path -LiteralPath $p) -and -not (Get-ChildItem -LiteralPath $p -Force)) { Remove-Item -LiteralPath $p }
    }
}

function Write-Info([string]$V, [string]$Tag, [string]$Source) {
    $lines = @("version=$V", "tag=$Tag", "source=$Source", "sha256=$($script:Sha)", "installed_at=$((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))")
    Set-Content -LiteralPath (Join-Path $Dir ".install-info") -Value $lines -Encoding ASCII
}

# --------------------------------------------------------------- releases --
# The newest release (or the one tagged $Version) with a launcher zip for
# Windows; releases that carry only the Custom server are passed over.
function Resolve-Release {
    $url = if ($env:REMIELLE_RELEASES_URL) { $env:REMIELLE_RELEASES_URL } else { "https://api.github.com/repos/$Repo/releases?per_page=30" }
    $releases = @()
    try {
        $releases = @(Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = "Remielle-Astral-installer"; "Accept" = "application/vnd.github+json" })
    } catch {
        if (-not $Version) {
            Fail (T "Could not reach the release list of {0} (offline, or GitHub's hourly limit). Try again later, or use -Version TAG or -Zip FILE." "\u0e40\u0e02\u0e49\u0e32\u0e16\u0e36\u0e07\u0e23\u0e32\u0e22\u0e01\u0e32\u0e23 release \u0e02\u0e2d\u0e07 {0} \u0e44\u0e21\u0e48\u0e44\u0e14\u0e49 (\u0e2d\u0e2d\u0e1f\u0e44\u0e25\u0e19\u0e4c \u0e2b\u0e23\u0e37\u0e2d\u0e40\u0e01\u0e34\u0e19\u0e42\u0e04\u0e27\u0e15\u0e32 GitHub) \u0e25\u0e2d\u0e07\u0e43\u0e2b\u0e21\u0e48\u0e20\u0e32\u0e22\u0e2b\u0e25\u0e31\u0e07 \u0e2b\u0e23\u0e37\u0e2d\u0e43\u0e0a\u0e49 -Version / -Zip" $Repo)
        }
    }
    $want = if ($Version) { $Version -replace '^[vV]', '' } else { "" }
    foreach ($r in ($releases | ForEach-Object { $_ })) {
        if ($r.draft) { continue }
        if ($want -and (($r.tag_name -replace '^[vV]', '') -ne $want)) { continue }
        $zip = $r.assets | Where-Object { $_.name -match "^remielle-astral-.+-$Platform\.zip$" } | Select-Object -First 1
        if (-not $zip) { continue }
        $sums = $r.assets | Where-Object { $_.name -eq "SHA256SUMS" } | Select-Object -First 1
        return [pscustomobject]@{
            Tag = $r.tag_name; Url = $zip.browser_download_url; Name = $zip.name
            SumsUrl = if ($sums) { $sums.browser_download_url } else { "" }
            Version = ($zip.name -replace '^remielle-astral-', '') -replace "-$Platform\.zip$", ''
        }
    }
    if ($want) {
        $name = "remielle-astral-$want-$Platform.zip"
        return [pscustomobject]@{
            Tag = "v$want"; Url = "https://github.com/$Repo/releases/download/v$want/$name"; Name = $name
            SumsUrl = "https://github.com/$Repo/releases/download/v$want/SHA256SUMS"; Version = $want
        }
    }
    Fail (T "No release of {0} carries remielle-astral-*-{1}.zip yet." "\u0e22\u0e31\u0e07\u0e44\u0e21\u0e48\u0e21\u0e35 release \u0e02\u0e2d\u0e07 {0} \u0e17\u0e35\u0e48\u0e21\u0e35 remielle-astral-*-{1}.zip" $Repo $Platform)
}

function Get-File([string]$Url, [string]$OutFile) {
    if ($Url -like "file://*") { Copy-Item -LiteralPath ([Uri]$Url).LocalPath -Destination $OutFile -Force; return }
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -Headers @{ "User-Agent" = "Remielle-Astral-installer" }
}

# The zip against the SHA256SUMS line for its name; the launcher's own
# updater refuses the same way.
function Confirm-Sum([string]$ZipPath, [string]$SumsPath, [string]$Name) {
    $want = ""
    foreach ($line in Get-Content -LiteralPath $SumsPath) {
        $parts = $line.Trim() -split '\s+', 2
        if ($parts.Count -eq 2 -and $parts[1].TrimStart('*') -eq $Name) { $want = $parts[0].ToLower(); break }
    }
    if (-not $want) { Fail (T "SHA256SUMS has no line for {0}; nothing was installed." "SHA256SUMS \u0e44\u0e21\u0e48\u0e21\u0e35\u0e1a\u0e23\u0e23\u0e17\u0e31\u0e14\u0e02\u0e2d\u0e07 {0} \u0e08\u0e36\u0e07\u0e44\u0e21\u0e48\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07" $Name) }
    $have = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLower()
    if ($want -ne $have) { Fail (T "{0} does not match its SHA256SUMS (damaged or altered download); nothing was installed." "{0} \u0e44\u0e21\u0e48\u0e15\u0e23\u0e07\u0e01\u0e31\u0e1a SHA256SUMS (\u0e44\u0e1f\u0e25\u0e4c\u0e40\u0e2a\u0e35\u0e22\u0e2b\u0e23\u0e37\u0e2d\u0e16\u0e39\u0e01\u0e41\u0e01\u0e49) \u0e08\u0e36\u0e07\u0e44\u0e21\u0e48\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07" $Name) }
    $script:Sha = $have
}

# ----------------------------------------------------------- system checks --
function Test-WebView2 {
    $id = "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
    foreach ($k in @("HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$id", "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$id", "HKCU:\Software\Microsoft\EdgeUpdate\Clients\$id")) {
        try { $pv = (Get-ItemProperty -Path $k -ErrorAction Stop).pv; if ($pv -and $pv -ne "0.0.0.0") { return $pv } } catch { }
    }
    return ""
}

function Show-Checks {
    $wv = Test-WebView2
    if ($wv) { Ok (T "WebView2 Runtime {0} is present" "\u0e21\u0e35 WebView2 Runtime {0} \u0e41\u0e25\u0e49\u0e27" $wv) }
    else { Warn (T "The WebView2 Runtime was not found; the launcher offers to install it on first start (or get it from https://go.microsoft.com/fwlink/p/?LinkId=2124703)." "\u0e44\u0e21\u0e48\u0e1e\u0e1a WebView2 Runtime \u0e25\u0e31\u0e19\u0e40\u0e0a\u0e2d\u0e23\u0e4c\u0e08\u0e30\u0e40\u0e2a\u0e19\u0e2d\u0e43\u0e2b\u0e49\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07\u0e15\u0e2d\u0e19\u0e40\u0e1b\u0e34\u0e14\u0e04\u0e23\u0e31\u0e49\u0e07\u0e41\u0e23\u0e01") }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Note (T "Git for Windows is not installed: needed only for the Official server and patch." "\u0e22\u0e31\u0e07\u0e44\u0e21\u0e48\u0e21\u0e35 Git for Windows: \u0e43\u0e0a\u0e49\u0e40\u0e09\u0e1e\u0e32\u0e30\u0e40\u0e0b\u0e34\u0e23\u0e4c\u0e1f\u0e41\u0e25\u0e30\u0e41\u0e1e\u0e15\u0e0a\u0e4c Official")
    }
}

# ---------------------------------------------------------------- shortcuts --
function Set-Shortcut([string]$Path, [string]$Target) {
    $wsh = New-Object -ComObject WScript.Shell
    if (Test-Path -LiteralPath $Path) {
        $old = $wsh.CreateShortcut($Path).TargetPath
        if ($old -and -not $old.StartsWith($Dir, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $old)) {
            Note (T "Left {0}: it starts a Remielle Astral elsewhere ({1})" "\u0e44\u0e21\u0e48\u0e41\u0e15\u0e30 {0} \u0e40\u0e1e\u0e23\u0e32\u0e30\u0e40\u0e1b\u0e34\u0e14 Remielle Astral \u0e17\u0e35\u0e48\u0e2d\u0e37\u0e48\u0e19 ({1})" $Path $old)
            return
        }
    }
    $s = $wsh.CreateShortcut($Path)
    $s.TargetPath = $Target
    $s.WorkingDirectory = $Dir
    $s.IconLocation = "$Target,0"
    $s.Description = "Remielle Astral - Zenless Zone Zero server launcher"
    $s.Save()
}

function Set-Integration([string]$V) {
    $exe = Get-ExeIn $Dir
    $desktop = [Environment]::GetFolderPath("Desktop")
    if ($desktop) { Set-Shortcut (Join-Path $desktop "Remielle Astral.lnk") $exe }
    $programs = [Environment]::GetFolderPath("Programs")
    if ($programs) { Set-Shortcut (Join-Path $programs "Remielle Astral.lnk") $exe }
    Ok (T "Desktop and Start menu shortcuts" "\u0e17\u0e32\u0e07\u0e25\u0e31\u0e14\u0e1a\u0e19 Desktop \u0e41\u0e25\u0e30 Start menu")

    # Settings > Apps lists it, and its Uninstall button runs uninstall.ps1.
    $uninstall = Join-Path $Dir "tools\uninstall.ps1"
    $size = [int]((Get-ChildItem -LiteralPath $Dir -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notlike "*\.remielle-cache\*" } | Measure-Object Length -Sum).Sum / 1KB)
    New-Item -Path $AppKey -Force | Out-Null
    $values = @{
        DisplayName = "Remielle Astral"; DisplayVersion = $V; Publisher = "thaxao"
        DisplayIcon = $exe; InstallLocation = $Dir; URLInfoAbout = "https://github.com/$Repo"
        UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$uninstall`""
        QuietUninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$uninstall`" -Yes"
    }
    foreach ($k in $values.Keys) { Set-ItemProperty -Path $AppKey -Name $k -Value $values[$k] }
    Set-ItemProperty -Path $AppKey -Name NoModify -Value 1 -Type DWord
    Set-ItemProperty -Path $AppKey -Name NoRepair -Value 1 -Type DWord
    Set-ItemProperty -Path $AppKey -Name EstimatedSize -Value $size -Type DWord
    Ok (T "Listed in Settings > Apps (Uninstall works from there)" "\u0e2d\u0e22\u0e39\u0e48\u0e43\u0e19 Settings > Apps (\u0e16\u0e2d\u0e19\u0e01\u0e32\u0e23\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07\u0e08\u0e32\u0e01\u0e15\u0e23\u0e07\u0e19\u0e31\u0e49\u0e19\u0e44\u0e14\u0e49)")
}

# ------------------------------------------------------------------- modes --
function Invoke-Check {
    $have = Get-VersionIn $Dir
    $rel = Resolve-Release
    Say "Remielle Astral"
    $none = T "not installed" "\u0e22\u0e31\u0e07\u0e44\u0e21\u0e48\u0e44\u0e14\u0e49\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07"
    Note ((T "Installed: {0} ({1})" "\u0e17\u0e35\u0e48\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07: {0} ({1})" $(if ($have) { $have } else { $none }) $Dir))
    Note (T "Newest: {0} ({1})" "\u0e43\u0e2b\u0e21\u0e48\u0e2a\u0e38\u0e14: {0} ({1})" $rel.Version $rel.Tag)
    if ($have -and (Test-Newer $rel.Version $have)) { Ok (T "An update is available: run this installer again." "\u0e21\u0e35\u0e2d\u0e31\u0e1e\u0e40\u0e14\u0e17: \u0e23\u0e31\u0e19\u0e15\u0e31\u0e27\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07\u0e19\u0e35\u0e49\u0e2d\u0e35\u0e01\u0e04\u0e23\u0e31\u0e49\u0e07") }
    elseif ($have) { Ok (T "Up to date." "\u0e40\u0e1b\u0e47\u0e19\u0e23\u0e38\u0e48\u0e19\u0e25\u0e48\u0e32\u0e2a\u0e38\u0e14\u0e41\u0e25\u0e49\u0e27") }
}

function Invoke-Rollback([string]$Temp) {
    $prev = Join-Path $Dir ".remielle-cache/previous"
    if (-not (Get-ExeIn $prev)) { Fail (T "There is no earlier version to put back." "\u0e44\u0e21\u0e48\u0e21\u0e35\u0e23\u0e38\u0e48\u0e19\u0e01\u0e48\u0e2d\u0e19\u0e2b\u0e19\u0e49\u0e32\u0e43\u0e2b\u0e49\u0e22\u0e49\u0e2d\u0e19\u0e01\u0e25\u0e31\u0e1a") }
    $v = Get-VersionIn $prev
    if (-not (Ask (T "Put back {0}?" "\u0e22\u0e49\u0e2d\u0e19\u0e01\u0e25\u0e31\u0e1a\u0e40\u0e1b\u0e47\u0e19 {0} \u0e44\u0e2b\u0e21?" $(if ($v) { $v } else { "the previous version" })) $true)) { return }
    Stop-Launcher $Dir
    $copy = Join-Path $Temp "previous"
    Copy-Item -LiteralPath $prev -Destination $copy -Recurse -Force
    Install-From $copy
    Write-Info $(if ($v) { $v } else { "unknown" }) "" "rollback"
    Ok (T "Rolled back; -Rollback again undoes it." "\u0e22\u0e49\u0e2d\u0e19\u0e01\u0e25\u0e31\u0e1a\u0e41\u0e25\u0e49\u0e27 \u0e23\u0e31\u0e19 -Rollback \u0e2d\u0e35\u0e01\u0e04\u0e23\u0e31\u0e49\u0e07\u0e40\u0e1e\u0e37\u0e48\u0e2d\u0e01\u0e25\u0e31\u0e1a")
}

function Invoke-Install([string]$Temp) {
    $have = Get-VersionIn $Dir
    if ($Zip) {
        if (-not (Test-Path -LiteralPath $Zip)) { Fail "$Zip does not exist" }
        $zipFull = (Resolve-Path -LiteralPath $Zip).Path
        $name = Split-Path $zipFull -Leaf
        $rel = [pscustomobject]@{ Tag = ""; Url = "file:///$($zipFull.Replace('\', '/'))"; Name = $name; SumsUrl = ""
            Version = ($name -replace '^remielle-astral-', '') -replace "-$Platform\.zip$", '' }
    } else {
        Say (T "Looking up releases of {0}" "\u0e15\u0e23\u0e27\u0e08 release \u0e02\u0e2d\u0e07 {0}" $Repo)
        $rel = Resolve-Release
    }

    if (-not $have -and (Get-ExeIn $Dir)) {
        Note (T "Installed: an older build  ->  {0}" "\u0e17\u0e35\u0e48\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07: \u0e23\u0e38\u0e48\u0e19\u0e40\u0e01\u0e48\u0e32  ->  {0}" $rel.Version)
    } elseif ($have) {
        Note (T "Installed: {0}  ->  {1}" "\u0e17\u0e35\u0e48\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07: {0}  ->  {1}" $have $rel.Version)
        if ($have -eq $rel.Version -and -not $Force) {
            if (-not (Ask (T "{0} is already installed. Reinstall it?" "\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07 {0} \u0e2d\u0e22\u0e39\u0e48\u0e41\u0e25\u0e49\u0e27 \u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07\u0e0b\u0e49\u0e33\u0e44\u0e2b\u0e21?" $have) $false)) {
                Ok (T "Already up to date; nothing changed." "\u0e40\u0e1b\u0e47\u0e19\u0e23\u0e38\u0e48\u0e19\u0e25\u0e48\u0e32\u0e2a\u0e38\u0e14\u0e2d\u0e22\u0e39\u0e48\u0e41\u0e25\u0e49\u0e27 \u0e44\u0e21\u0e48\u0e44\u0e14\u0e49\u0e40\u0e1b\u0e25\u0e35\u0e48\u0e22\u0e19\u0e2d\u0e30\u0e44\u0e23")
                return
            }
        } elseif (Test-Newer $have $rel.Version) {
            if (-not (Ask (T "{0} is older than the installed {1}. Install it anyway?" "{0} \u0e40\u0e01\u0e48\u0e32\u0e01\u0e27\u0e48\u0e32 {1} \u0e17\u0e35\u0e48\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07\u0e2d\u0e22\u0e39\u0e48 \u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07\u0e15\u0e48\u0e2d\u0e44\u0e2b\u0e21?" $rel.Version $have) $false)) { return }
        }
    }

    $zipPath = Join-Path $Temp $rel.Name
    if ($Zip) {
        Copy-Item -LiteralPath $zipFull -Destination $zipPath -Force
        $sums = Join-Path (Split-Path $zipFull) "SHA256SUMS"
        if (Test-Path -LiteralPath $sums) { Confirm-Sum $zipPath $sums $rel.Name; Ok "SHA256 OK" }
        else {
            $script:Sha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLower()
            Warn (T "No SHA256SUMS beside the zip: it is installed unchecked." "\u0e44\u0e21\u0e48\u0e21\u0e35 SHA256SUMS \u0e02\u0e49\u0e32\u0e07 zip \u0e08\u0e36\u0e07\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07\u0e42\u0e14\u0e22\u0e44\u0e21\u0e48\u0e44\u0e14\u0e49\u0e15\u0e23\u0e27\u0e08")
        }
    } else {
        Say ((T "Downloading" "\u0e14\u0e32\u0e27\u0e19\u0e4c\u0e42\u0e2b\u0e25\u0e14") + " " + $rel.Name)
        Get-File $rel.Url $zipPath
        if (-not $rel.SumsUrl) { Fail (T "The release has no SHA256SUMS, so the download cannot be checked; nothing was installed." "release \u0e19\u0e35\u0e49\u0e44\u0e21\u0e48\u0e21\u0e35 SHA256SUMS \u0e15\u0e23\u0e27\u0e08\u0e44\u0e1f\u0e25\u0e4c\u0e44\u0e21\u0e48\u0e44\u0e14\u0e49 \u0e08\u0e36\u0e07\u0e44\u0e21\u0e48\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07") }
        $sums = Join-Path $Temp "SHA256SUMS"
        Get-File $rel.SumsUrl $sums
        Confirm-Sum $zipPath $sums $rel.Name
        Ok "SHA256 OK"
    }

    $unpacked = Join-Path $Temp "unpacked"
    Expand-Archive -LiteralPath $zipPath -DestinationPath $unpacked -Force
    $exe = Get-ChildItem -LiteralPath $unpacked -Recurse -File | Where-Object { $_.Name -in @("remielle-astral.exe", "Remielle Astral.exe") } | Select-Object -First 1
    if (-not $exe) { Fail (T "The zip holds no remielle-astral.exe." "\u0e43\u0e19 zip \u0e44\u0e21\u0e48\u0e21\u0e35 remielle-astral.exe") }
    $root = $exe.DirectoryName
    $fs = [IO.File]::OpenRead($exe.FullName)
    $m0 = $fs.ReadByte(); $m1 = $fs.ReadByte(); $fs.Close()
    if ($m0 -ne 0x4D -or $m1 -ne 0x5A) { Fail (T "remielle-astral.exe in the zip is not a Windows program." "remielle-astral.exe \u0e43\u0e19 zip \u0e44\u0e21\u0e48\u0e43\u0e0a\u0e48\u0e42\u0e1b\u0e23\u0e41\u0e01\u0e23\u0e21 Windows") }
    $built = Get-VersionIn $root
    $newVersion = if ($built) { $built } else { $rel.Version }
    Show-Checks

    Stop-Launcher $Dir
    Say ((T "Installing {0} -> {1}" "\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07 {0} -> {1}" $newVersion $Dir))
    Install-From $root
    Write-Info $newVersion $rel.Tag $rel.Url
    Ok (T "Program files replaced; settings, saves and mods kept" "\u0e41\u0e17\u0e19\u0e17\u0e35\u0e48\u0e44\u0e1f\u0e25\u0e4c\u0e42\u0e1b\u0e23\u0e41\u0e01\u0e23\u0e21\u0e41\u0e25\u0e49\u0e27 \u0e01\u0e32\u0e23\u0e15\u0e31\u0e49\u0e07\u0e04\u0e48\u0e32 \u0e40\u0e0b\u0e1f \u0e41\u0e25\u0e30\u0e21\u0e47\u0e2d\u0e14\u0e22\u0e31\u0e07\u0e2d\u0e22\u0e39\u0e48\u0e04\u0e23\u0e1a")
    if (Test-Path -LiteralPath (Join-Path $Dir ".remielle-cache/previous")) {
        Note (T "The replaced version is kept for: install.ps1 -Rollback" "\u0e40\u0e01\u0e47\u0e1a\u0e23\u0e38\u0e48\u0e19\u0e40\u0e14\u0e34\u0e21\u0e44\u0e27\u0e49\u0e2a\u0e33\u0e2b\u0e23\u0e31\u0e1a: install.ps1 -Rollback")
    }
    if (-not $NoShortcuts) { Set-Integration $newVersion }

    Write-Host ""
    Write-Host (T "Remielle Astral {0} is installed." "\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07 Remielle Astral {0} \u0e40\u0e23\u0e35\u0e22\u0e1a\u0e23\u0e49\u0e2d\u0e22" $newVersion) -ForegroundColor Green
    Write-Host (T "This is a demo build: if you find a bug, please report it on Discord (the link is in the launcher)." "\u0e23\u0e38\u0e48\u0e19\u0e19\u0e35\u0e49\u0e22\u0e31\u0e07\u0e40\u0e1b\u0e47\u0e19\u0e40\u0e14\u0e42\u0e21 \u0e16\u0e49\u0e32\u0e40\u0e08\u0e2d\u0e1a\u0e31\u0e04\u0e41\u0e08\u0e49\u0e07\u0e17\u0e32\u0e07 Discord \u0e44\u0e14\u0e49\u0e40\u0e25\u0e22 (\u0e25\u0e34\u0e07\u0e01\u0e4c\u0e2d\u0e22\u0e39\u0e48\u0e43\u0e19\u0e25\u0e31\u0e19\u0e40\u0e0a\u0e2d\u0e23\u0e4c)")
    if (-not $NoLaunch -and (Ask (T "Start Remielle Astral now?" "\u0e40\u0e1b\u0e34\u0e14 Remielle Astral \u0e40\u0e25\u0e22\u0e44\u0e2b\u0e21?") $true)) {
        Start-Process -FilePath (Get-ExeIn $Dir) -WorkingDirectory $Dir
    }
}

# -------------------------------------------------------------------- main --
function Invoke-Main {
    if (-not $Dir) {
        if (-not $env:LOCALAPPDATA) { Fail "LOCALAPPDATA is not set" }
        $script:Dir = Join-Path $env:LOCALAPPDATA "Remielle-Astral"
    }
    $script:Dir = $Dir.TrimEnd('\', '/')
    $settings = Join-Path $Dir "settings.json"
    $script:Thai = (Get-Culture).Name -like "th*"
    if (Test-Path -LiteralPath $settings) {
        $s = Get-Content -LiteralPath $settings -Raw
        if ($s -match '"lang":\s*"th"') { $script:Thai = $true }
        if ($s -match '"lang":\s*"en"') { $script:Thai = $false }
    }
    if (-not [Environment]::Is64BitOperatingSystem) { Fail (T "Remielle Astral is built for 64-bit Windows only." "Remielle Astral \u0e21\u0e35\u0e40\u0e09\u0e1e\u0e32\u0e30 Windows 64-bit") }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

    $mutex = New-Object Threading.Mutex($false, "Local\RemielleAstral_Installer_Lock")
    $owned = $false
    try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) { Fail (T "Another install or uninstall of Remielle Astral is running." "\u0e21\u0e35\u0e01\u0e32\u0e23\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07\u0e2b\u0e23\u0e37\u0e2d\u0e16\u0e2d\u0e19\u0e01\u0e32\u0e23\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07 Remielle Astral \u0e17\u0e33\u0e07\u0e32\u0e19\u0e2d\u0e22\u0e39\u0e48\u0e41\u0e25\u0e49\u0e27") }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("remielle-astral-install-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    try {
        if ($Check) { Invoke-Check }
        elseif ($Rollback) { Invoke-Rollback $temp }
        else { Invoke-Install $temp }
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        if ($owned) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

if (-not $env:REMIELLE_INSTALLER_NO_MAIN) {
    try { Invoke-Main }
    catch {
        Write-Host ("error: " + $_.Exception.Message) -ForegroundColor Red
        # Run as a file: a failing exit code.  Under `irm | iex` exit would
        # close the user's own PowerShell window, so only the message.
        if ($PSCommandPath) { exit 1 }
    }
}
