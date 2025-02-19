# Get-Report.ps1
# Author: Dylan Harvey
# Gathers information regarding the machine and its services. Much more detailed than Info.ps1
# Manual Version - Useful for threat hunting and hardening, writes to output file.

$outFile = ".\report.txt"

# Gather System Info
$hostname = $env:COMPUTERNAME
$domainRole = (Get-WmiObject Win32_ComputerSystem).DomainRole
$domainRoleText = @("Standalone Workstation", "Member Workstation", "Standalone Server", "Member Server", "Backup Domain Controller", "Primary Domain Controller")[$domainRole]
$os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture
$uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime | Select-Object Days, Hours, Minutes, Seconds
$installedRoles = Get-WindowsFeature | Where-Object { $_.Installed -eq $true } | Select-Object Name, DisplayName
$openPorts = Get-NetTCPConnection | Where-Object { $_.State -eq "Listen" } | Select-Object LocalAddress, LocalPort, OwningProcess
$runningServices = Get-Service | Where-Object { $_.Status -eq "Running" } | Select-Object Name, DisplayName

# Firewall
$firewallStatus = Get-NetFirewallProfile | Select-Object Name, Enabled

# Network Configuration
$networkAdapters = Get-NetIPConfiguration | Select-Object InterfaceAlias, IPv4Address, InterfaceDescription
$DNSServers = Get-DnsClientServerAddress | Select-Object -ExpandProperty ServerAddresses

# Shared Folders
$sharedFolders = Get-SmbShare | Select-Object Name, Path, Description

# Group Policy Rules
$gpRemoteDesktop = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server").fDenyTSConnections -eq 0
$gpNLA = Get-WmiObject -class Win32_TSGeneralSetting -Namespace root\cimv2\terminalservices | Select-Object UserAuthenticationRequired

$report = @"
=== Machine Info === 
Hostname: $hostname
Domain Role: $domainRoleText
OS Information: $($os.Caption) ($($os.Version), $($os.OSArchitecture))
Uptime: $($uptime.Days)d, $($uptime.Hours)h:$($uptime.Minutes)m:$($uptime.Seconds)s

=== Installed Roles & Features === 
$($installedRoles.DisplayName -join "`n")

=== Running Important Services ===
$($runningServices.DisplayName -join "`n")

=== Firewall Status ===
$($firewallStatus | Format-Table -AutoSize | Out-String)

=== Listening Ports ===
$($openPorts | Format-Table -AutoSize | Out-String)

=== Network Configuration ===
$($networkAdapters | Format-Table -AutoSize | Out-String)

=== DNS Servers ===
$($DNSServers -join "`n")

=== Shared Folders ===
$($sharedFolders | Out-String)

=== Group Policy ===
Remote Desktop: $(if ($gpRemoteDesktop -eq $true) {"Enabled"} else {"Disabled"})
NLA: $(if ($gpNLA -eq $true) {"Enabled"} else {"Disabled"})
"@

Write-Host $report
$report | Out-File $outFile
Write-Host "Report saved to '$outFile'" -ForegroundColor Green
