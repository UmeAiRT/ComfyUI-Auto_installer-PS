<!-- Generated: 2026-03-25 | Source: scripts/dependencies.json, scripts/environment.yml -->

# Data Models & Configuration

## dependencies.json (105 lines)

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
All tools include `url` and `sha256` for integrity verification.
Authenticode-signed tools also include `authenticode_subject`.

| Tool | SHA256 | Authenticode |
|------|--------|-------------|
| `vs_build_tools` | yes | "Microsoft Corporation" |
| `aria2` | yes | no |
| `git` | yes | "Johannes Schindelin" |
| `python` | yes (3.13.11) | "Python Software Foundation" |
| `miniconda` | yes | "Anaconda, Inc." |
| `uv` | yes (install.ps1) | no |

### `pip_packages`
- `upgrade`: `["pip", "wheel"]`
- `torch.packages`: `"torch==2.10.0+cu130 torchvision torchaudio xformers"`
- `torch.index_url`: `"https://download.pytorch.org/whl/cu130"`
- `comfyui_requirements`: `"requirements.txt"` (relative to ComfyUI dir)
- `wheels`: array of `{ "name", "url", "sha256", "_note_sha256" }`:
  - nunchaku 1.2.1+cu13.0torch2.10 (cp313, HF Assets repo)
  - insightface 0.7.3 (cp313, HF Assets repo)
  - Both sha256 fields currently empty (TODO: verify after HF hosting move)
- `standard`: 14 packages (facexlib, cython, onnxruntime-gpu, hf_xet, nvidia-ml-py, cupy-cuda13x, imageio-ffmpeg, rotary_embedding_torch, blend_modes, omegaconf, segment_anything, gguf, deepdiff, py-cpuinfo)
- `git_repos`: `[]` (empty, unused)

### `files`
| Key | Destination | SHA256 |
|-----|------------|--------|
| `comfy_settings` | `user/default/comfy.settings.json` | no |
| `custom_nodes_csv` | `scripts/custom_nodes.csv` | yes |
| `installer_script` | `scripts/comfyui_triton_sageattention.py` | yes |
| `nunchaku_versions` | `ComfyUI/custom_nodes/ComfyUI-nunchaku/nunchaku_versions.json` | yes |

All file URLs point to `raw.githubusercontent.com/UmeAiRT/ComfyUI-Auto_installer-PS/main/...`.

## environment.yml (18 lines)

Conda environment specification for "Full" install mode:
- **Name**: `UmeAiRT`
- **Channels**: conda-forge, pytorch, nvidia, defaults
- **Dependencies**: python=3.13.11, git, cuda-toolkit=13.0.2, pip, ninja, ccache, c-compiler, cxx-compiler
- **Pip**: triton-windows

## Global State Variables

Scripts use `$global:` variables for cross-function communication:

| Variable | Set by | Used by |
|----------|--------|---------|
| `$global:logFile` | Each script init | `Write-Log`, `Invoke-AndLog` |
| `$global:totalSteps` | Each script init | `Write-Log` (Level 0 headers) |
| `$global:currentStep` | `Write-Log` (auto-increment) or `$ResumeFromStep - 1` | `Write-Log` (Level 0 headers) |
| `$global:hasGpu` | Phase 2 init (`Test-NvidiaGpu`) | Not referenced after assignment |

## File-Based State

| File | Written by | Read by | Content |
|------|-----------|---------|---------|
| `scripts/install_type` | Phase 1 | Phase 2, Update, all bat files | `"venv"` or `"conda"` |
| `scripts/Launch-Phase2.ps1` | Phase 1 (generated) | Phase 1 (launched) | Env activation + Phase 2 call |
| `umeairt-user-config.json` | Install-ComfyUI.ps1 / user | All entry points | `{ "gh_user", "gh_reponame", "gh_branch", ... }` |
| `repo-config.json` | User (manual, deprecated) | All entry points (fallback) | `{ "gh_user", "gh_reponame", "gh_branch" }` |
| `scripts/snapshot.json` | Bootstrap download | Phase 2, Update | ComfyUI-Manager snapshot for node restoration |
| `scripts/user-snapshot.json` | Update (interactive save) | Update (priority 4) | User's saved snapshot |
| `scripts/custom_nodes.csv` | Bootstrap download | Phase 2 (fallback) | CSV with Name, RepoUrl columns |
| `logs/install.log` | Phase 1/2 | User (debugging) | Timestamped log entries |
| `logs/update.log` | Update script | User (debugging) | Timestamped log entries |
| `logs/bootstrap.log` | Bootstrap-Downloader | User (debugging) | Download success/failure log |

## Model Download Data Flow

Model downloads are **procedural** — no structured metadata objects.
Each download script calls `Save-File -Uri <url> -OutFile <path>` directly based on
user menu choices. URLs are hardcoded string literals, not data-driven from a config file.
Models are hosted on HuggingFace under `huggingface.co/UmeAiRT/ComfyUI-Auto-Installer-Assets/resolve/main/models/`.

Model directory structure under `InstallRoot/models/`:
```
models/
├── diffusion_models/      (FLUX, WAN, HiDream, LTX safetensors)
├── text_encoders/T5/      (T5 text encoder models)
├── unet/                  (GGUF quantized models)
├── clip/                  (CLIP models)
├── vae/                   (ae.safetensors)
├── xlabs/controlnets/     (XLabs ControlNet v3)
├── pulid/                 (PuLID face models)
├── style_models/          (REDUX)
├── loras/                 (LoRAs by model family)
└── upscale_models/        (RealESRGAN, AnimeSharp, UltraSharp, NMKD)
```
