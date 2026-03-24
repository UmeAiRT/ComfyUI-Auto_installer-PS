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

title UmeAiRT ComfyUI Updater
echo.
set "InstallPath=%~dp0"
if "%InstallPath:~-1%"=="\" set "InstallPath=%InstallPath:~0,-1%"

:: ----------------------------------------------------------------------------
:: Section 1: Bootstrap Downloader (Self-Update)
:: ----------------------------------------------------------------------------

set "ScriptsFolder=%InstallPath%\scripts"
set "BootstrapScript=%ScriptsFolder%\Bootstrap-Downloader.ps1"
set "RepoConfigFile=%InstallPath%\repo-config.json"

:: Default values for GitHub repo source
set "GhUser=UmeAiRT"
set "GhRepoName=ComfyUI-Auto_installer-PS"
set "GhBranch=main"

:: Check for repo-config.json and read custom values if present
if exist "%RepoConfigFile%" (
    echo [INFO] Found repo-config.json, reading custom repository settings...
    for /f "usebackq delims=" %%a in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$c = Get-Content '%RepoConfigFile%' | ConvertFrom-Json; if ($c.gh_user) { $c.gh_user }"`) do set "GhUser=%%a"
    for /f "usebackq delims=" %%a in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$c = Get-Content '%RepoConfigFile%' | ConvertFrom-Json; if ($c.gh_reponame) { $c.gh_reponame }"`) do set "GhRepoName=%%a"
    for /f "usebackq delims=" %%a in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$c = Get-Content '%RepoConfigFile%' | ConvertFrom-Json; if ($c.gh_branch) { $c.gh_branch }"`) do set "GhBranch=%%a"
)

:: Display the repo source
echo [INFO] Using: %GhUser%/%GhRepoName% @ %GhBranch%

:: Build the bootstrap URL from the configured values
set "BootstrapUrl=https://github.com/%GhUser%/%GhRepoName%/raw/%GhBranch%/scripts/Bootstrap-Downloader.ps1"

echo [INFO] Forcing update of the bootstrap script itself...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%BootstrapUrl%' -OutFile '%BootstrapScript%'"
if %errorlevel% neq 0 (
    echo [ERROR] Failed to download the bootstrap script. Check connection/URL.
    pause
    goto :eof
)
echo [OK] Bootstrap script is now up-to-date.

echo [INFO] Running the bootstrap script to update all other files...
:: [FIX] We send -SkipSelf so the (now updated) bootstrap doesn't download this .bat file
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BootstrapScript%" -InstallPath "%InstallPath%" -GhUser "%GhUser%" -GhRepoName "%GhRepoName%" -GhBranch "%GhBranch%" -SkipSelf 
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
powershell.exe -ExecutionPolicy Bypass -File "%ScriptsFolder%\Update-ComfyUI.ps1" -InstallPath "%InstallPath%"
echo.
echo [INFO] The update script is complete.
pause

endlocal
