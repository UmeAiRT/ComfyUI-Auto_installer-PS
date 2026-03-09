@echo off
setlocal
chcp 65001 >nul
set "PYTHONPATH="
set "PYTHONNOUSERSITE=1"
set "PYTHONUTF8=1"
where pwsh >nul 2>&1 && set "PS_EXE=pwsh" || set "PS_EXE=powershell"
title UmeAiRT ComfyUI Installer

:: ============================================================================
:: File: UmeAiRT-Install-ComfyUI.bat
:: Description: Main entry point for the ComfyUI installation.
::              Reads fork config, bootstraps all scripts, then launches
::              Install-ComfyUI.ps1 which handles path selection and Phase 1.
:: Author: UmeAiRT
:: ============================================================================

:: Default fork coordinates
set "GH_USER=UmeAiRT"
set "GH_REPO=ComfyUI-Auto_installer"
set "GH_BRANCH=main"

:: Convert backslashes to forward slashes — %~dp0 always ends in \
:: Passing "%~dp0" as a PS param produces "A:\path\" where \" escapes the quote.
:: Forward slashes work in cmd.exe file operations since Windows NT 3.1.
set "INSTALL_DIR=%~dp0"
set "INSTALL_DIR=%INSTALL_DIR:\=/%"

:: Override from config files if present (fork / branch testing)
:: Priority: umeairt-user-config.json > repo-config.json (deprecated) > defaults
:: Uses ConvertFrom-Json(...) instead of pipe to avoid cmd interpreting | in backticks.
:: PS_EXE is never quoted here — it is always "pwsh" or "powershell" (no spaces).
set "CFG_FILE="
if exist "%~dp0umeairt-user-config.json" set "CFG_FILE=umeairt-user-config.json"
if not defined CFG_FILE if exist "%~dp0repo-config.json" set "CFG_FILE=repo-config.json"

if defined CFG_FILE (
    echo [INFO] Found %CFG_FILE% -- reading fork settings...
    for /f "usebackq delims=" %%a in (`%PS_EXE% -NoProfile -ExecutionPolicy Bypass -Command "$j=ConvertFrom-Json (Get-Content (Join-Path $env:INSTALL_DIR $env:CFG_FILE) -Raw); if($j.gh_user){$j.gh_user}"`) do set "GH_USER=%%a"
    for /f "usebackq delims=" %%a in (`%PS_EXE% -NoProfile -ExecutionPolicy Bypass -Command "$j=ConvertFrom-Json (Get-Content (Join-Path $env:INSTALL_DIR $env:CFG_FILE) -Raw); if($j.gh_reponame){$j.gh_reponame}"`) do set "GH_REPO=%%a"
    for /f "usebackq delims=" %%a in (`%PS_EXE% -NoProfile -ExecutionPolicy Bypass -Command "$j=ConvertFrom-Json (Get-Content (Join-Path $env:INSTALL_DIR $env:CFG_FILE) -Raw); if($j.gh_branch){$j.gh_branch}"`) do set "GH_BRANCH=%%a"
)

echo [INFO] Using: %GH_USER%/%GH_REPO% @ %GH_BRANCH%

:: Create scripts folder if needed
if not exist "%INSTALL_DIR%scripts/" md "%INSTALL_DIR%scripts"

:: Download Bootstrap-Downloader.ps1 fresh, then run it to pull all required scripts
set "BOOTSTRAP_SCRIPT=%INSTALL_DIR%scripts/Bootstrap-Downloader.ps1"
set "BOOTSTRAP_URL=https://github.com/%GH_USER%/%GH_REPO%/raw/%GH_BRANCH%/scripts/Bootstrap-Downloader.ps1"
echo [INFO] Downloading bootstrap script...
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri $env:BOOTSTRAP_URL -OutFile $env:BOOTSTRAP_SCRIPT -UseBasicParsing -ErrorAction Stop"
if errorlevel 1 (
    echo [ERROR] Failed to download bootstrap script. Check your internet connection.
    pause
    exit /b 1
)

echo [INFO] Running bootstrap to download all required files...
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%INSTALL_DIR%scripts/Bootstrap-Downloader.ps1" -InstallPath "%INSTALL_DIR%" -GhUser "%GH_USER%" -GhRepoName "%GH_REPO%" -GhBranch "%GH_BRANCH%"
if errorlevel 1 (
    echo [ERROR] Bootstrap failed. See above for details.
    pause
    exit /b 1
)

:: Launch Install-ComfyUI.ps1 — handles path selection, config persistence, and Phase 1
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%INSTALL_DIR%scripts/Install-ComfyUI.ps1" %*
if %errorlevel% neq 0 pause
