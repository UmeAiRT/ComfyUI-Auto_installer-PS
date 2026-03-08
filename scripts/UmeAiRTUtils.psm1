<#
.SYNOPSIS
    Shared utility functions for UmeAiRT scripts.
.DESCRIPTION
    This module contains common functions used across the ComfyUI installation and update scripts,
    including logging, file downloading, command execution, and GPU detection.
.AUTHOR
    UmeAiRT
#>

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Write-Log {
    <#
    .SYNOPSIS
        Writes a message to the console and the log file.
    .DESCRIPTION
        Handles logging with different levels (indentation) and colors.
        Automatically adds timestamps to the log file.
    .PARAMETER Message
        The message string to log.
    .PARAMETER Level
        The indentation/formatting level:
        -2 : Raw output (no prefix)
         0 : Step header (Yellow, surrounded by separators)
         1 : Main item ("  - ")
         2 : Sub-item ("    -> ")
         3 : Info/Debug ("      [INFO] ")
    .PARAMETER Color
        Console text color (e.g., "Green", "Red", "Yellow"). Default depends on Level.
    #>
    param(
        [string]$Message,
        [int]$Level = 1,
        [string]$Color = "Default"
    )
    
    # Ensure $logFile is defined, otherwise use fallback
    if (-not $global:logFile) {
        $global:logFile = Join-Path $PSScriptRoot "default_module_log.txt"
    }

    $prefix = ""
    $defaultColor = "White"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    try {
        switch ($Level) {
            -2 { $prefix = "" }
            0 {
                $global:currentStep++
                $stepStr = "[Step $($global:currentStep)/$($global:totalSteps)]"
                $wrappedMessage = "| $stepStr $Message |"
                $separator = "=" * ($wrappedMessage.Length)
                $consoleMessage = "`n$separator`n$wrappedMessage`n$separator"
                $logMessage = "[$timestamp] $stepStr $Message"
                $defaultColor = "Yellow"
            }
            1 { $prefix = "  - " }
            2 { $prefix = "    -> " }
            3 { $prefix = "      [INFO] " }
        }
        if ($Color -eq "Default") { $Color = $defaultColor }
        if ($Level -ne 0) {
            $logMessage = "[$timestamp] $($prefix.Trim()) $Message"
            $consoleMessage = "$prefix$Message"
        }
        Write-Host $consoleMessage -ForegroundColor $Color
        Add-Content -Path $global:logFile -Value $logMessage -Encoding utf8 -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "Internal error in Write-Log: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-AndLog {
    <#
    .SYNOPSIS
        Executes an external command, logging both the command and its output.
    .DESCRIPTION
        Runs an executable with arguments. Captures stdout/stderr to a temporary file,
        logs it, and throws an exception on failure (unless IgnoreErrors is set).
    .PARAMETER File
        Path to the executable.
    .PARAMETER Arguments
        Arguments string for the executable.
    .PARAMETER IgnoreErrors
        If set, script execution continues even if the command returns a non-zero exit code.
    #>
    param(
        [string]$File,
        [string]$Arguments,
        [switch]$IgnoreErrors
    )
    
    # Ensure $logFile is defined
    if (-not $global:logFile) {
        $global:logFile = Join-Path $PSScriptRoot "default_module_log.txt"
    }
    
    $tempLogFile = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString() + ".tmp")
    try {
        Write-Log "Executing: $File $Arguments" -Level 3 -Color DarkGray
        $CommandToRun = "& `"$File`" $Arguments *>&1 | Out-File -FilePath `"$tempLogFile`" -Encoding utf8"
        Invoke-Expression $CommandToRun
        $output = if (Test-Path $tempLogFile) { Get-Content $tempLogFile } else { @() }

        if ($LASTEXITCODE -ne 0 -and -not $IgnoreErrors) {
            Write-Log "ERROR: Command failed with code $LASTEXITCODE." -Color Red
            Write-Log "Command: $File $Arguments" -Color Red
            Write-Log "Error Output:" -Color Red
            $output | ForEach-Object { Write-Host $_ -ForegroundColor Red; Add-Content -Path $global:logFile -Value $_ -Encoding utf8 -ErrorAction SilentlyContinue }
            throw "Command execution failed. Check logs."
        }
        else {
            Add-Content -Path $global:logFile -Value $output -Encoding utf8 -ErrorAction SilentlyContinue
        }
    }
    catch {
        $errMsg = "FATAL ERROR executing: $File $Arguments. Error: $($_.Exception.Message)"
        Write-Log $errMsg -Color Red
        Add-Content -Path $global:logFile -Value $errMsg -Encoding utf8 -ErrorAction SilentlyContinue
        Read-Host "A fatal error occurred. Press Enter to exit."
        exit 1
    }
    finally {
        if (Test-Path $tempLogFile) { Remove-Item $tempLogFile -ErrorAction SilentlyContinue }
    }
}

function Confirm-FileHash {
    <#
    .SYNOPSIS
        Verifies a file's cryptographic hash. Deletes the file and throws on mismatch.
    .PARAMETER Path
        Path to the file to verify.
    .PARAMETER Expected
        Expected hash value (hex string, case-insensitive).
    .PARAMETER Algorithm
        Hash algorithm. Default: SHA256.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Expected,
        [string]$Algorithm = 'SHA256'
    )
    $actual = (Get-FileHash -Path $Path -Algorithm $Algorithm).Hash
    if ($actual -ne $Expected.ToUpper()) {
        Remove-Item $Path -Force -ErrorAction SilentlyContinue
        throw "SECURITY: Hash mismatch for '$(Split-Path $Path -Leaf)'`n  Expected: $Expected`n  Actual:   $actual`n  File deleted. Aborting."
    }
    Write-Log "  [verified] $(Split-Path $Path -Leaf)" -Color Green
}

function Confirm-Authenticode {
    <#
    .SYNOPSIS
        Verifies the Authenticode signature on a Windows binary. Deletes and throws on failure.
    .PARAMETER Path
        Path to the signed file (.exe, .msi, etc.).
    .PARAMETER ExpectedSubject
        Substring expected in the signing certificate's Subject field (e.g. "Microsoft Corporation").
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedSubject
    )
    $sig = Get-AuthenticodeSignature -FilePath $Path
    if ($sig.Status -ne 'Valid') {
        Remove-Item $Path -Force -ErrorAction SilentlyContinue
        throw "SECURITY: Invalid Authenticode signature on '$(Split-Path $Path -Leaf)': $($sig.Status). File deleted."
    }
    if ($sig.SignerCertificate.Subject -notmatch [regex]::Escape($ExpectedSubject)) {
        Remove-Item $Path -Force -ErrorAction SilentlyContinue
        throw "SECURITY: Unexpected signer on '$(Split-Path $Path -Leaf)'`n  Expected subject: $ExpectedSubject`n  Got: $($sig.SignerCertificate.Subject)`n  File deleted."
    }
    Write-Log "  [authenticated] $(Split-Path $Path -Leaf) — $($sig.SignerCertificate.Subject)" -Color Green
}

function Set-ManagerUseUv {
    <#
    .SYNOPSIS
        Ensures ComfyUI Manager's config.ini has use_uv = True.
    .PARAMETER InstallPath
        Root install directory (parent of the user/ folder).
    #>
    param([string]$InstallPath)
    $configPath = Join-Path $InstallPath "user/__manager/config.ini"
    $configDir  = Split-Path $configPath -Parent
    if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
    if (Test-Path $configPath) {
        $content = Get-Content $configPath -Raw
        if ($content -match 'use_uv\s*=') {
            $content = $content -replace 'use_uv\s*=\s*\S+', 'use_uv = True'
        } else {
            $content = $content.TrimEnd() + "`nuse_uv = True`n"
        }
        Set-Content $configPath $content -Encoding UTF8
    } else {
        @"
[default]
use_uv = True
"@ | Set-Content $configPath -Encoding UTF8
    }
    Write-Log "ComfyUI Manager: use_uv = True" -Color Green
}

function Save-File {
    <#
    .SYNOPSIS
        Downloads a file using aria2c (if available) or Invoke-WebRequest.
    .DESCRIPTION
        Attempts to download a file from a URI to a local path.
        It prioritizes aria2c for speed/resuming, falling back to PowerShell's native Invoke-WebRequest.
        If ExpectedHash is provided and non-empty, verifies SHA256 after download.
    .PARAMETER Uri
        The source URL.
    .PARAMETER OutFile
        The destination file path.
    .PARAMETER ExpectedHash
        Optional SHA256 hash to verify after download. Empty string skips verification.
    #>
    param(
        [string]$Uri,
        [string]$OutFile,
        [string]$ExpectedHash = ""
    )
    
    if (Test-Path $OutFile) {
        $FileName = Split-Path -Path $OutFile -Leaf
        Write-Log "File '$FileName' already exists. Skipping download." -Level 2 -Color Green
        if ($ExpectedHash -and $ExpectedHash.Trim() -ne "") {
            Confirm-FileHash -Path $OutFile -Expected $ExpectedHash
        }
        return
    }
    Write-Log "Downloading `"$($Uri.Split('/')[-1])`"" -Level 2 -Color DarkGray
    
    # Expected path for aria2c.exe (installed by Phase 1)
    $aria2ExePath = Join-Path $env:LOCALAPPDATA "aria2\aria2c.exe"
    
    try {
        # --- Attempt 1: Aria2 ---
        if (-not (Test-Path $aria2ExePath)) {
            throw "aria2c.exe not found at '$aria2ExePath'."
        }
        
        Write-Log "Using aria2c from '$aria2ExePath'..." -Level 3
        $OutDir = Split-Path -Path $OutFile -Parent
        $OutName = Split-Path -Path $OutFile -Leaf

        # Recreate argument string
        $aria2Args = "--console-log-level=warn --disable-ipv6 --quiet=true -x 16 -s 16 -k 1M --dir=`"$OutDir`" --out=`"$OutName`" `"$Uri`""
        
        Write-Log "Executing: $aria2ExePath $aria2Args" -Level 3 -Color DarkGray

        # Use Invoke-Expression to force PowerShell to parse argument string correctly
        $CommandToRun = "& `"$aria2ExePath`" $aria2Args 2>&1"
        $output = Invoke-Expression $CommandToRun | Out-String
        Add-Content -Path $global:logFile -Value $output -Encoding utf8 -ErrorAction SilentlyContinue

        if ($LASTEXITCODE -ne 0) {
            # Catch failure and throw exception for fallback
            throw "aria2c command failed with code $LASTEXITCODE. Output: $output"
        }
        
        Write-Log "Download successful (aria2c)." -Level 3

    }
    catch {
        # --- Attempt 2: Fallback PowerShell ---
        Write-Log "aria2c failed or not found ('$($_.Exception.Message)'), using slower Invoke-WebRequest..." -Level 3
        
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Tls13
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
            Write-Log "Download successful (PowerShell)." -Level 3
        }
        catch {
            Write-Log "ERROR: Download failed for '$Uri'. Both aria2c and PowerShell failed. Error: $($_.Exception.Message)" -Color Red
            throw "Download failed."
        }
    }
    if ($ExpectedHash -and $ExpectedHash.Trim() -ne "") {
        Confirm-FileHash -Path $OutFile -Expected $ExpectedHash
    }
}

function Read-UserChoice {
    <#
    .SYNOPSIS
        Prompts the user to select from a list of choices.
    .DESCRIPTION
        Displays a prompt and a list of valid choices. Loops until a valid answer is received.
    .PARAMETER Prompt
        The question to ask.
    .PARAMETER Choices
        An array of strings describing the options.
    .PARAMETER ValidAnswers
        An array of valid input strings (case-insensitive).
    .OUTPUTS
        The user's choice (converted to uppercase).
    #>
    param(
        [string]$Prompt,
        [string[]]$Choices,
        [string[]]$ValidAnswers
    )

    $choice = ''
    while ($choice -notin $ValidAnswers) {
        Write-Log "`n$Prompt" -Color Yellow
        foreach ($line in $Choices) {
            Write-Host "  $line" -ForegroundColor Green
        }
        $choice = (Read-Host "Enter your choice and press Enter").ToUpper()
        if ($choice -notin $ValidAnswers) {
            Write-Log "Invalid choice. Please try again." -Color Red
        }
    }
    return $choice
}

function Test-NvidiaGpu {
    <#
    .SYNOPSIS
        Checks for the presence of an NVIDIA GPU via nvidia-smi.
    .DESCRIPTION
        Runs `nvidia-smi -L` to detect GPUs. This usually requires the Conda environment
        (or system drivers) to be available/activated.
    .OUTPUTS
        Boolean ($true if detected, $false otherwise).
    #>
    Write-Log "Checking for NVIDIA GPU..." -Level 1
    try {
        # nvidia-smi.exe is available (from conda env or system)
        # -L lists GPUs. 2>&1 merges error and output streams.
        $gpuCheck = & "nvidia-smi" -L 2>&1 | Out-String

        if ($LASTEXITCODE -eq 0 -and $gpuCheck -match 'GPU 0:') {
            Write-Log "NVIDIA GPU detected." -Level 2 -Color Green
            Write-Log "$($gpuCheck.Trim())" -Level 3
            return $true
        }
        else {
            Write-Log "WARNING: No NVIDIA GPU detected. Skipping GPU-only packages." -Level 1 -Color Yellow
            Write-Log "nvidia-smi output (for debugging): $gpuCheck" -Level 3
            return $false
        }
    }
    catch {
        Write-Log "WARNING: 'nvidia-smi' command failed. Assuming no GPU." -Level 1 -Color Yellow
        Write-Log "Error details: $($_.Exception.Message)" -Level 3
        return $false
    }
}

function Get-GpuVramInfo {
    <#
    .SYNOPSIS
        Queries NVIDIA GPU information including name and total VRAM.
    .DESCRIPTION
        Uses nvidia-smi to get GPU name and memory.
    .OUTPUTS
        PSObject with GpuName (string) and VramGiB (int) properties, or $null if detection fails.
    #>

    if (-not (Get-Command 'nvidia-smi' -ErrorAction SilentlyContinue)) {
        return $null
    }

    try {
        # Properly quote arguments to handle spaces in CSV format; nounits removes " MiB" suffix
        $gpuInfoCsv = & nvidia-smi --query-gpu="name,memory.total" --format="csv,noheader,nounits" 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Log "nvidia-smi query failed with exit code $LASTEXITCODE" -Level 3 -Color Yellow
            return $null
        }

        if ($gpuInfoCsv) {
            $gpuInfoParts = $gpuInfoCsv.Split(',')
            $gpuName = $gpuInfoParts[0].Trim()
            # nounits format gives raw MiB value, no string replacement needed
            $gpuMemoryMiB = [int]$gpuInfoParts[1].Trim()
            $gpuMemoryGiB = [math]::Round($gpuMemoryMiB / 1024)

            return [PSCustomObject]@{
                GpuName = $gpuName
                VramGiB = $gpuMemoryGiB
            }
        }
    }
    catch {
        Write-Log "Could not retrieve GPU information. Error: $($_.Exception.Message)" -Level 3 -Color Red
    }

    return $null
}

function Test-PyVersion {
    <#
    .SYNOPSIS
        Checks if a specific Python command corresponds to version 3.13.
    .DESCRIPTION
        Runs `<Command> <Arguments> --version` and checks if output matches "Python 3.13".
    .PARAMETER Command
        The executable (e.g., "python", "py").
    .PARAMETER Arguments
        The arguments (e.g., "-3.13", "").
    .OUTPUTS
        Boolean ($true if 3.13 is detected).
    #>
    param(
        [string]$Command,
        [string]$Arguments
    )
    
    try {
        # Execute command to get version (redirect stderr to stdout)
        $output = & $Command $Arguments --version 2>&1
        
        # Check if output contains "Python 3.13"
        if ($output -match "Python 3\.13") { 
            return $true 
        }
    }
    catch {
        # Command failed or not found
        return $false
    }
    
    return $false
}

function Read-UserConfig {
    <#
    .SYNOPSIS
        Reads GitHub repo settings from umeairt-user-config.json (or deprecated repo-config.json)
        and outputs KEY=VALUE lines to stdout.
    .PARAMETER UserConfigFile
        Path to umeairt-user-config.json.
    .PARAMETER RepoConfigFile
        Path to repo-config.json (deprecated fallback).
    .OUTPUTS
        Four lines: GhUser=..., GhRepoName=..., GhBranch=..., ConfigSource=...
    #>
    param(
        [Parameter(Mandatory)][string]$UserConfigFile,
        [Parameter(Mandatory)][string]$RepoConfigFile
    )

    $gh  = 'UmeAiRT'
    $gn  = 'ComfyUI-Auto_installer'
    $gb  = 'main'
    $src = '(defaults)'

    if (Test-Path $UserConfigFile) {
        $c   = Get-Content $UserConfigFile -Raw | ConvertFrom-Json
        $src = 'umeairt-user-config.json'
        if ($c.PSObject.Properties['gh_user']     -and $c.gh_user)     { $gh = $c.gh_user }
        if ($c.PSObject.Properties['gh_reponame'] -and $c.gh_reponame) { $gn = $c.gh_reponame }
        if ($c.PSObject.Properties['gh_branch']   -and $c.gh_branch)   { $gb = $c.gh_branch }
    } elseif (Test-Path $RepoConfigFile) {
        $c   = Get-Content $RepoConfigFile -Raw | ConvertFrom-Json
        $src = 'repo-config.json (deprecated)'
        if ($c.gh_user)     { $gh = $c.gh_user }
        if ($c.gh_reponame) { $gn = $c.gh_reponame }
        if ($c.gh_branch)   { $gb = $c.gh_branch }
    }

    if ($gh -match '[^a-zA-Z0-9_-]')   { Write-Error 'gh_user contains invalid characters.';     exit 1 }
    if ($gn -match '[^a-zA-Z0-9_-]')   { Write-Error 'gh_reponame contains invalid characters.'; exit 1 }
    if ($gb -match '[^a-zA-Z0-9_./-]') { Write-Error 'gh_branch contains invalid characters.';   exit 1 }

    Write-Output "GhUser=$gh"
    Write-Output "GhRepoName=$gn"
    Write-Output "GhBranch=$gb"
    Write-Output "ConfigSource=$src"
}

function ConvertTo-ForwardSlash {
    <#
    .SYNOPSIS
        Normalizes path separators to forward slashes.
    .DESCRIPTION
        Replaces the OS-native directory separator with the alternate separator.
        On Windows: replaces \ with /.
        On Linux/macOS: both separators are already /, so this is a no-op.
        Accepts pipeline input for ergonomic chaining with Join-Path.
    .PARAMETER Path
        One or more path strings to normalize.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Path
    )
    process {
        foreach ($p in $Path) {
            $p.Replace(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            )
        }
    }
}

function Resolve-CleanPath {
    <#
    .SYNOPSIS
        Trims trailing slashes and normalizes to forward slashes.
    .DESCRIPTION
        Combines TrimEnd of both separator types with ConvertTo-ForwardSlash.
        Use at every point where a path arrives from user input, CLI params,
        or environment variables to ensure a consistent internal representation.
    .PARAMETER Path
        Path string to clean.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path
    )
    process {
        ConvertTo-ForwardSlash ($Path.TrimEnd('\', '/'))
    }
}

# --- END OF FILE ---
Export-ModuleMember -Function Write-Log, Invoke-AndLog, Save-File, Confirm-FileHash, Confirm-Authenticode, Set-ManagerUseUv, Test-NvidiaGpu, Read-UserChoice, Get-GpuVramInfo, Test-PyVersion, Read-UserConfig, ConvertTo-ForwardSlash, Resolve-CleanPath
