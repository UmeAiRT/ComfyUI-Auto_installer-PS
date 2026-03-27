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
    The GitHub repository name (default: "ComfyUI-Auto_installer-PS").
.PARAMETER GhBranch
    The GitHub branch to use (default: "main").
.PARAMETER v
    Verbose mode: echo log entries to console in addition to the log file.
.PARAMETER vv
    Extra-verbose mode: all of -v, plus print the full download URI for each file.
#>

param(
    [string]$InstallPath,
    [string]$GhUser      = "",   # empty = read from config, then fall back to upstream default
    [string]$GhRepoName  = "",
    [string]$GhBranch    = "",
    [switch]$v,   # -v  : also echo log entries to console
    [switch]$vv   # -vv : all of -v + show full URIs for each download
)
$_verbosity = if ($vv) { 2 } elseif ($v) { 1 } else { 0 }

# Inline path helper — UmeAiRTUtils.psm1 is not yet available during bootstrap
function ConvertTo-ForwardSlash { param([string]$Path) $Path.Replace('\', '/') }

# Inline config reader — no module dependency
function _BsReadCfg {
    param([string]$File, [string]$Key)
    if (-not (Test-Path $File)) { return "" }
    try {
        $j = Get-Content $File -Raw | ConvertFrom-Json
        if ($j.PSObject.Properties[$Key] -and $j.$Key) { return [string]$j.$Key }
    } catch {}
    return ""
}

# If fork settings not supplied, try config files before falling back to upstream defaults
if (-not $GhUser -or -not $GhRepoName -or -not $GhBranch) {
    foreach ($f in @("$InstallPath/umeairt-user-config.json", "$InstallPath/repo-config.json")) {
        if (-not $GhUser)     { $GhUser     = _BsReadCfg $f "gh_user" }
        if (-not $GhRepoName) { $GhRepoName = _BsReadCfg $f "gh_reponame" }
        if (-not $GhBranch)   { $GhBranch   = _BsReadCfg $f "gh_branch" }
    }
    if (-not $GhUser)     { $GhUser     = "UmeAiRT" }
    if (-not $GhRepoName) { $GhRepoName = "ComfyUI-Auto_installer-PS" }
    if (-not $GhBranch)   { $GhBranch   = "main" }
}

# Inline log helper — UmeAiRTUtils.psm1 not available during bootstrap
function _AppendLog { param([string]$f, [string]$m)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $f -Value "[$ts] $m" -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($script:_verbosity -ge 1) { Write-Host "  [LOG] $m" -ForegroundColor DarkGray }
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
    @{ RepoPath = "UmeAiRT-Update-ComfyUI.bat";          LocalPath = "UmeAiRT-Update-ComfyUI.bat" },
    @{ RepoPath = "UmeAiRT-Bootstrap.bat";               LocalPath = "UmeAiRT-Bootstrap.bat" },
    # Self-update: ensures this script picks up fixes on next run
    @{ RepoPath = "scripts/Bootstrap-Downloader.ps1";   LocalPath = "scripts/Bootstrap-Downloader.ps1" }
)

# Resolve the current commit hash for the branch via GitHub API (best-effort)
$commitHash = ""
try {
    $apiUrl = "https://api.github.com/repos/$GhUser/$GhRepoName/commits/$GhBranch"
    $commitInfo = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -Headers @{ 'User-Agent' = 'UmeAiRT-Installer' } -ErrorAction Stop
    $commitHash = $commitInfo.sha.Substring(0, 8)
} catch {}

$sourceLabel = if ($commitHash) { "$GhUser/$GhRepoName @ $GhBranch ($commitHash)" } else { "$GhUser/$GhRepoName @ $GhBranch" }
Write-Host "[INFO] Downloading the latest versions of the installation scripts from $sourceLabel ..."
_AppendLog $_bootstrapLog "=== Bootstrap started: $sourceLabel ==="

# Set TLS protocol for compatibility
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Tls13

$failed = @()

foreach ($file in $filesToDownload) {
    $uri = $baseUrl + $file.RepoPath
    $outFile = ConvertTo-ForwardSlash (Join-Path $InstallPath $file.LocalPath)

    # Ensure the destination directory exists before downloading
    $outDir = ConvertTo-ForwardSlash (Split-Path -Path $outFile -Parent)
    if (-not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    # Clear read-only attribute if file already exists, so overwrite succeeds
    if (Test-Path $outFile) {
        Set-ItemProperty -Path $outFile -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    }

    Write-Host "  - Downloading $($file.RepoPath)..."
    if ($_verbosity -ge 2) { Write-Host "      [URI] $uri" -ForegroundColor DarkGray }
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
