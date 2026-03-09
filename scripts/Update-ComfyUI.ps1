<#
.SYNOPSIS
    Automated updater for ComfyUI and its components.
.DESCRIPTION
    This script updates:
    - ComfyUI core (via Git).
    - Custom Nodes (via ComfyUI-Manager CLI and 'update all').
    - Python dependencies (uv/pip requirements).
    - Optimized components (Triton/SageAttention via DazzleML).
.PARAMETER InstallPath
    The root directory for the installation.
.PARAMETER SnapshotPath
    Optional path to a specific snapshot file to use for node restore.
    If omitted the script prompts interactively (recommended: save current nodes first).
#>

param(
    [string]$InstallPath  = ((Split-Path -Path $PSScriptRoot -Parent).Replace('\', '/')),
    [string]$SnapshotPath = "",
    [string]$GhUser       = "",   # empty = read from config
    [string]$GhRepoName   = "",
    [string]$GhBranch     = ""
)

#===========================================================================
# SECTION 1: SCRIPT CONFIGURATION & HELPER FUNCTIONS
#===========================================================================

# --- Encoding Support (CJK/Accents) ---
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$env:PYTHONUTF8 = "1"

# --- Paths and Configuration ---
$comfyPath = "$InstallPath/ComfyUI"
# Target internal folder (Junctions handle the redirection to external storage)
$internalCustomNodesPath = "$comfyPath/custom_nodes"
$workflowPath = "$InstallPath/user/default/workflows/UmeAiRT-Workflow"
$condaPath = "$($env:LOCALAPPDATA.Replace('\','/'))/Miniconda3"
$logPath = "$InstallPath/logs"
$logFile = "$logPath/update_log.txt"
$scriptPath = "$InstallPath/scripts"

# --- Load Dependencies from JSON ---
$dependenciesFile = "$scriptPath/dependencies.json"
if (-not (Test-Path $dependenciesFile)) {
    Write-Host "FATAL: dependencies.json not found at '$dependenciesFile'. Cannot proceed." -ForegroundColor Red
    Read-Host "Press Enter to exit."
    exit 1
}
$dependencies = Get-Content -Raw -Path $dependenciesFile | ConvertFrom-Json

if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Force -Path $logPath | Out-Null }

# --- Helper Functions ---
Import-Module "$($PSScriptRoot.Replace('\','/'))/UmeAiRTUtils.psm1" -Force
$global:logFile = $logFile
$global:totalSteps = 4
$global:currentStep = 0

# --- Resolve fork config: CLI args take precedence over config file ---
if (-not $GhUser) {
    $cfgLines = Read-UserConfig `
        -UserConfigFile "$InstallPath/umeairt-user-config.json" `
        -RepoConfigFile "$InstallPath/repo-config.json"
    $cfg = @{}
    $cfgLines | ForEach-Object {
        $parts = $_ -split '=', 2
        if ($parts.Count -eq 2) { $cfg[$parts[0].Trim()] = $parts[1].Trim() }
    }
    $GhUser = $cfg.GhUser; $GhRepoName = $cfg.GhRepoName; $GhBranch = $cfg.GhBranch
}

# --- Bootstrap self-update ---
$bootstrapUrl    = "https://github.com/$GhUser/$GhRepoName/raw/$GhBranch/scripts/Bootstrap-Downloader.ps1"
$bootstrapScript = "$($PSScriptRoot.Replace('\','/'))/Bootstrap-Downloader.ps1"
Write-Host "[INFO] Updating bootstrap and all scripts ($GhUser/$GhRepoName @ $GhBranch)..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $bootstrapUrl -OutFile $bootstrapScript -UseBasicParsing -ErrorAction Stop
    & $bootstrapScript -InstallPath $InstallPath -GhUser $GhUser -GhRepoName $GhRepoName -GhBranch $GhBranch -SkipSelf
    Write-Host "[OK] All scripts are up-to-date." -ForegroundColor Green
} catch {
    Write-Host "[WARN] Bootstrap self-update failed: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "[WARN] Continuing with existing scripts." -ForegroundColor Yellow
}

#===========================================================================
# SECTION 1.5: ENVIRONMENT DETECTION
#===========================================================================
$installTypeFile = "$scriptPath/install_type"
$pythonExe = "python" # Default fallback

if (Test-Path $installTypeFile) {
    $installType = Get-Content -Path $installTypeFile -Raw
    $installType = $installType.Trim()

    if ($installType -eq "venv") {
        $venvPython = "$scriptPath/venv/Scripts/python.exe"
        if (Test-Path $venvPython) {
            $pythonExe = $venvPython
            Write-Host "[INIT] Detected VENV installation. Using: $pythonExe" -ForegroundColor Cyan
        }
    } elseif ($installType -eq "conda") {
        $condaEnvPython = "$($env:LOCALAPPDATA.Replace('\','/'))/Miniconda3/envs/UmeAiRT/python.exe"
        if (Test-Path $condaEnvPython) {
            $pythonExe = $condaEnvPython
            Write-Host "[INIT] Detected CONDA installation. Using: $pythonExe" -ForegroundColor Cyan
        }
    }
} else {
    Write-Host "[WARN] 'install_type' file not found. Assuming System Python." -ForegroundColor Yellow
}

#===========================================================================
# SECTION 2: UPDATE PROCESS
#===========================================================================
Clear-Host
Write-Log "===============================================================================" -Level -2
Write-Log "             Starting UmeAiRT ComfyUI Update Process" -Level -2 -Color Yellow
Write-Log "===============================================================================" -Level -2
Write-Log "Python Executable used: $pythonExe" -Level 1

# --- 1. Update Git Repositories (Core & Workflows) ---
Write-Log "Updating Core Git repositories..." -Level 0 -Color Green
Write-Log "Updating ComfyUI Core..." -Level 1
Invoke-AndLog "git" "-C `"$comfyPath`" pull"
Write-Log "Checking main ComfyUI requirements..." -Level 1
$mainReqs = "$comfyPath/requirements.txt"
Invoke-AndLog "uv" "pip install --python `"$pythonExe`" -r `"$mainReqs`""

# --- 2. Update and Install Custom Nodes (Manager CLI) ---
Write-Log "Updating/Installing Custom Nodes..." -Level 0 -Color Green

# --- A. Update ComfyUI-Manager FIRST ---
$managerPath = "$internalCustomNodesPath/ComfyUI-Manager"
Write-Log "Updating ComfyUI-Manager..." -Level 1
if (Test-Path $managerPath) {
    Invoke-AndLog "git" "-C `"$managerPath`" pull"
} else {
    Write-Log "ComfyUI-Manager missing. Installing..." -Level 2
    Invoke-AndLog "git" "clone https://github.com/ltdrdata/ComfyUI-Manager.git `"$managerPath`""
}

# --- B. Update Manager Dependencies (Critical for CLI) ---
$managerReqs = "$managerPath/requirements.txt"
if (Test-Path $managerReqs) {
    Write-Log "Updating ComfyUI-Manager dependencies..." -Level 1
    Invoke-AndLog "uv" "pip install --python `"$pythonExe`" -r `"$managerReqs`""
}

# --- C. Enable uv in ComfyUI Manager config ---
Set-ManagerUseUv -InstallPath $InstallPath

$cmCliScript = "$managerPath/cm-cli.py"

# --- D. Setup Environment Variables for CLI ---
# This matches the logic in Phase 2 to prevent "ModuleNotFoundError"
$env:PYTHONPATH = "$comfyPath;$managerPath;$env:PYTHONPATH"
$env:COMFYUI_PATH = $comfyPath

# --- E. Snapshot Resolution ---
$userSnapshotFile      = "$scriptPath/user-snapshot.json"
$upstreamSnapshotFile  = "$scriptPath/snapshot.json"
$effectiveSnapshotFile = $null
$snapshotSource        = ""

# Priority 1: -SnapshotPath param
if ($SnapshotPath -and $SnapshotPath.Trim() -ne "") {
    if (-not (Test-Path $SnapshotPath)) {
        Write-Log "WARNING: -SnapshotPath '$SnapshotPath' not found, falling through." -Color Yellow
    } else {
        $effectiveSnapshotFile = $SnapshotPath.Trim()
        $snapshotSource = "parameter (-SnapshotPath)"
    }
}

# Priority 2: snapshot_path in umeairt-user-config.json
if ($null -eq $effectiveSnapshotFile) {
    $userConfigPath = "$InstallPath/umeairt-user-config.json"
    if (Test-Path $userConfigPath) {
        try {
            $uc = Get-Content $userConfigPath -Raw | ConvertFrom-Json
            if ($uc.PSObject.Properties["snapshot_path"] -and $uc.snapshot_path) {
                $cfgPath = [string]$uc.snapshot_path
                if (-not (Test-Path $cfgPath)) {
                    Write-Log "WARNING: snapshot_path '$cfgPath' not found, falling through." -Color Yellow
                } else {
                    $effectiveSnapshotFile = $cfgPath
                    $snapshotSource = "umeairt-user-config.json"
                }
            }
        } catch {
            Write-Log "WARNING: Could not read snapshot_path from config: $($_.Exception.Message)" -Color Yellow
        }
    }
}

# Priority 3+4: interactive prompt
if ($null -eq $effectiveSnapshotFile) {
    Write-Host ""
    Write-Host "  *** CUSTOM NODE PROTECTION ***"
    Write-Host ""
    Write-Host "  If you have installed custom nodes beyond what UmeAiRT ships by default,"
    Write-Host "  answer YES to save a snapshot of your current setup before updating."
    Write-Host "  Your snapshot will be used to restore any nodes that go missing after the update."
    Write-Host ""
    Write-Host "  Answer NO only if your current install is broken and you want to start fresh,"
    Write-Host "  or if you intentionally want to reset to UmeAiRT's default node set."
    Write-Host ""
    $answer = (Read-Host "  Protect your custom nodes? [Y/n]").Trim()
    if ($answer -eq "" -or $answer -match "^[Yy]") {
        try {
            Invoke-AndLog $pythonExe "`"$cmCliScript`" save-snapshot --output `"$userSnapshotFile`""
            if (Test-Path $userSnapshotFile) {
                $effectiveSnapshotFile = $userSnapshotFile
                $snapshotSource = "auto-saved (this run)"
            } else {
                Write-Log "WARNING: save-snapshot ran but file not found, falling through." -Color Yellow
            }
        } catch {
            Write-Log "WARNING: save-snapshot failed: $($_.Exception.Message)" -Color Yellow
        }
    }
    # Priority 4: pre-existing user-snapshot.json
    if ($null -eq $effectiveSnapshotFile -and (Test-Path $userSnapshotFile)) {
        $effectiveSnapshotFile = $userSnapshotFile
        $snapshotSource = "existing user-snapshot.json"
    }
    # Priority 5: upstream fallback
    if ($null -eq $effectiveSnapshotFile -and (Test-Path $upstreamSnapshotFile)) {
        $effectiveSnapshotFile = $upstreamSnapshotFile
        $snapshotSource = "upstream snapshot.json (fallback)"
        Write-Log "NOTE: Using upstream snapshot — consider saving your own via ComfyUI Manager." -Color Yellow
    }
}

if ($effectiveSnapshotFile) {
    Write-Log "Snapshot: $snapshotSource" -Color Cyan
}

# --- F. Global Update Strategy ---

# 1. Restore Snapshot to ensure all nodes are present
if ($null -ne $effectiveSnapshotFile -and (Test-Path $effectiveSnapshotFile)) {
    Write-Log "Install missing nodes first..." -Level 1 -Color Cyan
    try {
        Invoke-AndLog $pythonExe "`"$cmCliScript`" restore-snapshot `"$effectiveSnapshotFile`""
    } catch {
        Write-Log "WARNING: Snapshot restore encountered issues." -Level 1 -Color Yellow
    }
} else {
    Write-Log "WARNING: No snapshot available, skipping restore-snapshot." -Color Yellow
}

# 2. Update All Nodes (New & Existing)
Write-Log "Performing GLOBAL UPDATE of all custom nodes..." -Level 1 -Color Cyan
try {
    # 'update all' handles git pulls, requirements.txt, and install.py scripts automatically
    Invoke-AndLog $pythonExe "`"$cmCliScript`" update all"
    Write-Log "All custom nodes updated successfully via CLI!" -Level 1 -Color Green
} catch {
    Write-Log "ERROR: Global update failed. Check logs." -Level 1 -Color Red
}

# --- 3. Update Optimized Components (Triton/SageAttention) ---
Write-Log "Updating Optimized Components (Triton/SageAttention)..." -Level 0 -Color Green
$installerInfo = $dependencies.files.installer_script
$installerDest = "$InstallPath/$($installerInfo.destination.Replace('\','/'))"

try {
    # Always download fresh to get latest logic
    $installerSha256 = if ($installerInfo.PSObject.Properties["sha256"]) { [string]$installerInfo.sha256 } else { "" }
    Save-File -Uri $installerInfo.url -OutFile $installerDest -ExpectedHash $installerSha256

    if (Test-Path $installerDest) {
        Write-Log "Executing DazzleML Installer (Upgrade Mode)..." -Level 1
        Invoke-AndLog $pythonExe "`"$installerDest`" --upgrade --non-interactive --base-path `"$comfyPath`" --python `"$pythonExe`""
    }
}
catch {
    Write-Log "Error updating optimized components: $($_.Exception.Message)" -Level 1 -Color Red
}

# --- Cleanup Env Vars ---
$env:PYTHONPATH = $env:PYTHONPATH -replace [regex]::Escape("$comfyPath;"), ""
$env:PYTHONPATH = $env:PYTHONPATH -replace [regex]::Escape("$managerPath;"), ""
$env:COMFYUI_PATH = $null

Write-Log "===============================================================================" -Level -2
Write-Log "Update process complete!" -Level -2 -Color Yellow
Write-Log "===============================================================================" -Level -2
