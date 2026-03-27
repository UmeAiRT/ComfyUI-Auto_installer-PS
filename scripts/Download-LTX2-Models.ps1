<#
.SYNOPSIS
    Interactive downloader for LTX-Video 2 (LTX2) models.
.DESCRIPTION
    Downloads LTX-2 GGUF quantized models and support files (VAE, Text Encoder, LoRAs) for ComfyUI.
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

	if ($gpuInfo.VramGiB -ge 24) { Write-Log "Recommendation: GGUF Q8_0" -Color Cyan }
    elseif ($gpuInfo.VramGiB -ge 16) { Write-Log "Recommendation: GGUF Q5_K_M" -Color Cyan }
    elseif ($gpuInfo.VramGiB -ge 7) { Write-Log "Recommendation: GGUF Q4_K_S" -Color Cyan }
    else { Write-Log "Recommendation: GGUF Q3_K_S (performance may vary)" -Color Cyan }
}
else {
    Write-Log "No NVIDIA GPU detected. Please choose based on your hardware." -Color Gray
}
Write-Log "-------------------------------------------------------------------------------"

# --- User Prompts ---
# Base model download is currently disabled/commented out in source logic
# $baseChoice = Read-UserChoice -Prompt "Do you want to download LTXV base models?" -Choices @("A) 13B (30Gb)", "B) 2B (7Gb)", "C) All", "D) No") -ValidAnswers @("A", "B", "C", "D")

if ($DownloadAll) {
    $ggufChoice = 'D'
} else {
    $ggufChoice = Read-UserChoice -Prompt "Do you want to download LTXV GGUF models?" -Choices @("A) Q8_0 (24+GB Vram)", "B) Q5_K_M (12-16GB Vram)", "C) Q4_K_S (less than 12GB Vram)", "D) All", "E) No") -ValidAnswers @("A", "B", "C", "D", "E")
}

# --- Download Process ---
Write-Log "Starting LTX-2 model downloads..." -Color Cyan

$baseUrl = "https://huggingface.co/UmeAiRT/ComfyUI-Auto-Installer-Assets/resolve/main/models"
$ltxvChkptDir = Join-Path $modelsPath "checkpoints\LTX2"
$difftDir = Join-Path $modelsPath "diffusion_models"
$ltxvUnetDir = Join-Path $modelsPath "unet\LTX2"
$vaeDir = Join-Path $modelsPath "vae"
$upscaleDir = Join-Path $modelsPath "latent_upscale_models"
$lorasDir = Join-Path $modelsPath "loras"
$clipDir = Join-Path $modelsPath "clip"

New-Item -Path $ltxvChkptDir, $ltxvUnetDir, $vaeDir, $upscaleDir -ItemType Directory -Force | Out-Null

# Logic adaptation: If GGUF choice is not 'No', we download support files.
$doDownload = ($ggufChoice -ne 'E')

if ($doDownload) {
    Write-Log "Downloading LTX2 VAE..."
    Save-FileCollecting -Uri "$baseUrl/vae/LTX2_video_vae_bf16.safetensors" -OutFile (Join-Path $vaeDir "LTX2_video_vae_bf16.safetensors")
    Save-FileCollecting -Uri "$baseUrl/vae/LTX2_audio_vae_bf16.safetensors" -OutFile (Join-Path $vaeDir "LTX2_audio_vae_bf16.safetensors")

    Write-Log "Downloading LTX2 text encoder..."
    Save-FileCollecting -Uri "$baseUrl/text_encoders/LTX-2/ltx-2-19b-embeddings_connector_dev_bf16.safetensors" -OutFile (Join-Path $clipDir "ltx-2-19b-embeddings_connector_dev_bf16.safetensors")
    Save-FileCollecting -Uri "$baseUrl/text_encoders/GEMMA-3/gemma-3-12b-it-IQ4_XS.gguf" -OutFile (Join-Path $clipDir "gemma-3-12b-it-IQ4_XS.gguf")

    Write-Log "Downloading MelBandRoformer..."
    Save-FileCollecting -Uri "$baseUrl/diffusion_models/MelBandRoFormer/melband-roformer-fp32.safetensors" -OutFile (Join-Path $difftDir "melband-roformer-fp32.safetensors")
	
    Write-Log "Downloading LTX2 spatial upscaler..."
    Save-FileCollecting -Uri "$baseUrl/latent_upscale_models/ltx-2-spatial-upscaler-x2-1.0.safetensors" -OutFile (Join-Path $upscaleDir "ltx-2-spatial-upscaler-x2-1.0.safetensors")

    Write-Log "Downloading recommended LoRA..."
    Save-FileCollecting -Uri "$baseUrl/loras/LTX-2/ltx-2-19b-distilled-lora-384.safetensors" -OutFile (Join-Path $lorasDir "ltx-2-19b-distilled-lora-384.safetensors")
    Save-FileCollecting -Uri "$baseUrl/loras/LTX-2/ltx-2-19b-ic-lora-detailer.safetensors" -OutFile (Join-Path $lorasDir "ltx-2-19b-ic-lora-detailer.safetensors")
}

if ($ggufChoice -ne 'E') {
    Write-Log "Downloading LTX2 GGUF models..."
    if ($ggufChoice -in 'A', 'D') {
        Save-FileCollecting -Uri "$baseUrl/diffusion_models/LTX-2/LTX-2-19B-Dev-Q8_0.gguf" -OutFile (Join-Path $ltxvUnetDir "LTX-2-19B-Dev-Q8_0.gguf")
    }
    if ($ggufChoice -in 'B', 'D') {
        Save-FileCollecting -Uri "$baseUrl/diffusion_models/LTX-2/LTX-2-19B-Dev-Q5_K_S.gguf" -OutFile (Join-Path $ltxvUnetDir "LTX-2-19B-Dev-Q5_K_S.gguf")
    }
    if ($ggufChoice -in 'C', 'D') {
        Save-FileCollecting -Uri "$baseUrl/diffusion_models/LTX-2/LTX-2-19B-Dev-Q4_K_S.gguf" -OutFile (Join-Path $ltxvUnetDir "LTX-2-19B-Dev-Q4_K_S.gguf")
    }
}

Show-DownloadSummary
Write-Log "LTX-2 model downloads complete." -Color Green
if (-not $DownloadAll) { Read-Host "Press Enter to return to the main installer." }
