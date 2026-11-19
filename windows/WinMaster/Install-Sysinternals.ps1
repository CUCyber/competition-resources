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
$zipPath = "$installPath.zip"

function Install-Sysinternals {
    Write-Host "Installing Sysinternals..."
    try {
        Write-Host "Downloading Sysinternals..." -ForegroundColor Cyan
        # -UseBasicParsing: avoids the IE-engine dependency of Invoke-WebRequest in Windows PowerShell 5.1
        Invoke-WebRequest -UseBasicParsing -Uri "https://download.sysinternals.com/files/SysinternalsSuite.zip" -OutFile $zipPath

        Write-Host "Extracting Sysinternals..." -ForegroundColor Magenta
        Expand-Archive -Path $zipPath -DestinationPath $installPath -Force

        # Sanity-check the tools Master/Startup depend on, since they get run as SYSTEM
        foreach($exe in "PsExec64.exe", "sigcheck64.exe") {
            $exePath = Join-Path $installPath $exe
            if(-not (Test-Path -Path $exePath -PathType Leaf)) {
                throw "$exe is missing after extraction"
            }
            $sig = Get-AuthenticodeSignature -FilePath $exePath
            if($sig.Status -in "NotSigned", "HashMismatch" -or $sig.SignerCertificate.Subject -notmatch "O=Microsoft Corporation") {
                throw "$exe failed signature check (status: $($sig.Status))"
            }
        }

        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Write-Host "Sysinternals installed to $installPath" -ForegroundColor Green
    }
    catch {
        Write-Host "Sysinternals install failed: $($_.Exception.Message)" -ForegroundColor Red
        # Clean up so the next run starts fresh instead of finding a half-extracted folder
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $installPath -Recurse -Force -ErrorAction SilentlyContinue
        exit 1
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
