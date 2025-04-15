# Install-Sysmon.ps1
# Author: Dylan Harvey
# Downloads and installs Sysmon.
param (
    [switch]$Uninstall
)

[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
$global:ProgressPreference = "SilentlyContinue"

$installPath = "C:\Windows\Sysmon"

function Install-Sysmon {
    Write-Host "Installing Sysmon..."
    New-Item -ItemType Directory -Force -Path $installPath | Out-Null;

    Write-Host "Downloading Sysmon..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri https://download.sysinternals.com/files/Sysmon.zip -Outfile "$installPath.zip"
    Expand-Archive -Path "$installPath.zip" -DestinationPath $installPath -Force

    Write-Host "Downloading configuration file..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml -Outfile "$installPath\sysmonconfig-export.xml"

    Write-Host "Installing Sysmon..." -ForegroundColor Magenta
    Start-Process -FilePath "$installPath\Sysmon64.exe" -ArgumentList "-accepteula -i `"$installPath\sysmonconfig-export.xml`"" -Wait -NoNewWindow

    Write-Host "Sysmon installed!" -ForegroundColor Green
}

function Uninstall-Sysmon {
    Write-Host "Uninstalling Sysmon..."
    Write-Host "Running Sysmon uninstaller..." -ForegroundColor Magenta
    Start-Process -FilePath "$installPath\Sysmon64.exe" -ArgumentList "-u force" -Wait -NoNewWindow

    Write-Host "Cleaning up files..." -ForegroundColor Magenta
    Remove-Item -Path $installPath -Recurse -Force

    Write-Host "Sysmon uninstalled." -ForegroundColor Green
}

if ($Uninstall) {
    Uninstall-Sysmon
} else {
    Install-Sysmon
}
