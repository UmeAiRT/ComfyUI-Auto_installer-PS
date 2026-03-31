<#
.SYNOPSIS
    Interactive downloader for LTX-Video (LTX1) models.
.DESCRIPTION
    Downloads LTX-Video base models and GGUF quantized models for ComfyUI.
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

    if ($gpuInfo.VramGiB -ge 30) { Write-Log "Recommendation: Base 13B" -Color Cyan }
    elseif ($gpuInfo.VramGiB -ge 24) { Write-Log "Recommendation: GGUF Q8_0" -Color Cyan }
    elseif ($gpuInfo.VramGiB -ge 16) { Write-Log "Recommendation: GGUF Q5_K_M" -Color Cyan }
    elseif ($gpuInfo.VramGiB -ge 7) { Write-Log "Recommendation: Base 2B or GGUF Q3_K_S" -Color Cyan }
    else { Write-Log "Recommendation: GGUF Q3_K_S (performance may vary)" -Color Cyan }
}
else {
    Write-Log "No NVIDIA GPU detected. Please choose based on your hardware." -Color Gray
}
Write-Log "-------------------------------------------------------------------------------"

# --- User Prompts ---
if ($DownloadAll) {
    $baseChoice = 'C'; $ggufChoice = 'D'
} else {
    $baseChoice = Read-UserChoice -Prompt "Do you want to download LTXV base models?" -Choices @("A) 13B (30Gb)", "B) 2B (7Gb)", "C) All", "D) No") -ValidAnswers @("A", "B", "C", "D")
    $ggufChoice = Read-UserChoice -Prompt "Do you want to download LTXV GGUF models?" -Choices @("A) Q8_0 (24GB Vram)", "B) Q5_K_M (16GB Vram)", "C) Q3_K_S (less than 12GB Vram)", "D) All", "E) No") -ValidAnswers @("A", "B", "C", "D", "E")
}

# --- Download Process ---
Write-Log "Starting LTX-Video model downloads..." -Color Cyan

$baseUrl = "https://huggingface.co/UmeAiRT/ComfyUI-Auto-Installer-Assets/resolve/main/models"
$ltxvChkptDir = Join-Path $modelsPath "checkpoints\LTXV"
$ltxvUnetDir = Join-Path $modelsPath "unet\LTXV"
$vaeDir = Join-Path $modelsPath "vae"

New-Item -Path $ltxvChkptDir, $ltxvUnetDir, $vaeDir -ItemType Directory -Force | Out-Null

$doDownload = ($baseChoice -ne 'D' -or $ggufChoice -ne 'E')

if ($doDownload) {
    Write-Log "Downloading LTXV common support file (VAE)..."
    Save-FileCollecting -Uri "$baseUrl/vae/ltxv-13b-0.9.7-vae-BF16.safetensors" -OutFile (Join-Path $vaeDir "ltxv-13b-0.9.7-vae-BF16.safetensors")
}

if ($baseChoice -ne 'D') {
    Write-Log "Downloading LTXV base model(s)..."
    if ($baseChoice -in 'A', 'C') {
        Save-FileCollecting -Uri "$baseUrl/checkpoints/LTXV/ltxv-13b-0.9.7-dev.safetensors" -OutFile (Join-Path $ltxvChkptDir "ltxv-13b-0.9.7-dev.safetensors")
    }
    if ($baseChoice -in 'B', 'C') {
        Save-FileCollecting -Uri "$baseUrl/checkpoints/LTXV/ltxv-2b-0.9.6-dev-04-25.safetensors" -OutFile (Join-Path $ltxvChkptDir "ltxv-2b-0.9.6-dev-04-25.safetensors")
    }
}

if ($ggufChoice -ne 'E') {
    Write-Log "Downloading LTXV GGUF models..."
    if ($ggufChoice -in 'A', 'D') {
        Save-FileCollecting -Uri "$baseUrl/diffusion_models/LTXV/LTXV-13B-0.9.8-Dev-Q8_0.gguf" -OutFile (Join-Path $ltxvUnetDir "LTXV-13B-0.9.8-Dev-Q8_0.gguf")
    }
    if ($ggufChoice -in 'B', 'D') {
        Save-FileCollecting -Uri "$baseUrl/diffusion_models/LTXV/LTXV-13B-0.9.8-Dev-Q5_K_S.gguf" -OutFile (Join-Path $ltxvUnetDir "LTXV-13B-0.9.8-Dev-Q5_K_S.gguf")
    }
    if ($ggufChoice -in 'C', 'D') {
        Save-FileCollecting -Uri "$baseUrl/diffusion_models/LTXV/LTXV-13B-0.9.8-Dev-Q3_K_S.gguf" -OutFile (Join-Path $ltxvUnetDir "LTXV-13B-0.9.8-Dev-Q3_K_S.gguf")
    }
}

Show-DownloadSummary
Write-Log "LTX-Video model downloads complete." -Color Green
if (-not $DownloadAll) { Read-Host "Press Enter to return to the main installer." }
