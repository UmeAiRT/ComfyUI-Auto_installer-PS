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
#>

param(
    [string]$InstallPath,
    [string]$GhUser = "UmeAiRT",
    [string]$GhRepoName = "ComfyUI-Auto_installer",
    [string]$GhBranch = "main"
)

# Inline path helper — UmeAiRTUtils.psm1 is not yet available during bootstrap
function ConvertTo-ForwardSlash { param([string]$Path) $Path.Replace('\', '/') }

# Inline log helper — UmeAiRTUtils.psm1 not available during bootstrap
function _AppendLog { param([string]$f, [string]$m)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $f -Value "[$ts] $m" -Encoding UTF8 -ErrorAction SilentlyContinue
}
$_bootstrapLog = ConvertTo-ForwardSlash (Join-Path $InstallPath "logs/bootstrap.log")

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

# Build the base URL from parameters (allows developer testing of forks)
$baseUrl = "https://raw.githubusercontent.com/$GhUser/$GhRepoName/$GhBranch/"

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
    @{ RepoPath = "UmeAiRT-Install-ComfyUI.bat";         LocalPath = "UmeAiRT-Install-ComfyUI.bat" },
    @{ RepoPath = "UmeAiRT-Update-ComfyUI.bat";          LocalPath = "UmeAiRT-Update-ComfyUI.bat" }
)

Write-Host "[INFO] Downloading the latest versions of the installation scripts..."
_AppendLog $_bootstrapLog "=== Bootstrap started: $GhUser/$GhRepoName @ $GhBranch ==="

# Set TLS protocol for compatibility
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$failed = @()

foreach ($file in $filesToDownload) {
    $uri = $baseUrl + $file.RepoPath
    $outFile = ConvertTo-ForwardSlash (Join-Path $InstallPath $file.LocalPath)

    # Ensure the destination directory exists before downloading
    $outDir = ConvertTo-ForwardSlash (Split-Path -Path $outFile -Parent)
    if (-not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    Write-Host "  - Downloading $($file.RepoPath)..."
    try {
        Invoke-WebRequest -Uri $uri -OutFile $outFile -ErrorAction Stop
        _AppendLog $_bootstrapLog "Downloaded $($file.RepoPath)"
    } catch {
        _AppendLog $_bootstrapLog "FAILED: $($file.RepoPath) — $($_.Exception.Message)"
        Write-Host "[WARN] Failed to download '$($file.RepoPath)': $($_.Exception.Message)" -ForegroundColor Yellow
        $failed += $file.RepoPath
    }
}

if ($failed.Count -gt 0) {
    _AppendLog $_bootstrapLog "=== Bootstrap completed with $($failed.Count) failure(s) ==="
    Write-Host ""
    Write-Host "################################################################################" -ForegroundColor Red
    Write-Host "[ERROR] Bootstrap failed to download $($failed.Count) file(s):" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "[ERROR] These files were NOT updated. Re-run the update to retry." -ForegroundColor Red
    Write-Host "################################################################################" -ForegroundColor Red
    Write-Host ""
    exit 1
}

_AppendLog $_bootstrapLog "=== Bootstrap complete ==="
Write-Host "[OK] All required files have been downloaded successfully." -ForegroundColor Green
exit 0
