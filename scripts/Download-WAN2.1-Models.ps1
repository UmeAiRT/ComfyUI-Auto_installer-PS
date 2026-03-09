<#
.SYNOPSIS
    Interactive downloader for WAN 2.1 models.
.DESCRIPTION
    Downloads WAN 2.1 base models, GGUF quantized models (T2V, I2V 480p, I2V 720p),
    ControlNets, and VACE models for ComfyUI.
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

    if ($gpuInfo.VramGiB -ge 24) { Write-Log "Recommendation: bf16/fp16 or GGUF Q8_0." -Color Cyan }
    elseif ($gpuInfo.VramGiB -ge 16) { Write-Log "Recommendation: fp8 or GGUF Q5_K_M." -Color Cyan }
    else { Write-Log "Recommendation: GGUF Q3_K_S." -Color Cyan }
}
else {
    Write-Log "No NVIDIA GPU detected. Please choose based on your hardware." -Color Gray
}
Write-Log "-------------------------------------------------------------------------------"

# --- User Prompts ---
$baseChoice = Read-UserChoice -Prompt "Do you want to download WAN base models?" -Choices @("A) bf16", "B) fp16", "C) fp8", "D) All", "E) No") -ValidAnswers @("A", "B", "C", "D", "E")
$ggufT2VChoice = Read-UserChoice -Prompt "Do you want to download WAN text-to-video GGUF models?" -Choices @("A) Q8_0", "B) Q5_K_M", "C) Q3_K_S", "D) All", "E) No") -ValidAnswers @("A", "B", "C", "D", "E")
$gguf480Choice = Read-UserChoice -Prompt "Do you want to download WAN image-to-video 480p GGUF models?" -Choices @("A) Q8_0", "B) Q5_K_M", "C) Q3_K_S", "D) All", "E) No") -ValidAnswers @("A", "B", "C", "D", "E")
$gguf720Choice = Read-UserChoice -Prompt "Do you want to download WAN image-to-video 720p GGUF models?" -Choices @("A) Q8_0", "B) Q5_K_M", "C) Q3_K_S", "D) All", "E) No") -ValidAnswers @("A", "B", "C", "D", "E")
$controlChoice = Read-UserChoice -Prompt "Do you want to download WAN FUN CONTROL base models?" -Choices @("A) bf16", "B) fp8", "C) All", "D) No") -ValidAnswers @("A", "B", "C", "D")
$controlGgufChoice = Read-UserChoice -Prompt "Do you want to download WAN FUN CONTROL GGUF models?" -Choices @("A) Q8_0", "B) Q5_K_M", "C) Q3_K_S", "D) All", "E) No") -ValidAnswers @("A", "B", "C", "D", "E")
$vaceChoice = Read-UserChoice -Prompt "Do you want to download WAN VACE base models?" -Choices @("A) fp16", "B) fp8", "C) All", "D) No") -ValidAnswers @("A", "B", "C", "D")
$vaceGgufChoice = Read-UserChoice -Prompt "Do you want to download WAN VACE GGUF models?" -Choices @("A) Q8_0", "B) Q5_K_M", "C) Q4_K_S", "D) All", "E) No") -ValidAnswers @("A", "B", "C", "D", "E")

# --- Download Process ---
Write-Log "Starting WAN model downloads..." -Color Cyan

$baseUrl = "https://huggingface.co/UmeAiRT/ComfyUI-Auto_installer/resolve/main/models"
$wanDiffDir = "$modelsPath/diffusion_models/WAN"
$wanUnetDir = "$modelsPath/unet/WAN"
$clipDir = "$modelsPath/clip"
$vaeDir = "$modelsPath/vae"
$visionDir = "$modelsPath/clip_vision"

New-Item -Path $wanDiffDir, $wanUnetDir, $clipDir, $vaeDir, $visionDir -ItemType Directory -Force | Out-Null

$doDownload = ($baseChoice -ne 'E' -or $ggufT2VChoice -ne 'E' -or $gguf480Choice -ne 'E' -or $gguf720Choice -ne 'E' -or $controlChoice -ne 'D' -or $controlGgufChoice -ne 'E' -or $vaceChoice -ne 'D' -or $vaceGgufChoice -ne 'E')

if ($doDownload) {
    Write-Log "Downloading common support files..."
    Save-File -Uri "$baseUrl/vae/wan_2.1_vae.safetensors" -OutFile "$vaeDir/wan_2.1_vae.safetensors"
    Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors" -OutFile "$clipDir/umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors"
    Save-File -Uri "$baseUrl/clip_vision/clip_vision_h.safetensors" -OutFile "$visionDir/clip_vision_h.safetensors"
}

# Base Models
if ($baseChoice -ne 'E') {
    Write-Log "Downloading Base Models..."
    if ($baseChoice -in 'A', 'D') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.1_t2v_14B_bf16.safetensors" -OutFile "$wanDiffDir/wan2.1_t2v_14B_bf16.safetensors"
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.1_i2v_720p_14B_bf16.safetensors" -OutFile "$wanDiffDir/wan2.1_i2v_720p_14B_bf16.safetensors"
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.1_i2v_480p_14B_bf16.safetensors" -OutFile "$wanDiffDir/wan2.1_i2v_480p_14B_bf16.safetensors"
    }
    if ($baseChoice -in 'B', 'D') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.1_t2v_14B_fp16.safetensors" -OutFile "$wanDiffDir/wan2.1_t2v_14B_fp16.safetensors"
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.1_i2v_720p_14B_fp16.safetensors" -OutFile "$wanDiffDir/wan2.1_i2v_720p_14B_fp16.safetensors"
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.1_i2v_480p_14B_fp16.safetensors" -OutFile "$wanDiffDir/wan2.1_i2v_480p_14B_fp16.safetensors"
    }
    if ($baseChoice -in 'C', 'D') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.1_t2v_14B_fp8_e4m3fn.safetensors" -OutFile "$wanDiffDir/wan2.1_t2v_14B_fp8_e4m3fn.safetensors"
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.1_i2v_720p_14B_fp8_e4m3fn.safetensors" -OutFile "$wanDiffDir/wan2.1_i2v_720p_14B_fp8_e4m3fn.safetensors"
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.1_i2v_480p_14B_fp8_e4m3fn.safetensors" -OutFile "$wanDiffDir/wan2.1_i2v_480p_14B_fp8_e4m3fn.safetensors"
    }
}
# GGUF T2V
if ($ggufT2VChoice -ne 'E') {
    Write-Log "Downloading T2V GGUF Models..."
    if ($ggufT2VChoice -in 'A', 'D') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.1-t2v-14b-Q8_0.gguf" -OutFile "$wanUnetDir/wan2.1-t2v-14b-Q8_0.gguf"
        Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-Q8_0.gguf" -OutFile "$clipDir/umt5-xxl-encoder-Q8_0.gguf"
    }
    if ($ggufT2VChoice -in 'B', 'D') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.1-t2v-14b-Q5_K_M.gguf" -OutFile "$wanUnetDir/wan2.1-t2v-14b-Q5_K_M.gguf"
        Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-Q5_K_M.gguf" -OutFile "$clipDir/umt5-xxl-encoder-Q5_K_M.gguf"
    }
    if ($ggufT2VChoice -in 'C', 'D') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.1-t2v-14b-Q3_K_S.gguf" -OutFile "$wanUnetDir/wan2.1-t2v-14b-Q3_K_S.gguf"
        Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-Q3_K_S.gguf" -OutFile "$clipDir/umt5-xxl-encoder-Q3_K_S.gguf"
    }
}
# GGUF I2V 480p
if ($gguf480Choice -ne 'E') {
    Write-Log "Downloading I2V 480p GGUF Models..."
    if ($gguf480Choice -in 'A', 'D') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.1-i2v-14b-480p-Q8_0.gguf" -OutFile "$wanUnetDir/wan2.1-i2v-14b-480p-Q8_0.gguf"
        Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-Q8_0.gguf" -OutFile "$clipDir/umt5-xxl-encoder-Q8_0.gguf"
    }
    if ($gguf480Choice -in 'B', 'D') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.1-i2v-14b-480p-Q5_K_M.gguf" -OutFile "$wanUnetDir/wan2.1-i2v-14b-480p-Q5_K_M.gguf"
        Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-Q5_K_M.gguf" -OutFile "$clipDir/umt5-xxl-encoder-Q5_K_M.gguf"
    }
    if ($gguf480Choice -in 'C', 'D') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.1-i2v-14b-480p-Q3_K_S.gguf" -OutFile "$wanUnetDir/wan2.1-i2v-14b-480p-Q3_K_S.gguf"
        Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-Q3_K_S.gguf" -OutFile "$clipDir/umt5-xxl-encoder-Q3_K_S.gguf"
    }
}
# GGUF I2V 720p
if ($gguf720Choice -ne 'E') {
    Write-Log "Downloading I2V 720p GGUF Models..."
    if ($gguf720Choice -in 'A', 'D') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.1-i2v-14b-720p-Q8_0.gguf" -OutFile "$wanUnetDir/wan2.1-i2v-14b-720p-Q8_0.gguf"
        Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-Q8_0.gguf" -OutFile "$clipDir/umt5-xxl-encoder-Q8_0.gguf"
    }
    if ($gguf720Choice -in 'B', 'D') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.1-i2v-14b-720p-Q5_K_M.gguf" -OutFile "$wanUnetDir/wan2.1-i2v-14b-720p-Q5_K_M.gguf"
        Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-Q5_K_M.gguf" -OutFile "$clipDir/umt5-xxl-encoder-Q5_K_M.gguf"
    }
    if ($gguf720Choice -in 'C', 'D') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.1-i2v-14b-720p-Q3_K_S.gguf" -OutFile "$wanUnetDir/wan2.1-i2v-14b-720p-Q3_K_S.gguf"
        Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-Q3_K_S.gguf" -OutFile "$clipDir/umt5-xxl-encoder-Q3_K_S.gguf"
    }
}
# ControlNet Models
if ($controlChoice -ne 'D') {
    Write-Log "Downloading ControlNet Models..."
    if ($controlChoice -in 'A', 'C') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.1-fun-14B-control.safetensors" -OutFile "$wanDiffDir/wan2.1-fun-14B-control.safetensors"
    }
    if ($controlChoice -in 'B', 'C') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/Wan2.1-Fun-V1_1-InP-14B_fp8_e4m3fn.safetensors" -OutFile "$wanDiffDir/Wan2.1-Fun-V1_1-InP-14B_fp8_e4m3fn.safetensors"
    }
}
# ControlNet GGUF
if ($controlGgufChoice -ne 'E') {
    Write-Log "Downloading ControlNet GGUF Models..."
    if ($controlGgufChoice -in 'A', 'D') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.1-fun-14b-control-Q8_0.gguf" -OutFile "$wanUnetDir/wan2.1-fun-14b-control-Q8_0.gguf"
        Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-Q8_0.gguf" -OutFile "$clipDir/umt5-xxl-encoder-Q8_0.gguf"
    }
    if ($controlGgufChoice -in 'B', 'D') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.1-fun-14b-control-Q5_K_M.gguf" -OutFile "$wanUnetDir/wan2.1-fun-14b-control-Q5_K_M.gguf"
        Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-Q5_K_M.gguf" -OutFile "$clipDir/umt5-xxl-encoder-Q5_K_M.gguf"
    }
    if ($controlGgufChoice -in 'C', 'D') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.1-fun-14b-control-Q3_K_S.gguf" -OutFile "$wanUnetDir/wan2.1-fun-14b-control-Q3_K_S.gguf"
        Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-Q3_K_S.gguf" -OutFile "$clipDir/umt5-xxl-encoder-Q3_K_S.gguf"
    }
}
# VACE Models
if ($vaceChoice -ne 'D') {
    Write-Log "Downloading VACE Models..."
    if ($vaceChoice -in 'A', 'C') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.1_vace_14B_fp16.safetensors" -OutFile "$wanDiffDir/wan2.1_vace_14B_fp16.safetensors"
    }
    if ($vaceChoice -in 'B', 'C') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.1_vace_14B_fp8_e4m3fn.safetensors" -OutFile "$wanDiffDir/wan2.1_vace_14B_fp8_e4m3fn.safetensors"
    }
}
# VACE GGUF
if ($vaceGgufChoice -ne 'E') {
    Write-Log "Downloading VACE GGUF Models..."
    if ($vaceGgufChoice -in 'A', 'D') {
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.1-VACE-14B-Q8_0.gguf" -OutFile "$wanUnetDir/Wan2.1-VACE-14B-Q8_0.gguf"
        Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-Q8_0.gguf" -OutFile "$clipDir/umt5-xxl-encoder-Q8_0.gguf"
    }
    if ($vaceGgufChoice -in 'B', 'D') {
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.1-VACE-14B-Q5_K_S.gguf" -OutFile "$wanUnetDir/Wan2.1-VACE-14B-Q5_K_S.gguf"
        Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-Q5_K_M.gguf" -OutFile "$clipDir/umt5-xxl-encoder-Q5_K_M.gguf"
    }
    if ($vaceGgufChoice -in 'C', 'D') {
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.1-VACE-14B-Q4_K_S.gguf" -OutFile "$wanUnetDir/Wan2.1-VACE-14B-Q4_K_S.gguf"
        Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-Q3_K_S.gguf" -OutFile "$clipDir/umt5-xxl-encoder-Q3_K_S.gguf"
    }
}

Write-Log "WAN model downloads complete." -Color Green
Read-Host "Press Enter to return to the main installer."
