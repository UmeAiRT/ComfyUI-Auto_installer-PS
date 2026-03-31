<#
.SYNOPSIS
    Entry point for the UmeAiRT ComfyUI installation.
.DESCRIPTION
    Prompts for install path, reads fork configuration, downloads the bootstrap
    script, and launches Install-ComfyUI-Phase1.ps1.
    All logic formerly in UmeAiRT-Install-ComfyUI.bat has been moved here.
.PARAMETER InstallPath
    Where to install ComfyUI. Defaults to the parent of the scripts folder.
.PARAMETER GhUser
    GitHub user/org hosting the installer repo. Default: UmeAiRT.
.PARAMETER GhRepoName
    GitHub repository name. Default: ComfyUI-Auto_installer-PS.
.PARAMETER GhBranch
    Git branch to pull scripts from. Default: main.
#>
param(
    [string]$InstallPath  = "",
    [string]$GhUser       = "UmeAiRT",
    [string]$GhRepoName   = "ComfyUI-Auto_installer-PS",
    [string]$GhBranch     = "main",
    [switch]$v,   # -v  : show [INFO] messages + command output on success
    [switch]$vv   # -vv : all of -v + print each command line before running
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$env:PYTHONUTF8 = "1"

# ---------------------------------------------------------------------------
# Welcome
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "          Welcome to the UmeAiRT ComfyUI Installer" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# Resolve install path
# ---------------------------------------------------------------------------
$defaultPath = (Split-Path -Path $PSScriptRoot -Parent).Replace('\', '/')

if (-not $InstallPath) {
    Write-Host "Where would you like to install ComfyUI?" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Current path: $defaultPath"
    Write-Host ""
    Write-Host "  Press ENTER to use the current path, or enter a full path (e.g., D:\ComfyUI)."
    Write-Host ""
    $userInput = (Read-Host "Enter installation path").Trim()
    $InstallPath = if ($userInput) { $userInput } else { $defaultPath }
}

$InstallPath = $InstallPath.TrimEnd('\', '/').Replace('\', '/')

# --- Early logging setup (psm1 not yet available) ---
$logPath = "$InstallPath/logs"
$logFile = "$logPath/install.log"

function _RotateLog { param([string]$f, [int]$k = 3)
    $old = "$f.$k"; if (Test-Path $old) { Remove-Item $old -Force -EA SilentlyContinue }
    for ($i = $k - 1; $i -ge 1; $i--) { $s = "$f.$i"; $d = "$f.$($i+1)"; if (Test-Path $s) { Rename-Item $s $d -Force -EA SilentlyContinue } }
    if (Test-Path $f) { Rename-Item $f "$f.1" -Force -EA SilentlyContinue }
}
function _AppendLog { param([string]$f, [string]$m)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $f -Value "[$ts] $m" -Encoding UTF8 -ErrorAction SilentlyContinue
}

if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath -Force | Out-Null }
_RotateLog $logFile
_RotateLog "$logPath/bootstrap.log"
_AppendLog $logFile "=== Install session started ==="
_AppendLog $logFile "InstallPath: $InstallPath"
_AppendLog $logFile "PSVersion: $($PSVersionTable.PSVersion)  PSEdition: $($PSVersionTable.PSEdition)"
_AppendLog $logFile "Fork (bat-resolved): $GhUser/$GhRepoName @ $GhBranch"

Write-Host ""
Write-Host "[INFO] Installing to: $InstallPath" -ForegroundColor Cyan
Write-Host "Press any key to begin..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Host ""

# ---------------------------------------------------------------------------
# Resolve fork config
# If psm1 is already present (re-run or fork setup), read config from JSON.
# CLI params always take precedence. On fresh install (no psm1), use defaults.
# ---------------------------------------------------------------------------
$psm1Path       = "$($PSScriptRoot.Replace('\','/'))/UmeAiRTUtils.psm1"
$userConfigFile = "$InstallPath/umeairt-user-config.json"
$repoConfigFile = "$InstallPath/repo-config.json"

if (Test-Path $psm1Path) {
    Import-Module $psm1Path -Force
    $cfgLines = Read-UserConfig -UserConfigFile $userConfigFile -RepoConfigFile $repoConfigFile
    $cfg = @{}
    $cfgLines | ForEach-Object {
        $parts = $_ -split '=', 2
        if ($parts.Count -eq 2) { $cfg[$parts[0].Trim()] = $parts[1].Trim() }
    }
    # CLI params (explicitly passed) override config file values
    if (-not $PSBoundParameters.ContainsKey('GhUser'))     { $GhUser     = $cfg.GhUser }
    if (-not $PSBoundParameters.ContainsKey('GhRepoName')) { $GhRepoName = $cfg.GhRepoName }
    if (-not $PSBoundParameters.ContainsKey('GhBranch'))   { $GhBranch   = $cfg.GhBranch }
    Write-Host "[INFO] Config source: $($cfg.ConfigSource)" -ForegroundColor Cyan
} else {
    # Fresh install: validate CLI arg values directly (same rules as Read-UserConfig)
    if ($GhUser     -match '[^a-zA-Z0-9_-]')   { Write-Error 'GhUser contains invalid characters.';     exit 1 }
    if ($GhRepoName -match '[^a-zA-Z0-9_-]')   { Write-Error 'GhRepoName contains invalid characters.'; exit 1 }
    if ($GhBranch   -match '[^a-zA-Z0-9_./-]') { Write-Error 'GhBranch contains invalid characters.';   exit 1 }
}

Write-Host "[INFO] Using: $GhUser/$GhRepoName @ $GhBranch" -ForegroundColor Cyan
_AppendLog $logFile "Config source: $(if ($null -ne $cfg.ConfigSource) { $cfg.ConfigSource } else { 'defaults' })"
_AppendLog $logFile "Fork: $GhUser/$GhRepoName @ $GhBranch"

# ---------------------------------------------------------------------------
# Prepare scripts folder
# ---------------------------------------------------------------------------
$scriptsFolder   = "$InstallPath/scripts"
$bootstrapScript = "$scriptsFolder/Bootstrap-Downloader.ps1"
$bootstrapUrl    = "https://raw.githubusercontent.com/$GhUser/$GhRepoName/$GhBranch/scripts/Bootstrap-Downloader.ps1"

if (-not (Test-Path $scriptsFolder)) {
    Write-Host "[INFO] Creating scripts folder: $scriptsFolder" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $scriptsFolder -Force | Out-Null
}

# ---------------------------------------------------------------------------
# Download and run bootstrap
# ---------------------------------------------------------------------------
Write-Host "[INFO] Downloading bootstrap script..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $bootstrapUrl -OutFile $bootstrapScript -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Host "[ERROR] Failed to download bootstrap script." -ForegroundColor Red
    Write-Host "[ERROR] URL: $bootstrapUrl" -ForegroundColor Red
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "[ERROR] Check your internet connection and gh_user/gh_branch settings." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "[INFO] Running bootstrap to download all required files..." -ForegroundColor Cyan
& $bootstrapScript -InstallPath $InstallPath -GhUser $GhUser -GhRepoName $GhRepoName -GhBranch $GhBranch
if ($LASTEXITCODE -ne 0 -or -not $?) {
    Write-Host "[ERROR] Bootstrap script failed. See above for details." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "[OK] Bootstrap download complete." -ForegroundColor Green
Write-Host ""
_AppendLog $logFile "Bootstrap complete."

# ---------------------------------------------------------------------------
# Persist resolved fork config to umeairt-user-config.json
# Merge with any existing keys (e.g. snapshot_path) so we don't clobber them.
# ---------------------------------------------------------------------------
$configObj = [ordered]@{ gh_user = $GhUser; gh_reponame = $GhRepoName; gh_branch = $GhBranch }
if (Test-Path $userConfigFile) {
    try {
        $existing = Get-Content $userConfigFile -Raw | ConvertFrom-Json
        $existing | Get-Member -MemberType NoteProperty | ForEach-Object {
            $k = $_.Name
            if ($k -notin @('gh_user', 'gh_reponame', 'gh_branch')) {
                $configObj[$k] = $existing.$k
            }
        }
    } catch { }
}
$configObj | ConvertTo-Json -Depth 10 | Set-Content $userConfigFile -Encoding UTF8

# ---------------------------------------------------------------------------
# Launch Phase 1
# ---------------------------------------------------------------------------
Write-Host "[INFO] Launching Phase 1 installer..." -ForegroundColor Cyan
Write-Host ""
$phase1 = "$scriptsFolder/Install-ComfyUI-Phase1.ps1"
$verbSplat = @{}
if ($vv) { $verbSplat.vv = $true } elseif ($v) { $verbSplat.v = $true }
& $phase1 -InstallPath $InstallPath @verbSplat
