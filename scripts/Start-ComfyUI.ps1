<#
.SYNOPSIS
    ComfyUI launcher for UmeAiRT installer.
    Called by UmeAiRT-Start-ComfyUI.bat and UmeAiRT-Start-ComfyUI_LowVRAM.bat.

.PARAMETER InstallPath
    Root directory of the UmeAiRT ComfyUI installation.

.PARAMETER LowVRAM
    Launch ComfyUI with low-VRAM memory optimisation flags:
    --disable-smart-memory --lowvram --fp8_e4m3fn-text-enc

.NOTES
    Compatible with Windows PowerShell 5.1 and PowerShell 7+.
    Reads umeairt-user-config.json for network and repository settings.
#>
param(
    [Parameter(Mandatory)][string]$InstallPath,
    [switch]$LowVRAM
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Trim any trailing path separator passed by %~dp0
$InstallPath = $InstallPath.TrimEnd('\', '/').Replace('\', '/')

# ============================================================================
# Helpers
# ============================================================================
function Write-Info { param([string]$Msg) Write-Host "[INFO]  $Msg" -ForegroundColor Cyan }
function Write-Warn { param([string]$Msg) Write-Host "[WARN]  $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "[ERROR] $Msg" -ForegroundColor Red }
function Abort      { param([string]$Msg) Write-Err $Msg; exit 1 }

# ============================================================================
# Section 1: Python environment variables
# ============================================================================
$env:PYTHONPATH       = ''
$env:PYTHONNOUSERSITE = '1'
$env:PYTHONUTF8       = '1'

# ============================================================================
# Section 2: Environment detection and activation
# ============================================================================
Write-Info 'Checking installation type...'

$installTypeFile = "$InstallPath/scripts/install_type"
$installType     = 'conda'

if (Test-Path $installTypeFile) {
    $installType = (Get-Content $installTypeFile -Raw).Trim()
} elseif (Test-Path "$InstallPath/scripts/venv") {
    $installType = 'venv'
}

if ($installType -eq 'venv') {
    Write-Info 'Activating venv environment...'
    $activateScript = "$InstallPath/scripts/venv/Scripts/Activate.ps1"
    if (-not (Test-Path $activateScript)) {
        Abort "venv activate script not found: $activateScript"
    }
    . $activateScript
} else {
    Write-Info 'Activating Conda environment...'
    $condaHook = "$($env:LOCALAPPDATA.Replace('\','/'))/Miniconda3/shell/condabin/conda-hook.ps1"
    if (-not (Test-Path $condaHook)) {
        Abort "Conda hook not found at: $condaHook`nEnsure Miniconda3 is installed under %LOCALAPPDATA%."
    }
    . $condaHook
    conda activate UmeAiRT
    if ($LASTEXITCODE -ne 0) {
        Abort "Failed to activate Conda environment 'UmeAiRT'."
    }
}

# ============================================================================
# Section 3: Read umeairt-user-config.json
# ============================================================================
$configPath = "$InstallPath/umeairt-user-config.json"
$config     = $null

if (Test-Path $configPath) {
    Write-Info 'Reading umeairt-user-config.json...'
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    } catch {
        Abort "Failed to parse umeairt-user-config.json: $_"
    }
}

# Helper: safely read a string property from the config object (PS 5.1 + 7 compatible)
function Get-ConfigString {
    param([string]$Field, [string]$Default = '')
    if ($null -eq $config) { return $Default }
    if (-not $config.PSObject.Properties[$Field]) { return $Default }
    $val = $config.$Field
    if ($null -eq $val) { return $Default }
    return [string]$val
}

function Get-ConfigValue {
    param([string]$Field)
    if ($null -eq $config) { return $null }
    if (-not $config.PSObject.Properties[$Field]) { return $null }
    return $config.$Field
}

# ============================================================================
# Section 4: Validate config fields
# ============================================================================

# -- gh_user and gh_reponame: alphanumeric, hyphens, underscores --
foreach ($field in @('gh_user', 'gh_reponame')) {
    $val = Get-ConfigString $field
    if ($val -and $val -notmatch '^[a-zA-Z0-9_-]+$') {
        Abort "$field contains invalid characters. Allowed: letters, numbers, hyphens, underscores."
    }
}

# -- gh_branch: alphanumeric, hyphens, underscores, dots, forward slashes --
$ghBranch = Get-ConfigString 'gh_branch'
if ($ghBranch -and $ghBranch -notmatch '^[a-zA-Z0-9_./-]+$') {
    Abort "gh_branch contains invalid characters. Allowed: letters, numbers, hyphens, underscores, dots, forward slashes."
}

# ============================================================================
# Section 5: Build network arguments
# ============================================================================
$networkArgs = @()

$listenEnabled = $false
$listenEnabledRaw = Get-ConfigValue 'listen_enabled'
if ($null -ne $listenEnabledRaw) {
    $listenEnabled = [bool]$listenEnabledRaw
}

if ($listenEnabled) {
    # listen_address is required when listen is enabled
    $listenAddress = Get-ConfigString 'listen_address'
    if (-not $listenAddress) {
        Abort "listen_enabled is true but listen_address is not set.`nEdit umeairt-user-config.json and set listen_address to a valid IP (e.g. '127.0.0.1' or '127.0.0.1,100.64.0.1')."
    }

    # Validate each comma-separated segment: only IPv4/IPv6 address characters allowed
    $segments = $listenAddress -split ','
    foreach ($segment in $segments) {
        $segment = $segment.Trim()
        if (-not $segment) {
            Abort "listen_address contains an empty segment after splitting on commas."
        }
        if ($segment -notmatch '^[0-9a-fA-F:.]+$') {
            Abort "listen_address segment '$segment' contains invalid characters.`nOnly IPv4 and IPv6 addresses are accepted."
        }
    }

    # Warn if exposing all interfaces
    $openSegments = $segments | Where-Object { $_.Trim() -eq '0.0.0.0' -or $_.Trim() -eq '::' }
    if ($openSegments) {
        Write-Warn "listen_address includes '$($openSegments -join ', ')' — ComfyUI will be accessible on ALL network interfaces."
        Write-Warn "Ensure your firewall is configured appropriately before proceeding."
    }

    $networkArgs += '--listen'
    $networkArgs += $listenAddress

    # -- listen_port --
    $portRaw = Get-ConfigValue 'listen_port'
    if ($null -ne $portRaw) {
        $portInt = 0
        if ($portRaw -is [int] -or $portRaw -is [long]) {
            $portInt = [int]$portRaw
        } elseif (-not [int]::TryParse([string]$portRaw, [ref]$portInt)) {
            Abort "listen_port '$portRaw' is not a valid integer."
        }
        if ($portInt -lt 1 -or $portInt -gt 65535) {
            Abort "listen_port $portInt is out of range. Valid range: 1–65535."
        }
        if ($portInt -lt 1024) {
            Write-Warn "listen_port $portInt is a privileged port (below 1024). This may require elevated permissions."
        }
        if ($portInt -ne 8188) {
            $networkArgs += '--port'
            $networkArgs += [string]$portInt
        }
    }
}

# ============================================================================
# Section 6: Build VRAM arguments
# ============================================================================
$vramArgs = @()
if ($LowVRAM) {
    Write-Info 'Low VRAM mode enabled.'
    $vramArgs = @('--disable-smart-memory', '--lowvram', '--fp8_e4m3fn-text-enc')
}

# ============================================================================
# Section 7: Launch ComfyUI
# ============================================================================
$mode = if ($LowVRAM) { 'Low VRAM / Stability Mode' } else { 'Performance Mode' }
Write-Info "Starting ComfyUI ($mode)..."

$comfyDir = "$InstallPath/ComfyUI"
if (-not (Test-Path $comfyDir)) {
    Abort "ComfyUI directory not found: $comfyDir`nHas ComfyUI been installed? Run UmeAiRT-Install-ComfyUI.bat first."
}

Set-Location $comfyDir

$pythonArgs = @('main.py', '--use-sage-attention', '--auto-launch') + $networkArgs + $vramArgs

& python $pythonArgs
