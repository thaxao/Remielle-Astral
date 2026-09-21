# Remielle Astral uninstaller for Windows (PowerShell 5.1 or 7).
#
#   irm https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/uninstall.ps1 | iex
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/uninstall.ps1))) -Purge
#   Settings > Apps > Remielle Astral > Uninstall   (runs this file from the install folder)
#
# By default only the program goes: its files (the release's MANIFEST), the
# shortcuts, the Apps entry and the PATH entry.  settings.json, the Custom
# server and its saves, the save backups, the caches and the mod library stay,
# so a later install carries on where this one stopped.
#
#   -Purge       remove those too.  settings.json, the saves and the save
#                backups are packed into %USERPROFILE%\Remielle-Astral-backup-<date>.zip
#                first; the mod library is only removed when you say so
#   -WithMods    with -Purge: remove the mod library without asking
#   -NoBackup    with -Purge: no archive
#   -DryRun      show what would be removed and change nothing
#   -Dir DIR     the install folder (default %LOCALAPPDATA%\Remielle-Astral)
#   -Yes         answer every question with its default
#
# The game client and an Official server checkout live in folders of your
# own and are never touched.  Plain ASCII on purpose: see install.ps1.

param(
    [switch]$Purge,
    [switch]$WithMods,
    [switch]$NoBackup,
    [switch]$DryRun,
    [string]$Dir = "",
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$AppKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\RemielleAstral"
$LegacyFiles = @(
    "remielle-astral.exe", "Remielle Astral.exe", "remielle-astral.exe.old", "Remielle Astral.exe.old", "README.md", "LICENSE", "icon.png", "MANIFEST", ".install-info",
    "tools/remielle-update", "tools/build-official-patch", "tools/import-patch",
    "tools/install.sh", "tools/install.ps1", "tools/install.cmd",
    "tools/update.sh", "tools/update.ps1", "tools/update.cmd",
    "tools/uninstall.sh", "tools/uninstall.ps1", "tools/uninstall.cmd",
    "patch/Pryce.exe", "patch/Armorer.dll"
)
$ModParts = @("xxmi", "mods.json", "staging", "quarantine", "backups", "cache")
$script:Thai = $false

function T([string]$En, [string]$Th) {
    $text = if ($script:Thai -and $Th) { [regex]::Unescape($Th) } else { $En }
    if ($args.Count -gt 0) { return $text -f $args }
    return $text
}
function Say([string]$m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok([string]$m) { Write-Host "  [+] $m" -ForegroundColor Green }
function Did([string]$m) { if (-not $DryRun) { Ok $m } }
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

function Get-Size([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return "0 B" }
    $item = Get-Item -LiteralPath $Path -Force
    $bytes = if ($item.PSIsContainer) { (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } else { $item.Length }
    if (-not $bytes) { $bytes = 0 }
    if ($bytes -ge 1GB) { return "{0:N1} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N1} MB" -f ($bytes / 1MB) }
    return "{0:N0} KB" -f ($bytes / 1KB)
}

function Test-Inside([string]$Path) {
    if (-not $Path -or $Path.Trim().Length -eq 0) { return $false }
    try {
        $full = [IO.Path]::GetFullPath($Path)
        $root = [IO.Path]::GetFullPath($Dir).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        return $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)
    } catch {
        return $false
    }
}

# Deletes a path inside the install folder, or only says so with -DryRun.
function Remove-Path([string]$Path) {
    if (-not (Test-Inside $Path)) { Warn "refusing to remove $Path"; return }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($DryRun) { Note ((T "would remove" "\u0e08\u0e30\u0e25\u0e1a") + " $Path"); return }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-ProgramFiles {
    $list = New-Object Collections.Generic.List[string]
    $m = Join-Path $Dir "MANIFEST"
    if (Test-Path -LiteralPath $m) { foreach ($l in Get-Content -LiteralPath $m) { $list.Add($l.Trim()) } }
    foreach ($l in $LegacyFiles) { $list.Add($l) }
    $list | Where-Object {
        $_ -and -not $_.StartsWith("/") -and -not $_.StartsWith("\") -and $_ -notmatch '(^|[/\\])\.\.([/\\]|$)' -and $_ -notmatch '^[A-Za-z]:'
    } | Sort-Object -Unique
}

# Processes whose program lives under $Folder (by path, so nothing else is
# touched).
function Get-ProcessesUnder([string]$Folder) {
    if (-not $Folder -or $Folder.Trim().Length -eq 0) { return @() }
    try {
        $root = [IO.Path]::GetFullPath($Folder).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        return @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            try { $_.Path -and $_.Path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) } catch { $false }
        })
    } catch {
        return @()
    }
}

function Stop-Processes([string]$What, $Procs) {
    $Procs = @($Procs)
    if ($Procs.Count -eq 0) { return }
    $ids = ($Procs | ForEach-Object { $_.Id }) -join ", "
    if ($DryRun) { Note (T "would close {0} (pid {1})" "\u0e08\u0e30\u0e1b\u0e34\u0e14 {0} (pid {1})" $What $ids); return }
    foreach ($p in $Procs) { try { [void]$p.CloseMainWindow() } catch { } }
    for ($i = 0; $i -lt 50; $i++) {
        if (-not ($Procs | Where-Object { -not $_.HasExited })) { break }
        Start-Sleep -Milliseconds 100
    }
    $Procs | Where-Object { -not $_.HasExited } | ForEach-Object { try { $_.Kill() } catch { } }
    Start-Sleep -Milliseconds 300
    Ok (T "Closed {0}" "\u0e1b\u0e34\u0e14 {0} \u0e41\u0e25\u0e49\u0e27" $What)
}

function Get-ShortcutTarget([string]$Path) {
    try { return (New-Object -ComObject WScript.Shell).CreateShortcut($Path).TargetPath } catch { return "" }
}

function Invoke-Main {
    if (-not $Dir) {
        if (-not $env:LOCALAPPDATA) { Fail "LOCALAPPDATA is not set" }
        $script:Dir = Join-Path $env:LOCALAPPDATA "Remielle-Astral"
    }
    try {
        $script:Dir = [IO.Path]::GetFullPath($Dir).TrimEnd('\', '/')
    } catch {
        Fail "Invalid directory: $Dir"
    }
    foreach ($bad in @($env:LOCALAPPDATA, $env:APPDATA, $env:USERPROFILE, $env:SystemRoot, $env:ProgramFiles, [IO.Path]::GetPathRoot($Dir))) {
        if ($bad -and $Dir.TrimEnd('\', '/') -ieq $bad.TrimEnd('\', '/')) { Fail "refusing to work on $Dir" }
    }
    $settings = Join-Path $Dir "settings.json"
    $script:Thai = (Get-Culture).Name -like "th*"
    $settingsText = ""
    if (Test-Path -LiteralPath $settings) {
        $settingsText = Get-Content -LiteralPath $settings -Raw
        if ($settingsText -match '"lang":\s*"th"') { $script:Thai = $true }
        if ($settingsText -match '"lang":\s*"en"') { $script:Thai = $false }
    }

    $desktop = [Environment]::GetFolderPath("Desktop")
    $userDesktop = Join-Path $env:USERPROFILE "Desktop"
    $programs = [Environment]::GetFolderPath("Programs")
    $links = @()
    foreach ($folder in @($desktop, $userDesktop, $programs)) {
        if ($folder -and (Test-Path -LiteralPath $folder)) { $links += (Join-Path $folder "Remielle Astral.lnk") }
    }
    $hasProgram = (Test-Path -LiteralPath (Join-Path $Dir "remielle-astral.exe")) -or (Test-Path -LiteralPath (Join-Path $Dir "Remielle Astral.exe")) -or
        (Test-Path -LiteralPath (Join-Path $Dir "MANIFEST")) -or (Test-Path -LiteralPath (Join-Path $Dir ".install-info"))
    $hasApp = Test-Path -Path $AppKey
    $ourLinks = @($links | Where-Object {
        if (-not (Test-Path -LiteralPath $_)) { return $false }
        $tgt = Get-ShortcutTarget $_
        return ($tgt -and (Test-Inside $tgt))
    })
    if (-not $hasProgram -and -not $hasApp -and $ourLinks.Count -eq 0 -and (-not $Purge -or -not (Test-Path -LiteralPath $Dir))) {
        Say (T "Remielle Astral is not installed in {0}." "\u0e44\u0e21\u0e48\u0e1e\u0e1a Remielle Astral \u0e43\u0e19 {0}" $Dir)
        return
    }
    if ((Test-Path -LiteralPath $Dir) -and -not $hasProgram -and -not (Test-Path -LiteralPath $settings) -and -not (Test-Path -LiteralPath (Join-Path $Dir "xxmi"))) {
        Fail (T "{0} does not look like a Remielle Astral folder; nothing was removed." "{0} \u0e44\u0e21\u0e48\u0e43\u0e0a\u0e48\u0e42\u0e1f\u0e25\u0e40\u0e14\u0e2d\u0e23\u0e4c\u0e02\u0e2d\u0e07 Remielle Astral \u0e08\u0e36\u0e07\u0e44\u0e21\u0e48\u0e25\u0e1a\u0e2d\u0e30\u0e44\u0e23" $Dir)
    }

    $mutex = New-Object Threading.Mutex($false, "Local\RemielleAstral_Installer_Lock")
    $owned = $false
    try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) { Fail (T "Another install or uninstall of Remielle Astral is running." "\u0e21\u0e35\u0e01\u0e32\u0e23\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07\u0e2b\u0e23\u0e37\u0e2d\u0e16\u0e2d\u0e19\u0e01\u0e32\u0e23\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07 Remielle Astral \u0e17\u0e33\u0e07\u0e32\u0e19\u0e2d\u0e22\u0e39\u0e48\u0e41\u0e25\u0e49\u0e27") }
    try {
        # ---- the plan
        Say ((T "Uninstalling Remielle Astral" "\u0e16\u0e2d\u0e19\u0e01\u0e32\u0e23\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07 Remielle Astral") + " ($Dir)")
        if ($DryRun) { Note (T "dry run: nothing is changed" "\u0e17\u0e14\u0e25\u0e2d\u0e07\u0e14\u0e39: \u0e44\u0e21\u0e48\u0e21\u0e35\u0e2d\u0e30\u0e44\u0e23\u0e16\u0e39\u0e01\u0e40\u0e1b\u0e25\u0e35\u0e48\u0e22\u0e19") }
        $fate = if ($Purge) { T "removed" "\u0e25\u0e1a" } else { T "kept" "\u0e40\u0e01\u0e47\u0e1a\u0e44\u0e27\u0e49" }
        $parts = @(
            @("settings.json", (T "settings" "\u0e01\u0e32\u0e23\u0e15\u0e31\u0e49\u0e07\u0e04\u0e48\u0e32")),
            @("remielle-server", (T "Custom server and its saves (Persistent)" "\u0e40\u0e0b\u0e34\u0e23\u0e4c\u0e1f Custom \u0e41\u0e25\u0e30\u0e40\u0e0b\u0e1f (Persistent)")),
            @(".remielle-cache", (T "save backups, pictures and caches" "\u0e2a\u0e33\u0e23\u0e2d\u0e07\u0e40\u0e0b\u0e1f \u0e23\u0e39\u0e1b \u0e41\u0e25\u0e30\u0e41\u0e04\u0e0a"))
        )
        foreach ($p in $parts) {
            $path = Join-Path $Dir $p[0]
            if (Test-Path -LiteralPath $path) { Note ("{0} ({1}): {2} - {3}" -f $p[0], (Get-Size $path), $fate, $p[1]) }
        }
        $modsHere = @($ModParts | Where-Object { Test-Path -LiteralPath (Join-Path $Dir $_) })
        if ($modsHere.Count -gt 0) {
            $modsFate = if ($Purge -and $WithMods) { T "removed" "\u0e25\u0e1a" } else { T "kept unless you say otherwise" "\u0e40\u0e01\u0e47\u0e1a\u0e44\u0e27\u0e49 \u0e16\u0e49\u0e32\u0e44\u0e21\u0e48\u0e2a\u0e31\u0e48\u0e07\u0e25\u0e1a" }
            Note ("{0}: {1}" -f (T "mod library" "\u0e04\u0e25\u0e31\u0e07\u0e21\u0e47\u0e2d\u0e14"), $modsFate)
        }
        foreach ($key in @("server_dir", "client_dir")) {
            if ($settingsText -match ('"' + $key + '":\s*"([^"]+)"')) {
                $label = if ($key -eq "server_dir") { T "Official server folder, not touched:" "\u0e42\u0e1f\u0e25\u0e40\u0e14\u0e2d\u0e23\u0e4c\u0e40\u0e0b\u0e34\u0e23\u0e4c\u0e1f Official \u0e44\u0e21\u0e48\u0e41\u0e15\u0e30:" } else { T "Game client folder, not touched:" "\u0e42\u0e1f\u0e25\u0e40\u0e14\u0e2d\u0e23\u0e4c\u0e40\u0e01\u0e21 \u0e44\u0e21\u0e48\u0e41\u0e15\u0e30:" }
                Note ("$label " + ($Matches[1] -replace '\\\\', '\'))
            }
        }

        $question = if ($Purge) { T "Remove Remielle Astral and its data?" "\u0e25\u0e1a Remielle Astral \u0e41\u0e25\u0e30\u0e02\u0e49\u0e2d\u0e21\u0e39\u0e25\u0e17\u0e31\u0e49\u0e07\u0e2b\u0e21\u0e14\u0e44\u0e2b\u0e21?" } else { T "Remove the program (your data stays)?" "\u0e25\u0e1a\u0e42\u0e1b\u0e23\u0e41\u0e01\u0e23\u0e21 (\u0e02\u0e49\u0e2d\u0e21\u0e39\u0e25\u0e22\u0e31\u0e07\u0e2d\u0e22\u0e39\u0e48) \u0e44\u0e2b\u0e21?" }
        if (-not (Ask $question $true)) { Ok (T "Cancelled." "\u0e22\u0e01\u0e40\u0e25\u0e34\u0e01\u0e41\u0e25\u0e49\u0e27"); return }
        $dropMods = $false
        if ($Purge -and $modsHere.Count -gt 0) {
            $dropMods = $WithMods -or (Ask (T "Also delete the mod library (your mods)?" "\u0e25\u0e1a\u0e04\u0e25\u0e31\u0e07\u0e21\u0e47\u0e2d\u0e14 (\u0e21\u0e47\u0e2d\u0e14\u0e02\u0e2d\u0e07\u0e04\u0e38\u0e13) \u0e14\u0e49\u0e27\u0e22\u0e44\u0e2b\u0e21?") $false)
        }

        # ---- close what runs from here
        $server = Join-Path $Dir "remielle-server"
        $launchers = @(Get-ProcessesUnder $Dir | Where-Object { -not (Test-Path -LiteralPath $server) -or -not $_.Path.StartsWith($server, [StringComparison]::OrdinalIgnoreCase) })
        Stop-Processes "Remielle Astral" $launchers
        if (Test-Path -LiteralPath $server) {
            $servers = @(Get-ProcessesUnder $server)
            if ($servers.Count -gt 0 -and ($Purge -or (Ask (T "The Custom server is running. Stop it?" "\u0e40\u0e0b\u0e34\u0e23\u0e4c\u0e1f Custom \u0e01\u0e33\u0e25\u0e31\u0e07\u0e23\u0e31\u0e19 \u0e2b\u0e22\u0e38\u0e14\u0e44\u0e2b\u0e21?") $true))) {
                Stop-Processes (T "the Custom server" "\u0e40\u0e0b\u0e34\u0e23\u0e4c\u0e1f Custom") $servers
            }
        }

        # ---- archive before anything is deleted
        if ($Purge -and -not $NoBackup) {
            $keep = @("settings.json", "remielle-server/Persistent", ".remielle-cache/backups", "mods.json") | Where-Object { Test-Path -LiteralPath (Join-Path $Dir $_) }
            if ($keep) {
                $backupDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
                $archive = Join-Path $backupDir ("Remielle-Astral-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".zip")
                if ($DryRun) { Note ((T "would archive" "\u0e08\u0e30\u0e40\u0e01\u0e47\u0e1a") + " " + ($keep -join ", ") + " -> $archive") }
                else {
                    $stage = Join-Path ([IO.Path]::GetTempPath()) ("remielle-astral-backup-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
                    try {
                        foreach ($k in $keep) {
                            $dst = Join-Path $stage $k
                            New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
                            Copy-Item -LiteralPath (Join-Path $Dir $k) -Destination $dst -Recurse -Force
                        }
                        # -Force on the listing: a wildcard would skip dot-named folders.
                        $top = @(Get-ChildItem -LiteralPath $stage -Force | ForEach-Object { $_.FullName })
                        Compress-Archive -LiteralPath $top -DestinationPath $archive -Force
                    } catch {
                        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
                        Fail (T "Could not archive the saves to {0}; nothing was removed." "\u0e40\u0e01\u0e47\u0e1a\u0e40\u0e0b\u0e1f\u0e25\u0e07 {0} \u0e44\u0e21\u0e48\u0e2a\u0e33\u0e40\u0e23\u0e47\u0e08 \u0e08\u0e36\u0e07\u0e44\u0e21\u0e48\u0e25\u0e1a\u0e2d\u0e30\u0e44\u0e23" $archive)
                    } finally {
                        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    Ok (T "Saves and settings archived: {0} ({1})" "\u0e40\u0e01\u0e47\u0e1a\u0e40\u0e0b\u0e1f\u0e41\u0e25\u0e30\u0e01\u0e32\u0e23\u0e15\u0e31\u0e49\u0e07\u0e04\u0e48\u0e32\u0e44\u0e27\u0e49\u0e17\u0e35\u0e48: {0} ({1})" $archive (Get-Size $archive))
                }
            }
        }

        # ---- the program
        foreach ($f in Get-ProgramFiles) { Remove-Path (Join-Path $Dir $f) }
        Remove-Path (Join-Path $Dir ".remielle-cache/previous")
        if (Test-Path -LiteralPath $Dir) {
            Get-ChildItem -LiteralPath $Dir -Recurse -File -Force -Filter "*.astral-new" -ErrorAction SilentlyContinue | ForEach-Object { Remove-Path $_.FullName }
        }
        if (-not $DryRun) {
            foreach ($sub in @("tools", "patch")) {
                $p = Join-Path $Dir $sub
                if ((Test-Path -LiteralPath $p) -and -not (Get-ChildItem -LiteralPath $p -Force)) { Remove-Item -LiteralPath $p }
            }
        }
        Did (T "Program files removed" "\u0e25\u0e1a\u0e44\u0e1f\u0e25\u0e4c\u0e42\u0e1b\u0e23\u0e41\u0e01\u0e23\u0e21\u0e41\u0e25\u0e49\u0e27")

        # ---- the data, with -Purge
        if ($Purge) {
            foreach ($p in @("settings.json", "remielle-server", ".remielle-cache")) { Remove-Path (Join-Path $Dir $p) }
            if ($dropMods) { foreach ($p in $ModParts) { Remove-Path (Join-Path $Dir $p) } }
            Did (T "Data removed" "\u0e25\u0e1a\u0e02\u0e49\u0e2d\u0e21\u0e39\u0e25\u0e41\u0e25\u0e49\u0e27")
        }

        # ---- shortcuts, Apps entry and PATH that are ours
        foreach ($l in $links) {
            if (-not (Test-Path -LiteralPath $l)) { continue }
            $target = Get-ShortcutTarget $l
            if (-not $target -or (Test-Inside $target)) {
                if ($DryRun) { Note ((T "would remove" "\u0e08\u0e30\u0e25\u0e1a") + " $l") } else { Remove-Item -LiteralPath $l -Force -ErrorAction SilentlyContinue }
            } else {
                Note (T "Left {0}: it starts a Remielle Astral elsewhere ({1})" "\u0e44\u0e21\u0e48\u0e41\u0e15\u0e30 {0} \u0e40\u0e1e\u0e23\u0e32\u0e30\u0e40\u0e1b\u0e34\u0e14 Remielle Astral \u0e17\u0e35\u0e48\u0e2d\u0e37\u0e48\u0e19 ({1})" $l $target)
            }
        }
        if (Test-Path -Path $AppKey) {
            if ($DryRun) { Note ((T "would remove" "\u0e08\u0e30\u0e25\u0e1a") + " Settings > Apps entry") } else { Remove-Item -Path $AppKey -Recurse -Force -ErrorAction SilentlyContinue }
        }
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath) {
            $parts = $userPath.Split(';')
            $rest = @($parts | Where-Object { $_ -and $_.TrimEnd('\') -ine $Dir })
            if ($rest.Count -ne @($parts | Where-Object { $_ }).Count) {
                if ($DryRun) { Note ((T "would remove from PATH:" "\u0e08\u0e30\u0e25\u0e1a\u0e08\u0e32\u0e01 PATH:") + " $Dir") } else { [Environment]::SetEnvironmentVariable("Path", ($rest -join ';'), "User") }
            }
        }
        Did (T "Shortcuts, Apps entry and PATH cleaned" "\u0e25\u0e1a\u0e17\u0e32\u0e07\u0e25\u0e31\u0e14 \u0e23\u0e32\u0e22\u0e01\u0e32\u0e23\u0e43\u0e19 Apps \u0e41\u0e25\u0e30 PATH \u0e41\u0e25\u0e49\u0e27")

        # ---- what is left
        Write-Host ""
        if ($DryRun) { Write-Host (T "Dry run finished: nothing was changed." "\u0e17\u0e14\u0e25\u0e2d\u0e07\u0e40\u0e2a\u0e23\u0e47\u0e08: \u0e44\u0e21\u0e48\u0e21\u0e35\u0e2d\u0e30\u0e44\u0e23\u0e16\u0e39\u0e01\u0e40\u0e1b\u0e25\u0e35\u0e48\u0e22\u0e19"); return }
        if ((Test-Path -LiteralPath $Dir) -and -not (Get-ChildItem -LiteralPath $Dir -Force)) { Remove-Item -LiteralPath $Dir -Force }
        Write-Host (T "Remielle Astral is uninstalled." "\u0e16\u0e2d\u0e19\u0e01\u0e32\u0e23\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07 Remielle Astral \u0e40\u0e23\u0e35\u0e22\u0e1a\u0e23\u0e49\u0e2d\u0e22") -ForegroundColor Green
        if (Test-Path -LiteralPath $Dir) {
            $left = (Get-ChildItem -LiteralPath $Dir -Force | ForEach-Object { $_.Name }) -join " "
            Write-Host (T "Kept in {0}: {1}" "\u0e22\u0e31\u0e07\u0e40\u0e01\u0e47\u0e1a\u0e44\u0e27\u0e49\u0e43\u0e19 {0}: {1}" $Dir $left)
            if (-not $Purge) { Write-Host (T "Installing again picks these up. To remove them too: uninstall.ps1 -Purge" "\u0e15\u0e34\u0e14\u0e15\u0e31\u0e49\u0e07\u0e43\u0e2b\u0e21\u0e48\u0e08\u0e30\u0e43\u0e0a\u0e49\u0e02\u0e49\u0e2d\u0e21\u0e39\u0e25\u0e40\u0e2b\u0e25\u0e48\u0e32\u0e19\u0e35\u0e49\u0e15\u0e48\u0e2d \u0e16\u0e49\u0e32\u0e08\u0e30\u0e25\u0e1a\u0e14\u0e49\u0e27\u0e22: uninstall.ps1 -Purge") }
            else { Write-Host (T "The mod library was kept. To remove it too: uninstall.ps1 -Purge -WithMods" "\u0e04\u0e25\u0e31\u0e07\u0e21\u0e47\u0e2d\u0e14\u0e22\u0e31\u0e07\u0e2d\u0e22\u0e39\u0e48 \u0e16\u0e49\u0e32\u0e08\u0e30\u0e25\u0e1a\u0e14\u0e49\u0e27\u0e22: uninstall.ps1 -Purge -WithMods") }
        }
    } finally {
        if ($owned) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

if (-not $env:REMIELLE_INSTALLER_NO_MAIN) {
    try { Invoke-Main }
    catch {
        Write-Host ("error: " + $_.Exception.Message) -ForegroundColor Red
        if ($PSCommandPath) { exit 1 }
    }
}
