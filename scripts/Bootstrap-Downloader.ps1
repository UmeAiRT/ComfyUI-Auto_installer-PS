<#
.SYNOPSIS
    Bootstraps the installation by downloading all required scripts and configuration files.
.DESCRIPTION
    This script is the first entry point for the auto-installer.
    It downloads the latest version of the PowerShell scripts, batch launchers, and config files
    from the GitHub repository to the local installation directory.
.PARAMETER InstallPath
    The root directory where the files should be installed.
.PARAMETER GhUser
    The GitHub username (default: "UmeAiRT").
.PARAMETER GhRepoName
    The GitHub repository name (default: "ComfyUI-Auto_installer").
.PARAMETER GhBranch
    The GitHub branch to use (default: "main").
.PARAMETER SkipSelf
    If true, skips downloading 'UmeAiRT-Update-ComfyUI.bat' to avoid file locking issues during self-updates.
#>

param(
    [string]$InstallPath,
    [string]$GhUser = "UmeAiRT",
    [string]$GhRepoName = "ComfyUI-Auto_installer",
    [string]$GhBranch = "main",
    [switch]$SkipSelf = $false
)

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

# Build the base URL from parameters (allows developer testing of forks)
$baseUrl = "https://github.com/$GhUser/$GhRepoName/raw/$GhBranch/"

# Define the list of files to download
$filesToDownload = @(
    # PowerShell Scripts
    @{ RepoPath = "scripts/Install-ComfyUI.ps1";         LocalPath = "scripts/Install-ComfyUI.ps1" },
    @{ RepoPath = "scripts/Install-ComfyUI-Phase1.ps1";  LocalPath = "scripts/Install-ComfyUI-Phase1.ps1" },
    @{ RepoPath = "scripts/Install-ComfyUI-Phase2.ps1";  LocalPath = "scripts/Install-ComfyUI-Phase2.ps1" },
    @{ RepoPath = "scripts/Update-ComfyUI.ps1";          LocalPath = "scripts/Update-ComfyUI.ps1" },
    @{ RepoPath = "scripts/Start-ComfyUI.ps1";           LocalPath = "scripts/Start-ComfyUI.ps1" },
    @{ RepoPath = "umeairt-user-config.json.example"; LocalPath = "umeairt-user-config.json.example" },
    @{ RepoPath = "scripts/Download-FLUX-Models.ps1";    LocalPath = "scripts/Download-FLUX-Models.ps1" },
    @{ RepoPath = "scripts/Download-WAN2.1-Models.ps1";  LocalPath = "scripts/Download-WAN2.1-Models.ps1" },
    @{ RepoPath = "scripts/Download-WAN2.2-Models.ps1";  LocalPath = "scripts/Download-WAN2.2-Models.ps1" },
    @{ RepoPath = "scripts/Download-HIDREAM-Models.ps1"; LocalPath = "scripts/Download-HIDREAM-Models.ps1" },
    @{ RepoPath = "scripts/Download-LTX1-Models.ps1";    LocalPath = "scripts/Download-LTX1-Models.ps1" },
    @{ RepoPath = "scripts/Download-LTX2-Models.ps1";    LocalPath = "scripts/Download-LTX2-Models.ps1" },
    @{ RepoPath = "scripts/Download-QWEN-Models.ps1";    LocalPath = "scripts/Download-QWEN-Models.ps1" },
    @{ RepoPath = "scripts/Download-Z-IMAGES-Models.ps1"; LocalPath = "scripts/Download-Z-IMAGES-Models.ps1" },
    @{ RepoPath = "scripts/Download-Models.ps1";          LocalPath = "scripts/Download-Models.ps1" },
    @{ RepoPath = "scripts/UmeAiRTUtils.psm1";           LocalPath = "scripts/UmeAiRTUtils.psm1" },
    # Configuration Files
    @{ RepoPath = "scripts/environment.yml";             LocalPath = "scripts/environment.yml" },
    @{ RepoPath = "scripts/dependencies.json";           LocalPath = "scripts/dependencies.json" },
    @{ RepoPath = "scripts/custom_nodes.csv";            LocalPath = "scripts/custom_nodes.csv" },
    @{ RepoPath = "scripts/snapshot.json";               LocalPath = "scripts/snapshot.json" },
    # Batch Launchers
    @{ RepoPath = "UmeAiRT-Start-ComfyUI.bat";           LocalPath = "UmeAiRT-Start-ComfyUI.bat" },
    @{ RepoPath = "UmeAiRT-Start-ComfyUI_LowVRAM.bat";   LocalPath = "UmeAiRT-Start-ComfyUI_LowVRAM.bat" },
    @{ RepoPath = "UmeAiRT-Download_models.bat";         LocalPath = "UmeAiRT-Download_models.bat" },
    @{ RepoPath = "UmeAiRT-Update-ComfyUI.bat";          LocalPath = "UmeAiRT-Update-ComfyUI.bat" }
)

Write-Host "[INFO] Downloading the latest versions of the installation scripts..."

# Set TLS protocol for compatibility
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

foreach ($file in $filesToDownload) {
    $uri = $baseUrl + $file.RepoPath
    $outFile = Join-Path $InstallPath $file.LocalPath

    if ($SkipSelf -and $file.LocalPath -eq "UmeAiRT-Update-ComfyUI.bat") {
        Write-Host "  - Skipping 'UmeAiRT-Update-ComfyUI.bat' (SkipSelf)"
        continue
    }

    # Ensure the destination directory exists before downloading
    $outDir = Split-Path -Path $outFile -Parent
    if (-not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    Write-Host "  - Downloading $($file.RepoPath)..."
    try {
        Invoke-WebRequest -Uri $uri -OutFile $outFile -ErrorAction Stop
    } catch {
        Write-Host "[ERROR] Failed to download '$($file.RepoPath)'. Please check your internet connection and the repository URL." -ForegroundColor Red
        # Pause to allow user to see the error, then exit.
        Read-Host "Press Enter to exit."
        exit 1
    }
}

Write-Host "[OK] All required files have been downloaded successfully." -ForegroundColor Green
