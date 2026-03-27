<#
.SYNOPSIS
    Interactive downloader for HiDream models.
.DESCRIPTION
    Downloads HiDream base models and GGUF quantized models for ComfyUI.
    Provides recommendations based on detected GPU VRAM.
.PARAMETER InstallPath
    The root directory of the installation.
#>

param(
    [string]$InstallPath = $PSScriptRoot,
    [switch]$DownloadAll,
    [switch]$v,
    [switch]$vv
)

# ============================================================================
# INITIALIZATION
# ============================================================================
$InstallPath = $InstallPath.Trim('"')
Import-Module (Join-Path $PSScriptRoot "UmeAiRTUtils.psm1") -Force
$global:Verbosity = if ($vv) { 2 } elseif ($v) { 1 } else { 0 }

# ============================================================================
# MAIN EXECUTION
# ============================================================================

$modelsPath = Join-Path $InstallPath "models"
if (-not (Test-Path $modelsPath)) {
    Write-Log "Models directory does not exist, creating it..." -Color Yellow
    New-Item -Path $modelsPath -ItemType Directory -Force | Out-Null
}

# --- GPU Detection & Recommendations ---
Write-Log "-------------------------------------------------------------------------------"
Write-Log "Checking for NVIDIA GPU to provide model recommendations..." -Color Yellow
$gpuInfo = Get-GpuVramInfo
if ($gpuInfo) {
    Write-Log "GPU: $($gpuInfo.GpuName)" -Color Green
    Write-Log "VRAM: $($gpuInfo.VramGiB) GB" -Color Green

    if ($gpuInfo.VramGiB -ge 16) {
        Write-Log "Recommendation: fp16" -Color Cyan
    }
    elseif ($gpuInfo.VramGiB -ge 12) {
        Write-Log "Recommendation: fp8 or GGUF Q8" -Color Cyan
    }
    elseif ($gpuInfo.VramGiB -ge 8) {
        Write-Log "Recommendation: GGUF Q5" -Color Cyan
    }
    else {
        Write-Log "Recommendation: GGUF Q4 or Lower" -Color Cyan
    }
}
else {
    Write-Log "No NVIDIA GPU detected. Please choose based on your hardware." -Color Gray
}
Write-Log "-------------------------------------------------------------------------------"

# --- User Prompts ---
if ($DownloadAll) {
    $baseChoice = 'A'; $ggufChoice = 'D'
} else {
    $baseChoice = Read-UserChoice -Prompt "Do you want to download HiDream base models?" -Choices @("A) fp8", "B) No") -ValidAnswers @("A", "B")
    $ggufChoice = Read-UserChoice -Prompt "Do you want to download HiDream GGUF models?" -Choices @("A) Q8_0", "B) Q5_K_S", "C) Q4_K_S", "D) All", "E) No") -ValidAnswers @("A", "B", "C", "D", "E")
}

# --- Download Process ---
Write-Log "Starting HiDream model downloads..." -Color Cyan

$baseUrl = "https://huggingface.co/UmeAiRT/ComfyUI-Auto-Installer-Assets/resolve/main/models"
$hidreamDiffDir = Join-Path $modelsPath "diffusion_models\HiDream"
$hidreamUnetDir = Join-Path $modelsPath "unet\HiDream"

New-Item -Path $hidreamDiffDir, $hidreamUnetDir -ItemType Directory -Force | Out-Null

if ($baseChoice -eq 'A') {
    Write-Log "Downloading HiDream base models..."
    Save-FileCollecting -Uri "$baseUrl/diffusion_models/HiDream/hidream-i1-dev-fp8.safetensors" -OutFile (Join-Path $hidreamDiffDir "hidream-i1-dev-fp8.safetensors")
}

if ($ggufChoice -ne 'E') {
    Write-Log "Downloading HiDream GGUF models..."
    if ($ggufChoice -in 'A', 'D') {
        Save-FileCollecting -Uri "$baseUrl/diffusion_models/HiDream/HiDream-I1-Dev-Q8_0.gguf" -OutFile (Join-Path $hidreamUnetDir "hidream-i1-dev-Q8_0.gguf")
    }
    if ($ggufChoice -in 'B', 'D') {
        Save-FileCollecting -Uri "$baseUrl/diffusion_models/HiDream/HiDream-I1-Dev-Q5_K_S.gguf" -OutFile (Join-Path $hidreamUnetDir "hidream-i1-dev-Q5_K_S.gguf")
    }
    if ($ggufChoice -in 'C', 'D') {
        Save-FileCollecting -Uri "$baseUrl/diffusion_models/HiDream/HiDream-I1-Dev-Q4_K_S.gguf" -OutFile (Join-Path $hidreamUnetDir "hidream-i1-dev-Q4_K_S.gguf")
    }
}

Show-DownloadSummary
Write-Log "HiDream model downloads complete." -Color Green
if (-not $DownloadAll) { Read-Host "Press Enter to return to the main installer." }
