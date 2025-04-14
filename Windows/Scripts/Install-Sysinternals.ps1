# Install-Sysinternals.ps1
# Author: Dylan Harvey
# Downloads and installs SysinternalsSuite.
# TODO: Add uninstall flag (Delete files)

[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
$global:ProgressPreference = "SilentlyContinue"

$installPath = "C:\SysinternalsSuite"

Write-Host "Downloading SysInternals..." -ForegroundColor Cyan
Invoke-WebRequest -Uri "https://download.sysinternals.com/files/SysinternalsSuite.zip" -OutFile "$installPath.zip";
Write-Host "Extracting SysInternals..." -ForegroundColor Magenta
Expand-Archive -Path "$installPath.zip" -DestinationPath $installPath

Write-Host "SysInternals installed to $installPath" -ForegroundColor Green
