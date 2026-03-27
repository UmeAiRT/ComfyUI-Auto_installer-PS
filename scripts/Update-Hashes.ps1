<#
.SYNOPSIS
    Populates sha256 fields in dependencies.json by downloading each artifact and hashing it.
.DESCRIPTION
    Run this script when adding or upgrading dependencies. Only entries with an empty sha256
    are processed. Use -Force to re-hash entries that already have a value.

    After running, review changes with:  git diff scripts/dependencies.json
    Then commit the updated file as part of the release.
.PARAMETER DependenciesFile
    Path to dependencies.json. Defaults to the file alongside this script.
.PARAMETER Force
    Re-hash all entries, including those that already have a sha256 value.
#>
param(
    [string]$DependenciesFile = (Join-Path $PSScriptRoot "dependencies.json"),
    [switch]$Force
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Tls13

$json = Get-Content $DependenciesFile -Raw | ConvertFrom-Json
$tmpDir = Join-Path $env:TEMP "umeairt_hash_$(Get-Random)"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

function Get-UrlHash {
    param([string]$Url)
    $fileName = ($Url.Split('/')[-1].Split('?')[0])
    if (-not $fileName) { $fileName = "download_$(Get-Random)" }
    $outFile = Join-Path $tmpDir $fileName
    Write-Host "  Downloading $fileName..." -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $Url -OutFile $outFile -UseBasicParsing
    $hash = (Get-FileHash $outFile -Algorithm SHA256).Hash
    Remove-Item $outFile -ErrorAction SilentlyContinue
    return $hash
}

function Update-Entry {
    param($Entry, [string]$Label, [switch]$Force)
    if (-not $Entry.PSObject.Properties["sha256"]) { return }
    if ($Entry.sha256 -ne "" -and -not $Force) { return }
    Write-Host $Label -ForegroundColor Cyan
    try {
        $hash = Get-UrlHash -Url $Entry.url
        $Entry.sha256 = $hash
        Write-Host "  -> $hash" -ForegroundColor Green
    } catch {
        Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
}

foreach ($key in $json.tools.PSObject.Properties.Name) {
    Update-Entry -Entry $json.tools.$key -Label "tools.$key" -Force:$Force
}

foreach ($wheel in $json.pip_packages.wheels) {
    Update-Entry -Entry $wheel -Label "pip_packages.wheels[$($wheel.name)]" -Force:$Force
}

foreach ($key in $json.files.PSObject.Properties.Name) {
    Update-Entry -Entry $json.files.$key -Label "files.$key" -Force:$Force
}

Remove-Item $tmpDir -Recurse -ErrorAction SilentlyContinue

$json | ConvertTo-Json -Depth 10 | Set-Content $DependenciesFile -Encoding UTF8
Write-Host "`nDone. Review with: git diff scripts/dependencies.json" -ForegroundColor Yellow
