@echo off
setlocal

:: ============================================================================
:: File: UmeAiRT-Start-ComfyUI_LowVRAM.bat
:: Description: Launcher for ComfyUI (Low VRAM / Stability Mode).
::              Thin wrapper — all logic is in scripts\Start-ComfyUI.ps1.
:: Author: UmeAiRT
:: ============================================================================

:: Prefer PowerShell 7+ (pwsh) if available, fall back to Windows PowerShell 5.1
where pwsh >nul 2>&1 && set "PS_EXE=pwsh" || set "PS_EXE=powershell"

%PS_EXE% -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-ComfyUI.ps1" -InstallPath "%~dp0" -LowVRAM

pause
