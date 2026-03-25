<!-- Generated: 2026-03-25 | Source files: 24 | Token estimate: ~1200 -->

# Backend Scripts

## Shared Utilities (`scripts/UmeAiRTUtils.psm1`, 587 lines)

14 exported functions used across all scripts:

### Invoke-LogRotation (line 15)
Rotates log files, keeps N previous runs (default 3).
- Renames `log` → `log.1` → `log.2` → `log.3`; deletes `.4+`
- Called once per session entry point (Install, Update) before any writes

### Write-Log (line 42)
Dual-output logging: console (colored) + log file (timestamped).
- Level -2: raw (no prefix)
- Level 0: step header with `[Step N/M]`, yellow, `=` separators, increments `$global:currentStep`
- Level 1: `"  - "` prefix
- Level 2: `"    -> "` prefix
- Level 3: `"      [INFO] "` prefix
- Uses `$global:logFile`, `$global:currentStep`, `$global:totalSteps`

### Invoke-AndLog (line 101)
Runs external commands via `Invoke-Expression`, captures output to temp file, logs it.
- On non-zero exit: logs error + throws (unless `-IgnoreErrors` switch)
- On fatal catch: `Read-Host` pause + `exit 1`
- Cleans up temp file in `finally` block

### Confirm-FileHash (line 151)
Verifies SHA256 of a file. Deletes file and throws on mismatch.
- Primary: `Get-FileHash -Algorithm SHA256`
- Fallback: `System.Security.Cryptography.SHA256` (.NET, for powershell.exe compat)
- Params: `$Path`, `$Expected`, `$Algorithm = 'SHA256'`

### Confirm-Authenticode (line 187)
Verifies Authenticode signature on Windows binaries. Deletes file and throws on failure.
- Checks `Get-AuthenticodeSignature` status is 'Valid'
- Checks signer certificate Subject contains `$ExpectedSubject`

### Set-ManagerUseUv (line 212)
Ensures `user/__manager/config.ini` has `use_uv = True`.
- Creates config file/dir if missing; patches in-place if present

### Save-File (line 240)
Downloads files with aria2c primary, Invoke-WebRequest fallback.
- `-Force` switch: bypasses exists-check (used by Update for re-download)
- Without `-Force`: skips if file exists, then verifies hash if `-ExpectedHash` provided
- `-ExpectedHash`: SHA256 verification after download via `Confirm-FileHash`
- aria2c path: `$env:LOCALAPPDATA\aria2\aria2c.exe` with flags `-x 16 -s 16 -k 1M`
- Fallback: `Invoke-WebRequest` with TLS 1.2/1.3
- Null guard on `$global:logFile` check before writing aria2c output to log

### Read-UserChoice (line 322)
Interactive menu: displays prompt + choices array, loops until valid answer.
- Returns uppercase string (e.g., "A", "B", "C")
- Used by Download-*-Models.ps1 scripts for letter-based menus

### Test-NvidiaGpu (line 357)
Runs `nvidia-smi -L`, returns `$true` if "GPU 0:" found in output.

### Get-GpuVramInfo (line 391)
Queries `nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits`.
Returns `[PSCustomObject]@{ GpuName = string; VramGiB = int }` or `$null`.

### Test-PyVersion (line 434)
Runs `<Command> <Arguments> --version`, returns `$true` if output matches "Python 3.13".

### Read-UserConfig (line 469)
Reads `gh_user`/`gh_reponame`/`gh_branch` from `umeairt-user-config.json` (preferred)
or deprecated `repo-config.json` fallback. Validates each field with regex.
Outputs 4 KEY=VALUE lines: `GhUser`, `GhRepoName`, `GhBranch`, `ConfigSource`.

### ConvertTo-ForwardSlash (line 515)
Converts backslashes to forward slashes in a path string.

### Resolve-CleanPath (line 542)
Resolves and normalises a path to forward slashes.

---

## Install Entry Point (`scripts/Install-ComfyUI.ps1`, 182 lines)

Reads config, sets up early logging, runs bootstrap, persists fork config.
Default `GhRepoName`: `ComfyUI-Auto_installer-PS`.
Accepts `-v` / `-vv` verbosity switches; forwards them to Phase 1 via splatting.

### Flow
1. Inline `_RotateLog`/`_AppendLog` helpers (psm1 not yet loaded)
2. Rotate `logs/install.log` and `logs/bootstrap.log`
3. Read config via `Read-UserConfig` (if psm1 already on disk) or use defaults
4. Validate fork params; log config source
5. Download `Bootstrap-Downloader.ps1` from `raw.githubusercontent.com`
6. Run bootstrap (`-SkipSelf`)
7. Persist resolved fork config to `umeairt-user-config.json` (merge with existing keys)
8. Build `$verbSplat` hash from `-v`/`-vv` params; launch Phase 1 with splat forwarding

---

## Install Phase 1 (`scripts/Install-ComfyUI-Phase1.ps1`, 634 lines)

### Flow
1. Load dependencies.json, import UmeAiRTUtils, set `$global:logFile = "$logPath/install.log"`
2. Detect `$psExe` (pwsh vs powershell.exe) for all subprocess spawns
3. If `-RunAdminTasks` flag: enable Long Paths registry + install VS Build Tools (SHA256 + Authenticode verified), then exit
4. Otherwise: check if admin tasks needed, self-elevate via `Start-Process $psExe -Verb RunAs` if so
5. Install type menu: `Read-Host` with `"1"` (Light/venv) or `"2"` (Full/Conda)
6. Install aria2 (download accelerator) to `$env:LOCALAPPDATA\aria2\`
7. Git detection: `Get-Command "git"`, auto-install prompt if missing (SHA256 + Authenticode verified)
8. **Light path**: detect Python 3.13 (`py -3.13` or `python`), auto-install if missing (SHA256 + Authenticode verified), create venv
9. **Full path**: install Miniconda if missing (SHA256 + Authenticode verified), accept TOS, remove old env, `conda env create -f environment.yml`
10. uv install: check `Get-Command uv` (system-wide) first; download only if absent; add local bin to PATH only if not system-wide
11. Generate `Launch-Phase2.ps1` (venv activate or conda-hook + activate)
12. Launch Phase 2 in new window via `Start-Process $psExe`

### Key Variables
- `$psExe`: "pwsh" or "powershell.exe" (detected at runtime)
- `$installType`: "Light" or "Full"
- `$pythonCommand` / `$pythonArgs`: detected Python executable

---

## Install Phase 2 (`scripts/Install-ComfyUI-Phase2.ps1`, 523 lines)

### Flow
1. UTF-8 encoding setup; load dependencies.json; import UmeAiRTUtils; detect GPU
2. Set `$global:logFile = "$logPath/install.log"` (appends to Phase 1 log)
3. Inherit `$psExe` from Phase 1 environment
4. Git long paths config; clone ComfyUI
5. Junction architecture: 5 folders (custom_nodes, models, output, input, user)
6. Core deps: ninja, pip/wheel upgrade, torch+cu130+xformers, ComfyUI requirements
7. Standard pip packages; .whl installs (nunchaku, insightface) with SHA256 verification
8. Custom nodes: ComfyUI-Manager clone → cm-cli.py restore-snapshot or CSV fallback
9. UmeAiRT-Sync node install; MagCache hotfix (line 13 patch)
10. Triton/SageAttention: DazzleML installer (venv) or manual pip (Conda)
11. Nunchaku config URL from `dependencies.files.nunchaku_versions.url`; ComfyUI settings download
12. Optional model packs: Y/N loop for 8 packs

All pip calls use `uv pip install --python "$pythonExe"` (no pip-only flags).

---

## Update Script (`scripts/Update-ComfyUI.ps1`, 448 lines)

### Parameters
- `$SnapshotPath`: optional path to a specific snapshot file
- `$ResumeFromStep`: skip to step N (valid: 1-3, default 1)
- `$BootstrapOnly`: download scripts and exit
- `-v` / `-vv`: verbosity levels

### Flow
1. Define `$dependenciesFile` path (not loaded yet)
2. Import UmeAiRTUtils; rotate `update.log` and `bootstrap.log`; set `$global:logFile`
3. **Migrate** `repo-config.json` → `umeairt-user-config.json` (one-time, old installs only)
4. Read fork config via `Read-UserConfig`
5. Bootstrap self-update: download fresh `Bootstrap-Downloader.ps1` from `raw.githubusercontent.com`, run with `-SkipSelf`
6. **Load `dependencies.json` from disk** (after bootstrap — always uses freshly downloaded version)
7. Environment detection: read `scripts/install_type`, resolve `$pythonExe`
8. Validate `$ResumeFromStep` (1-3); pre-seed `$global:currentStep = $ResumeFromStep - 1`
9. **Step 1** (if `$ResumeFromStep -le 1`): ComfyUI git pull + requirements; ComfyUI-Manager update; snapshot resolve (5-priority chain) + cm-cli restore + update all
10. **Step 2** (if `$ResumeFromStep -le 2`): ComfyUI-nunchaku cleanup (remove corrupted non-git dirs); DazzleML installer `--upgrade`
11. **Step 3**: Re-pin managed wheels via `uv pip install --force-reinstall`

### Snapshot Priority Chain
1. `-SnapshotPath` CLI param
2. `snapshot_path` key in `umeairt-user-config.json`
3. Interactive prompt → auto-save to `scripts/user-snapshot.json`
4. Pre-existing `scripts/user-snapshot.json`
5. Upstream `scripts/snapshot.json` (fallback)

---

## Bootstrap Downloader (`scripts/Bootstrap-Downloader.ps1`, 157 lines)

Downloads all scripts + configs from `raw.githubusercontent.com` via `Invoke-WebRequest`.
Parameters: `$InstallPath`, `$GhUser`, `$GhRepoName`, `$GhBranch`, `-v`/`-vv`.
Reads fork config from `umeairt-user-config.json` / `repo-config.json` if params empty.
File list: 15 PS1 scripts + 6 bat launchers + 4 config files.
Self-update: includes itself as last entry in download list.
Clears read-only attributes before overwriting.
Logs each download to `logs/bootstrap.log` via inline `_AppendLog` helper.

---

## Model Download Scripts (`scripts/Download-*-Models.ps1`)

All follow the same pattern:
1. Import UmeAiRTUtils, detect GPU via `Get-GpuVramInfo`
2. Show VRAM-based recommendations
3. Series of `Read-UserChoice` calls with letter-based menus (A/B/C/D...)
4. Procedural `Save-File -Uri ... -OutFile ...` calls based on choices
5. Models hosted on HuggingFace at `https://huggingface.co/UmeAiRT/ComfyUI-Auto-Installer-Assets/resolve/main/models/`

8 model packs: FLUX, WAN2.1, WAN2.2, HIDREAM, LTX1, LTX2, QWEN, Z-IMAGE.
