# Install-Sysmon.ps1
# Author: Dylan Harvey
# Downloads and installs Sysmon.
# TODO: Add uninstall flag (Sysmon64.exe -u force)

[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
$global:ProgressPreference = "SilentlyContinue"

$installPath = "C:\Windows\Sysmon"
New-Item -ItemType Directory -Force -Path $installPath | Out-Null;

Write-Host "Downloading Sysmon..." -ForegroundColor Cyan
Invoke-WebRequest -Uri https://download.sysinternals.com/files/Sysmon.zip -Outfile "$installPath.zip"
Expand-Archive -Path "$installPath.zip" -DestinationPath $installPath -Force

Write-Host "Downloading Configuration File..." -ForegroundColor Cyan
Invoke-WebRequest -Uri https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml -Outfile "$installPath\sysmonconfig-export.xml"

Write-Host "Installing Sysmon..." -ForegroundColor Magenta
Start-Process -FilePath "$installPath\Sysmon64.exe" -ArgumentList "-accepteula -i `"$installPath\sysmonconfig-export.xml`"" -Wait -NoNewWindow

Write-Host "Sysmon Installed!" -ForegroundColor Green
