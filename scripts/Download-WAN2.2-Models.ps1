<#
.SYNOPSIS
    Interactive downloader for WAN 2.2 models.
.DESCRIPTION
    Downloads WAN 2.2 Text-to-Video and Image-to-Video models (fp16, fp8, GGUF),
    Lightning LoRA, Fun Control, Fun Inpaint, and Fun Camera Control models.
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

    if ($gpuInfo.VramGiB -ge 40) { Write-Log "Recommendation: fp16" -Color Cyan }
    elseif ($gpuInfo.VramGiB -ge 23) { Write-Log "Recommendation: fp8 or GGUF Q8" -Color Cyan }
    elseif ($gpuInfo.VramGiB -ge 16) { Write-Log "Recommendation: Q5_K_M" -Color Cyan }
    else { Write-Log "Recommendation: Q3_K_S" -Color Cyan }
}
else {
    Write-Log "No NVIDIA GPU detected. Please choose based on your hardware." -Color Gray
}
Write-Log "-------------------------------------------------------------------------------"

# --- User Prompts ---
$T2VChoice = Read-UserChoice -Prompt "Do you want to download WAN text-to-video models?" -Choices @("A) fp16", "B) fp8", "C) Q8_0", "D) Q5_K_M", "E) Q3_K_S", "F) All", "G) No") -ValidAnswers @("A", "B", "C", "D", "E", "F", "G")
$I2VChoice = Read-UserChoice -Prompt "Do you want to download WAN image-to-video models?" -Choices @("A) fp16", "B) fp8", "C) Q8_0", "D) Q5_K_M", "E) Q3_K_S", "F) All", "G) No") -ValidAnswers @("A", "B", "C", "D", "E", "F", "G")
$LoRAChoice = Read-UserChoice -Prompt "Do you want to download Lightning LoRA ?" -Choices @("A) Yes", "B) No") -ValidAnswers @("A", "B")
$funcontrolChoice = Read-UserChoice -Prompt "Do you want to download WAN FUN CONTROL models?" -Choices @("A) fp16", "B) fp8", "C) Q8_0", "D) Q5_K_M", "E) Q3_K_S", "F) All", "G) No") -ValidAnswers @("A", "B", "C", "D", "E", "F", "G")
$funinpaintChoice = Read-UserChoice -Prompt "Do you want to download WAN FUN INPAINT models?" -Choices @("A) fp16", "B) fp8", "C) Q8_0", "D) Q5_K_M", "E) Q3_K_S", "F) All", "G) No") -ValidAnswers @("A", "B", "C", "D", "E", "F", "G")
$funcameraChoice = Read-UserChoice -Prompt "Do you want to download WAN FUN CAMERA CONTROL models?" -Choices @("A) fp16", "B) fp8", "C) Q8_0", "D) Q5_K_M", "E) Q3_K_S", "F) All", "G) No") -ValidAnswers @("A", "B", "C", "D", "E", "F", "G")

# --- Download Process ---
Write-Log "Starting WAN 2.2 model downloads..." -Color Cyan

$baseUrl = "https://huggingface.co/UmeAiRT/ComfyUI-Auto_installer/resolve/main/models"
$wanDiffDir = "$modelsPath/diffusion_models/WAN"
$wanUnetDir = "$modelsPath/unet/WAN"
$clipDir = "$modelsPath/clip"
$vaeDir = "$modelsPath/vae"
$loraDir = "$modelsPath/loras/WAN"

New-Item -Path $wanDiffDir, $wanUnetDir, $clipDir, $vaeDir, $loraDir -ItemType Directory -Force | Out-Null

$doDownload = ($T2VChoice -ne 'G' -or $I2VChoice -ne 'G' -or $LoRAChoice -eq 'A' -or $funcontrolChoice -ne 'G' -or $funinpaintChoice -ne 'G' -or $funcameraChoice -ne 'G')

if ($doDownload) {
    Write-Log "Downloading common support files..."
    Save-File -Uri "$baseUrl/vae/wan_2.1_vae.safetensors" -OutFile "$vaeDir/wan_2.1_vae.safetensors"
    Save-File -Uri "$baseUrl/clip/umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors" -OutFile "$clipDir/umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors"
    Save-File -Uri "$baseUrl/clip/open-clip-xlm-roberta-large-vit-huge-14.safetensors" -OutFile "$clipDir/open-clip-xlm-roberta-large-vit-huge-14.safetensors"
}

# T2V Models
if ($T2VChoice -ne 'G') {
    Write-Log "Downloading T2V Models..."
    if ($T2VChoice -in 'A', 'F') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.2_t2v_14B_bf16.safetensors" -OutFile "$wanDiffDir/wan2.2_t2v_14B_bf16.safetensors"
    }
    if ($T2VChoice -in 'B', 'F') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.2_t2v_14B_fp8_e4m3fn.safetensors" -OutFile "$wanDiffDir/wan2.2_t2v_14B_fp8_e4m3fn.safetensors"
    }
    if ($T2VChoice -in 'C', 'F') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.2-t2v-14b-Q8_0.gguf" -OutFile "$wanUnetDir/wan2.2-t2v-14b-Q8_0.gguf"
    }
    if ($T2VChoice -in 'D', 'F') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.2-t2v-14b-Q5_K_M.gguf" -OutFile "$wanUnetDir/wan2.2-t2v-14b-Q5_K_M.gguf"
    }
    if ($T2VChoice -in 'E', 'F') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.2-t2v-14b-Q3_K_S.gguf" -OutFile "$wanUnetDir/wan2.2-t2v-14b-Q3_K_S.gguf"
    }
}

# I2V Models
if ($I2VChoice -ne 'G') {
    Write-Log "Downloading I2V Models..."
    if ($I2VChoice -in 'A', 'F') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.2_i2v_14B_bf16.safetensors" -OutFile "$wanDiffDir/wan2.2_i2v_14B_bf16.safetensors"
    }
    if ($I2VChoice -in 'B', 'F') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.2_i2v_14B_fp8_e4m3fn.safetensors" -OutFile "$wanDiffDir/wan2.2_i2v_14B_fp8_e4m3fn.safetensors"
    }
    if ($I2VChoice -in 'C', 'F') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.2-i2v-14b-Q8_0.gguf" -OutFile "$wanUnetDir/wan2.2-i2v-14b-Q8_0.gguf"
    }
    if ($I2VChoice -in 'D', 'F') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.2-i2v-14b-Q5_K_M.gguf" -OutFile "$wanUnetDir/wan2.2-i2v-14b-Q5_K_M.gguf"
    }
    if ($I2VChoice -in 'E', 'F') {
        Save-File -Uri "$baseUrl/unet/WAN/wan2.2-i2v-14b-Q3_K_S.gguf" -OutFile "$wanUnetDir/wan2.2-i2v-14b-Q3_K_S.gguf"
    }
}

# LoRA
if ($LoRAChoice -eq 'A') {
    Write-Log "Downloading LoRA..."
    Save-File -Uri "$baseUrl/loras/WAN/Wan2.2-14B-Lightning.safetensors" -OutFile "$loraDir/Wan2.2-14B-Lightning.safetensors"
}

# Fun Control
if ($funcontrolChoice -ne 'G') {
    Write-Log "Downloading FUN CONTROL Models..."
    if ($funcontrolChoice -in 'A', 'F') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.2_fun_control_14B_bf16.safetensors" -OutFile "$wanDiffDir/wan2.2_fun_control_14B_bf16.safetensors"
    }
    if ($funcontrolChoice -in 'B', 'F') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.2_fun_control_14B_fp8_scaled.safetensors" -OutFile "$wanDiffDir/wan2.2_fun_control_14B_fp8_scaled.safetensors"
    }
    if ($funcontrolChoice -in 'C', 'F') {
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.2-Fun-A14B-Control-Q8_0.gguf" -OutFile "$wanUnetDir/Wan2.2-Fun-A14B-Control-Q8_0.gguf"
    }
    if ($funcontrolChoice -in 'D', 'F') {
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.2-Fun-A14B-Control-Q5_K_S.gguf" -OutFile "$wanUnetDir/Wan2.2-Fun-A14B-Control-Q5_K_S.gguf"
    }
    if ($funcontrolChoice -in 'E', 'F') {
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.2-Fun-A14B-Control-Q3_K_S.gguf" -OutFile "$wanUnetDir/Wan2.2-Fun-A14B-Control-Q3_K_S.gguf"
    }
}

# Fun Inpaint
if ($funinpaintChoice -ne 'G') {
    Write-Log "Downloading FUN INPAINT Models..."
    if ($funinpaintChoice -in 'A', 'F') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.2_fun_inpainting_low_noise_14B_bf16.safetensors" -OutFile "$wanDiffDir/wan2.2_fun_inpainting_low_noise_14B_bf16.safetensors"
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.2_fun_inpainting_high_noise_14B_bf16.safetensors" -OutFile "$wanDiffDir/wan2.2_fun_inpainting_high_noise_14B_bf16.safetensors"
    }
    if ($funinpaintChoice -in 'B', 'F') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.2_fun_inpainting_low_noise_14B_fp8_scaled.safetensors" -OutFile "$wanDiffDir/wan2.2_fun_inpainting_low_noise_14B_fp8_scaled.safetensors"
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.2_fun_inpainting_high_noise_14B_fp8_scaled.safetensors" -OutFile "$wanDiffDir/wan2.2_fun_inpainting_high_noise_14B_fp8_scaled.safetensors"
    }
    if ($funinpaintChoice -in 'C', 'F') {
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.2-Fun-A14B-InP_LowNoise-Q8_0.gguf" -OutFile "$wanUnetDir/Wan2.2-Fun-A14B-InP_LowNoise-Q8_0.gguf"
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.2-Fun-A14B-InP_HighNoise-Q8_0.gguf" -OutFile "$wanUnetDir/Wan2.2-Fun-A14B-InP_HighNoise-Q8_0.gguf"
    }
    if ($funinpaintChoice -in 'D', 'F') {
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.2-Fun-A14B-InP_LowNoise-Q5_K_S.gguf" -OutFile "$wanUnetDir/Wan2.2-Fun-A14B-InP_LowNoise-Q5_K_S.gguf"
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.2-Fun-A14B-InP_HighNoise-Q5_K_S.gguf" -OutFile "$wanUnetDir/Wan2.2-Fun-A14B-InP_HighNoise-Q5_K_S.gguf"
    }
    if ($funinpaintChoice -in 'E', 'F') {
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.2-Fun-A14B-InP_LowNoise-Q3_K_S.gguf" -OutFile "$wanUnetDir/Wan2.2-Fun-A14B-InP_LowNoise-Q3_K_S.gguf"
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.2-Fun-A14B-InP_HighNoise-Q3_K_S.gguf" -OutFile "$wanUnetDir/Wan2.2-Fun-A14B-InP_HighNoise-Q3_K_S.gguf"
    }
}

# Fun Camera
if ($funcameraChoice -ne 'G') {
    Write-Log "Downloading FUN CAMERA CONTROL Models..."
    if ($funcameraChoice -in 'A', 'F') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.2_fun_camera_high_noise_14B_bf16.safetensors" -OutFile "$wanDiffDir/wan2.2_fun_camera_high_noise_14B_bf16.safetensors"
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.2_fun_camera_low_noise_14B_bf16.safetensors" -OutFile "$wanDiffDir/wan2.2_fun_camera_low_noise_14B_bf16.safetensors"
    }
    if ($funcameraChoice -in 'B', 'F') {
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.2_fun_camera_high_noise_14B_fp8_scaled.safetensors" -OutFile "$wanDiffDir/wan2.2_fun_camera_high_noise_14B_fp8_scaled.safetensors"
        Save-File -Uri "$baseUrl/diffusion_models/WAN/wan2.2_fun_camera_low_noise_14B_fp8_scaled.safetensors" -OutFile "$wanDiffDir/wan2.2_fun_camera_low_noise_14B_fp8_scaled.safetensors"
    }
    if ($funcameraChoice -in 'C', 'F') {
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.2-Fun-A14B-Control-Camera-LowNoise-Q8_0.gguf" -OutFile "$wanUnetDir/Wan2.2-Fun-A14B-Control-Camera-LowNoise-Q8_0.gguf"
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.2-Fun-A14B-Control-Camera-HighNoise-Q8_0.gguf" -OutFile "$wanUnetDir/Wan2.2-Fun-A14B-Control-Camera-HighNoise-Q8_0.gguf"
    }
    if ($funcameraChoice -in 'D', 'F') {
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.2-Fun-A14B-Control-Camera-HighNoise-Q5_K_S.gguf" -OutFile "$wanUnetDir/Wan2.2-Fun-A14B-Control-Camera-HighNoise-Q5_K_S.gguf"
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.2-Fun-A14B-Control-Camera-LowNoise-Q5_K_S.gguf" -OutFile "$wanUnetDir/Wan2.2-Fun-A14B-Control-Camera-LowNoise-Q5_K_S.gguf"
    }
    if ($funcameraChoice -in 'E', 'F') {
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.2-Fun-A14B-Control-Camera-HighNoise-Q3_K_S.gguf" -OutFile "$wanUnetDir/Wan2.2-Fun-A14B-Control-Camera-HighNoise-Q3_K_S.gguf"
        Save-File -Uri "$baseUrl/unet/WAN/Wan2.2-Fun-A14B-Control-Camera-LowNoise-Q3_K_S.gguf" -OutFile "$wanUnetDir/Wan2.2-Fun-A14B-Control-Camera-LowNoise-Q3_K_S.gguf"
    }
}

Write-Log "WAN2.2 model downloads complete." -Color Green
Read-Host "Press Enter to return to the main installer."
