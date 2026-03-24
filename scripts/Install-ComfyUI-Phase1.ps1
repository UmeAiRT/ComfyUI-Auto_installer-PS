<#
.SYNOPSIS
    Phase 1 of the ComfyUI Auto-Installer.
.DESCRIPTION
    This script handles the initial setup of the environment:
    - Administrator privilege checks (VS Build Tools, Long Paths).
    - Installation of system dependencies (Git, Aria2, Python 3.13 or Miniconda).
    - Creation of the Python environment (venv or Conda).
    - Preparation of the launcher for Phase 2.
.PARAMETER InstallPath
    The root directory for the installation.
.PARAMETER RunAdminTasks
    Internal flag used when self-elevating to run administrative tasks.
#>

#===========================================================================
# SECTION 1: SCRIPT CONFIGURATION & HELPER FUNCTIONS
#===========================================================================

param(
    [string]$InstallPath,
    [switch]$RunAdminTasks # Flag for elevated mode
)

# --- Path Definitions ---
$comfyPath = Join-Path $InstallPath "ComfyUI"
$scriptPath = Join-Path $InstallPath "scripts"
$condaPath = Join-Path $env:LOCALAPPDATA "Miniconda3"
$condaExe = Join-Path $condaPath "Scripts\conda.exe"
$logPath = Join-Path $InstallPath "logs"
$logFile = Join-Path $logPath "install_log.txt"

# --- Security Protocol ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Load dependencies EARLY ---
$dependenciesFile = Join-Path $scriptPath "dependencies.json"
if (-not (Test-Path $dependenciesFile)) {
    Write-Host "FATAL: dependencies.json not found at '$dependenciesFile'..." -ForegroundColor Red
    Read-Host
    exit 1
}
try {
    $dependencies = Get-Content -Raw -Path $dependenciesFile | ConvertFrom-Json
} catch {
    Write-Host "FATAL: Failed to parse dependencies.json. Error: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host
    exit 1
}

# --- Create Log Directory ---
if (-not (Test-Path $logPath)) {
    try { New-Item -ItemType Directory -Force -Path $logPath | Out-Null }
    catch { Write-Host "WARN: Could not create log directory '$logPath'" -ForegroundColor Yellow }
}

# --- Helper Function: Check Admin Status ---
function Test-IsAdmin {
    try {
        $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
        return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

# --- Import Utilities ---
Import-Module (Join-Path $scriptPath "UmeAiRTUtils.psm1") -Force

#===========================================================================
# SECTION 2: MAIN SCRIPT EXECUTION
#===========================================================================
$global:totalSteps = 9 # Phase 1 = Setup Admin (if needed) + Setup Env + Launch Phase 2
$global:currentStep = 0

if ($RunAdminTasks) {
    # -------------------------------------------------------------------------
    # SUB-SECTION: Elevated Tasks (Admin Mode)
    # -------------------------------------------------------------------------
    Write-Host "`n=== Performing Administrator Tasks ===`n" -ForegroundColor Cyan

    # Task 1: Enable Long Paths
    Write-Host "[Admin Task 1/2] Enabling support for long paths (Registry)..." -ForegroundColor Yellow
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"; $regKey = "LongPathsEnabled"
    try {
        if ((Get-ItemPropertyValue -Path $regPath -Name $regKey -ErrorAction SilentlyContinue) -ne 1) {
            Set-ItemProperty -Path $regPath -Name $regKey -Value 1 -Type DWord -Force -ErrorAction Stop
            Write-Host "- Long path support enabled." -ForegroundColor Green
        }
        else { Write-Host "- Long path support already enabled." -ForegroundColor Green }
    }
    catch { Write-Host "- ERROR: Unable to enable long paths. $_" -ForegroundColor Red }

    # Task 2: VS Build Tools
    Write-Host "[Admin Task 2/2] Checking/Installing VS Build Tools..." -ForegroundColor Yellow
    $depFileAdmin = Join-Path $scriptPath "dependencies.json"
    $vsToolAdmin = $null
    if (Test-Path $depFileAdmin) {
        try { $depsAdmin = Get-Content -Raw -Path $depFileAdmin | ConvertFrom-Json } catch { $depsAdmin = $null }
        if ($depsAdmin -ne $null -and $depsAdmin.PSObject.Properties.Name -contains 'tools' -and $depsAdmin.tools.PSObject.Properties.Name -contains 'vs_build_tools') {
            $vsToolAdmin = $depsAdmin.tools.vs_build_tools
        }
    }
    if ($vsToolAdmin -ne $null -and $vsToolAdmin.install_path) {
        $vsInstallCheckPathAdmin = $ExecutionContext.InvokeCommand.ExpandString($vsToolAdmin.install_path)
        if (-not (Test-Path $vsInstallCheckPathAdmin)) {
            Write-Host "- Installing VS Build Tools..." -ForegroundColor Yellow
            $vsInstallerAdmin = Join-Path $env:TEMP "vs_buildtools_admin.exe"
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $vsToolAdmin.url -OutFile $vsInstallerAdmin -UseBasicParsing -ErrorAction Stop
                Write-Host "- Launching the VS Build Tools installer (may take some time)..."
                Start-Process -FilePath $vsInstallerAdmin -ArgumentList $vsToolAdmin.arguments -Wait -ErrorAction Stop
                Remove-Item $vsInstallerAdmin -ErrorAction SilentlyContinue
                Write-Host "- VS Build Tools installed." -ForegroundColor Green
            }
            catch { Write-Host "- ERROR: Failed to download/install VS Build Tools. $_" -ForegroundColor Red }
        }
        else { Write-Host "- VS Build Tools already installed." -ForegroundColor Green }
    }
    else { Write-Host "- ERROR: Unable to find VS Build Tools information in '$depFileAdmin'." -ForegroundColor Red }

    Write-Host "`n=== Administrative tasks completed. Closing this window. ===" -ForegroundColor Green
    Start-Sleep -Seconds 3
    exit 0

}
else {
    # -------------------------------------------------------------------------
    # SUB-SECTION: Standard User Tasks (Pre-Checks)
    # -------------------------------------------------------------------------
    $needsElevation = $false
    Write-Log "Checking for prerequisites that may require admin rights..." -Level 1

    # Check Long Paths
    if ((Get-ItemPropertyValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -ErrorAction SilentlyContinue) -ne 1) {
        Write-Log "Long path support must be enabled (Admin required)." -Level 2 -Color Yellow; $needsElevation = $true
    }
    else { Write-Log "Long path support OK." -Level 2 -Color Green }

    # Check VS Build Tools
    if ($dependencies -ne $null -and $dependencies.tools -ne $null -and $dependencies.tools.vs_build_tools -ne $null -and $dependencies.tools.vs_build_tools.install_path) {
        $vsInstallCheckPath = $ExecutionContext.InvokeCommand.ExpandString($dependencies.tools.vs_build_tools.install_path)
        if (-not (Test-Path $vsInstallCheckPath)) {
            Write-Log "VS Build Tools must be installed (Admin required)." -Level 2 -Color Yellow; $needsElevation = $true
        }
        else { Write-Log "VS Build Tools OK." -Level 2 -Color Green }
    }
    else { Write-Log "WARNING: Unable to verify VS Build Tools. Elevation may be required." -Level 2 -Color Yellow; $needsElevation = $true }

    # Elevate if needed
    if ($needsElevation -and -not (Test-IsAdmin)) {
        Write-Host "`nAdministrator privileges are required for initial setup." -ForegroundColor Yellow
        Write-Host "Re-running part of the script with elevation..." -ForegroundColor Yellow
        Write-Host "Please accept the UAC prompt." -ForegroundColor Yellow
        $psArgs = "-ExecutionPolicy Bypass -NoProfile -File `"$($MyInvocation.MyCommand.Definition)`" -RunAdminTasks -InstallPath `"$InstallPath`""
        try {
            $adminProcess = Start-Process powershell.exe -Verb RunAs -ArgumentList $psArgs -Wait -PassThru -ErrorAction Stop
            if ($adminProcess.ExitCode -ne 0) { throw "The administrator process failed (code $($adminProcess.ExitCode))." }
            Write-Host "`nAdmin configuration completed successfully. Resuming installation..." -ForegroundColor Green; Start-Sleep 2
        }
        catch {
            Write-Host "ERROR: Elevation failed or admin script failed: $($_.Exception.Message)" -ForegroundColor Red
            Read-Host "Press Enter to exit."; exit 1
        }
    }
    elseif ($needsElevation -and (Test-IsAdmin)) {
        Write-Host "`nWARNING: The script was run as Admin, but elevation was required." -ForegroundColor Yellow
        Write-Host "Admin tasks will be performed, but the rest will also run as Admin." -ForegroundColor Yellow
        Write-Log "[Admin Tasks within User Script] Performing Admin tasks..." -Level 1
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"; $regKey = "LongPathsEnabled"
        try { Set-ItemProperty -Path $regPath -Name $regKey -Value 1 -Type DWord -Force -ErrorAction Stop; Write-Log "[Admin] Long paths OK." -Level 2 } catch { Write-Log "[Admin] ERROR Long paths" -Level 2 -Color Red }
    }

    Clear-Host
    Write-Host "-------------------------------------------------------------------------------"
    $asciiBanner = @'
                          __  __               ___    _ ____  ______
                         / / / /___ ___  ___  /   |  (_) __ \/_  __/
                        / / / / __ `__ \/ _ \/ /| | / / /_/ / / / 
                       / /_/ / / / / / /  __/ ___ |/ / _, _/ / /
                       \____/_/ /_/ /_/\___/_/  |_/_/_/ |_| /_/
'@
    Write-Host $asciiBanner -ForegroundColor Cyan
    Write-Host "-------------------------------------------------------------------------------"
    Write-Host "                           ComfyUI - Auto-Installer                            " -ForegroundColor Yellow
    Write-Host "                                 Version 4.3                                   " -ForegroundColor White
    Write-Host "-------------------------------------------------------------------------------"

    # --- Step 0: Choose Installation Type ---
    $validChoices = @("1", "2")
    Write-Host "`nChoose installation type:" -ForegroundColor Cyan
    Write-Host "1. Light (Recommended) - Uses your existing Python 3.13 (Standard venv)" -ForegroundColor Green
    Write-Host "2. Full - Installs Miniconda, Python 3.13, Git, CUDA (Isolated environment)" -ForegroundColor Yellow

    $installTypeChoice = ""
    while ($installTypeChoice -notin $validChoices) {
        $installTypeChoice = Read-Host "Enter choice (1 or 2)"
    }
    $installType = if ($installTypeChoice -eq "1") { "Light" } else { "Full" }
    $installTypeFile = Join-Path $scriptPath "install_type"
    $phase2LauncherPath = Join-Path $scriptPath "Launch-Phase2.ps1"
    $phase2ScriptPath = Join-Path $scriptPath "Install-ComfyUI-Phase2.ps1"

    Write-Log "Checking/Installing aria2 (Download Accelerator)..." -Level 1
    $aria2Url = "https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip"
    $aria2ZipPath = Join-Path $env:TEMP "aria2.zip"
    $aria2InstallPath = Join-Path $env:LOCALAPPDATA "aria2"
    $aria2ExePath = Join-Path $aria2InstallPath "aria2c.exe"

    if (-not (Test-Path $aria2ExePath)) {
        Write-Log "Downloading aria2..." -Level 2
        try {
            Save-File -Uri $aria2Url -OutFile $aria2ZipPath
            Write-Log "Extracting aria2..." -Level 2
            if (-not (Test-Path $aria2InstallPath)) { New-Item -ItemType Directory -Path $aria2InstallPath -Force | Out-Null }
            Expand-Archive -Path $aria2ZipPath -DestinationPath $aria2InstallPath -Force
            $extractedExe = Get-ChildItem -Path $aria2InstallPath -Filter "aria2c.exe" -Recurse | Select-Object -First 1
            if ($extractedExe) {
                if ($extractedExe.DirectoryName -ne $aria2InstallPath) {
                    Move-Item -Path $extractedExe.FullName -Destination $aria2InstallPath -Force
                    Remove-Item -Path $extractedExe.DirectoryName -Recurse -Force -ErrorAction SilentlyContinue
                }
                Write-Log "aria2c.exe installed successfully." -Level 2 -Color Green
            }
        }
        catch {
            Write-Log "WARNING: Failed to install aria2. Downloads will be standard speed." -Level 2 -Color Yellow
        }
        finally {
            if (Test-Path $aria2ZipPath) { Remove-Item $aria2ZipPath -ErrorAction SilentlyContinue }
        }
    }
    else {
        Write-Log "aria2 is already installed." -Level 1 -Color Green
    }
    # Add aria2 to PATH for current session
    $env:PATH = "$aria2InstallPath;$env:PATH"

    # ---------------------------------------------------------
    # GIT DETECTION AND INSTALLATION
    # ---------------------------------------------------------
    Write-Log "Checking for Git..." -Level 1
    if (Get-Command "git" -ErrorAction SilentlyContinue) {
        $gitVer = git --version 2>&1
        Write-Log "Git detected: $gitVer" -Level 1 -Color Green
    }
    else {
        Write-Log "WARNING: Git is not installed." -Level 1 -Color Yellow
        Write-Host "Git is required to download ComfyUI and custom nodes." -ForegroundColor Yellow

        $choice = ""
        while ($choice -notin @("Y","N")) {
            $choice = Read-Host "Would you like to download and install Git automatically? (Y/N)"
        }

        if ($choice -eq "Y") {
            Write-Log "Initiating Git installation..." -Level 1
            # Git for Windows 2.47.1 (64-bit) - Official Standalone Installer
            $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe"
            $gitInstaller = Join-Path $env:TEMP "git-installer.exe"

            try {
                Save-File -Uri $gitUrl -OutFile $gitInstaller
                Write-Log "Installing Git (Please accept UAC if prompted)..." -Level 2

                # Silent Install Arguments
                # /VERYSILENT: No GUI
                # /NORESTART: Don't reboot
                # /SP-: Skip setup prompt
                $gitArgs = "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS"
                
                $proc = Start-Process -FilePath $gitInstaller -ArgumentList $gitArgs -Wait -PassThru

                if ($proc.ExitCode -eq 0) {
                    Write-Log "Git installed successfully." -Level 1 -Color Green
                    
                    # Refresh PATH for the current session so we can use 'git' immediately
                    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
                    
                    if (Get-Command "git" -ErrorAction SilentlyContinue) {
                        Write-Log "Git is now available for this session." -Level 2 -Color Green
                    }
                }
                else {
                    Write-Log "ERROR: Git installer failed with code $($proc.ExitCode)." -Level 1 -Color Red
                    Read-Host "Press Enter to exit."; exit 1
                }
            }
            catch {
                Write-Log "ERROR downloading/installing Git: $($_.Exception.Message)" -Level 1 -Color Red
                Read-Host "Press Enter to exit."; exit 1
            }
            finally {
                Remove-Item $gitInstaller -ErrorAction SilentlyContinue
            }
        }
        else {
             Write-Log "Installation aborted. Git is mandatory." -Level 1 -Color Red
             Read-Host "Press Enter to exit."; exit 1
        }
    }

    if ($installType -eq "Light") {
        Write-Log "Selected: Light Installation (venv)" -Level 0
        Set-Content -Path $installTypeFile -Value "venv" -Force

        # ---------------------------------------------------------
        # AUTOMATIC DETECTION AND INSTALLATION OF PYTHON 3.13
        # ---------------------------------------------------------
        Write-Log "Checking for Python 3.13..." -Level 1
        $pythonCommand = $null
        $pythonArgs = $null

        # 1. Attempt detection via Launcher (py)
        if (Get-Command 'py' -ErrorAction SilentlyContinue) {
            # Uses Test-PyVersion from UmeAiRTUtils.psm1
            if (Test-PyVersion -Command "py" -Arguments "-3.13") {
                $pythonCommand = "py"; $pythonArgs = "-3.13"
                Write-Log "Python Launcher detected with Python 3.13." -Level 1 -Color Green
            }
        }

        # 2. Attempt detection via System PATH (python)
        if ($null -eq $pythonCommand -and (Get-Command 'python' -ErrorAction SilentlyContinue)) {
            # Uses Test-PyVersion from UmeAiRTUtils.psm1
            if (Test-PyVersion -Command "python" -Arguments "") {
                $pythonCommand = "python"; $pythonArgs = ""
                Write-Log "System Python 3.13 detected." -Level 1 -Color Green
            }
        }

        # 3. DETECTION FAILED -> PROPOSE INSTALLATION
        if ($null -eq $pythonCommand) {
            Write-Log "WARNING: Python 3.13 was not found on your system." -Level 1 -Color Yellow
            Write-Host "`nPython 3.13 is required for ComfyUI." -ForegroundColor Yellow
            
            $choice = ""
            while ($choice -notin @("Y","N")) {
                $choice = Read-Host "Would you like to download and install Python 3.13 automatically? (Y/N)"
            }

            if ($choice -eq "Y") {
                Write-Log "Initiating Python 3.13 installation..." -Level 1
                
                # Official Python 3.13.11 URL (Stable)
                $pyUrl = "https://www.python.org/ftp/python/3.13.11/python-3.13.11-amd64.exe"
                $pyInstaller = Join-Path $env:TEMP "python-3.13.11-amd64.exe"
                
                try {
                    # Download
                    Write-Log "Downloading Python 3.13 installer..." -Level 2
                    Save-File -Uri $pyUrl -OutFile $pyInstaller 
                    
                    # Installation
                    Write-Log "Installing Python (this may take a minute)..." -Level 2
                    $proc = Start-Process -FilePath $pyInstaller -ArgumentList "/passive PrependPath=1 Include_launcher=1 Include_test=0" -Wait -PassThru
                    
                    if ($proc.ExitCode -eq 0) {
                        Write-Log "Python 3.13 installed successfully." -Level 1 -Color Green
                        
                        # POST-INSTALLATION REDETECTION (Manual path check)
                        $possiblePaths = @(
                            "C:\Program Files\Python313\python.exe",
                            "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe"
                        )
                        
                        foreach ($path in $possiblePaths) {
                            if (Test-Path $path) {
                                $pythonCommand = $path
                                $pythonArgs = ""
                                Write-Log "New installation detected at: $path" -Level 2 -Color Green
                                break
                            }
                        }
                        
                        # Fallback to launcher check
                        if ($null -eq $pythonCommand) {
                            try {
                                cmd /c "py -3.13 --version" | Out-Null
                                if ($LASTEXITCODE -eq 0) {
                                    $pythonCommand = "py"; $pythonArgs = "-3.13"
                                    Write-Log "New installation detected via Launcher." -Level 2 -Color Green
                                }
                            } catch {}
                        }
                    }
                    else {
                        Write-Log "ERROR: Python installer failed with code $($proc.ExitCode)." -Level 1 -Color Red
                    }
                    Remove-Item $pyInstaller -ErrorAction SilentlyContinue
                }
                catch {
                    Write-Log "ERROR during Python download/install: $($_.Exception.Message)" -Level 1 -Color Red
                }
            }
        }

        # 4. FINAL CHECK
        if ($null -eq $pythonCommand) {
            Write-Log "FATAL ERROR: Python 3.13 is required." -Level 1 -Color Red
            Write-Log "Please install it manually from python.org and restart this script." -Level 1
            Read-Host "Press Enter to exit."
            exit 1
        }

        # 5. Create venv
        $venvPath = Join-Path $scriptPath "venv"
        if (-not (Test-Path $venvPath)) {
            Write-Log "Creating virtual environment (venv) at '$venvPath'..." -Level 1
            if ($pythonArgs) { $venvArgs = "$pythonArgs -m venv `"$venvPath`"" } 
            else { $venvArgs = "-m venv `"$venvPath`"" }
            Invoke-AndLog $pythonCommand $venvArgs
        }
        else {
            Write-Log "Virtual environment already exists." -Level 1 -Color Green
        }

        # 6. Prepare Launch-Phase2.ps1 for venv
        $launcherContent = @'
try {
    . "$PSScriptRoot\venv\Scripts\Activate.ps1"
} catch {
    Write-Host "FAILED to activate venv: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "Phase 2 Launch (venv)..." -ForegroundColor Cyan
$installPath = Split-Path $PSScriptRoot -Parent
& "$PSScriptRoot\Install-ComfyUI-Phase2.ps1" -InstallPath $installPath
Write-Host "End of Phase 2. Press Enter to close this window."
Read-Host
'@

    }
    else {
        # --- Step 1: Setup Miniconda and Conda Environment ---
        Write-Log "Selected: Full Installation (Miniconda)" -Level 0
        Set-Content -Path $installTypeFile -Value "conda" -Force

        Write-Log "Setting up Miniconda and Conda Environment" -Level 0
        if (-not (Test-Path $condaPath)) {
            Write-Log "Miniconda not found. Installing..." -Level 1 -Color Yellow
            $minicondaInstaller = Join-Path $env:TEMP "Miniconda3-latest-Windows-x86_64.exe"
            $minicondaUrl = $dependencies.tools.miniconda.url
            if (-not $minicondaUrl) { $minicondaUrl = "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe" }
            Save-File -Uri $minicondaUrl -OutFile $minicondaInstaller
            Write-Log "Running Miniconda installer (this may take a minute)..." -Level 2
            $installerProcess = Start-Process -FilePath $minicondaInstaller -ArgumentList "/InstallationType=JustMe /RegisterPython=0 /S /D=$condaPath" -Wait -PassThru
            if ($installerProcess.ExitCode -ne 0) {
                Write-Log "ERROR: Miniconda installer failed with exit code $($installerProcess.ExitCode)" -Level 1 -Color Red
                Read-Host "Press Enter to exit."
                exit 1
            }
            Write-Log "Miniconda installed successfully." -Level 2 -Color Green

            # Verify conda.exe exists with retry (installer may still be finishing)
            $retryCount = 0
            $maxRetries = 10
            while (-not (Test-Path $condaExe) -and $retryCount -lt $maxRetries) {
                $retryCount++
                Write-Log "Waiting for Miniconda installation to complete... ($retryCount/$maxRetries)" -Level 3
                Start-Sleep -Seconds 2
            }

            Remove-Item $minicondaInstaller -ErrorAction SilentlyContinue
        }
        else { Write-Log "Miniconda is already installed at '$condaPath'" -Level 1 -Color Green }

        if (-not (Test-Path $condaExe)) { Write-Log "FATAL ERROR: conda.exe not found after installation/verification" -Color Red; Read-Host "Press Enter."; exit 1 }

        Write-Log "Accepting Anaconda Terms of Service..." -Level 1
        Invoke-AndLog "$condaExe" "tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main"
        Invoke-AndLog "$condaExe" "tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r"
        Invoke-AndLog "$condaExe" "tos accept --override-channels --channel https://repo.anaconda.com/pkgs/msys2"

        Write-Log "Attempting to remove old 'UmeAiRT' environment for a clean install..." -Level 1
        Invoke-AndLog "$condaExe" "env remove -n UmeAiRT -y" -IgnoreErrors
        Write-Log "Creating new Conda environment 'UmeAiRT' from '$scriptPath\environment.yml'..." -Level 1
        Invoke-AndLog "$condaExe" "env create -f `"$scriptPath\environment.yml`""
        Write-Log "Environment 'UmeAiRT' created successfully." -Level 2 -Color Green

        Write-Log "Conda environment ready." -Level 1 -Color Green

        # Prepare Launch-Phase2.ps1 for Conda
        $launcherContent = @'
try {
    $condaHook = Join-Path $env:LOCALAPPDATA "Miniconda3\shell\condabin\conda-hook.ps1"
    . $condaHook
    conda activate UmeAiRT
} catch {
    Write-Host "FAILED to activate the Conda 'UmeAiRT' environment: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "Phase 2 Launch (Conda)..." -ForegroundColor Cyan
$installPath = Split-Path $PSScriptRoot -Parent
& "$PSScriptRoot\Install-ComfyUI-Phase2.ps1" -InstallPath $installPath
Write-Host "End of Phase 2. Press Enter to close this window."
Read-Host
'@
    }

    # Write Launcher
    try {
        [System.IO.File]::WriteAllText($phase2LauncherPath, $launcherContent, (New-Object System.Text.UTF8Encoding $true))
    }
    catch {
        Write-Log "ERROR: Unable to create '$phase2LauncherPath'. $($_.Exception.Message)" -Color Red
        Read-Host "Press Enter."
        exit 1
    }

    Write-Log "Phase 2 of the installation has been launched..." -Level 0
    Write-Log "A new window will open for Phase 2..." -Level 2
    try { Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$phase2LauncherPath`"" -Wait -ErrorAction Stop } catch { Write-Log "ERROR: Unable to launch Phase 2 ($($_.Exception.Message))." -Color Red; Read-Host "Press Enter."; exit 1 }

    #===========================================================================
    # FINALIZATION 
    #===========================================================================
    Write-Log "-------------------------------------------------------------------------------" -Color Green
    Write-Log "Phase 1 is complete. Phase 2 was executed in a separate window." -Color Green
}
