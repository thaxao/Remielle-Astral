# Remielle Astral

**A launcher and account editor for [Remielle](https://git.xeondev.com/remielle/remielle),
the Zenless Zone Zero server emulator.**
Made by **thaxao**.

Remielle Astral is a desktop app for Linux and Windows that
starts and watches Remielle's three servers, keeps the server checkout and the
client's `offsets.zon` in step with upstream git, launches the game through
Wine with ZZMI mods, and edits a player's save: agents, W-Engines, Drive Discs,
squads and the endgame schedule.

Keep the server checkout next to this folder and it is found on its own:

```
Documents/
├── remielle/          ← server (git clone of remielle, branch 0.1.x)
└── Remielle-Astral/   ← this folder
```

## Pages

| Page | What it does |
| --- | --- |
| **Play** | Server status, start / stop / restart, launch the game, active squad, recent log |
| **Squads** | The game's quick teams (up to 20): pick agents, build their discs, pick a W-Engine and Bangboo, save presets. Agents with an animated portrait move (Agent motion, on by default) |
| **Agents** | Every playable agent: add or remove, level, promotion, Mindscape, skill levels, outfit, W-Engine and the six disc slots |
| **Engines** | The W-Engine inventory: add, level, ascension, overclock, who equips it |
| **Discs** | The Drive Disc inventory and a generator that builds a 4-piece + 2-piece set with chosen main stats and substats |
| **Endgames** | The bosses of the live Shiyu Defense, Deadly Assault, Threshold Simulation and Annihilation Simulacrum seasons, and which zone each entrance offers |
| **Updates** | Server updates from git, the client's `offsets.zon`, and the launcher itself |
| **Mods** | ZZMI install, installed mods and profiles, GameBanana browser |
| **HUD** | `custom.uid`, the on-screen text the patch draws, with a colour preview and a gradient helper |
| **Console** | Server, game and launcher logs; rmctl commands |
| **Settings** | Folders, Wine, build mode, update interval, offsets source |
| **About** | Who made it and what inspired it, the credits, how to read the version number, and (while it is a demo) where to report bugs, with a button that copies the version and system details |

The interface is in Thai and English (switch in the sidebar).

## How it runs

The launcher is **one program per system**: its code and its window share a
process, and the pages are built into the binary. It opens **no network
port** — the window asks the launcher for each page directly — so there is
nothing on `127.0.0.1` while it runs, no browser is involved, and a second
start just brings the open window to the front.

| | Linux | Windows |
| --- | --- | --- |
| File | `remielle-astral` | `Remielle Astral.exe` |
| Window | GTK 3 + WebKitGTK 4.1 | WebView2 (built into Windows 10 and 11) |
| Frame | none: the launcher draws its own title bar (drag to move, double-click to maximize) and resizes from its edges | the same, with Windows' snapping and shadow |

The window's size and position are remembered in `.remielle-cache/window.ini`.
Closing the window stops the Remielle servers the launcher started.

### Window and rendering

The window keeps a 16:9 shape. At any size it shows the same layout, drawn
larger or smaller: 0.89x at HD, 1.33x at FHD, 1.78x at 2K and 2.67x at 4K.
The engine lays the page out again at each scale, so text and pictures stay
sharp instead of being stretched. Settings > Window size has HD, HD+, FHD, 2K
and 4K presets, showing only those that fit the screen.

On Linux the page is drawn on the GPU (WebKitGTK's DMA-BUF renderer). On a
laptop with Intel and NVIDIA graphics it uses the GPU that drives the screen.
The NVIDIA offload variables that `prime-run` sets are dropped, because
frames drawn on the NVIDIA GPU cannot be shown by that screen, which left the
window blank. Other settings:

- `ASTRAL_FORCE_NVIDIA=1` draws on NVIDIA anyway, without the GPU renderer.
- `ASTRAL_SOFTWARE_RENDER=1` draws on the CPU, for when the window stays
  blank. This is slow.
- After a crash of the page process, the next start draws on the CPU by
  itself. Delete `.remielle-cache/software-render` to go back to the GPU.

## Requirements

To run:

- **Linux:** GTK 3 and WebKitGTK 4.1 (`webkit2gtk-4.1`), plus `git`, `curl`,
  `7z`, `openssl` and Wine to launch the game.
- **Windows:** nothing extra for the launcher itself. Where the WebView2
  Runtime is missing (an old Windows 10, or Wine), the launcher offers to
  download and install it from Microsoft. Installing and updating the
  Remielle **server** needs [Git for Windows](https://git-scm.com/download/win).
- Optional: `vipsthumbnail` (libvips) for smaller agent pictures.

To build: [Zig 0.14](https://ziglang.org/download/) and, on Linux, the GTK 3
and WebKitGTK 4.1 development packages
(`pkg-config --exists gtk+-3.0 webkit2gtk-4.1`). The Windows `.exe` is
cross-compiled from Linux by the same `zig build`.

Remielle itself needs the Zig version its `envrc` names (0.16.0 today). The
launcher downloads it into the checkout's `.direnv/` the first time it builds
the servers, as `envrc` would.

## Install and uninstall

One command installs the newest release (pre-releases included), and the same
command updates an installed copy:

```bash
# Linux
curl -fsSL https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/install.sh | bash
```

```powershell
# Windows (PowerShell)
irm https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/install.ps1 | iex
```

```cmd
:: Windows (Command Prompt)
curl -fsSL https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/install.cmd -o install.cmd && install.cmd && del install.cmd
```

On Arch Linux (and Manjaro, Garuda, EndeavourOS), install it from the AUR
instead, so pacman updates and removes it:

```bash
yay -S remielle-astral-bin      # install; yay -Syu updates it
yay -Rns remielle-astral-bin    # remove; your data stays
```

The package puts the program in `/opt/remielle-astral`. Each user's settings,
saves, Custom server and mods go to `~/.local/share/remielle-astral`, the same
folder the script install uses, so moving between the two keeps them. The
launcher's own updater stays off, because pacman does the updating.
`tools/aur-update` bumps the package to the version in `src/main.zig`, and
`tools/aur-update --push` publishes it; publish the GitHub release first.

What the installer does:

- It checks the download against the release's `SHA256SUMS` and refuses a
  mismatch. Releases that only carry the Custom server are skipped.
- It installs to `~/.local/share/remielle-astral` (Linux) or
  `%LOCALAPPDATA%\Remielle-Astral` (Windows).
- It replaces only the program's own files, which the release lists in
  `MANIFEST`. `settings.json`, the saves, the Custom server, the mod library
  and the caches in the same folder stay as they are.
- It keeps the version it replaced, so `--rollback` / `-Rollback` puts it back.
- It closes a running launcher first, and nothing else. Servers keep running.
- It says when the installed version is already current, and asks before a
  downgrade.
- On Linux it names any missing library (GTK 3, WebKitGTK 4.1) with the
  install command for your distribution. It adds a `~/.local/bin` link and a
  menu entry, and keeps a menu entry made by a source build.
- On Windows it checks for the WebView2 Runtime and makes Desktop and Start
  menu shortcuts. It lists the install in Settings > Apps, whose Uninstall
  button runs `tools\uninstall.ps1`.

Options (Linux `--flag`, Windows `-Flag`):

| Option | Effect |
| --- | --- |
| `--version TAG` | install that release |
| `--zip FILE` | install a downloaded zip, checked against a `SHA256SUMS` beside it |
| `--check` | show the installed and the newest version |
| `--rollback` | put back the version the last install replaced |
| `--force` | reinstall the same version |
| `--dir DIR` | another install folder |
| `--yes` | no questions |

Pass options to the one-liners like this:

- Linux: `curl -fsSL …/install.sh | bash -s -- --check`
- Windows: `& ([scriptblock]::Create((irm …/install.ps1))) -Check`

The uninstaller removes the program, the link and the menu entry or
shortcuts. It keeps your data unless asked, so a later install carries on:

```bash
curl -fsSL https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/uninstall.sh | bash               # keep data
curl -fsSL https://raw.githubusercontent.com/thaxao/Remielle-Astral/main/tools/uninstall.sh | bash -s -- --purge # remove data too
```

On Windows, use Settings > Apps > Remielle Astral > Uninstall, or run
`uninstall.ps1` with `-Purge`.

- `--purge` first packs `settings.json`, the saves (`remielle-server/Persistent`)
  and the save backups into `~/Remielle-Astral-backup-<date>.tar.gz` (`.zip` on
  Windows). Then it removes the data.
- The mod library goes only when you confirm it, or with `--with-mods`.
- `--dry-run` lists what would be removed.
- The game client and an Official server checkout are never touched.

## Build and run

```sh
zig build            # zig-out/bin/remielle-astral and zig-out/bin/remielle-astral.exe
zig build gui        # open the window (and add it to the application menu)
zig build test       # unit tests
zig build release    # public zips + SHA256SUMS in .remielle-cache/release/
zig build web        # development only: the pages on http://127.0.0.1:21090
```

`zig build web` is the one thing that listens on a port. It serves the same
pages to a browser and reads `src/static` from disk on every request, so a
page edit shows on reload; the app never does this.

`zig build` also writes a menu entry to
`zig-out/share/applications/io.github.thaxao.RemielleAstral.desktop`;
`zig build menu` installs it.

## First start

The first start opens **Setup** (it can be skipped and reopened from
Settings):

1. **Configuration** — the account to edit, the Shiyu Defense / Deadly Assault
   / Deadly Assault Hard zones, language, agent motion, dynamic background and
   rank badges.
2. **Updates & offsets** — how often to check, build mode, the `offsets.zon`
   source.
3. **Server** — Official or Custom (see below), and its folder, clone or
   install.
4. **Game client** — the folder, Wine, and which client patch to install.
5. **Mods** — the mod library.

## Official and Custom

There are two server editions and two client patches. Both choices can be
changed at any time on the Updates page.

| | Official | Custom |
| --- | --- | --- |
| Server | Upstream Remielle, unmodified: a git checkout built on this computer that follows upstream (see *Server updates*) | A ready-made build with Remielle Astral's additions. It installs and updates from its releases, and needs no git or Zig |
| Real-time (equip, remove items, quick teams reach the running game) | Locked: edits go to the save and show after the next login | Yes |
| New accounts without a server restart | Locked | Yes |
| Client patch | `remielle.exe` + `thaumiel.dll`, built from upstream thaumiel on this computer (its offsets are built in) | `Pryce.exe` + `Armorer.dll`, carried with the launcher |
| `offsets.zon` sync, HUD text (`custom.uid`) | Locked | Yes |

Which edition runs is read from the server's own `remielle-gamesv` binary, so
the locks follow what actually runs, not a setting. The locked features are
shown grey with a lock.

- **Install Custom** downloads `remielle-server-<version>-<platform>.zip` from
  the releases of `custom_server.repo` (empty: the launcher's own repository),
  checks it against `SERVER-SHA256SUMS`, and unpacks it to
  `custom_server.dir` (empty: `remielle-server/` beside the launcher). On the
  first install it can copy `Persistent/` (accounts and saves) over from the
  Official server; existing files are never overwritten. Updates install over
  the same folder and keep `Persistent/`.
- `custom_server.repo` may also be the full URL of a releases list in the
  GitHub shape (for example a Gitea `/api/v1/repos/<owner>/<name>/releases`).
- Switching edition while the servers run stops them and starts the other
  edition's servers.
- Installing either patch moves the other one's files aside as
  `*.remielle-bak` (or a dated name when a different backup is already there);
  nothing is deleted. The Official patch is built by
  `tools/build-official-patch`, which fetches thaumiel and the Zig version it
  pins; on Windows it needs Git for Windows.

The launcher is open source, so the lock is a product boundary, not a security
one.

### Publishing the Custom server

From the private server checkout (it must carry `rmnet.custom_edition`, the
`remielle-custom-edition features=...` text gamesv prints at start):

```sh
tools/publish-custom-server ~/Documents/remielle                  # zips + SERVER-SHA256SUMS in .remielle-cache/release/
tools/publish-custom-server ~/Documents/remielle --version 0.1.1-custom.2 --publish
```

It builds Linux and Windows (ReleaseSafe) and packs the binaries, the
`config.zon` files, `assets/filecfg`, `pb.stable.zig`, `rand_properties.zig`,
the licence and an `edition.json`. `--publish` uploads them with `gh` as a
release of their own (tag `server-v<version>`), which the launcher's own update
check passes over.

## Windows

- The patched client is started directly, without Wine, so the Wine fields are
  hidden on Windows.
- Git for Windows brings both `git` and `bash` (`tools/remielle-update` is a
  shell script). The Updates page says so plainly when they are missing.
  Everything else — the save editor, mods, the HUD text, the launcher's own
  updates — works without it.
- ZZMI mods need the game on the same machine; the launcher deploys
  `d3d11.dll` beside the client exactly as on Linux, minus the Wine overrides.
- Under Wine the `.exe` runs as well, given a WebView2 Runtime in the prefix
  (the launcher offers to install it); the window is then a plain frameless
  window that resizes from its edges.

## Server updates

Every 30 minutes (Settings → Updates), and when you press **Check for updates**,
the launcher fetches the branch the checkout follows and lists the new commits.
**Update server** then:

1. fetches the branch,
2. checks local changes: edits to files the new commits do not touch are kept;
   an edit to a file they do change stops the update and names the file,
3. fast-forwards (`git merge --ff-only --autostash`),
4. prepares the Zig version from `envrc`,
5. builds the servers (`zig build -Doptimize=ReleaseSafe` by default),
6. checks the binaries and records which commit they were built from,

and restarts the servers if they were running. If the build fails, the source
is moved back to where it was and rebuilt, and running servers are left alone.
**Rebuild** and **Roll back…** (to any recent commit) run the same way. The
steps are in `tools/remielle-update`, which also works from a terminal.

### If you edit the server's code

Editing the checkout does not stop `git pull` updates:

- An edit to a file the new commits do not touch is carried across
  (`--autostash`) and is still there afterwards.
- An edit to a file they do change stops the update, names the file, and
  changes nothing. Commit, stash or revert it, then update.
- Your own commits are never merged by **Update server**: with commits on both
  sides the state is *diverged*, and the button that appears is **Replay my
  commits**, which rebases yours onto the new ones
  (`tools/remielle-update rebase`). A conflicting rebase is aborted, so the
  checkout stays exactly as it was; finish that one by hand with
  `git rebase origin/<branch>`.
- A failed build after either one restores the previous commit and rebuilds it.

## Updating the launcher

The launcher checks its own GitHub releases (Settings field
`update.launcher_repo`, shown on the Updates page) and installs them itself:
it downloads the zip for the platform it runs on, refuses anything whose
SHA256 does not match the release's `SHA256SUMS`, and copies the files over its
own folder. `settings.json`, `.remielle-cache/`, the mod library and the server
checkout are never touched. Reopen the launcher afterwards to run the new
build; on Windows the running `.exe` is renamed aside and removed on the next
start.

A release zip holds the program (`remielle-astral` or `Remielle Astral.exe`),
`tools/`, this README and the licence. Unpack it anywhere and run the program.

To publish a release from this tree:

```sh
zig build release                     # zips for Linux and Windows + SHA256SUMS
zig build release -Dtag=v1.0.2        # a tag other than v<version>
zig build release -Dpublish=true      # also upload with gh release create
```

Bump `.version` in `build.zig.zon` and `version` in `src/main.zig` together:
that number is what the updater compares against the release tag.

## Client offsets

The client patch that reads `offsets.zon` beside the game (Pryce.exe with
Armorer.dll) needs values matching the client build. The launcher fetches
`assets/offsets.zon` from the patch repository
([remielle/thaumiel](https://git.xeondev.com/remielle/thaumiel)) with git,
compares it value by value with the client's copy, and when they differ writes
the published file over it, keeping `offsets.zon.bak`. Formatting changes do
not count as a difference.

- Branch: `auto` follows the server branch. `0.1.x` and `master` use the patch
  repository's `master`; a pinned server branch such as `0.1.x-3.2.12` uses the
  patch branch `3.2.12`. Any other branch can be set in Settings.
- It checks on start, on every update check, before launching the game if the
  last check is over ten minutes old, and when you press **Sync now**.
- Offline, the copy from the last successful fetch is used.
- The Updates page shows the changed fields, warns when the published file is
  for a different client version than `version_info`, and warns when fields were
  added or removed (the patch rejects a file whose fields it was not built for).

## Account editing

The account pages edit `Persistent/LocalStorage/USD_<uid>.bin` in the server
checkout. The save is decoded in the page using the schema gamesv is built with
(`rmpb/src/pb.stable.zig`), so fields the launcher does not know are written
back unchanged, and a new field upstream does not need a launcher update.

- If gamesv is running, the player is kicked first so the server saves, then
  the edit is written. Log in again to see it.
- If the save changed on disk after the page loaded it, the write is refused
  unless you choose to overwrite.
- Every write keeps a backup under `.remielle-cache/backups/`.
- A save with no agent or W-Engine list gets every agent / engine from the
  server; the first edit writes that full list into the save.
- Squad names are limited to 14 bytes (gamesv refuses longer ones).

The catalog (which agents, engines and disc sets exist) comes from the server's
own asset tables, so agents newer than any website still appear. Names and
pictures come from the [Enka Network](https://github.com/EnkaNetwork/API-docs)
store, refreshed daily and cached in `.remielle-cache/`.

Endgame changes are written to `CALENDAR.bin`; with gamesv running they are also
sent through rmctl so they apply immediately.

## Mods (ZZMI)

**Install / update ZZMI** downloads
[XXMI-Libs-Package](https://github.com/SpectrumQT/XXMI-Libs-Package) and
[ZZMI-Package](https://github.com/leotorrez/ZZMI-Package) into
`~/.local/share/remielle-astral/xxmi/`. Mods live in its `zzmi/Mods` folder.

When mods are on, a launch copies `d3d11.dll`, `d3dcompiler_47.dll` and
`d3dx.ini` beside the game, links `Core`, `ShaderFixes` and `Mods` there, sets
`[Loader] target = ZenlessZoneZeroBeta.exe`, and starts Wine with
`WINEDLLOVERRIDES=d3d11=n,b`. A `Mods` folder already in the client is moved
aside, never deleted. With mods off, the launcher removes the DLLs it placed
(only when they are byte for byte its own copies).

Package signatures are checked against the XXMI key when GitHub's API provides
them; the result is shown after installing.

## Network use

The launcher goes online for: git fetches of the server checkout, the offsets
repository and (for the Official patch) thaumiel, the Custom server's
releases, Zig downloads for the server build, the Enka Network store and its
images, nanoka.cc (endgame seasons, boss pictures, animated agent portraits),
GameBanana, and the ZZMI packages. Everything downloaded is cached under
`.remielle-cache/`.

## Files

| Path | What it holds |
| --- | --- |
| `settings.json` | This machine's settings (not committed) |
| `.remielle-cache/` | Offsets repository cache, store data, pictures, build record, backups (not committed) |
| `tools/remielle-update` | The update / rebase / rebuild / roll back script |
| `tools/remielle-release` | Packs the public zips, their `MANIFEST` and `SHA256SUMS` |
| `tools/install.sh`, `tools/uninstall.sh` | Linux installer and uninstaller |
| `tools/install.ps1`, `tools/uninstall.ps1`, `*.cmd` | Windows installer and uninstaller |
| `tools/build-official-patch` | Builds and installs the Official client patch |
| `tools/publish-custom-server` | Packs (and optionally publishes) the Custom server |
| `src/` | Backend (Zig), window (C) and dashboard (HTML/CSS/JS) |

## Credits

- **[Remielle](https://git.xeondev.com/remielle/remielle)** and
  **[Thaumiel](https://git.xeondev.com/remielle/thaumiel)** (AGPL-3.0) by the
  Remielle developers: the server and client patch this launcher manages. It
  does not include their code.
- **[PearlSR Astral](https://github.com/thaxao/PearlSR-Astral)**: the launcher
  this one grew from (process supervision, mod manager, desktop window).
- **[Ps Setup](https://pssetup.zenless.app)** by RoxyTheProxy: showed what a
  Remielle account editor should cover.
- **GachaMeow**: the look this launcher's interface follows.
- **[Enka Network](https://github.com/EnkaNetwork/API-docs)**: agent, W-Engine
  and Drive Disc names and pictures.
- **[XXMI](https://github.com/SpectrumQT/XXMI-Launcher)**,
  **XXMI-Libs-Package** and **ZZMI-Package** (GPL-3.0): the mod loader, downloaded
  and managed, not bundled.
- **[nanoka.cc](https://zzz.nanoka.cc)**: endgame season data, boss pictures
  and the animated agent portraits (Spine skeletons) on the Squads page.
- **[Ps Setup](https://pssetup.zenless.app)**: rank, specialty, attribute,
  attack-type and faction icons.
- **[Spine Runtimes](https://esotericsoftware.com)** (`spine-player` 4.1, Spine
  Runtimes License): plays the animated portraits.
- **[Microsoft Edge WebView2](https://developer.microsoft.com/microsoft-edge/webview2/)**
  SDK (BSD-style licence): the Windows window; `WebView2Loader.dll` is built in.
- **[GameBanana](https://gamebanana.com)**: mod browsing.
- Fonts: **Barlow Condensed**, **Kanit** and **Caveat** (SIL Open Font License),
  bundled.

## License

Remielle Astral is licensed under the Apache License 2.0 (see `LICENSE`).
Third-party components keep their own licenses.

Zenless Zone Zero is a trademark of HoYoverse. This project is not affiliated
with or endorsed by HoYoverse.
