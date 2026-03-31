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
::              Reads fork config, downloads Install-ComfyUI.ps1, then launches
::              it — Install-ComfyUI.ps1 handles the full bootstrap, path
::              selection, config persistence, and Phase 1.
:: Author: UmeAiRT
:: ============================================================================

:: Default fork coordinates
set "GH_USER=UmeAiRT"
set "GH_REPO=ComfyUI-Auto_installer-PS"
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

:: Download Install-ComfyUI.ps1 — it handles the full bootstrap and Phase 1
set "INSTALL_SCRIPT=%INSTALL_DIR%scripts/Install-ComfyUI.ps1"
set "INSTALL_URL=https://github.com/%GH_USER%/%GH_REPO%/raw/%GH_BRANCH%/scripts/Install-ComfyUI.ps1"
echo [INFO] Downloading installer script...
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri $env:INSTALL_URL -OutFile $env:INSTALL_SCRIPT -UseBasicParsing -ErrorAction Stop"
if errorlevel 1 (
    echo [ERROR] Failed to download installer script. Check your internet connection.
    pause
    exit /b 1
)

:: Launch Install-ComfyUI.ps1 — pass resolved fork coords so it uses the right repo even before psm1 exists
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%INSTALL_DIR%scripts/Install-ComfyUI.ps1" -GhUser "%GH_USER%" -GhRepoName "%GH_REPO%" -GhBranch "%GH_BRANCH%" %*
if %errorlevel% neq 0 pause
