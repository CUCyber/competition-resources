# Install-Firefox.ps1
# Author: Dylan Harvey
# Downloads and installs Firefox silently. Has option to uninstall.
param (
    [switch]$Uninstall
)

[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
$global:ProgressPreference = "SilentlyContinue"

$DownloadUrl = "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US"
$InstallerPath = "$env:TEMP\FirefoxInstaller.exe"

function Install-Firefox {
    Write-Host "Downloading Firefox..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath

    Write-Host "Installing Firefox..." -ForegroundColor Magenta
    Start-Process -FilePath $InstallerPath -ArgumentList "/S" -Wait

    Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue

    Write-Host "Firefox installed." -ForegroundColor Green
}

function Uninstall-Firefox {
    Write-Host "Uninstalling Firefox..." -ForegroundColor Yellow

    $UninstallPath = "${env:ProgramFiles}\Mozilla Firefox\uninstall\helper.exe"

    if (Test-Path $UninstallPath) {
        Write-Host "Removing Firefox..." -ForegroundColor Magenta
        Start-Process -FilePath $UninstallPath -ArgumentList "/S" -Wait
        Write-Host "Firefox removed." -ForegroundColor Green
    } else {
        Write-Warning "Firefox uninstaller not found at $UninstallPath"
    }
}

if ($Uninstall) {
    Uninstall-Firefox
} else {
    Install-Firefox
}
