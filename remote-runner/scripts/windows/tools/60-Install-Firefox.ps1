# 60-Install-Firefox.ps1
# Author: Dylan Harvey
# Downloads and installs Firefox silently.
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
$global:ProgressPreference = "SilentlyContinue"

$DownloadUrl = "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US"
$InstallerPath = "$env:TEMP\FirefoxInstaller.exe"

Write-Host "Downloading Firefox..."
Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath

Write-Host "Installing Firefox..."
Start-Process -FilePath $InstallerPath -ArgumentList "/S" -Wait

Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue

Write-Host "Firefox installed."
