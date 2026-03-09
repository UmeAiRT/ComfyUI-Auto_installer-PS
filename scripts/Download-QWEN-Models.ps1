<#
.SYNOPSIS
    Interactive downloader for QWEN models.
.DESCRIPTION
    Downloads QWEN base and Edit models, GGUF quantized models, and Lightning LoRAs for ComfyUI.
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

    if ($gpuInfo.VramGiB -ge 24) { Write-Log "Recommendation: bf16 or fp8" -Color Cyan }
    elseif ($gpuInfo.VramGiB -ge 16) { Write-Log "Recommendation: GGUF Q8_0" -Color Cyan }
    elseif ($gpuInfo.VramGiB -ge 12) { Write-Log "Recommendation: GGUF Q5_K_S" -Color Cyan }
    else { Write-Log "Recommendation: GGUF Q4_K_S" -Color Cyan }
}
else {
    Write-Log "No NVIDIA GPU detected. Please choose based on your hardware." -Color Gray
}
Write-Log "-------------------------------------------------------------------------------"

# --- User Prompts ---
$baseChoice = Read-UserChoice -Prompt "Do you want to download QWEN base models? " -Choices @("A) bf16", "B) fp8", "C) All", "D) No") -ValidAnswers @("A", "B", "C", "D")
$ggufChoice = Read-UserChoice -Prompt "Do you want to download QWEN GGUF models?" -Choices @("A) Q8_0", "B) Q5_K_S", "C) Q4_K_S", "D) All", "E) No") -ValidAnswers @("A", "B", "C", "D", "E")
$editChoice = Read-UserChoice -Prompt "Do you want to download QWEN EDIT models? " -Choices @("A) bf16", "B) fp8", "C) All", "D) No") -ValidAnswers @("A", "B", "C", "D")
$editggufChoice = Read-UserChoice -Prompt "Do you want to download QWEN EDIT GGUF models?" -Choices @("A) Q8_0", "B) Q5_K_S", "C) Q4_K_S", "D) All", "E) No") -ValidAnswers @("A", "B", "C", "D", "E")
$lightChoice = Read-UserChoice -Prompt "Do you want to download QWEN Lightning LoRA? " -Choices @("A) 8 Steps", "B) 4 Steps", "C) All", "D) No") -ValidAnswers @("A", "B", "C", "D")

# --- Download Process ---
Write-Log "Starting QWEN model downloads..." -Color Cyan

$baseUrl = "https://huggingface.co/UmeAiRT/ComfyUI-Auto_installer/resolve/main/models"
$QWENDiffDir = "$modelsPath/diffusion_models/QWEN"
$QWENUnetDir = "$modelsPath/unet/QWEN"
$QWENLoRADir = "$modelsPath/loras/QWEN"
$clipDir = "$modelsPath/clip"
$vaeDir = "$modelsPath/vae"

New-Item -Path $QWENDiffDir, $QWENUnetDir, $QWENLoRADir, $clipDir, $vaeDir -ItemType Directory -Force | Out-Null

$doDownload = ($baseChoice -ne 'D' -or $ggufChoice -ne 'E' -or $editChoice -ne 'D' -or $editggufChoice -ne 'E')

if ($doDownload) {
    Write-Log "Downloading QWEN common support files (VAE, CLIPs)..."
    Save-File -Uri "$baseUrl/vae/qwen_image_vae.safetensors" -OutFile "$vaeDir/qwen_image_vae.safetensors"
}

# Base Models
if ($baseChoice -ne 'D') {
    Write-Log "Downloading QWEN base model..."
    if ($baseChoice -in 'A', 'C') {
        Save-File -Uri "$baseUrl/diffusion_models/qwen_image_bf16.safetensors" -OutFile "$QWENUnetDir/qwen_image_bf16.safetensors"
        Save-File -Uri "$baseUrl/clip/qwen_2.5_vl_7b.safetensors" -OutFile "$clipDir/qwen_2.5_vl_7b.safetensors"
    }
    if ($baseChoice -in 'B', 'C') {
        Save-File -Uri "$baseUrl/diffusion_models/qwen_image_fp8_e4m3fn.safetensors" -OutFile "$QWENUnetDir/qwen_image_fp8_e4m3fn.safetensors"
        Save-File -Uri "$baseUrl/clip/qwen_2.5_vl_7b_fp8_scaled.safetensors" -OutFile "$clipDir/qwen_2.5_vl_7b_fp8_scaled.safetensors"
    }
}

# GGUF Models
if ($ggufChoice -ne 'E') {
    Write-Log "Downloading QWEN GGUF models..."
    if ($ggufChoice -in 'A', 'D') {
        Save-File -Uri "$baseUrl/unet/QWEN/Qwen_Image_Distill-Q8_0.gguf" -OutFile "$QWENUnetDir/Qwen_Image_Distill-Q8_0.gguf"
        Save-File -Uri "$baseUrl/clip/Qwen2.5-VL-7B-Instruct-UD-Q4_K_S.gguf" -OutFile "$clipDir/Qwen2.5-VL-7B-Instruct-UD-Q4_K_S.gguf"
    }
    if ($ggufChoice -in 'B', 'D') {
        Save-File -Uri "$baseUrl/unet/QWEN/Qwen_Image_Distill-Q5_K_S.gguf" -OutFile "$QWENUnetDir/Qwen_Image_Distill-Q5_K_S.gguf"
        Save-File -Uri "$baseUrl/clip/Qwen2.5-VL-7B-Instruct-UD-Q4_K_S.gguf" -OutFile "$clipDir/Qwen2.5-VL-7B-Instruct-UD-Q4_K_S.gguf"
    }
    if ($ggufChoice -in 'C', 'D') {
        Save-File -Uri "$baseUrl/unet/QWEN/Qwen_Image_Distill-Q4_K_S.gguf" -OutFile "$QWENUnetDir/Qwen_Image_Distill-Q4_K_S.gguf"
        Save-File -Uri "$baseUrl/clip/Qwen2.5-VL-7B-Instruct-UD-Q4_K_S.gguf" -OutFile "$clipDir/Qwen2.5-VL-7B-Instruct-UD-Q4_K_S.gguf"
    }
}

# Edit Models
if ($editChoice -ne 'D') {
    Write-Log "Downloading QWEN base model..."
    if ($editChoice -in 'A', 'C') {
        Save-File -Uri "$baseUrl/diffusion_models/qwen_image_edit_bf16.safetensors" -OutFile "$QWENUnetDir/qwen_image_edit_bf16.safetensors"
        Save-File -Uri "$baseUrl/clip/qwen_2.5_vl_7b.safetensors" -OutFile "$clipDir/qwen_2.5_vl_7b.safetensors"
    }
    if ($editChoice -in 'B', 'C') {
        Save-File -Uri "$baseUrl/diffusion_models/qwen_image_edit_fp8_e4m3fn.safetensors" -OutFile "$QWENUnetDir/qwen_image_edit_fp8_e4m3fn.safetensors"
        Save-File -Uri "$baseUrl/clip/qwen_2.5_vl_7b_fp8_scaled.safetensors" -OutFile "$clipDir/qwen_2.5_vl_7b_fp8_scaled.safetensors"
    }
}

# Edit GGUF
if ($editggufChoice -ne 'E') {
    Write-Log "Downloading QWEN GGUF models..."
    if ($editggufChoice -in 'A', 'D') {
        Save-File -Uri "$baseUrl/unet/QWEN/Qwen_Image_Edit-Q8_0.gguf" -OutFile "$QWENUnetDir/Qwen_Image_Edit-Q8_0.gguf"
        Save-File -Uri "$baseUrl/clip/Qwen2.5-VL-7B-Instruct-UD-Q4_K_S.gguf" -OutFile "$clipDir/Qwen2.5-VL-7B-Instruct-UD-Q4_K_S.gguf"
    }
    if ($editggufChoice -in 'B', 'D') {
        Save-File -Uri "$baseUrl/unet/QWEN/Qwen_Image_Edit-Q5_K_S.gguf" -OutFile "$QWENUnetDir/Qwen_Image_Edit-Q5_K_S.gguf"
        Save-File -Uri "$baseUrl/clip/Qwen2.5-VL-7B-Instruct-UD-Q4_K_S.gguf" -OutFile "$clipDir/Qwen2.5-VL-7B-Instruct-UD-Q4_K_S.gguf"
    }
    if ($editggufChoice -in 'C', 'D') {
        Save-File -Uri "$baseUrl/unet/QWEN/Qwen_Image_Edit-Q4_K_S.gguf" -OutFile "$QWENUnetDir/Qwen_Image_Edit-Q4_K_S.gguf"
        Save-File -Uri "$baseUrl/clip/Qwen2.5-VL-7B-Instruct-UD-Q4_K_S.gguf" -OutFile "$clipDir/Qwen2.5-VL-7B-Instruct-UD-Q4_K_S.gguf"
    }
}

# Lightning LoRAs
if ($lightChoice -ne 'D') {
    Write-Log "Downloading QWEN Lightning LoRA..."
    if ($lightChoice -in 'A', 'C') {
        Save-File -Uri "$baseUrl/loras/QWEN/Qwen-Image-Lightning-8steps-V2.0.safetensors" -OutFile "$QWENLoRADir/Qwen-Image-Lightning-8steps-V2.0.safetensors"
        Save-File -Uri "$baseUrl/loras/QWEN/Qwen-Image-Edit-Lightning-8steps-V1.0.safetensors" -OutFile "$QWENLoRADir/Qwen-Image-Edit-Lightning-8steps-V1.0.safetensors"
    }
    if ($lightChoice -in 'B', 'C') {
        Save-File -Uri "$baseUrl/loras/QWEN/Qwen-Image-Lightning-4steps-V2.0.safetensors" -OutFile "$QWENLoRADir/Qwen-Image-Lightning-4steps-V2.0.safetensors"
        Save-File -Uri "$baseUrl/loras/QWEN/Qwen-Image-Edit-Lightning-4steps-V1.0.safetensors" -OutFile "$QWENLoRADir/Qwen-Image-Edit-Lightning-4steps-V1.0.safetensors"
    }
}

Write-Log "QWEN model downloads complete." -Color Green
Read-Host "Press Enter to return to the main installer."
