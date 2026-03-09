<#
.SYNOPSIS
    Phase 2 of the ComfyUI Auto-Installer (Environment Setup & Dependencies).
.DESCRIPTION
    This script runs inside the configured environment (venv or Conda).
    It handles:
    - Cloning ComfyUI.
    - Setting up the external folder architecture (linking 'models', 'custom_nodes', etc.).
    - Installing Python dependencies (pip, torch, etc.).
    - Installing Custom Nodes via ComfyUI-Manager CLI (snapshot or CSV).
    - Installing Triton and SageAttention via DazzleML.
    - Downloading optional model packs.
.PARAMETER InstallPath
    The root directory for the installation.
#>

#===========================================================================
# SECTION 1: SCRIPT CONFIGURATION & HELPER FUNCTIONS
#===========================================================================

param(
    [string]$InstallPath = ((Split-Path -Path $PSScriptRoot -Parent).Replace('\', '/'))
)

$InstallPath = $InstallPath.TrimEnd('\', '/').Replace('\', '/')

# --- Encoding Support (CJK/Accents) ---
# Force Windows Console to use UTF-8 (Code Page 65001)
# This prevents UnicodeDecodeError when Python subprocess reads output containing accents (e.g. byte 0xfc)
$null = chcp 65001

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

# Force Python to strictly use UTF-8 for all IO operations
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

# --- Paths ---
$comfyPath = "$InstallPath/ComfyUI"
$comfyUserPath = "$comfyPath/user"
$scriptPath = "$InstallPath/scripts"
$logPath = "$InstallPath/logs"
$logFile = "$logPath/install_log.txt"

# --- Security Protocol ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Load Dependencies ---
$dependenciesFile = "$($scriptPath)/dependencies.json"
if (-not (Test-Path $dependenciesFile)) {
    Write-Host "FATAL: dependencies.json not found..." -ForegroundColor Red
    Read-Host
    exit 1
}
$dependencies = Get-Content -Raw -Path $dependenciesFile | ConvertFrom-Json

# --- Create Log Directory ---
if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Force -Path $logPath | Out-Null }

# --- Import Utilities ---
Import-Module "$scriptPath/UmeAiRTUtils.psm1" -Force
$global:logFile = "$logPath/install_log.txt"
$global:hasGpu = Test-NvidiaGpu

#===========================================================================
# SECTION 1.5: ENVIRONMENT DETECTION (SAFETY NET)
#===========================================================================
# This ensures we use the correct Python executable even if the .bat launcher wasn't used.

$installTypeFile = "$scriptPath/install_type"
$pythonExe = "python" # Default fallback (relies on PATH)

if (Test-Path $installTypeFile) {
    $iType = Get-Content -Path $installTypeFile -Raw
    $iType = $iType.Trim()

    if ($iType -eq "venv") {
        $venvPython = "$scriptPath/venv/Scripts/python.exe"
        if (Test-Path $venvPython) {
            $pythonExe = $venvPython
            Write-Log "VENV MODE DETECTED: Using $pythonExe" -Level 1 -Color Cyan
        }
    }
    elseif ($iType -eq "conda") {
        # Checks specifically for the UmeAiRT environment python
        $condaEnvPython = "$($env:LOCALAPPDATA.Replace('\','/'))/Miniconda3/envs/UmeAiRT/python.exe"
        if (Test-Path $condaEnvPython) {
            $pythonExe = $condaEnvPython
            Write-Log "CONDA MODE DETECTED: Using $pythonExe" -Level 1 -Color Cyan
        }
    }
}
else {
    Write-Log "WARNING: Installation type not detected. Using system Python (if available)." -Level 1 -Color Yellow
}

#===========================================================================
# SECTION 2: MAIN SCRIPT EXECUTION
#===========================================================================
$global:totalSteps = 9
$global:currentStep = 2
$totalCores = [int]$env:NUMBER_OF_PROCESSORS
$optimalParallelJobs = [int][Math]::Floor(($totalCores * 3) / 4)
if ($optimalParallelJobs -lt 1) { $optimalParallelJobs = 1 }

# --- Step 1: Git Configuration ---
Write-Log "Configuring Git to handle long paths (system-wide)..." -Level 1
try { Invoke-AndLog "git" "config --system core.longpaths true" -IgnoreErrors } catch { Write-Log "Warning: Failed to set git config (might need admin)." -Level 2 -Color Yellow }

# --- Step 2: Clone ComfyUI ---
Write-Log "Cloning ComfyUI" -Level 0
if (-not (Test-Path $comfyPath)) {
    Write-Log "Cloning ComfyUI repository from $($dependencies.repositories.comfyui.url)..." -Level 1
    $cloneArgs = "clone $($dependencies.repositories.comfyui.url) `"$comfyPath`""
    Invoke-AndLog "git" $cloneArgs

    if (-not (Test-Path $comfyPath)) {
        Write-Log "FATAL: ComfyUI cloning failed. Please check the logs." -Level 0 -Color Red
        Read-Host "Press Enter to exit."
        exit 1
    }
}
else {
    Write-Log "ComfyUI directory already exists" -Level 1 -Color Green
}

#===========================================================================
# SECTION 2.5: ARCHITECTURE SETUP (External Folders)
#===========================================================================
Write-Log "Configuring External Folders Architecture..." -Level 0

$externalFolders = @("custom_nodes", "models", "output", "input", "user")

foreach ($folder in $externalFolders) {
    $externalPath = "$InstallPath/$folder"
    $internalPath = "$comfyPath/$folder"

    # Check if the internal folder exists (Standard ComfyUI folder from git clone)
    if (Test-Path $internalPath) {
        $item = Get-Item $internalPath
        # Only process if it's a real folder, not already a junction
        if ($item.Attributes -notmatch "ReparsePoint") {
            
            if (-not (Test-Path $externalPath)) {
                # CASE 1: External does NOT exist.
                # We MOVE the internal folder to external. This preserves subfolders (checkpoints, loras, vae...)!
                Write-Log "Moving default structure of '$folder' to external location..." -Level 1
                Move-Item -Path $internalPath -Destination $externalPath -Force
            }
            else {
                # CASE 2: External ALREADY exists (Previous install).
                # We COPY content from internal to external (to fill missing default folders), then delete internal.
                Write-Log "External '$folder' detected. Merging default structure..." -Level 1
                Copy-Item -Path "$internalPath/*" -Destination $externalPath -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -Path $internalPath -Recurse -Force
            }
        }
    }
    elseif (-not (Test-Path $externalPath)) {
        # CASE 3: Neither exist (rare). Create empty external.
        New-Item -ItemType Directory -Force -Path $externalPath | Out-Null
    }

    # Create Junction (Internal -> External)
    if (-not (Test-Path $internalPath)) {
        cmd /c "mklink /J `"$($internalPath.Replace('/','\'))`" `"$($externalPath.Replace('/','\'))`"" | Out-Null
        Write-Log "Linked ComfyUI\$folder -> $folder (External)" -Level 1 -Color Cyan
    }
}

#===========================================================================
# BACK TO INSTALLATION
#===========================================================================

# --- Step 3: Install Core Dependencies ---
Write-Log "Installing Core Dependencies" -Level 0

# Check for ninja and install if missing
try {
    $ninjaCheck = & $pythonExe -m pip show ninja 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Installing ninja..." -Level 1
        Invoke-AndLog "uv" "pip install --python `"$pythonExe`" ninja"
    }
}
catch {
    Write-Log "Installing ninja..." -Level 1
    Invoke-AndLog "uv" "pip install --python `"$pythonExe`" ninja"
}

Write-Log "Upgrading pip and wheel" -Level 1
Invoke-AndLog "uv" "pip install --python `"$pythonExe`" --upgrade $($dependencies.pip_packages.upgrade -join ' ')"
Write-Log "Installing torch packages" -Level 1
Invoke-AndLog "uv" "pip install --python `"$pythonExe`" $($dependencies.pip_packages.torch.packages) --index-url $($dependencies.pip_packages.torch.index_url)"

Write-Log "Installing ComfyUI requirements" -Level 1
Invoke-AndLog "uv" "pip install --python `"$pythonExe`" -r `"$comfyPath/$($dependencies.pip_packages.comfyui_requirements)`""

# --- Step 4: Install Final Python Dependencies ---
Write-Log "Installing Python Dependencies" -Level 0
Write-Log "Installing standard packages..." -Level 1
Invoke-AndLog "uv" "pip install --python `"$pythonExe`" $($dependencies.pip_packages.standard -join ' ')"

# --- Step 5: Install Custom Nodes (via ComfyUI-Manager CLI) ---
Write-Log "Installing Custom Nodes via Manager CLI" -Level 0

# Thanks to junctions, we target the internal path, but data is stored externally!
$internalCustomNodes = "$comfyPath/custom_nodes"
Write-Log "Installing UmeAiRT Sync Manager (Core Component)..." -Level 1

# 1. Install ComfyUI-Manager FIRST (Required for CLI)
$managerPath = "$internalCustomNodes/ComfyUI-Manager"
if (-not (Test-Path $managerPath)) {
    Write-Log "Installing ComfyUI-Manager (Required for CLI)..." -Level 1 -Color Cyan
    Invoke-AndLog "git" "clone https://github.com/ltdrdata/ComfyUI-Manager.git `"$managerPath`""
}

# 2. Dependencies
$managerReqs = "$managerPath/requirements.txt"
if (Test-Path $managerReqs) {
    Write-Log "Installing ComfyUI-Manager dependencies (typer, etc.)..." -Level 1
    Invoke-AndLog "uv" "pip install --python `"$pythonExe`" -r `"$managerReqs`""
}

# 2b. Enable uv in ComfyUI Manager config
Set-ManagerUseUv -InstallPath $InstallPath

# 3. CLI Execution
$cmCliScript = "$managerPath/cm-cli.py"
$snapshotFile = "$scriptPath/snapshot.json"

# Set PYTHONPATH so the Manager finds its local modules (utils, etc.)
$env:PYTHONPATH = "$comfyPath;$managerPath;$env:PYTHONPATH"
$env:COMFYUI_PATH = $comfyPath

if (Test-Path $snapshotFile) {
    # --- METHOD A: Snapshot (Recommended) ---
    Write-Log "Installing custom nodes from snapshot.json..." -Level 1 -Color Cyan
    Write-Log "This may take a while as it installs all nodes and dependencies..." -Level 2
    
    try {
        # Using 'restore-snapshot' command
        Invoke-AndLog $pythonExe "`"$cmCliScript`" restore-snapshot `"$snapshotFile`""
        Write-Log "Custom nodes installation complete!" -Level 1 -Color Green
    }
    catch {
        Write-Log "ERROR: Snapshot restoration failed. Check logs." -Level 1 -Color Red
    }

}
else {
    # --- METHOD B: Fallback to CSV ---
    Write-Log "No snapshot.json found. Falling back to custom_nodes.csv..." -Level 1 -Color Yellow
    
    $csvPath = "$InstallPath/$($dependencies.files.custom_nodes_csv.destination.Replace('\','/'))"
    if (Test-Path $csvPath) {
        $customNodes = Import-Csv -Path $csvPath
        $successCount = 0
        $failCount = 0

        foreach ($node in $customNodes) {
            $nodeName = $node.Name
            $repoUrl = $node.RepoUrl
            $possiblePath = "$internalCustomNodes/$nodeName"

            if (-not (Test-Path $possiblePath)) {
                Write-Log "Installing $nodeName via CLI..." -Level 1
                try {
                    Invoke-AndLog $pythonExe "`"$cmCliScript`" install $repoUrl"
                    $successCount++
                }
                catch {
                    Write-Log "Failed to install $nodeName via CLI." -Level 2 -Color Red
                    $failCount++
                }
            }
            else {
                Write-Log "$nodeName already exists." -Level 1 -Color Green
                $successCount++
            }
        }
        Write-Log "Custom nodes installation summary: $successCount processed." -Level 1
    }
    else {
        Write-Log "WARNING: Neither snapshot.json nor custom_nodes.csv were found." -Level 1 -Color Red
    }
}

# UmeAiRT-Sync installation
$umeSyncPath = "$internalCustomNodes/ComfyUI-UmeAiRT-Sync"
if (-not (Test-Path $umeSyncPath)) {
    Write-Log "Installing ComfyUI-UmeAiRT-Sync (for workflows auto-update)..." -Level 1 -Color Cyan
    Invoke-AndLog "git" "clone https://github.com/UmeAiRT/ComfyUI-UmeAiRT-Sync.git `"$umeSyncPath`""
    if (Test-Path "$umeSyncPath/requirements.txt") {
        Invoke-AndLog "uv" "pip install --python `"$pythonExe`" -r `"$umeSyncPath/requirements.txt`""
    }
}
else {
    Write-Log "UmeAiRT Sync Manager already installed." -Level 1 -Color Green
}

# ===========================================================================
# HOTFIX: ComfyUI-MagCache (Line 13 Import Fix)
# ===========================================================================
$magCacheFolder = "$internalCustomNodes/ComfyUI-MagCache"
$filesToPatch = @("nodes.py", "nodes_calibration.py")

foreach ($fileName in $filesToPatch) {
    $targetFile = "$magCacheFolder/$fileName"

    if (Test-Path $targetFile) {
        Write-Log "Applying Hotfix to $fileName (Line 13)..." -Level 1
        try {
            $content = Get-Content -Path $targetFile
            
            # Safety check: Ensure file has enough lines
            if ($content.Count -ge 13) {
                # Modify line 13 (Index 12)
                $content[12] = "from comfy.ldm.lightricks.model import LTXBaseModel"
                
                # Save modifications
                Set-Content -Path $targetFile -Value $content -Encoding UTF8
                Write-Log "Hotfix applied successfully to $fileName." -Level 2 -Color Green
            }
            else {
                Write-Log "WARNING: Could not patch $fileName, file is too short." -Level 2 -Color Yellow
            }
        }
        catch {
            Write-Log "ERROR: Failed to apply hotfix to $fileName." -Level 2 -Color Red
        }
    }
}

# --- CLEANUP ENV VARS ---
$env:PYTHONPATH = $env:PYTHONPATH -replace [regex]::Escape("$comfyPath;"), ""
$env:PYTHONPATH = $env:PYTHONPATH -replace [regex]::Escape("$managerPath;"), ""
$env:COMFYUI_PATH = $null


# --- Step 6: Additional Packages from .whl ---
Write-Log "Installing packages from .whl files..." -Level 1
foreach ($wheel in $dependencies.pip_packages.wheels) {
    Write-Log "Installing $($wheel.name)" -Level 2
    $wheelPath = "$scriptPath/$($wheel.name).whl"
     
    try {
        $wheelSha256 = if ($wheel.PSObject.Properties["sha256"]) { [string]$wheel.sha256 } else { "" }
        Save-File -Uri $wheel.url -OutFile $wheelPath -ExpectedHash $wheelSha256

        if (Test-Path $wheelPath) {
            Invoke-AndLog "uv" "pip install --python `"$pythonExe`" `"$wheelPath`""
            Write-Log "$($wheel.name) installed successfully" -Level 3 -Color Green
            Remove-Item $wheelPath -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Log "Failed to download/install $($wheel.name) (continuing...)" -Level 3 -Color Yellow
    }
}

# --- Step 6b: Install Triton and SageAttention (Smart Hybrid Mode) ---
Write-Log "Installing Triton and SageAttention..." -Level 1

# Detect Environment Type
$isConda = [bool]($env:CONDA_PREFIX)

if (-not $isConda) {
    # ==============================================================================
    # OPTION A: STANDARD VENV (Use DazzleML Optimizer)
    # This is the preferred method. It works perfectly in Venv.
    # ==============================================================================
    Write-Log "Venv detected. Using DazzleML Optimized Installer..." -Level 1 -Color Cyan
    
    $installerInfo = $dependencies.files.installer_script
    $installerDest = "$InstallPath/$($installerInfo.destination.Replace('\','/'))"

    try {
        $dazzleSha256 = if ($installerInfo.PSObject.Properties["sha256"]) { [string]$installerInfo.sha256 } else { "" }
        Save-File -Uri $installerInfo.url -OutFile $installerDest -ExpectedHash $dazzleSha256

        if (Test-Path $installerDest) {
            # Execute the smart installer script
            Invoke-AndLog $pythonExe "`"$installerDest`" --install --non-interactive --base-path `"$comfyPath`" --python `"$pythonExe`""
        }
        else {
            Write-Log "Failed to download installer script." -Level 2 -Color Red
        }
    }
    catch {
        Write-Log "Error during optimized installation: $($_.Exception.Message)" -Level 2 -Color Red
    }
}
else {
    # ==============================================================================
    # OPTION B: CONDA MODE (Manual Safe Install)
    # The DazzleML script crashes in Conda (NoneType error on paths).
    # We use a manual fallback here to ensure stability.
    # ==============================================================================
    Write-Log "Conda detected. Using Manual Safe Mode to prevent installer crash..." -Level 1 -Color Yellow

    # 1. Fix CUDA_HOME for Conda
    if ($env:CUDA_PATH) {
        $env:CUDA_HOME = $env:CUDA_PATH
    }

    # 2. Install Triton-Windows (Official PyPI for Py3.13)
    Write-Log "Installing Triton-Windows..." -Level 2
    Invoke-AndLog "uv" "pip install --python `"$pythonExe`" triton-windows --no-warn-script-location"

    # 3. Install SageAttention (Direct Install)
    Write-Log "Installing SageAttention..." -Level 2
    try {
        Invoke-AndLog "uv" "pip install --python `"$pythonExe`" sageattention --no-warn-script-location --no-build-isolation"
        Write-Log "SageAttention installed successfully." -Level 2 -Color Green
    }
    catch {
        Write-Log "WARNING: Standard install failed. Retrying without dependency check..." -Level 2 -Color Yellow
        Invoke-AndLog "uv" "pip install --python `"$pythonExe`" sageattention --no-deps --no-warn-script-location --no-build-isolation"
    }
}

# --- Nunchaku Configuration Section ---

# 1. Define variables
$JsonUrl = "https://raw.githubusercontent.com/UmeAiRT/ComfyUI-Auto_installer/main/scripts/nunchaku_versions.json" 
$TargetDir = "$comfyPath/custom_nodes/ComfyUI-nunchaku"
$TargetFile = "$TargetDir/nunchaku_versions.json"

Write-Log "Configuring nunchaku_versions.json..." -Level 1 -Color Cyan

# 2. Create the directory if it doesn't exist
if (-not (Test-Path $TargetDir)) {
    Write-Log "Directory 'ComfyUI-nunchaku' not found. Creating it..." -Level 1
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
}

# 3. Download the file
try {
    Write-Log "Downloading configuration file from UmeAiRT repository..." -Level 1
    $nunchakuJsonSha256 = if ($dependencies.files.PSObject.Properties["nunchaku_versions"] -and $dependencies.files.nunchaku_versions.PSObject.Properties["sha256"]) { [string]$dependencies.files.nunchaku_versions.sha256 } else { "" }
    Save-File -Uri $JsonUrl -OutFile $TargetFile -ExpectedHash $nunchakuJsonSha256
    Write-Log "Success: nunchaku_versions.json installed." -Level 1 -Color Green
}
catch {
    Write-Log "ERROR: Failed to download nunchaku_versions.json." -Level 2 -Color Red
    Write-Log "Details: $($_.Exception.Message)" -Level 2 -Color Red
    Write-Log "Make sure the file exists at: $JsonUrl" -Level 2 -Color Gray
}

# --- End of Nunchaku Configuration ---

Write-Log "Downloading ComfyUI custom settings..." -Level 1
$settingsFile = $dependencies.files.comfy_settings
$settingsDest = "$InstallPath/$($settingsFile.destination.Replace('\','/'))"
$settingsDir = (Split-Path $settingsDest -Parent).Replace('\', '/')
if (-not (Test-Path $settingsDir)) { New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null }
$settingsSha256 = if ($settingsFile.PSObject.Properties["sha256"]) { [string]$settingsFile.sha256 } else { "" }
Save-File -Uri $settingsFile.url -OutFile $settingsDest -ExpectedHash $settingsSha256


# --- Step 7: Optional Model Pack Downloads ---
Write-Log "Optional Model Pack Downloads" -Level 0

$modelPacks = @(
    @{Name = "FLUX"; ScriptName = "Download-FLUX-Models.ps1" },
    @{Name = "WAN2.1"; ScriptName = "Download-WAN2.1-Models.ps1" },
    @{Name = "WAN2.2"; ScriptName = "Download-WAN2.2-Models.ps1" },
    @{Name = "HIDREAM"; ScriptName = "Download-HIDREAM-Models.ps1" },
    @{Name = "LTX1"; ScriptName = "Download-LTX1-Models.ps1" },
    @{Name = "LTX2"; ScriptName = "Download-LTX2-Models.ps1" },
    @{Name = "QWEN"; ScriptName = "Download-QWEN-Models.ps1" },
    @{Name = "Z-IMAGE"; ScriptName = "Download-Z-IMAGES-Models.ps1" }
)
$scriptsSubFolder = "$InstallPath/scripts"

foreach ($pack in $modelPacks) {
    $packScriptPath = "$scriptsSubFolder/$($pack.ScriptName)"
    if (-not (Test-Path $packScriptPath)) {
        Write-Log "Model downloader script not found: '$($pack.ScriptName)'. Skipping." -Level 1 -Color Red
        continue
    }

    $validInput = $false
    while (-not $validInput) {
        Write-Log "Would you like to download $($pack.Name) models? (Y/N)" -Level 1 -Color Yellow
        $choice = Read-Host

        if ($choice -eq 'Y' -or $choice -eq 'y') {
            Write-Log "Launching downloader for $($pack.Name) models..." -Level 2 -Color Green
            # External script call: We pass InstallPath
            & $packScriptPath -InstallPath $InstallPath
            $validInput = $true
        }
        elseif ($choice -eq 'N' -or $choice -eq 'n') {
            Write-Log "Skipping download for $($pack.Name) models." -Level 2
            $validInput = $true
        }
        else {
            Write-Log "Invalid choice. Please enter Y or N." -Level 2 -Color Red
        }
    }
}

#===========================================================================
# FINALIZATION
#===========================================================================
Write-Log "-------------------------------------------------------------------------------" -Color Green
Write-Log "Installation of ComfyUI and all nodes is complete!" -Color Green
Read-Host "Press Enter to close this window."
