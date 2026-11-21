# Install-Sysinternals.ps1
# Author: Dylan Harvey - Modified by BlueNitrobotX
# Downloads and installs SysinternalsSuite.
param (
    [switch]$Uninstall,
    [string]$pathParam
)

# Make failures terminating so the try/catch (and the exit code Startup.ps1 checks) actually work
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$global:ProgressPreference = "SilentlyContinue"

if($pathParam) {
    $installPath = $pathParam
} else {
    $installPath = "C:\SysinternalsSuite"
}

function Install-Sysinternals {
    Write-Host "Installing Sysinternals..."
    $stage = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    $zipPath = Join-Path $stage 'suite.zip'
    $extracted = Join-Path $stage 'suite'
    $createdStage = $null
    try {
        $createdStage = New-Item -Path $stage -ItemType Directory
        Write-Host "Downloading Sysinternals..." -ForegroundColor Cyan
        # -UseBasicParsing: avoids the IE-engine dependency of Invoke-WebRequest in Windows PowerShell 5.1
        Invoke-WebRequest -UseBasicParsing -Uri "https://download.sysinternals.com/files/SysinternalsSuite.zip" -OutFile $zipPath

        Write-Host "Extracting Sysinternals..." -ForegroundColor Magenta
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extracted

        # Sanity-check the tools Master/Startup depend on, since they get run as SYSTEM
        foreach($exe in "PsExec64.exe", "sigcheck64.exe") {
            $exePath = Join-Path $extracted $exe
            if(-not (Test-Path -Path $exePath -PathType Leaf)) {
                throw "$exe is missing after extraction"
            }
            if(-not (& "$PSScriptRoot\Test-SysinternalsSignature.ps1" $exePath)) {
                throw "$exe does not have a valid Microsoft signature"
            }
        }

        New-Item -Path $installPath -ItemType Directory -Force | Out-Null
        Get-ChildItem -LiteralPath $extracted -Force |
            Copy-Item -Destination $installPath -Recurse -Force
        Write-Host "Sysinternals installed to $installPath" -ForegroundColor Green
    }
    catch {
        Write-Host "Sysinternals install failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    finally {
        if ($createdStage) {
            Remove-Item -LiteralPath $createdStage.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Uninstall-Sysinternals {
    Write-Host "Uninstalling Sysinternals..."
    Write-Host "Removing Sysinternals..." -ForegroundColor Magenta
    Remove-Item -Path $installPath -Recurse -Force
    Write-Host "Sysinternals removed." -ForegroundColor Green
}

if ($Uninstall) {
    # Was commented out, so -Uninstall silently did nothing. Re-comment if that was intentional.
    Uninstall-Sysinternals
} else {
    Install-Sysinternals
}
