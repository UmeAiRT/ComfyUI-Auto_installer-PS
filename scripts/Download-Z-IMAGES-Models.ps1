<#
.SYNOPSIS
    Interactive downloader for Z-IMAGE Turbo models.
.DESCRIPTION
    Downloads Z-IMAGE Turbo BF16 (Base) and GGUF quantized models (Optimized).
    Also downloads RealESRGAN upscalers.
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
    Write-Log "Could not find ComfyUI models path at '$modelsPath'. Exiting." -Color Red
    Read-Host "Press Enter to exit."
    exit
}

# --- GPU Detection & Recommendation ---
Write-Log "-------------------------------------------------------------------------------"
Write-Log "Checking for NVIDIA GPU to provide model recommendations..." -Color Yellow
$gpuInfo = Get-GpuVramInfo
if ($gpuInfo) {
    Write-Log "GPU: $($gpuInfo.GpuName)" -Color Green
    Write-Log "VRAM: $($gpuInfo.VramGiB) GB" -Color Green
    # Precise Recommendations based on file sizes + ~3-4GB overhead for System/CLIP/Context
    if ($gpuInfo.VramGiB -ge 24) {
        Write-Log "Recommendation: BF16 (Best Quality) or GGUF Q8_0" -Color Cyan
    }
    elseif ($gpuInfo.VramGiB -ge 16) {
        Write-Log "Recommendation: BF16 (Might use shared RAM) or GGUF Q8_0 (Safe)" -Color Cyan
    }
    elseif ($gpuInfo.VramGiB -ge 12) {
        # Q8 is 7.22GB. Leaves ~4.8GB. Safe.
        Write-Log "Recommendation: GGUF Q8_0 (High Quality)" -Color Cyan
    }
    elseif ($gpuInfo.VramGiB -ge 10) {
        # Q6 is 5.91GB. Leaves ~4GB. Safe.
        Write-Log "Recommendation: GGUF Q6_K" -Color Cyan
    }
    elseif ($gpuInfo.VramGiB -ge 8) {
        # Q6 (5.9GB) is risky (leaves <2GB).
        # Q5 (5.19GB) leaves ~2.8GB. Sweet spot.
        Write-Log "Recommendation: GGUF Q5_K_S (Balanced) or Q4_K_S (Safe)" -Color Cyan
    }
    elseif ($gpuInfo.VramGiB -ge 6) {
        # Q4 (4.66GB) is risky (leaves <1.4GB).
        # Q3 (3.79GB) leaves ~2.2GB. Safe.
        Write-Log "Recommendation: GGUF Q3_K_S" -Color Cyan
    }
    else {
        Write-Log "Recommendation: GGUF Q3_K_S (Expect system memory usage)" -Color Red
    }
}
else {
    Write-Log "No NVIDIA GPU detected. Please choose based on your hardware." -Color Gray
}
Write-Log "-------------------------------------------------------------------------------"

# --- User Prompts ---
if ($DownloadAll) {
    $baseChoice = 'A'; $ggufChoice = 'F'; $upscalerChoice = 'A'
} else {
    $baseChoice = Read-UserChoice -Prompt "Do you want to download Z-IMAGE Turbo BF16 (Base Model)? " -Choices @("A) Yes (Best Quality)", "B) No") -ValidAnswers @("A", "B")
    $ggufChoice = Read-UserChoice -Prompt "Do you want to download Z-IMAGE Turbo GGUF models (Optimized)?" -Choices @("A) Q8_0 (High Quality)", "B) Q6_K", "C) Q5_K_S (Balanced)", "D) Q4_K_S (Fast)", "E) Q3_K_S (Low VRAM)", "F) All", "G) No") -ValidAnswers @("A", "B", "C", "D", "E", "F", "G")
    $upscalerChoice = Read-UserChoice -Prompt "Do you want to download RealESRGAN Upscalers? " -Choices @("A) Yes", "B) No") -ValidAnswers @("A", "B")
}

# --- Download Process ---
Write-Log "Starting Z-IMAGE Turbo model downloads..." -Color Cyan

$baseUrl = "https://huggingface.co/UmeAiRT/ComfyUI-Auto-Installer-Assets/resolve/main/models"
$esrganUrl = "https://huggingface.co/spaces/Marne/Real-ESRGAN/resolve/main"

$ZImgUnetDir = Join-Path $modelsPath "unet\Z-IMG"
$ZImgDiffDir = Join-Path $modelsPath "diffusion_models\Z-IMG"
$clipDir = Join-Path $modelsPath "clip"
$vaeDir = Join-Path $modelsPath "vae"
$upscaleDir = Join-Path $modelsPath "upscale_models"

New-Item -Path $ZImgUnetDir, $ZImgDiffDir, $clipDir, $vaeDir, $upscaleDir -ItemType Directory -Force | Out-Null

# --- Determine if we need support files (VAE) ---
$doDownload = ($baseChoice -eq 'A' -or $ggufChoice -ne 'G')

if ($doDownload) {
    Write-Log "Downloading common support files (VAE)..."
    Save-FileCollecting -Uri "$baseUrl/vae/ae.safetensors" -OutFile (Join-Path $vaeDir "ae.safetensors")
}

# --- Download BF16 Base Model ---
if ($baseChoice -eq 'A') {
    Write-Log "Downloading Z-IMAGE Turbo BF16 Base Model..."
    Save-FileCollecting -Uri "$baseUrl/diffusion_models/Z-IMG/z-image-turbo-bf16.safetensors" -OutFile (Join-Path $ZImgDiffDir "z-image-turbo-bf16.safetensors")
    Save-FileCollecting -Uri "$baseUrl/text_encoders/QWEN/qwen3-4b.safetensors" -OutFile (Join-Path $clipDir "qwen3-4b.safetensors")
}

# --- Download GGUF Models ---
if ($ggufChoice -ne 'G') {
    Write-Log "Downloading Z-IMAGE Turbo GGUF models..."
    
    # Option A: Q8 (High Quality) -> CLIP Q8
    if ($ggufChoice -in 'A', 'F') {
        Write-Log "Downloading Q8_0 Set (UNet + CLIP)..."
        Save-FileCollecting -Uri "$baseUrl/diffusion_models/Z-IMG/Z-Image-Turbo-Q8_0.gguf" -OutFile (Join-Path $ZImgUnetDir "Z-Image-Turbo-Q8_0.gguf")
        Save-FileCollecting -Uri "$baseUrl/text_encoders/QWEN/Qwen3-4B-UD-Q8_K_XL.gguf" -OutFile (Join-Path $clipDir "Qwen3-4B-UD-Q8_K_XL.gguf")
    }

    # Option B: Q6 (Good Quality) -> CLIP Q6
    if ($ggufChoice -in 'B', 'F') {
        Write-Log "Downloading Q6_K Set (UNet + CLIP)..."
        Save-FileCollecting -Uri "$baseUrl/diffusion_models/Z-IMG/Z-Image-Turbo-Q6_K.gguf" -OutFile (Join-Path $ZImgUnetDir "Z-Image-Turbo-Q6_K.gguf")
        Save-FileCollecting -Uri "$baseUrl/text_encoders/QWEN/Qwen3-4B-UD-Q6_K_XL.gguf" -OutFile (Join-Path $clipDir "Qwen3-4B-UD-Q6_K_XL.gguf")
    }

    # Option C: Q5 (Balanced) -> CLIP Q5
    if ($ggufChoice -in 'C', 'F') {
        Write-Log "Downloading Q5_K Set (UNet + CLIP)..."
        Save-FileCollecting -Uri "$baseUrl/diffusion_models/Z-IMG/Z-Image-Turbo-Q5_K_S.gguf" -OutFile (Join-Path $ZImgUnetDir "Z-Image-Turbo-Q5_K_S.gguf")
        Save-FileCollecting -Uri "$baseUrl/text_encoders/QWEN/Qwen3-4B-UD-Q5_K_XL.gguf" -OutFile (Join-Path $clipDir "Qwen3-4B-UD-Q5_K_XL.gguf")
    }

    # Option D: Q4 (Fast) -> CLIP Q4
    if ($ggufChoice -in 'D', 'F') {
        Write-Log "Downloading Q4_K Set (UNet + CLIP)..."
        Save-FileCollecting -Uri "$baseUrl/diffusion_models/Z-IMG/Z-Image-Turbo-Q4_K_S.gguf" -OutFile (Join-Path $ZImgUnetDir "Z-Image-Turbo-Q4_K_S.gguf")
        Save-FileCollecting -Uri "$baseUrl/text_encoders/QWEN/Qwen3-4B-UD-Q4_K_XL.gguf" -OutFile (Join-Path $clipDir "Qwen3-4B-UD-Q4_K_XL.gguf")
    }

    # Option E: Q3 (Low VRAM) -> CLIP Q3
    if ($ggufChoice -in 'E', 'F') {
        Write-Log "Downloading Q3_K Set (UNet + CLIP)..."
        Save-FileCollecting -Uri "$baseUrl/diffusion_models/Z-IMG/Z-Image-Turbo-Q3_K_S.gguf" -OutFile (Join-Path $ZImgUnetDir "Z-Image-Turbo-Q3_K_S.gguf")
        Save-FileCollecting -Uri "$baseUrl/text_encoders/QWEN/Qwen3-4B-UD-Q3_K_XL.gguf" -OutFile (Join-Path $clipDir "Qwen3-4B-UD-Q3_K_XL.gguf")
    }
}

# --- Download Upscalers ---
if ($upscalerChoice -eq 'A') {
    Write-Log "Downloading RealESRGAN Upscalers..."
    Save-FileCollecting -Uri "$esrganUrl/RealESRGAN_x4plus.pth" -OutFile (Join-Path $upscaleDir "RealESRGAN_x4plus.pth")
    Save-FileCollecting -Uri "$esrganUrl/RealESRGAN_x4plus_anime_6B.pth" -OutFile (Join-Path $upscaleDir "RealESRGAN_x4plus_anime_6B.pth")
}

Show-DownloadSummary
Write-Log "Z-IMAGE Turbo model downloads complete." -Color Green
if (-not $DownloadAll) { Read-Host "Press Enter to return to the main installer." }
