@echo off
setlocal
chcp 65001 > nul
set "PYTHONPATH="
set "PYTHONNOUSERSITE=1"
set "PYTHONUTF8=1"

:: ============================================================================
:: File: UmeAiRT-Update-ComfyUI.bat
:: Description: Updater for ComfyUI and UmeAiRT scripts.
::              - Bootstraps the downloader to update scripts
::              - Activates environment
::              - Launches Update-ComfyUI.ps1
:: Author: UmeAiRT
:: ============================================================================

:: Prefer PowerShell 7+ (pwsh) if available, fall back to Windows PowerShell 5.1
where pwsh >nul 2>&1 && set "PS_EXE=pwsh" || set "PS_EXE=powershell"

title UmeAiRT ComfyUI Updater
echo.
set "InstallPath=%~dp0"
if "%InstallPath:~-1%"=="\" set "InstallPath=%InstallPath:~0,-1%"

:: ----------------------------------------------------------------------------
:: Section 1: Bootstrap Downloader (Self-Update)
:: ----------------------------------------------------------------------------

set "ScriptsFolder=%InstallPath%\scripts"
set "BootstrapScript=%ScriptsFolder%\Bootstrap-Downloader.ps1"
set "UserConfigFile=%InstallPath%\umeairt-user-config.json"
set "RepoConfigFile=%InstallPath%\repo-config.json"
set "CfgTmp=%TEMP%\umeairt_cfg_%RANDOM%.cmd"

:: Default values for GitHub repo source
set "GhUser=UmeAiRT"
set "GhRepoName=ComfyUI-Auto_installer"
set "GhBranch=main"
set "ConfigSource=(defaults)"

:: Read repository settings from umeairt-user-config.json (preferred) or
:: repo-config.json (deprecated fallback). Validate before URL interpolation.
%PS_EXE% -NoProfile -ExecutionPolicy Bypass -Command ^
    "$u='%UserConfigFile%'; $r='%RepoConfigFile%'; $o='%CfgTmp%';" ^
    "$gh='UmeAiRT'; $gn='ComfyUI-Auto_installer'; $gb='main'; $src='(defaults)';" ^
    "if (Test-Path $u) {" ^
    "  $c = Get-Content $u -Raw | ConvertFrom-Json; $src = 'umeairt-user-config.json';" ^
    "  if ($c.PSObject.Properties['gh_user']     -and $c.gh_user)     { $gh = $c.gh_user }" ^
    "  if ($c.PSObject.Properties['gh_reponame'] -and $c.gh_reponame) { $gn = $c.gh_reponame }" ^
    "  if ($c.PSObject.Properties['gh_branch']   -and $c.gh_branch)   { $gb = $c.gh_branch }" ^
    "} elseif (Test-Path $r) {" ^
    "  $c = Get-Content $r -Raw | ConvertFrom-Json; $src = 'repo-config.json (deprecated - migrate to umeairt-user-config.json)';" ^
    "  if ($c.gh_user)     { $gh = $c.gh_user }" ^
    "  if ($c.gh_reponame) { $gn = $c.gh_reponame }" ^
    "  if ($c.gh_branch)   { $gb = $c.gh_branch }" ^
    "};" ^
    "if ($gh -match '[^a-zA-Z0-9_-]') { Write-Error 'gh_user contains invalid characters.'; exit 1 };" ^
    "if ($gn -match '[^a-zA-Z0-9_-]') { Write-Error 'gh_reponame contains invalid characters.'; exit 1 };" ^
    "if ($gb -match '[^a-zA-Z0-9_./-]') { Write-Error 'gh_branch contains invalid characters.'; exit 1 };" ^
    "@('set GhUser='+$gh, 'set GhRepoName='+$gn, 'set GhBranch='+$gb, 'set ConfigSource='+$src) | Set-Content $o -Encoding ASCII"

if %errorlevel% neq 0 (
    echo [ERROR] Repository configuration validation failed. Check umeairt-user-config.json.
    if exist "%CfgTmp%" del "%CfgTmp%"
    pause
    goto :eof
)

call "%CfgTmp%"
del "%CfgTmp%" 2>nul

echo [INFO] Config source: %ConfigSource%
echo [INFO] Using: %GhUser%/%GhRepoName% @ %GhBranch%

:: Build the bootstrap URL from the configured values
set "BootstrapUrl=https://github.com/%GhUser%/%GhRepoName%/raw/%GhBranch%/scripts/Bootstrap-Downloader.ps1"

echo [INFO] Forcing update of the bootstrap script itself...
%PS_EXE% -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%BootstrapUrl%' -OutFile '%BootstrapScript%'"
if %errorlevel% neq 0 (
    echo [ERROR] Failed to download the bootstrap script. Check connection/URL.
    pause
    goto :eof
)
echo [OK] Bootstrap script is now up-to-date.

echo [INFO] Running the bootstrap script to update all other files...
:: -SkipSelf prevents the updated bootstrap from re-downloading this .bat file
%PS_EXE% -NoProfile -ExecutionPolicy Bypass -File "%BootstrapScript%" -InstallPath "%InstallPath%" -GhUser "%GhUser%" -GhRepoName "%GhRepoName%" -GhBranch "%GhBranch%" -SkipSelf
echo [OK] All scripts are now up-to-date.
echo.

:: ----------------------------------------------------------------------------
:: Section 2: Launch Update Script (Environment Activation)
:: ----------------------------------------------------------------------------
echo [INFO] Checking installation type...
set "InstallTypeFile=%InstallPath%\scripts\install_type"
set "InstallType=conda"

set "CondaPath=%LOCALAPPDATA%\Miniconda3"
set "CondaActivate=%CondaPath%\Scripts\activate.bat"

if exist "%InstallTypeFile%" (
    set /p InstallType=<"%InstallTypeFile%"
) else (
    if exist "%InstallPath%\scripts\venv" (
        set "InstallType=venv"
    )
)

if "%InstallType%"=="venv" (
    echo [INFO] Activating venv environment...
    call "%InstallPath%\scripts\venv\Scripts\activate.bat"
    if %errorlevel% neq 0 (
        echo [ERROR] Failed to activate venv environment.
        pause
        goto :eof
    )
) else (
    echo [INFO] Activating Conda environment 'UmeAiRT'...
    if not exist "%CondaActivate%" (
        echo [ERROR] Could not find Conda at: %CondaActivate%
        pause
        goto :eof
    )
    call "%CondaActivate%" UmeAiRT
    if %errorlevel% neq 0 (
        echo [ERROR] Failed to activate Conda environment 'UmeAiRT'.
        pause
        goto :eof
    )
)

echo [INFO] Launching PowerShell update script...
%PS_EXE% -ExecutionPolicy Bypass -File "%ScriptsFolder%\Update-ComfyUI.ps1" -InstallPath "%InstallPath%"
echo.
echo [INFO] The update script is complete.
pause

endlocal
