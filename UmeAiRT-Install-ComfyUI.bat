@echo off
setlocal
chcp 65001 > nul
set "PYTHONPATH="
set "PYTHONNOUSERSITE=1"
set "PYTHONUTF8=1"

:: ============================================================================
:: File: UmeAiRT-Install-ComfyUI.bat
:: Description: Main entry point for the ComfyUI installation.
::              - Sets up installation path
::              - Bootstraps the downloader script
::              - Launches the Phase 1 PowerShell installer
:: Author: UmeAiRT
:: ============================================================================

:: Prefer PowerShell 7+ (pwsh) if available, fall back to Windows PowerShell 5.1
where pwsh >nul 2>&1 && set "PS_EXE=pwsh" || set "PS_EXE=powershell"

title UmeAiRT ComfyUI Installer
echo.
cls
echo ============================================================================
echo           Welcome to the UmeAiRT ComfyUI Installer
echo ============================================================================
echo.

:: ----------------------------------------------------------------------------
:: Section 1: Set Installation Path
:: ----------------------------------------------------------------------------

:: 1. Define the default path (the current directory)
set "DefaultPath=%~dp0"
if "%DefaultPath:~-1%"=="\" set "DefaultPath=%DefaultPath:~0,-1%"

echo Where would you like to install ComfyUI?
echo.
echo Current path: %DefaultPath%
echo.
echo Press ENTER to use the current path.
echo Or, enter a full path (e.g., D:\ComfyUI) and press ENTER.
echo.

:: 2. Prompt the user
set /p "InstallPath=Enter installation path: "

:: 3. If user entered nothing, use the default
if "%InstallPath%"=="" (
    set "InstallPath=%DefaultPath%"
)

:: 4. Clean up the final path (in case the user added a trailing \)
if "%InstallPath:~-1%"=="\" set "InstallPath=%InstallPath:~0,-1%"

echo.
echo [INFO] Installing to: %InstallPath%
echo Press any key to begin...
pause > nul

:: ----------------------------------------------------------------------------
:: Section 2: Bootstrap Downloader Configuration
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
    "  if ($c.PSObject.Properties['gh_user']   -and $c.gh_user)     { $gh = $c.gh_user }" ^
    "  if ($c.PSObject.Properties['gh_reponame'] -and $c.gh_reponame) { $gn = $c.gh_reponame }" ^
    "  if ($c.PSObject.Properties['gh_branch'] -and $c.gh_branch)   { $gb = $c.gh_branch }" ^
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
    exit /b 1
)

call "%CfgTmp%"
del "%CfgTmp%" 2>nul

echo [INFO] Config source: %ConfigSource%
echo [INFO] Using: %GhUser%/%GhRepoName% @ %GhBranch%

:: Build the bootstrap URL from the configured values
set "BootstrapUrl=https://github.com/%GhUser%/%GhRepoName%/raw/%GhBranch%/scripts/Bootstrap-Downloader.ps1"

:: Create scripts folder if it doesn't exist
if not exist "%ScriptsFolder%" (
    echo [INFO] Creating the scripts folder: %ScriptsFolder%
    mkdir "%ScriptsFolder%"
)

:: Download the bootstrap script
echo [INFO] Downloading the bootstrap script...
%PS_EXE% -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%BootstrapUrl%' -OutFile '%BootstrapScript%'"

:: Run the bootstrap script to download all other files
echo [INFO] Running the bootstrap script to download all required files...
%PS_EXE% -NoProfile -ExecutionPolicy Bypass -File "%BootstrapScript%" -InstallPath "%InstallPath%" -GhUser "%GhUser%" -GhRepoName "%GhRepoName%" -GhBranch "%GhBranch%"
echo [OK] Bootstrap download complete.
echo.

:: ----------------------------------------------------------------------------
:: Section 3: Launch Main Installation Script
:: ----------------------------------------------------------------------------
echo [INFO] Launching the main installation script...
echo.
%PS_EXE% -ExecutionPolicy Bypass -File "%ScriptsFolder%\Install-ComfyUI-Phase1.ps1" -InstallPath "%InstallPath%"

echo.
echo [INFO] The script execution is complete.
pause
