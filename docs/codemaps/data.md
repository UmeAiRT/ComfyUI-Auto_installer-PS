<!-- Generated: 2026-03-03 | Source: scripts/dependencies.json, scripts/environment.yml, scripts/umeairt-user-config.json.example -->

# Data Models & Configuration

## dependencies.json

Central configuration file loaded by Phase 1, Phase 2, and Update scripts.
Top-level keys:

### `repositories`
```json
{
  "comfyui": { "url": "https://github.com/comfyanonymous/ComfyUI.git" },
  "workflows": { "url": "https://github.com/UmeAiRT/ComfyUI-Workflows" }
}
```

### `tools`
```json
{
  "vs_build_tools": {
    "install_path": "C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools",
    "url": "https://aka.ms/vs/17/release/vs_BuildTools.exe",
    "arguments": "--wait --quiet --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
  }
}
```

### `pip_packages`
- `upgrade`: `["pip", "wheel"]`
- `torch.packages`: `"torch==2.10.0+cu130 torchvision torchaudio xformers"`
- `torch.index_url`: `"https://download.pytorch.org/whl/cu130"`
- `comfyui_requirements`: `"requirements.txt"` (relative to ComfyUI dir)
- `wheels`: array of `{ "name": string, "url": string }` — nunchaku and insightface .whl files
- `standard`: array of package name strings (facexlib, cython, onnxruntime-gpu, hf_xet, nvidia-ml-py, cupy-cuda13x, imageio-ffmpeg, rotary_embedding_torch, blend_modes, omegaconf, segment_anything, gguf, deepdiff, pynvml, py-cpuinfo)
- `git_repos`: `[]` (empty, unused)

### `files`
- `comfy_settings`: `{ "url": "...", "destination": "user/default/comfy.settings.json" }`
- `custom_nodes_csv`: `{ "url": "...", "destination": "scripts/custom_nodes.csv" }`
- `installer_script`: `{ "url": "...(DazzleML)...", "destination": "scripts/comfyui_triton_sageattention.py" }`

## environment.yml (18 lines)

Conda environment specification for "Full" install mode:
- **Name**: `UmeAiRT`
- **Channels**: conda-forge, pytorch, nvidia, defaults
- **Dependencies**: python=3.13.11, git, cuda-toolkit=13.0.2, pip, ninja, ccache, c-compiler, cxx-compiler
- **Pip**: triton-windows

## umeairt-user-config.json (37 lines, NEW)

User-local configuration template. Never overwritten by bootstrap or updates.
Supports fork testing and network configuration. All fields are optional.

### Repository Source Override
- `gh_user`: GitHub username (alphanumeric, hyphens, underscores)
- `gh_reponame`: Repository name (alphanumeric, hyphens, underscores)
- `gh_branch`: Branch name (alphanumeric, hyphens, underscores, dots, forward slashes)
- Defaults: empty strings → use upstream UmeAiRT/ComfyUI-Auto_installer/main

### Network Listen Configuration
- `listen_enabled`: Boolean flag (default: false). When true, requires listen_address.
- `listen_address`: Single IP or comma-separated list (e.g., '127.0.0.1,100.64.0.1'). Accepts IPv4 and IPv6.
  - WARNING: '0.0.0.0' or '::' exposes ComfyUI on all interfaces.
  - Validated for allowed characters (IPv4/IPv6 format only).
- `listen_port`: Integer 1-65535 (default: 8188). Ports below 1024 are privileged.
  - If 8188 (default), omitted from `--port` argument to Python launcher.

Read by: `Start-ComfyUI.ps1` for network argument construction.

## repo-config.json (DEPRECATED)

Legacy configuration file, now deprecated. Still supported as fallback.
Install and Update bat files check for `umeairt-user-config.json` first, then fall back to `repo-config.json`.
Deprecation notice in example directs users to migrate to umeairt-user-config.json.

Supports same keys: `gh_user`, `gh_reponame`, `gh_branch`.
Does NOT support network configuration (listen_enabled, listen_address, listen_port).

## Global State Variables

Scripts use `$global:` variables for cross-function communication:

| Variable | Set by | Used by |
|----------|--------|---------|
| `$global:logFile` | Each script init | `Write-Log`, `Invoke-AndLog` |
| `$global:totalSteps` | Each script init | `Write-Log` (Level 0 headers) |
| `$global:currentStep` | `Write-Log` (auto-increment) | `Write-Log` (Level 0 headers) |
| `$global:hasGpu` | Phase 2 init (`Test-NvidiaGpu`) | Not referenced after assignment |

## File-Based State

| File | Written by | Read by | Content |
|------|-----------|---------|---------|
| `scripts/install_type` | Phase 1 | Phase 2, Update, Start, all bat files | `"venv"` or `"conda"` |
| `scripts/Launch-Phase2.ps1` | Phase 1 (generated) | Phase 1 (launched) | Env activation + Phase 2 call |
| `umeairt-user-config.json` | User (manual) | Install/Update/Start bat files | Repository source + network config (preferred) |
| `repo-config.json` | User (manual) | Install/Update bat files (fallback only) | Repository source only (deprecated) |
| `scripts/snapshot.json` | Bootstrap download | Phase 2, Update | ComfyUI-Manager snapshot for node restoration |
| `scripts/custom_nodes.csv` | Bootstrap download | Phase 2 (fallback) | CSV with Name, RepoUrl columns |
| `logs/install_log.txt` | Phase 1/2 | User (debugging) | Timestamped log entries |
| `logs/update_log.txt` | Update script | User (debugging) | Timestamped log entries |

## Model Download Data Flow

Model downloads are **procedural** — no structured metadata objects.
Each download script calls `Save-File -Uri <url> -OutFile <path>` directly based on
user menu choices. URLs are hardcoded string literals, not data-driven from a config file.
Models are hosted on HuggingFace under `huggingface.co/UmeAiRT/ComfyUI-Auto_installer/resolve/main/models/`.

Model directory structure under `InstallRoot/models/`:
```
models/
├── diffusion_models/FLUX/    (safetensors: fp16, fp8, schnell, canny, depth, fill, nunchaku)
├── unet/FLUX/                (GGUF quantized: Q2-Q8)
├── clip/                     (CLIP/T5 models: safetensors + GGUF)
├── vae/                      (ae.safetensors)
├── xlabs/controlnets/        (XLabs ControlNet v3)
├── pulid/                    (PuLID face models)
├── style_models/             (REDUX)
├── loras/FLUX/               (UmeAiRT LoRAs)
└── upscale_models/           (RealESRGAN, AnimeSharp, UltraSharp, NMKD)
```
