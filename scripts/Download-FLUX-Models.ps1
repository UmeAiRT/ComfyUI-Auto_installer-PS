<#
.SYNOPSIS
    Interactive downloader for FLUX models.
.DESCRIPTION
    Downloads FLUX base models, GGUF quantized models, ControlNets, LoRAs, and Upscalers.
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
$InstallPath = $InstallPath.Trim('"')
Import-Module (Join-Path $PSScriptRoot "UmeAiRTUtils.psm1") -Force

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

    if ($gpuInfo.VramGiB -ge 30) {
        Write-Log "Recommendation: fp16" -Color Cyan
    }
    elseif ($gpuInfo.VramGiB -ge 18) {
        Write-Log "Recommendation: fp8 or GGUF Q8" -Color Cyan
    }
    elseif ($gpuInfo.VramGiB -ge 16) {
        Write-Log "Recommendation: GGUF Q6" -Color Cyan
    }
    elseif ($gpuInfo.VramGiB -ge 14) {
        Write-Log "Recommendation: GGUF Q5" -Color Cyan
    }
    elseif ($gpuInfo.VramGiB -ge 12) {
        Write-Log "Recommendation: GGUF Q4" -Color Cyan
    }
    elseif ($gpuInfo.VramGiB -ge 8) {
        Write-Log "Recommendation: GGUF Q3" -Color Cyan
    }
    else {
        Write-Log "Recommendation: GGUF Q2" -Color Cyan
    }
}
else {
    Write-Log "No NVIDIA GPU detected. Please choose based on your hardware." -Color Gray
}
Write-Log "-------------------------------------------------------------------------------"

# --- User Prompts ---
$fluxChoice = Read-UserChoice -Prompt "Do you want to download FLUX base models?" -Choices @("A) fp16", "B) fp8", "C) All", "D) No") -ValidAnswers @("A", "B", "C", "D")
$ggufChoice = Read-UserChoice -Prompt "Do you want to download FLUX GGUF models?" -Choices @("A) Q8 (18GB VRAM)", "B) Q6 (14GB VRAM)", "C) Q5 (12GB VRAM)", "D) Q4 (10GB VRAM)", "E) Q3 (8GB VRAM)", "F) Q2 (6GB VRAM)", "G) All", "H) No") -ValidAnswers @("A", "B", "C", "D", "E", "F", "G", "H")
$nunchakuChoice = Read-UserChoice -Prompt "Do you want to download FLUX NUNCHAKU models?" -Choices @("A) Base", "B) Fill", "C) KONTEXT", "D) Krea", "E) All", "F) No") -ValidAnswers @("A", "B", "C", "D", "E", "F")
$schnellChoice = Read-UserChoice -Prompt "Do you want to download the FLUX SCHNELL model?" -Choices @("A) Yes", "B) No") -ValidAnswers @("A", "B")
$controlnetChoice = Read-UserChoice -Prompt "Do you want to download FLUX ControlNet models?" -Choices @("A) fp16", "B) fp8", "C) Q8", "D) Q5", "E) Q4", "F) All", "G) No") -ValidAnswers @("A", "B", "C", "D", "E", "F", "G")
$fillChoice = Read-UserChoice -Prompt "Do you want to download FLUX Fill models?" -Choices @("A) fp16", "B) fp8", "C) Q8", "D) Q6", "E) Q5", "F) Q4", "G) Q3", "H) All", "I) No") -ValidAnswers @("A", "B", "C", "D", "E", "F", "G", "H", "I")
$pulidChoice = Read-UserChoice -Prompt "Do you want to download FLUX PuLID and REDUX models?" -Choices @("A) Yes", "B) No") -ValidAnswers @("A", "B")
$upscaleChoice = Read-UserChoice -Prompt "Do you want to download Upscaler models ?" -Choices @("A) Yes", "B) No") -ValidAnswers @("A", "B")
$loraChoice = Read-UserChoice -Prompt "Do you want to download UmeAiRT LoRAs?" -Choices @("A) Yes", "B) No") -ValidAnswers @("A", "B")

# --- Download Process ---
Write-Log "Starting downloads based on your choices..." -Color Cyan

$baseUrl = "https://huggingface.co/UmeAiRT/ComfyUI-Auto-Installer-Assets/resolve/main/models"
$fluxDir = Join-Path $modelsPath "diffusion_models\FLUX"
$clipDir = Join-Path $modelsPath "clip"
$vaeDir = Join-Path $modelsPath "vae"
$unetFluxDir = Join-Path $modelsPath "unet\FLUX"
$controlnetDir = Join-Path $modelsPath "xlabs\controlnets"
$pulidDir = Join-Path $modelsPath "pulid"
$styleDir = Join-Path $modelsPath "style_models"
$loraDir = Join-Path $modelsPath "loras\FLUX"
$upscaleDir = Join-Path $modelsPath "upscale_models"

# Create directories
$requiredDirs = @($fluxDir, $clipDir, $vaeDir, $unetFluxDir, $controlnetDir, $pulidDir, $styleDir, $loraDir, $upscaleDir)
foreach ($dir in $requiredDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
}

$doDownload = ($fluxChoice -ne 'D' -or $ggufChoice -ne 'H' -or $nunchakuChoice -ne 'F' -or $schnellChoice -eq 'A' -or $controlnetChoice -ne 'G' -or $fillChoice -ne 'I')

if ($doDownload) {
    Write-Log "Downloading common support models (VAE, CLIP)..."
    Save-File -Uri "$baseUrl/vae/ae.safetensors" -OutFile (Join-Path $vaeDir "ae.safetensors")
    Save-File -Uri "$baseUrl/clip/clip_l.safetensors" -OutFile (Join-Path $clipDir "clip_l.safetensors")
}

# FLUX Base Models
if ($fluxChoice -in 'A', 'C') {
    Save-File -Uri "$baseUrl/diffusion_models/FLUX/flux1-dev-fp16.safetensors" -OutFile (Join-Path $fluxDir "flux1-dev-fp16.safetensors")
    Save-File -Uri "$baseUrl/clip/t5xxl_fp16.safetensors" -OutFile (Join-Path $clipDir "t5xxl_fp16.safetensors")
}
if ($fluxChoice -in 'B', 'C') {
    Save-File -Uri "$baseUrl/diffusion_models/FLUX/flux1-dev-fp8.safetensors" -OutFile (Join-Path $fluxDir "flux1-dev-fp8.safetensors")
    Save-File -Uri "$baseUrl/clip/t5xxl_fp8_e4m3fn.safetensors" -OutFile (Join-Path $clipDir "t5xxl_fp8_e4m3fn.safetensors")
}

# GGUF Models
if ($ggufChoice -in 'A', 'G') {
    Save-File -Uri "$baseUrl/clip/t5-v1_1-xxl-encoder-Q8_0.gguf" -OutFile (Join-Path $clipDir "t5-v1_1-xxl-encoder-Q8_0.gguf")
    Save-File -Uri "$baseUrl/unet/FLUX/flux1-dev-Q8_0.gguf" -OutFile (Join-Path $unetFluxDir "flux1-dev-Q8_0.gguf")
}
if ($ggufChoice -in 'B', 'G') {
    Save-File -Uri "$baseUrl/clip/t5-v1_1-xxl-encoder-Q6_K.gguf" -OutFile (Join-Path $clipDir "t5-v1_1-xxl-encoder-Q6_K.gguf")
    Save-File -Uri "$baseUrl/unet/FLUX/flux1-dev-Q6_K.gguf" -OutFile (Join-Path $unetFluxDir "flux1-dev-Q6_K.gguf")
}
if ($ggufChoice -in 'C', 'G') {
    Save-File -Uri "$baseUrl/clip/t5-v1_1-xxl-encoder-Q5_K_M.gguf" -OutFile (Join-Path $clipDir "t5-v1_1-xxl-encoder-Q5_K_M.gguf")
    Save-File -Uri "$baseUrl/unet/FLUX/flux1-dev-Q5_K_S.gguf" -OutFile (Join-Path $unetFluxDir "flux1-dev-Q5_K_S.gguf")
}
if ($ggufChoice -in 'D', 'G') {
    Save-File -Uri "$baseUrl/clip/t5-v1_1-xxl-encoder-Q4_K_S.gguf" -OutFile (Join-Path $clipDir "t5-v1_1-xxl-encoder-Q4_K_S.gguf")
    Save-File -Uri "$baseUrl/unet/FLUX/flux1-dev-Q4_K_S.gguf" -OutFile (Join-Path $unetFluxDir "flux1-dev-Q4_K_S.gguf")
}
if ($ggufChoice -in 'E', 'G') {
    Save-File -Uri "$baseUrl/clip/t5-v1_1-xxl-encoder-Q3_K_S.gguf" -OutFile (Join-Path $clipDir "t5-v1_1-xxl-encoder-Q3_K_S.gguf")
    Save-File -Uri "$baseUrl/unet/FLUX/flux1-dev-Q3_K_S.gguf" -OutFile (Join-Path $unetFluxDir "flux1-dev-Q3_K_S.gguf")
}
if ($ggufChoice -in 'F', 'G') {
    Save-File -Uri "$baseUrl/unet/FLUX/flux1-dev-Q2_K.gguf" -OutFile (Join-Path $unetFluxDir "flux1-dev-Q2_K.gguf")
}

# NUNCHAKU Model
if ($nunchakuChoice -in 'A', 'E') { Save-File -Uri "$baseUrl/diffusion_models/FLUX/svdq-int4_r32-flux.1-dev.safetensors" -OutFile (Join-Path $fluxDir "svdq-int4_r32-flux.1-dev.safetensors") }
if ($nunchakuChoice -in 'B', 'E') { Save-File -Uri "$baseUrl/diffusion_models/FLUX/svdq-int4_r32-flux.1-fill-dev.safetensors" -OutFile (Join-Path $fluxDir "svdq-int4_r32-flux.1-fill-dev.safetensors") }
if ($nunchakuChoice -in 'C', 'E') { Save-File -Uri "$baseUrl/diffusion_models/FLUX/svdq-int4_r32-flux.1-kontext-dev.safetensors" -OutFile (Join-Path $fluxDir "svdq-int4_r32-flux.1-kontext-dev.safetensors") }
if ($nunchakuChoice -in 'D', 'E') { Save-File -Uri "$baseUrl/diffusion_models/FLUX/svdq-int4_r32-flux.1-krea-dev.safetensors" -OutFile (Join-Path $fluxDir "svdq-int4_r32-flux.1-krea-dev.safetensors") }

if ($nunchakuChoice -ne 'F') { Save-File -Uri "$baseUrl/clip/umt5_xxl_fp8_e4m3fn_scaled.safetensors" -OutFile (Join-Path $clipDir "umt5_xxl_fp8_e4m3fn_scaled.safetensors") }

# Schnell Model
if ($schnellChoice -eq 'A') {
    Save-File -Uri "$baseUrl/diffusion_models/FLUX/flux1-schnell-fp8.safetensors" -OutFile (Join-Path $fluxDir "flux1-schnell-fp8.safetensors")
}

# ControlNet Models
if ($controlnetChoice -ne 'G') {
    if ($controlnetChoice -in 'A', 'B', 'F') { 
        Save-File -Uri "$baseUrl/xlabs/controlnets/flux-canny-controlnet-v3.safetensors" -OutFile (Join-Path $controlnetDir "flux-canny-controlnet-v3.safetensors")
        Save-File -Uri "$baseUrl/xlabs/controlnets/flux-depth-controlnet-v3.safetensors" -OutFile (Join-Path $controlnetDir "flux-depth-controlnet-v3.safetensors")
    }
    if ($controlnetChoice -in 'A', 'F') { Save-File -Uri "$baseUrl/diffusion_models/FLUX/flux1-canny-dev-fp16.safetensors" -OutFile (Join-Path $fluxDir "flux1-canny-dev-fp16.safetensors"); Save-File -Uri "$baseUrl/diffusion_models/FLUX/flux1-depth-dev-fp16.safetensors" -OutFile (Join-Path $fluxDir "flux1-depth-dev-fp16.safetensors") }
    if ($controlnetChoice -in 'B', 'F') { Save-File -Uri "$baseUrl/diffusion_models/FLUX/flux1-canny-dev-fp8.safetensors" -OutFile (Join-Path $fluxDir "flux1-canny-dev-fp8.safetensors"); Save-File -Uri "$baseUrl/diffusion_models/FLUX/flux1-depth-dev-fp8.safetensors" -OutFile (Join-Path $fluxDir "flux1-depth-dev-fp8.safetensors") }
    if ($controlnetChoice -in 'C', 'F') { Save-File -Uri "$baseUrl/unet/FLUX/flux1-canny-dev-fp16-Q8_0-GGUF.gguf" -OutFile (Join-Path $unetFluxDir "flux1-canny-dev-fp16-Q8_0-GGUF.gguf"); Save-File -Uri "$baseUrl/unet/FLUX/flux1-depth-dev-fp16-Q8_0-GGUF.gguf" -OutFile (Join-Path $unetFluxDir "flux1-depth-dev-fp16-Q8_0-GGUF.gguf") }
    if ($controlnetChoice -in 'D', 'F') { Save-File -Uri "$baseUrl/unet/FLUX/flux1-canny-dev-fp16-Q5_0-GGUF.gguf" -OutFile (Join-Path $unetFluxDir "flux1-canny-dev-fp16-Q5_0-GGUF.gguf"); Save-File -Uri "$baseUrl/unet/FLUX/flux1-depth-dev-fp16-Q5_0-GGUF.gguf" -OutFile (Join-Path $unetFluxDir "flux1-depth-dev-fp16-Q5_0-GGUF.gguf") }
    if ($controlnetChoice -in 'E', 'F') { Save-File -Uri "$baseUrl/unet/FLUX/flux1-canny-dev-fp16-Q4_0-GGUF.gguf" -OutFile (Join-Path $unetFluxDir "flux1-canny-dev-fp16-Q4_0-GGUF.gguf"); Save-File -Uri "$baseUrl/unet/FLUX/flux1-depth-dev-fp16-Q4_0-GGUF.gguf" -OutFile (Join-Path $unetFluxDir "flux1-depth-dev-fp16-Q4_0-GGUF.gguf") }
}

# Fill Models
if ($fillChoice -in 'A', 'H') { Save-File -Uri "$baseUrl/diffusion_models/FLUX/flux1-fill-dev-fp16.safetensors" -OutFile (Join-Path $fluxDir "flux1-fill-dev-fp16.safetensors") }
if ($fillChoice -in 'B', 'H') { Save-File -Uri "$baseUrl/diffusion_models/FLUX/flux1-fill-dev-fp8.safetensors" -OutFile (Join-Path $fluxDir "flux1-fill-dev-fp8.safetensors") }
if ($fillChoice -in 'C', 'H') { Save-File -Uri "$baseUrl/unet/FLUX/flux1-fill-dev-Q8_0.gguf" -OutFile (Join-Path $unetFluxDir "flux1-fill-dev-Q8_0.gguf") }
if ($fillChoice -in 'D', 'H') { Save-File -Uri "$baseUrl/unet/FLUX/flux1-fill-dev-Q6_K.gguf" -OutFile (Join-Path $unetFluxDir "flux1-fill-dev-Q6_K.gguf") }
if ($fillChoice -in 'E', 'H') { Save-File -Uri "$baseUrl/unet/FLUX/flux1-fill-dev-Q5_K_S.gguf" -OutFile (Join-Path $unetFluxDir "flux1-fill-dev-Q5_K_S.gguf") }
if ($fillChoice -in 'F', 'H') { Save-File -Uri "$baseUrl/unet/FLUX/flux1-fill-dev-Q4_K_S.gguf" -OutFile (Join-Path $unetFluxDir "flux1-fill-dev-Q4_K_S.gguf") }
if ($fillChoice -in 'G', 'H') { Save-File -Uri "$baseUrl/unet/FLUX/flux1-fill-dev-Q3_K_S.gguf" -OutFile (Join-Path $unetFluxDir "flux1-fill-dev-Q3_K_S.gguf") }

# PuLID Models
if ($pulidChoice -eq 'A') {
    Save-File -Uri "$baseUrl/pulid/pulid_flux_v0.9.0.safetensors" -OutFile (Join-Path $pulidDir "pulid_flux_v0.9.0.safetensors")
    Save-File -Uri "$baseUrl/style_models/flux1-redux-dev.safetensors" -OutFile (Join-Path $styleDir "flux1-redux-dev.safetensors")
}

# Upscaler Models
if ($upscaleChoice -eq 'A') {
    Save-File -Uri "$baseUrl/upscale_models/RealESRGAN_x4plus.pth" -OutFile (Join-Path $upscaleDir "RealESRGAN_x4plus.pth")
    Save-File -Uri "$baseUrl/upscale_models/RealESRGAN_x4plus_anime_6B.pth" -OutFile (Join-Path $upscaleDir "RealESRGAN_x4plus_anime_6B.pth")
    Save-File -Uri "$baseUrl/upscale_models/4x-AnimeSharp.pth" -OutFile (Join-Path $upscaleDir "4x-AnimeSharp.pth")
    Save-File -Uri "$baseUrl/upscale_models/4x-UltraSharp.pth" -OutFile (Join-Path $upscaleDir "4x-UltraSharp.pth")
    Save-File -Uri "$baseUrl/upscale_models/4x_NMKD-Siax_200k.pth" -OutFile (Join-Path $upscaleDir "4x_NMKD-Siax_200k.pth")
    Save-File -Uri "$baseUrl/upscale_models/RealESRGAN_x4.pth" -OutFile (Join-Path $upscaleDir "RealESRGAN_x4.pth")
}

# LoRA Models
if ($loraChoice -eq 'A') {
    Save-File -Uri "https://huggingface.co/UmeAiRT/FLUX.1-dev-LoRA-Ume_Sky/resolve/main/ume_sky_v2.safetensors" -OutFile (Join-Path $loraDir "ume_sky_v2.safetensors")
    Save-File -Uri "https://huggingface.co/UmeAiRT/FLUX.1-dev-LoRA-Modern_Pixel_art/resolve/main/ume_modern_pixelart.safetensors" -OutFile (Join-Path $loraDir "ume_modern_pixelart.safetensors")
    Save-File -Uri "https://huggingface.co/UmeAiRT/FLUX.1-dev-LoRA-Romanticism/resolve/main/ume_classic_Romanticism.safetensors" -OutFile (Join-Path $loraDir "ume_classic_Romanticism.safetensors")
    Save-File -Uri "https://huggingface.co/UmeAiRT/FLUX.1-dev-LoRA-Impressionism/resolve/main/ume_classic_impressionist.safetensors" -OutFile (Join-Path $loraDir "ume_classic_impressionist.safetensors")
}

Write-Log "FLUX model downloads complete." -Color Green
Read-Host "Press Enter to return to the main installer."
