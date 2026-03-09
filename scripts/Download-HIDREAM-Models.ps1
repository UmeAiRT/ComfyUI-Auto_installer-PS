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
    [string]$InstallPath = $PSScriptRoot
)

# ============================================================================
# INITIALIZATION
# ============================================================================
$InstallPath = $InstallPath.Trim('"').TrimEnd('\', '/').Replace('\', '/')
Import-Module "$($PSScriptRoot.Replace('\','/'))/UmeAiRTUtils.psm1" -Force

# ============================================================================
# MAIN EXECUTION
# ============================================================================

$modelsPath = "$InstallPath/models"
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
$baseChoice = Read-UserChoice -Prompt "Do you want to download HiDream base models?" -Choices @("A) fp16", "B) fp8", "C) All", "D) No") -ValidAnswers @("A", "B", "C", "D")
$ggufChoice = Read-UserChoice -Prompt "Do you want to download HiDream GGUF models?" -Choices @("A) Q8_0", "B) Q5_K_S", "C) Q4_K_S", "D) All", "E) No") -ValidAnswers @("A", "B", "C", "D", "E")

# --- Download Process ---
Write-Log "Starting HiDream model downloads..." -Color Cyan

$baseUrl = "https://huggingface.co/UmeAiRT/ComfyUI-Auto_installer/resolve/main/models"
$hidreamDiffDir = "$modelsPath/diffusion_models/HiDream"
$hidreamUnetDir = "$modelsPath/unet/HiDream"

New-Item -Path $hidreamDiffDir, $hidreamUnetDir -ItemType Directory -Force | Out-Null

if ($baseChoice -ne 'D') {
    Write-Log "Downloading HiDream base models..."
    if ($baseChoice -in 'A', 'C') {
        Save-File -Uri "$baseUrl/diffusion_models/HiDream/hidream_i1_dev_fp16.safetensors" -OutFile "$hidreamDiffDir/hidream_i1_dev_fp16.safetensors"
    }
    if ($baseChoice -in 'B', 'C') {
        Save-File -Uri "$baseUrl/diffusion_models/HiDream/hidream_i1_dev_fp8.safetensors" -OutFile "$hidreamDiffDir/hidream_i1_dev_fp8.safetensors"
    }
}

if ($ggufChoice -ne 'E') {
    Write-Log "Downloading HiDream GGUF models..."
    if ($ggufChoice -in 'A', 'D') {
        Save-File -Uri "$baseUrl/unet/HiDream/hidream-i1-dev-Q8_0.gguf" -OutFile "$hidreamUnetDir/hidream-i1-dev-Q8_0.gguf"
    }
    if ($ggufChoice -in 'B', 'D') {
        Save-File -Uri "$baseUrl/unet/HiDream/hidream-i1-dev-Q5_K_S.gguf" -OutFile "$hidreamUnetDir/hidream-i1-dev-Q5_K_S.gguf"
    }
    if ($ggufChoice -in 'C', 'D') {
        Save-File -Uri "$baseUrl/unet/HiDream/hidream-i1-dev-Q4_K_S.gguf" -OutFile "$hidreamUnetDir/hidream-i1-dev-Q4_K_S.gguf"
    }
}

Write-Log "HiDream model downloads complete." -Color Green
Read-Host "Press Enter to return to the main installer."
