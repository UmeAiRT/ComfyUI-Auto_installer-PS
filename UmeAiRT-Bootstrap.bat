@echo off
setlocal
chcp 65001 >nul
set "PYTHONPATH="
set "PYTHONNOUSERSITE=1"
set "PYTHONUTF8=1"
where pwsh >nul 2>&1 && set "PS_EXE=pwsh" || set "PS_EXE=powershell"
set "INSTALL_DIR=%~dp0"
if "%INSTALL_DIR:~-1%"=="\" set "INSTALL_DIR=%INSTALL_DIR:~0,-1%"
set "INSTALL_DIR=%INSTALL_DIR:\=/%"
title UmeAiRT Bootstrap

:: Default fork coordinates
set "GH_USER=UmeAiRT"
set "GH_REPO=ComfyUI-Auto_installer-PS"
set "GH_BRANCH=main"

:: Override from config files if present (fork / branch testing)
:: Priority: umeairt-user-config.json > repo-config.json (deprecated) > defaults
set "CFG_FILE="
if exist "%~dp0umeairt-user-config.json" set "CFG_FILE=umeairt-user-config.json"
if not defined CFG_FILE if exist "%~dp0repo-config.json" set "CFG_FILE=repo-config.json"

if defined CFG_FILE (
    echo [INFO] Found %CFG_FILE% -- reading fork settings...
    for /f "usebackq delims=" %%a in (`%PS_EXE% -NoProfile -ExecutionPolicy Bypass -Command "$j=ConvertFrom-Json (Get-Content (Join-Path $env:INSTALL_DIR $env:CFG_FILE) -Raw); if($j.gh_user){$j.gh_user}"`) do set "GH_USER=%%a"
    for /f "usebackq delims=" %%a in (`%PS_EXE% -NoProfile -ExecutionPolicy Bypass -Command "$j=ConvertFrom-Json (Get-Content (Join-Path $env:INSTALL_DIR $env:CFG_FILE) -Raw); if($j.gh_reponame){$j.gh_reponame}"`) do set "GH_REPO=%%a"
    for /f "usebackq delims=" %%a in (`%PS_EXE% -NoProfile -ExecutionPolicy Bypass -Command "$j=ConvertFrom-Json (Get-Content (Join-Path $env:INSTALL_DIR $env:CFG_FILE) -Raw); if($j.gh_branch){$j.gh_branch}"`) do set "GH_BRANCH=%%a"
)

echo ================================================================================
echo   UmeAiRT Bootstrap -- Download fresh copies of all scripts
echo ================================================================================
echo.
echo   Using: %GH_USER%/%GH_REPO% @ %GH_BRANCH%
echo   Run this to repair a broken or out-of-date install before updating.
echo   After this completes, run UmeAiRT-Update-ComfyUI.bat normally.
echo.

:: If Bootstrap-Downloader.ps1 is missing (completely broken install),
:: download it using resolved fork coordinates before proceeding.
if not exist "%INSTALL_DIR%\scripts\Bootstrap-Downloader.ps1" (
    echo [INFO] Bootstrap-Downloader.ps1 not found. Fetching from %GH_USER%/%GH_REPO%...
    if not exist "%INSTALL_DIR%\scripts" mkdir "%INSTALL_DIR%\scripts"
    "%PS_EXE%" -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $url = 'https://raw.githubusercontent.com/%GH_USER%/%GH_REPO%/%GH_BRANCH%/scripts/Bootstrap-Downloader.ps1'; Invoke-WebRequest -Uri $url -OutFile '%INSTALL_DIR%/scripts/Bootstrap-Downloader.ps1' -UseBasicParsing -ErrorAction Stop"
    if %errorlevel% neq 0 (
        echo.
        echo [ERROR] Could not download Bootstrap-Downloader.ps1.
        echo         Check your internet connection and try again.
        pause
        exit /b 1
    )
    echo [OK] Bootstrap-Downloader.ps1 downloaded.
    echo.
)

"%PS_EXE%" -ExecutionPolicy Bypass -File "%INSTALL_DIR%\scripts\Bootstrap-Downloader.ps1" -InstallPath "%INSTALL_DIR%" -GhUser "%GH_USER%" -GhRepoName "%GH_REPO%" -GhBranch "%GH_BRANCH%" %*

if %errorlevel% neq 0 (
    echo.
    echo [WARN] Bootstrap completed with download errors.
    echo        Some files may not have been updated. Check logs\bootstrap.log.
    pause
    exit /b 1
)

echo.
echo [OK] All scripts are up to date.
echo      You can now run UmeAiRT-Update-ComfyUI.bat to update ComfyUI.
echo.
pause
