<!-- Generated: 2026-03-25 | Source files: 24 | Token estimate: ~1200 -->

# Architecture

## System Overview

Windows-only ComfyUI auto-installer using PowerShell scripts and batch launchers.
Two-phase install, NTFS junction-based external folder architecture, bootstrap self-update.
Repo: `UmeAiRT/ComfyUI-Auto_installer-PS`.

## Entry Points (6 bat files)

```
UmeAiRT-Install-ComfyUI.bat       → reads fork config → downloads Install-ComfyUI.ps1 → launches it
UmeAiRT-Update-ComfyUI.bat        → thin passthrough → Update-ComfyUI.ps1 %*
UmeAiRT-Bootstrap.bat             → reads fork config → rescue-downloads Bootstrap-Downloader.ps1 if missing → runs it
UmeAiRT-Start-ComfyUI.bat         → calls scripts/Start-ComfyUI.ps1 (thin wrapper)
UmeAiRT-Start-ComfyUI_LowVRAM.bat → calls scripts/Start-ComfyUI.ps1 -LowVRAM (thin wrapper)
UmeAiRT-Download_models.bat       → numeric menu (1-8, Q quit) via set /p → Download-{MODEL}-Models.ps1
```

## Fork Configuration

All bat entry points (Install, Bootstrap) read `umeairt-user-config.json` (preferred) or
`repo-config.json` (deprecated) for fork testing. Keys: `gh_user`, `gh_reponame`, `gh_branch`.
Resolved coords are passed as `-GhUser`/`-GhRepoName`/`-GhBranch` params to PS1 scripts.
No hardcoded upstream URLs in any entry point — all use resolved fork coordinates.

## Bootstrap Self-Update

`Bootstrap-Downloader.ps1` downloads all project files (15 PS1 + 6 bat + 4 config) from
`raw.githubusercontent.com` using resolved fork coords. Includes itself as last entry
(self-update). Clears read-only attributes before overwriting. Logs to `logs/bootstrap.log`.

`UmeAiRT-Bootstrap.bat` is a standalone rescue tool — reads fork config, downloads
`Bootstrap-Downloader.ps1` if missing, passes fork coords through.

## Two-Phase Installation

**Phase 1** (`Install-ComfyUI-Phase1.ps1`, 634 lines):
- Admin tasks via UAC self-elevation: Long Paths registry key, VS Build Tools install
- Install type selection: `Read-Host` with numeric `1`/`2` choices (Light=venv, Full=Conda)
- System deps: aria2 (download accelerator), Git (auto-install prompt Y/N), Python 3.13 or Miniconda
- Creates environment: venv (`python -m venv`) or Conda (`conda env create -f environment.yml`)
- uv install: detects system-wide first, downloads only if absent
- Generates `Launch-Phase2.ps1` dynamically (env-specific activation + Phase2 call)
- Launches Phase 2 in a new PowerShell window

**Phase 2** (`Install-ComfyUI-Phase2.ps1`, 523 lines):
- Clones ComfyUI from `dependencies.repositories.comfyui.url`
- Sets up junction architecture (5 folders)
- Pip installs via `uv pip install`: ninja, pip/wheel upgrade, torch+cu130, ComfyUI requirements, standard packages
- Custom nodes via `cm-cli.py`: snapshot.json (primary) or custom_nodes.csv (fallback)
- UmeAiRT-Sync custom node (workflow auto-update)
- MagCache hotfix: patches line 13 of `nodes.py` and `nodes_calibration.py`
- Triton/SageAttention: DazzleML installer (venv) or manual pip (Conda fallback)
- Nunchaku config URL read from `dependencies.files.nunchaku_versions.url`
- .whl installs: nunchaku, insightface (URLs from dependencies.json, HF Assets repo)
- Optional model packs: Y/N `Read-Host` per pack (8 packs)

## ComfyUI Launch Flow (`Start-ComfyUI.ps1`, 249 lines)

Unified launcher for both standard and low-VRAM modes.

**Execution flow:**
1. Set Python isolation env vars (`PYTHONPATH=''`, `PYTHONNOUSERSITE=1`, `PYTHONUTF8=1`)
2. **MSVC toolchain activation (Triton unicode-path workaround):** locate `vswhere.exe`, run
   `vcvarsall.bat amd64`, capture environment via `cmd /c "... && set"`, replay into PS session,
   set `CC=cl.exe` so Triton's `build.py` uses MSVC instead of bundled `tcc.exe`.
   Falls back with a warning if MSVC is not installed — `tcc.exe` will fail on non-ASCII paths.
3. Detect install type (venv or conda) from `scripts/install_type` file or directory presence
4. Activate appropriate Python environment (venv Activate.ps1 or conda)
5. Read `umeairt-user-config.json` if present for network config
6. Validate config: gh_user/gh_reponame/gh_branch (alphanumeric + hyphens/underscores)
7. Validate network config: listen_enabled flag, listen_address (IPv4/IPv6), listen_port (1-65535)
8. Build network args: `--listen <address>` + optional `--port` (only if not default 8188)
9. Build VRAM args: if -LowVRAM flag, add `--disable-smart-memory --lowvram --fp8_e4m3fn-text-enc`
10. Launch: `python main.py --use-sage-attention --auto-launch <network-args> <vram-args>`

**Security:** listen_address validation prevents IP injection; warns if exposing 0.0.0.0 or ::
**Unicode paths:** MSVC handles non-ASCII install paths (e.g. Japanese folder names); tcc.exe cannot.

## Junction Architecture

ComfyUI internal folders are NTFS junctions to external folders at install root.
Enables clean `git pull` updates without overwriting user data.

```
InstallRoot/
├── ComfyUI/                 (git clone)
│   ├── custom_nodes/  →  junction → InstallRoot/custom_nodes/
│   ├── models/        →  junction → InstallRoot/models/
│   ├── output/        →  junction → InstallRoot/output/
│   ├── input/         →  junction → InstallRoot/input/
│   └── user/          →  junction → InstallRoot/user/
├── scripts/                 (PowerShell scripts, configs, venv if Light install)
├── logs/
└── *.bat                    (6 launchers)
```

## Environment Detection

All scripts detect install type via `scripts/install_type` file content ("venv" or "conda").
Fallback: check for `scripts/venv/` directory existence.
Bat files use `where pwsh` to prefer PowerShell 7+ over Windows PowerShell 5.1.
PS1 scripts resolve `$pythonExe` based on install type.
`$psExe` detected at runtime and inherited across phases.

## Update Flow (`Update-ComfyUI.ps1`, 448 lines)

Supports `--ResumeFromStep N` to skip completed steps on retry.

1. **Step 1**: `git pull` ComfyUI core + reinstall requirements.txt; update ComfyUI-Manager; snapshot restore + update all nodes
2. **Step 2**: ComfyUI-nunchaku cleanup (remove corrupted non-git dirs); DazzleML installer `--upgrade` (Triton/SageAttention)
3. **Step 3**: Re-pin managed wheels (nunchaku, insightface) via `uv pip install --force-reinstall`

## Key Files

| File | Lines | Purpose |
|------|-------|---------|
| `scripts/UmeAiRTUtils.psm1` | 587 | Shared utility module (14 exported functions) |
| `scripts/Install-ComfyUI.ps1` | 178 | Entry point: config, bootstrap, launch Phase 1 |
| `scripts/Install-ComfyUI-Phase1.ps1` | 634 | Admin setup + environment creation |
| `scripts/Install-ComfyUI-Phase2.ps1` | 523 | ComfyUI clone + deps + nodes + models |
| `scripts/Update-ComfyUI.ps1` | 448 | Updater with --ResumeFromStep support |
| `scripts/Start-ComfyUI.ps1` | 213 | ComfyUI launcher (env detection + network config) |
| `scripts/Bootstrap-Downloader.ps1` | 157 | Self-update downloader (includes self) |
| `scripts/Download-Models.ps1` | - | Model download menu dispatcher |
| `scripts/dependencies.json` | 105 | URLs, packages, tool configs, file hashes |
| `scripts/environment.yml` | 18 | Conda env spec (python=3.13.11, cuda-toolkit=13.0.2) |
| `UmeAiRT-Bootstrap.bat` | 53 | Standalone rescue tool with fork config reading |
