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
.PARAMETER v
    Verbose mode: show [INFO] messages and command output on success.
.PARAMETER vv
    Extra-verbose mode: all of -v, plus print each command line before running it.
.PARAMETER BootstrapOnly
    Download all scripts fresh from the configured source and exit without running the update.
    Use this to repair a bit-rotted install before running the full update.
#>

param(
    [string]$InstallPath    = ((Split-Path -Path $PSScriptRoot -Parent).Replace('\', '/')),
    [string]$SnapshotPath   = "",
    [string]$GhUser         = "",   # empty = read from config
    [string]$GhRepoName     = "",
    [string]$GhBranch       = "",
    [switch]$v,                     # -v  : show [INFO] messages + command output on success
    [switch]$vv,                    # -vv : all of -v + print each command line before running
    [switch]$BootstrapOnly          # download fresh scripts and exit; run again to update
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
$logFile = "$logPath/update.log"
$scriptPath = "$InstallPath/scripts"

$dependenciesFile = "$scriptPath/dependencies.json"

if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Force -Path $logPath | Out-Null }

# --- Inline config reader (no module dependency — runs before bootstrap) ---
function _ReadCfgValue {
    param([string]$File, [string]$Key)
    if (-not (Test-Path $File)) { return "" }
    try {
        $j = Get-Content $File -Raw | ConvertFrom-Json
        if ($j.PSObject.Properties[$Key] -and $j.$Key) { return [string]$j.$Key }
    } catch {}
    return ""
}

if (-not $GhUser) {
    foreach ($f in @("$InstallPath/umeairt-user-config.json", "$InstallPath/repo-config.json")) {
        if (-not $GhUser)     { $GhUser     = _ReadCfgValue $f "gh_user" }
        if (-not $GhRepoName) { $GhRepoName = _ReadCfgValue $f "gh_reponame" }
        if (-not $GhBranch)   { $GhBranch   = _ReadCfgValue $f "gh_branch" }
    }
    if (-not $GhUser)     { $GhUser     = "UmeAiRT" }
    if (-not $GhRepoName) { $GhRepoName = "ComfyUI-Auto_installer" }
    if (-not $GhBranch)   { $GhBranch   = "main" }
}

# --- Bootstrap: download fresh scripts BEFORE importing module ---
$bootstrapUrl    = "https://raw.githubusercontent.com/$GhUser/$GhRepoName/$GhBranch/scripts/Bootstrap-Downloader.ps1"
$bootstrapScript = "$($PSScriptRoot.Replace('\','/'))/Bootstrap-Downloader.ps1"
Write-Host "[INFO] Updating scripts from $GhUser/$GhRepoName @ $GhBranch..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $bootstrapUrl -OutFile $bootstrapScript -UseBasicParsing -ErrorAction Stop
    & $bootstrapScript -InstallPath $InstallPath -GhUser $GhUser -GhRepoName $GhRepoName -GhBranch $GhBranch
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] Bootstrap completed with download failures — some files may not be updated. Check logs/bootstrap.log." -ForegroundColor Yellow
    } else {
        Write-Host "[OK] All scripts are up-to-date." -ForegroundColor Green
    }
} catch {
    Write-Host "[WARN] Bootstrap self-update failed: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "[WARN] Continuing with existing scripts." -ForegroundColor Yellow
}

if ($BootstrapOnly) {
    Write-Host ""
    Write-Host "[OK] Scripts refreshed from $GhUser/$GhRepoName @ $GhBranch." -ForegroundColor Green
    Write-Host "     Run the updater again (without -BootstrapOnly) to proceed with the update." -ForegroundColor Cyan
    Read-Host "Press Enter to exit."
    exit 0
}

# --- Import module (now guaranteed fresh from bootstrap above) ---
Import-Module "$($PSScriptRoot.Replace('\','/'))/UmeAiRTUtils.psm1" -Force
Invoke-LogRotation "$logPath/update.log"
Invoke-LogRotation "$logPath/bootstrap.log"
$global:logFile = $logFile
$global:Verbosity = if ($vv) { 2 } elseif ($v) { 1 } else { 0 }
$global:totalSteps = 4
$global:currentStep = 0

# --- Migrate repo-config.json → umeairt-user-config.json (one-time, for pre-fix/network-exposure installs) ---
$userConfigFile  = "$InstallPath/umeairt-user-config.json"
$legacyConfigFile = "$InstallPath/repo-config.json"
if (-not (Test-Path $userConfigFile) -and (Test-Path $legacyConfigFile)) {
    Write-Log "Migrating repo-config.json → umeairt-user-config.json..." -Color Cyan
    try {
        $legacy = Get-Content $legacyConfigFile -Raw | ConvertFrom-Json
        $newCfg = [ordered]@{
            "_comment"             = @(
                "Migrated automatically from repo-config.json on first update to fix/network-exposure or later.",
                "This file will NEVER be overwritten by bootstrap or updates.",
                "Do NOT commit umeairt-user-config.json — it is personal to your machine.",
                "Leave any field as its default value (or remove it entirely) to use the built-in default."
            )
            "_section_repository"  = "--- Fork / Repository Source ---"
            "_comment_repository"  = @(
                "Override the GitHub repository that bootstrap downloads scripts from.",
                "Useful if you are running a fork. Leave all three empty to use the upstream defaults."
            )
            gh_user        = if ($legacy.PSObject.Properties['gh_user']     -and $legacy.gh_user)     { [string]$legacy.gh_user }     else { "" }
            gh_reponame    = if ($legacy.PSObject.Properties['gh_reponame'] -and $legacy.gh_reponame) { [string]$legacy.gh_reponame } else { "" }
            gh_branch      = if ($legacy.PSObject.Properties['gh_branch']   -and $legacy.gh_branch)   { [string]$legacy.gh_branch }   else { "" }
            "_section_listen"      = "--- Network Listen Configuration ---"
            "_comment_listen"      = @(
                "By default ComfyUI binds to 127.0.0.1 (localhost only).",
                "Set listen_enabled to true AND provide a listen_address to expose ComfyUI on additional interfaces.",
                "WARNING: '0.0.0.0' or '::' exposes ComfyUI to ALL network interfaces."
            )
            listen_enabled = $false
            listen_address = ""
            listen_port    = 8188
            "_section_snapshot"    = "--- Custom Node Snapshot ---"
            "_comment_snapshot"    = @(
                "Optional path to a snapshot file to use during updates.",
                "Leave empty to be prompted each time (recommended: saves current nodes first)."
            )
            snapshot_path  = ""
        }
        $newCfg | ConvertTo-Json -Depth 10 | Set-Content -Path $userConfigFile -Encoding UTF8
        # repo-config.json intentionally left in place — old Update bat still reads it for fork settings
        # until the bat itself gets updated by bootstrap on this run.
        Write-Log "Migration complete. repo-config.json left in place for compatibility." -Color Green
    } catch {
        Write-Log "WARNING: Migration failed: $($_.Exception.Message). Falling back to repo-config.json." -Color Yellow
    }
}

# --- Load dependencies.json after bootstrap so we always use the freshly-downloaded version ---
if (-not (Test-Path $dependenciesFile)) {
    Write-Log "FATAL: dependencies.json not found at '$dependenciesFile'. Cannot proceed." -Color Red
    Read-Host "Press Enter to exit."
    exit 1
}
$dependencies = Get-Content -Raw -Path $dependenciesFile | ConvertFrom-Json

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
    $isConda = ($installType -eq "conda")
} else {
    Write-Host "[WARN] 'install_type' file not found. Assuming System Python." -ForegroundColor Yellow
}

#===========================================================================
# SECTION 2: UPDATE PROCESS
#===========================================================================
Write-Log "===============================================================================" -Level -2
Write-Log "             Starting UmeAiRT ComfyUI Update Process" -Level -2 -Color Yellow
Write-Log "===============================================================================" -Level -2
Write-Log "Python Executable used: $pythonExe" -Level 1

# --- 1. Update Git Repositories (Core & Workflows) ---
Write-Log "Updating Core Git repositories..." -Level 0 -Color Green
Write-Log "Updating ComfyUI Core..." -Level 1
Invoke-AndLog "git" @("-C", $comfyPath, "pull")
Write-Log "Checking main ComfyUI requirements..." -Level 1
$mainReqs = "$comfyPath/requirements.txt"
Invoke-AndLog "uv" @("pip", "install", "--python", $pythonExe, "-r", $mainReqs)

# --- 2. Update and Install Custom Nodes (Manager CLI) ---
Write-Log "Updating/Installing Custom Nodes..." -Level 0 -Color Green

# --- A. Update ComfyUI-Manager FIRST ---
$managerPath = "$internalCustomNodesPath/ComfyUI-Manager"
Write-Log "Updating ComfyUI-Manager..." -Level 1
if (Test-Path $managerPath) {
    Invoke-AndLog "git" @("-C", $managerPath, "pull")
} else {
    Write-Log "ComfyUI-Manager missing. Installing..." -Level 2
    Invoke-AndLog "git" @("clone", "https://github.com/ltdrdata/ComfyUI-Manager.git", $managerPath)
}

# --- B. Update Manager Dependencies (Critical for CLI) ---
$managerReqs = "$managerPath/requirements.txt"
if (Test-Path $managerReqs) {
    Write-Log "Updating ComfyUI-Manager dependencies..." -Level 1
    Invoke-AndLog "uv" @("pip", "install", "--python", $pythonExe, "-r", $managerReqs)
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
            Invoke-AndLog $pythonExe @($cmCliScript, "save-snapshot", "--output", $userSnapshotFile)
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

# 0. Repair ComfyUI-nunchaku if it was installed as a zip extract (no .git directory).
#    This happened when the old mit-han-lab URL returned a zip instead of a git clone.
#    IMPORTANT: do NOT generalize this to all non-git dirs — Manager installs many nodes
#    as zips legitimately and they must not be removed here.
$customNodesPath = "$InstallPath/ComfyUI/custom_nodes"
$nunchakuDir = "$customNodesPath/ComfyUI-nunchaku"
if ((Test-Path $nunchakuDir) -and -not (Test-Path "$nunchakuDir/.git")) {
    Write-Log "ComfyUI-nunchaku has no .git directory — removing corrupt zip-extract for clean re-clone." -Level 1 -Color Yellow
    Remove-Item $nunchakuDir -Recurse -Force -ErrorAction SilentlyContinue
}

# 1. Restore Snapshot to ensure all nodes are present
if ($null -ne $effectiveSnapshotFile -and (Test-Path $effectiveSnapshotFile)) {
    Write-Log "Install missing nodes first..." -Level 1 -Color Cyan
    try {
        Invoke-AndLog $pythonExe @($cmCliScript, "restore-snapshot", $effectiveSnapshotFile)
    } catch {
        Write-Log "WARNING: Snapshot restore encountered issues — some nodes may be missing or broken." -Level 1 -Color Yellow
        Write-Log "  Check log for details: $($global:logFile)" -Level 1 -Color Yellow
    }
} else {
    Write-Log "WARNING: No snapshot available, skipping restore-snapshot." -Color Yellow
}

# 2. Update All Nodes (New & Existing)
Write-Log "Performing GLOBAL UPDATE of all custom nodes..." -Level 1 -Color Cyan
try {
    # 'update all' handles git pulls, requirements.txt, and install.py scripts automatically
    Invoke-AndLog $pythonExe @($cmCliScript, "update", "all")
    Write-Log "All custom nodes updated successfully via CLI!" -Level 1 -Color Green
} catch {
    Write-Log "ERROR: Custom node update failed — nodes may be out of date or broken." -Level 1 -Color Red
    Write-Log "  Check log for details: $($global:logFile)" -Level 1 -Color Red
}

# 2a. Re-pin managed wheels — cm-cli may downgrade packages like nunchaku via a node's own
#     pyproject.toml/uv.toml index (e.g. nunchaku's pypi/nunchaku_index.html only lists 1.0.1
#     for torch2.10). Reinstalling from our direct URLs bypasses those stale indices entirely.
Write-Log "Re-pinning managed wheels..." -Level 1 -Color Cyan
foreach ($wheel in $dependencies.pip_packages.wheels) {
    Write-Log "Re-pinning $($wheel.name)..." -Level 2
    try {
        Invoke-AndLog "uv" @("pip", "install", "--python", $pythonExe, $wheel.url)
        Write-Log "Re-pinned $($wheel.name)." -Level 2 -Color Green
    } catch {
        Write-Log "WARNING: Failed to re-pin $($wheel.name): $($_.Exception.Message)" -Level 2 -Color Yellow
    }
}

# --- 3. Update Optimized Components (Triton/SageAttention) ---
Write-Log "Updating Optimized Components (Triton/SageAttention)..." -Level 0 -Color Green

if (-not $isConda) {
    # ==============================================================================
    # OPTION A: VENV — Use DazzleML Optimizer
    # ==============================================================================
    $installerInfo = $dependencies.files.installer_script
    $installerDest = "$InstallPath/$($installerInfo.destination.Replace('\','/'))"

    try {
        # Always download fresh to get latest logic
        $installerSha256 = if ($installerInfo.PSObject.Properties["sha256"]) { [string]$installerInfo.sha256 } else { "" }
        Save-File -Uri $installerInfo.url -OutFile $installerDest -ExpectedHash $installerSha256 -Force

        if (Test-Path $installerDest) {
            Write-Log "Executing DazzleML Installer (Upgrade Mode)..." -Level 1
            Invoke-AndLog $pythonExe @($installerDest, "--upgrade", "--non-interactive", "--base-path", $comfyPath, "--python", $pythonExe)
        }
    }
    catch {
        Write-Log "Error updating optimized components: $($_.Exception.Message)" -Level 1 -Color Red
    }
}
else {
    # ==============================================================================
    # OPTION B: CONDA — Manual upgrade (DazzleML crashes in Conda environments)
    # ==============================================================================
    Write-Log "Conda detected. Using Manual Safe Mode to prevent installer crash..." -Level 1 -Color Yellow

    # Fix CUDA_HOME for Conda build tools
    if ($env:CUDA_PATH) { $env:CUDA_HOME = $env:CUDA_PATH }

    Write-Log "Upgrading Triton-Windows..." -Level 2
    Invoke-AndLog "uv" @("pip", "install", "--python", $pythonExe, "triton-windows", "--no-warn-script-location")

    Write-Log "Upgrading SageAttention..." -Level 2
    try {
        Invoke-AndLog "uv" @("pip", "install", "--python", $pythonExe, "sageattention", "--no-warn-script-location", "--no-build-isolation")
        Write-Log "SageAttention upgraded successfully." -Level 2 -Color Green
    }
    catch {
        Write-Log "WARNING: Standard upgrade failed. Retrying without dependency check..." -Level 2 -Color Yellow
        Invoke-AndLog "uv" @("pip", "install", "--python", $pythonExe, "sageattention", "--no-deps", "--no-warn-script-location", "--no-build-isolation")
    }
}

# --- Cleanup Env Vars ---
$env:PYTHONPATH = $env:PYTHONPATH -replace [regex]::Escape("$comfyPath;"), ""
$env:PYTHONPATH = $env:PYTHONPATH -replace [regex]::Escape("$managerPath;"), ""
$env:COMFYUI_PATH = $null

Write-Log "===============================================================================" -Level -2
Write-Log "Update process complete!" -Level -2 -Color Yellow
Write-Log "===============================================================================" -Level -2
Read-Host "Press Enter to close."
