$path = "C:\Windows\Sysmon\"

New-Item -ItemType Directory -Force -Path $path | Out-Null;

Set-Location $path

Write-Host "Retrieving Sysmon..."

Invoke-WebRequest -Uri https://download.sysinternals.com/files/Sysmon.zip -Outfile Sysmon.zip

Expand-Archive Sysmon.zip

Set-Location $path\Sysmon

Write-Host "Retrieving Configuration File..."

Invoke-WebRequest -Uri https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml -Outfile sysmonconfig-export.xml

Write-Host "Installing Sysmon..."

.\sysmon64.exe -accepteula -i sysmonconfig-export.xml

Write-Host "Sysmon Installed!"
