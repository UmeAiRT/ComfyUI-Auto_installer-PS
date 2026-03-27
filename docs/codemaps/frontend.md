<!-- Generated: 2026-03-25 | Source: *.bat, scripts/*.ps1 -->

# Frontend / User Interface Patterns

## Overview

All user interaction is via Windows console (batch files + PowerShell).
No web UI, no GUI. Two distinct input patterns used across scripts.

## Input Pattern 1: Read-Host (Numeric / Y-N)

Used in Phase 1 and Phase 2 for simple choices. Raw `Read-Host` with manual validation loops.

### Install Type Menu (Phase 1, lines 190-198)
```
Choose installation type:
1. Light (Recommended) - Uses your existing Python 3.13 (Standard venv)
2. Full - Installs Miniconda, Python 3.13, Git, CUDA (Isolated environment)
Enter choice (1 or 2): _
```
Validation: `while ($installTypeChoice -notin @("1", "2"))` loop.

### Y/N Prompts (Phase 1 + Phase 2)
Used for: Git auto-install, Python auto-install, model pack downloads.
```
Would you like to download FLUX models? (Y/N)
```
Validation: `while ($choice -notin @("Y","N"))` or manual `if/elseif/else` with retry.

### Model Pack Prompts (Phase 2, lines 476-502)
Iterates over 8 model packs, each with Y/N `Read-Host`:
```powershell
$modelPacks = @(
    @{Name = "FLUX"; ScriptName = "Download-FLUX-Models.ps1" },
    @{Name = "WAN2.1"; ScriptName = "Download-WAN2.1-Models.ps1" },
    # ... 6 more
)
foreach ($pack in $modelPacks) {
    # Y/N Read-Host loop per pack
}
```

## Input Pattern 2: Read-UserChoice (Letter-Based Menus)

Used in Download-*-Models.ps1 scripts via `Read-UserChoice` from UmeAiRTUtils.psm1.
Displays labeled choices, returns uppercase letter.

### Example: FLUX Base Models (Download-FLUX-Models.ps1, line 67)
```
Do you want to download FLUX base models?
  A) fp16
  B) fp8
  C) All
  D) No
Enter your choice and press Enter: _
```
Call: `Read-UserChoice -Prompt "..." -Choices @("A) fp16", "B) fp8", "C) All", "D) No") -ValidAnswers @("A", "B", "C", "D")`

## Input Pattern 3: Batch Menu (Download_models.bat)

Numeric menu in batch via `set /p`:
```
  Choose model to download:

    1. FLUX Models
    2. WAN2.1 Models
    3. WAN2.2 Models
    4. HIDREAM Models
    5. LTX1 Models
    6. LTX2 Models
    7. QWEN Models
    8. Z-IMAGE Models

    Q. Quit

Your choice: _
```
Dispatches via `if /i "%CHOICE%"=="1" goto :DOWNLOAD_FLUX` etc.
Returns to menu after each download completes.

## Output Patterns

### Write-Log Levels
All scripts use `Write-Log` for structured console output:
- **Level 0** (Yellow): Step headers with `[Step N/M]` and `===` separators
- **Level 1** (White): Main actions with `"  - "` prefix
- **Level 2** (White): Sub-actions with `"    -> "` prefix
- **Level 3** (DarkGray): Debug info with `"      [INFO] "` prefix

### GPU VRAM Recommendations (Download scripts)
Before model menus, `Get-GpuVramInfo` detects GPU and prints recommendation:
```
GPU: NVIDIA GeForce RTX 4090
VRAM: 24 GB
Recommendation: fp8 or GGUF Q8
```
Thresholds vary by model family (WAN2.2: >=40GB fp16, >=23GB fp8/Q8, >=16GB Q5, else Q3).

### ASCII Banner (Phase 1, lines 176-187)
Displays UmeAiRT logo + "ComfyUI - Auto-Installer Version 4.3" on Phase 1 start.

## Environment Activation (Bat files)

All bat launchers share the same environment detection + activation pattern:
1. Read `scripts\install_type` file (or fallback: check for `scripts\venv\`)
2. If venv: `call scripts\venv\Scripts\activate.bat`
3. If conda: `call %LOCALAPPDATA%\Miniconda3\Scripts\activate.bat` then `call conda activate UmeAiRT`
4. Error check with `pause` + `exit /b` on failure
