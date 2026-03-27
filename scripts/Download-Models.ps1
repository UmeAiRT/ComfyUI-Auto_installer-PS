param(
    [string]$InstallPath  = ((Split-Path $PSScriptRoot -Parent).Replace('\', '/')),
    [switch]$DownloadAll, # Skip all prompts and download everything for every model pack
    [switch]$v,           # -v  : show [INFO] messages
    [switch]$vv           # -vv : all of -v + print each command line before running
)

$scriptsDir = $PSScriptRoot.Replace('\', '/')

$scriptMap = [ordered]@{
    '1' = 'Download-FLUX-Models.ps1'
    '2' = 'Download-WAN2.1-Models.ps1'
    '3' = 'Download-WAN2.2-Models.ps1'
    '4' = 'Download-HIDREAM-Models.ps1'
    '5' = 'Download-LTX1-Models.ps1'
    '6' = 'Download-LTX2-Models.ps1'
    '7' = 'Download-QWEN-Models.ps1'
    '8' = 'Download-Z-IMAGES-Models.ps1'
}

# Build common splatted args passed to every sub-script
$commonArgs = @{ InstallPath = $InstallPath }
if ($vv) { $commonArgs['vv'] = $true } elseif ($v) { $commonArgs['v'] = $true }

if ($DownloadAll) {
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "    UmeAiRT Model Downloader — Download All"      -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  -DownloadAll: skipping all prompts, downloading everything." -ForegroundColor Yellow
    Write-Host ""
    foreach ($entry in $scriptMap.GetEnumerator()) {
        $target = "$scriptsDir/$($entry.Value)"
        Write-Host "--- $($entry.Value) ---" -ForegroundColor Cyan
        if (Test-Path $target) {
            & $target @commonArgs -DownloadAll
        } else {
            Write-Host "[ERROR] Script not found: $($entry.Value)" -ForegroundColor Red
        }
        Write-Host ""
    }
    Write-Host "[OK] All model packs downloaded." -ForegroundColor Green
    Read-Host "Press Enter to exit"
    return
}

while ($true) {
    Clear-Host
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "          UmeAiRT Model Downloader Menu"          -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Choose model to download:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    1. FLUX Models"
    Write-Host "    2. WAN2.1 Models"
    Write-Host "    3. WAN2.2 Models"
    Write-Host "    4. HIDREAM Models"
    Write-Host "    5. LTX1 Models"
    Write-Host "    6. LTX2 Models"
    Write-Host "    7. QWEN Models"
    Write-Host "    8. Z-IMAGE Models"
    Write-Host ""
    Write-Host "    Q. Quit"
    Write-Host ""

    $choice = (Read-Host "  Your choice").Trim().ToUpper()

    if ($choice -eq 'Q') { break }

    if ($scriptMap.ContainsKey($choice)) {
        $target = "$scriptsDir/$($scriptMap[$choice])"
        if (Test-Path $target) {
            & $target @commonArgs
        } else {
            Write-Host "[ERROR] Script not found: $($scriptMap[$choice])" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "[INFO] Download script complete." -ForegroundColor Green
        Read-Host "Press Enter to return to menu"
    } else {
        Write-Host "[WARN] Invalid choice. Please try again." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }
}
