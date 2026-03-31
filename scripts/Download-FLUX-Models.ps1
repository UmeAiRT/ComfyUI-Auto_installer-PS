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
if ($DownloadAll) {
    $fluxChoice = 'C'; $ggufChoice = 'G'; $nunchakuChoice = 'E'; $schnellChoice = 'A'
    $controlnetChoice = 'F'; $fillChoice = 'H'; $pulidChoice = 'A'; $upscaleChoice = 'A'; $loraChoice = 'A'
} else {
    $fluxChoice = Read-UserChoice -Prompt "Do you want to download FLUX base models?" -Choices @("A) fp16", "B) fp8", "C) All", "D) No") -ValidAnswers @("A", "B", "C", "D")
    $ggufChoice = Read-UserChoice -Prompt "Do you want to download FLUX GGUF models?" -Choices @("A) Q8 (18GB VRAM)", "B) Q6 (14GB VRAM)", "C) Q5 (12GB VRAM)", "D) Q4 (10GB VRAM)", "E) Q3 (8GB VRAM)", "F) Q2 (6GB VRAM)", "G) All", "H) No") -ValidAnswers @("A", "B", "C", "D", "E", "F", "G", "H")
    $nunchakuChoice = Read-UserChoice -Prompt "Do you want to download FLUX NUNCHAKU models?" -Choices @("A) Base", "B) Fill", "C) KONTEXT", "D) Krea", "E) All", "F) No") -ValidAnswers @("A", "B", "C", "D", "E", "F")
    $schnellChoice = Read-UserChoice -Prompt "Do you want to download the FLUX SCHNELL model?" -Choices @("A) Yes", "B) No") -ValidAnswers @("A", "B")
    $controlnetChoice = Read-UserChoice -Prompt "Do you want to download FLUX ControlNet models?" -Choices @("A) fp16", "B) fp8", "C) Q8", "D) Q5", "E) Q4", "F) All", "G) No") -ValidAnswers @("A", "B", "C", "D", "E", "F", "G")
    $fillChoice = Read-UserChoice -Prompt "Do you want to download FLUX Fill models?" -Choices @("A) fp16", "B) fp8", "C) Q8", "D) Q6", "E) Q5", "F) Q4", "G) Q3", "H) All", "I) No") -ValidAnswers @("A", "B", "C", "D", "E", "F", "G", "H", "I")
    $pulidChoice = Read-UserChoice -Prompt "Do you want to download FLUX PuLID and REDUX models?" -Choices @("A) Yes", "B) No") -ValidAnswers @("A", "B")
    $upscaleChoice = Read-UserChoice -Prompt "Do you want to download Upscaler models ?" -Choices @("A) Yes", "B) No") -ValidAnswers @("A", "B")
    $loraChoice = Read-UserChoice -Prompt "Do you want to download UmeAiRT LoRAs?" -Choices @("A) Yes", "B) No") -ValidAnswers @("A", "B")
}

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
    Save-FileCollecting -Uri "$baseUrl/vae/ae.safetensors" -OutFile (Join-Path $vaeDir "ae.safetensors")
    Save-FileCollecting -Uri "$baseUrl/clip/clip_l.safetensors" -OutFile (Join-Path $clipDir "clip_l.safetensors")
}

# FLUX Base Models
if ($fluxChoice -in 'A', 'C') {
    Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/flux1-dev-fp16.safetensors" -OutFile (Join-Path $fluxDir "flux1-dev-fp16.safetensors")
    Save-FileCollecting -Uri "$baseUrl/text_encoders/T5/t5xxl_fp16.safetensors" -OutFile (Join-Path $clipDir "t5xxl_fp16.safetensors")
}
if ($fluxChoice -in 'B', 'C') {
    Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/flux1-dev-fp8.safetensors" -OutFile (Join-Path $fluxDir "flux1-dev-fp8.safetensors")
    Save-FileCollecting -Uri "$baseUrl/text_encoders/T5/t5xxl_fp8_e4m3fn.safetensors" -OutFile (Join-Path $clipDir "t5xxl_fp8_e4m3fn.safetensors")
}

# GGUF Models
if ($ggufChoice -in 'A', 'G') {
    Save-FileCollecting -Uri "$baseUrl/text_encoders/T5/t5-v1_1-xxl-encoder-Q8_0.gguf" -OutFile (Join-Path $clipDir "t5-v1_1-xxl-encoder-Q8_0.gguf")
    Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Dev-Q8_0.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Dev-Q8_0.gguf")
}
if ($ggufChoice -in 'B', 'G') {
    Save-FileCollecting -Uri "$baseUrl/text_encoders/T5/t5-v1_1-xxl-encoder-Q6_K.gguf" -OutFile (Join-Path $clipDir "t5-v1_1-xxl-encoder-Q6_K.gguf")
    Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Dev-Q6_K.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Dev-Q6_K.gguf")
}
if ($ggufChoice -in 'C', 'G') {
    Save-FileCollecting -Uri "$baseUrl/text_encoders/T5/t5-v1_1-xxl-encoder-Q5_K_M.gguf" -OutFile (Join-Path $clipDir "t5-v1_1-xxl-encoder-Q5_K_M.gguf")
    Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Dev-Q5_K_S.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Dev-Q5_K_S.gguf")
}
if ($ggufChoice -in 'D', 'G') {
    Save-FileCollecting -Uri "$baseUrl/text_encoders/T5/t5-v1_1-xxl-encoder-Q4_K_S.gguf" -OutFile (Join-Path $clipDir "t5-v1_1-xxl-encoder-Q4_K_S.gguf")
    Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Dev-Q4_K_S.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Dev-Q4_K_S.gguf")
}
if ($ggufChoice -in 'E', 'G') {
    Save-FileCollecting -Uri "$baseUrl/text_encoders/T5/t5-v1_1-xxl-encoder-Q3_K_S.gguf" -OutFile (Join-Path $clipDir "t5-v1_1-xxl-encoder-Q3_K_S.gguf")
    Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Dev-Q3_K_S.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Dev-Q3_K_S.gguf")
}
if ($ggufChoice -in 'F', 'G') {
    Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Dev-Q2_K.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Dev-Q2_K.gguf")
}

# NUNCHAKU Model
if ($nunchakuChoice -in 'A', 'E') { Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/svdq-int4_r32-flux.1-dev.safetensors" -OutFile (Join-Path $fluxDir "svdq-int4_r32-flux.1-dev.safetensors") }
if ($nunchakuChoice -in 'B', 'E') { Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/svdq-int4_r32-flux.1-fill-dev.safetensors" -OutFile (Join-Path $fluxDir "svdq-int4_r32-flux.1-fill-dev.safetensors") }
if ($nunchakuChoice -in 'C', 'E') { Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/svdq-int4_r32-flux.1-kontext-dev.safetensors" -OutFile (Join-Path $fluxDir "svdq-int4_r32-flux.1-kontext-dev.safetensors") }
if ($nunchakuChoice -in 'D', 'E') { Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/svdq-int4_r32-flux.1-krea-dev.safetensors" -OutFile (Join-Path $fluxDir "svdq-int4_r32-flux.1-krea-dev.safetensors") }

if ($nunchakuChoice -ne 'F') { Save-FileCollecting -Uri "$baseUrl/text_encoders/T5/umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors" -OutFile (Join-Path $clipDir "umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors") }

# Schnell Model
if ($schnellChoice -eq 'A') {
    Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/flux1-schnell-fp8.safetensors" -OutFile (Join-Path $fluxDir "flux1-schnell-fp8.safetensors")
}

# ControlNet Models
if ($controlnetChoice -ne 'G') {
    if ($controlnetChoice -in 'A', 'B', 'F') { 
        Save-FileCollecting -Uri "$baseUrl/xlabs/controlnets/flux-canny-controlnet-v3.safetensors" -OutFile (Join-Path $controlnetDir "flux-canny-controlnet-v3.safetensors")
        Save-FileCollecting -Uri "$baseUrl/xlabs/controlnets/flux-depth-controlnet-v3.safetensors" -OutFile (Join-Path $controlnetDir "flux-depth-controlnet-v3.safetensors")
    }
    if ($controlnetChoice -in 'A', 'F') { Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/flux1-canny-dev-fp16.safetensors" -OutFile (Join-Path $fluxDir "flux1-canny-dev-fp16.safetensors"); Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/flux1-depth-dev-fp16.safetensors" -OutFile (Join-Path $fluxDir "flux1-depth-dev-fp16.safetensors") }
    if ($controlnetChoice -in 'B', 'F') { Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/flux1-canny-dev-fp8.safetensors" -OutFile (Join-Path $fluxDir "flux1-canny-dev-fp8.safetensors"); Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/flux1-depth-dev-fp8.safetensors" -OutFile (Join-Path $fluxDir "flux1-depth-dev-fp8.safetensors") }
    if ($controlnetChoice -in 'C', 'F') { Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Canny-Dev-Q8_0.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Canny-Dev-Q8_0.gguf"); Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Depth-Dev-Q8_0.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Depth-Dev-Q8_0.gguf") }
    if ($controlnetChoice -in 'D', 'F') { Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Canny-Dev-Q5_0.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Canny-Dev-Q5_0.gguf"); Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Depth-Dev-Q5_0.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Depth-Dev-Q5_0.gguf") }
    if ($controlnetChoice -in 'E', 'F') { Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Canny-Dev-Q4_0.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Canny-Dev-Q4_0.gguf"); Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Depth-Dev-Q4_0.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Depth-Dev-Q4_0.gguf") }
}

# Fill Models
if ($fillChoice -in 'A', 'H') { Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/flux1-fill-dev-fp16.safetensors" -OutFile (Join-Path $fluxDir "flux1-fill-dev-fp16.safetensors") }
if ($fillChoice -in 'B', 'H') { Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/flux1-fill-dev-fp8.safetensors" -OutFile (Join-Path $fluxDir "flux1-fill-dev-fp8.safetensors") }
if ($fillChoice -in 'C', 'H') { Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Fill-Dev-Q8_0.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Fill-Dev-Q8_0.gguf") }
if ($fillChoice -in 'D', 'H') { Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Fill-Dev-Q6_K.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Fill-Dev-Q6_K.gguf") }
if ($fillChoice -in 'E', 'H') { Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Fill-Dev-Q5_K_S.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Fill-Dev-Q5_K_S.gguf") }
if ($fillChoice -in 'F', 'H') { Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Fill-Dev-Q4_K_S.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Fill-Dev-Q4_K_S.gguf") }
if ($fillChoice -in 'G', 'H') { Save-FileCollecting -Uri "$baseUrl/diffusion_models/FLUX/Flux1-Fill-Dev-Q3_K_S.gguf" -OutFile (Join-Path $unetFluxDir "Flux1-Fill-Dev-Q3_K_S.gguf") }

# PuLID Models
if ($pulidChoice -eq 'A') {
    Save-FileCollecting -Uri "$baseUrl/pulid/pulid_flux_v0.9.0.safetensors" -OutFile (Join-Path $pulidDir "pulid_flux_v0.9.0.safetensors")
    Save-FileCollecting -Uri "$baseUrl/style_models/flux1-redux-dev.safetensors" -OutFile (Join-Path $styleDir "flux1-redux-dev.safetensors")
}

# Upscaler Models
if ($upscaleChoice -eq 'A') {
    Save-FileCollecting -Uri "$baseUrl/upscale_models/RealESRGAN_x4plus.pth" -OutFile (Join-Path $upscaleDir "RealESRGAN_x4plus.pth")
    Save-FileCollecting -Uri "$baseUrl/upscale_models/RealESRGAN_x4plus_anime_6B.pth" -OutFile (Join-Path $upscaleDir "RealESRGAN_x4plus_anime_6B.pth")
    Save-FileCollecting -Uri "$baseUrl/upscale_models/4x-AnimeSharp.pth" -OutFile (Join-Path $upscaleDir "4x-AnimeSharp.pth")
    Save-FileCollecting -Uri "$baseUrl/upscale_models/4x-UltraSharp.pth" -OutFile (Join-Path $upscaleDir "4x-UltraSharp.pth")
    Save-FileCollecting -Uri "$baseUrl/upscale_models/4x_NMKD-Siax_200k.pth" -OutFile (Join-Path $upscaleDir "4x_NMKD-Siax_200k.pth")
    Save-FileCollecting -Uri "$baseUrl/upscale_models/RealESRGAN_x4.pth" -OutFile (Join-Path $upscaleDir "RealESRGAN_x4.pth")
}

# LoRA Models
if ($loraChoice -eq 'A') {
    Save-FileCollecting -Uri "https://huggingface.co/UmeAiRT/FLUX.1-dev-LoRA-Ume_Sky/resolve/main/ume_sky_v2.safetensors" -OutFile (Join-Path $loraDir "ume_sky_v2.safetensors")
    Save-FileCollecting -Uri "https://huggingface.co/UmeAiRT/FLUX.1-dev-LoRA-Modern_Pixel_art/resolve/main/ume_modern_pixelart.safetensors" -OutFile (Join-Path $loraDir "ume_modern_pixelart.safetensors")
    Save-FileCollecting -Uri "https://huggingface.co/UmeAiRT/FLUX.1-dev-LoRA-Romanticism/resolve/main/ume_classic_Romanticism.safetensors" -OutFile (Join-Path $loraDir "ume_classic_Romanticism.safetensors")
    Save-FileCollecting -Uri "https://huggingface.co/UmeAiRT/FLUX.1-dev-LoRA-Impressionism/resolve/main/ume_classic_impressionist.safetensors" -OutFile (Join-Path $loraDir "ume_classic_impressionist.safetensors")
}

Show-DownloadSummary
Write-Log "FLUX model downloads complete." -Color Green
if (-not $DownloadAll) { Read-Host "Press Enter to return to the main installer." }
