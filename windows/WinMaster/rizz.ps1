# Author BlueNitrobotX
# Powershell profile to screw with red team


function Quit-Session { exit 0 }

# Ordinary command names resolve to aliases first in a session that loads this profile.
& {
    $cmdlets = @(
        'Get-Command', 'Get-Help', 'Get-Alias', 'Get-History', 'Get-ComputerInfo'
        'Get-Member', 'Get-Module', 'Get-Variable', 'Get-PSProvider', 'Get-Host', 'Get-CimClass'
        'Get-Location', 'Set-Location', 'Push-Location', 'Pop-Location', 'Get-PSDrive'
        'Get-ChildItem', 'Get-Item', 'Test-Path', 'Resolve-Path', 'Get-Content', 'Select-String'
        'Get-ItemProperty', 'Set-ItemProperty', 'New-Item', 'Copy-Item', 'Move-Item', 'Remove-Item'
        'Set-Content', 'Add-Content', 'Out-File', 'Get-Acl', 'Set-Acl'
        'Rename-Item', 'Clear-Content', 'Get-ItemPropertyValue', 'New-ItemProperty', 'Remove-ItemProperty'
        'Get-FileHash', 'Get-Volume', 'Get-Disk', 'Get-Partition'
        'Get-Clipboard', 'Set-Clipboard', 'Compress-Archive', 'Expand-Archive'
        'Get-LocalUser', 'Get-LocalGroup', 'Get-LocalGroupMember', 'Get-Process', 'Get-Service'
        'Get-CimInstance', 'Get-WmiObject', 'Get-WinEvent', 'Get-ScheduledTask'
        'Get-EventLog', 'Get-HotFix', 'Get-ScheduledTaskInfo', 'Get-ComputerRestorePoint'
        'Start-Service', 'Stop-Service', 'Restart-Service', 'Set-Service'
        'Get-ADDomain', 'Get-ADForest', 'Get-ADComputer', 'Get-ADUser', 'Get-ADGroup', 'Get-ADGroupMember'
        'Get-NetIPConfiguration', 'Get-NetIPAddress', 'Get-NetTCPConnection', 'Test-NetConnection'
        'Test-Connection', 'Resolve-DnsName', 'Invoke-WebRequest', 'Invoke-RestMethod'
        'Get-NetAdapter', 'Get-NetRoute', 'Get-NetNeighbor', 'Get-NetUDPEndpoint', 'Get-DnsClientCache'
        'Get-NetFirewallProfile', 'Get-NetFirewallRule', 'Get-SmbShare', 'Get-SmbConnection', 'Get-SmbMapping'
        'Get-BitsTransfer', 'Start-BitsTransfer'
        'Start-Process', 'Stop-Process', 'Invoke-Expression', 'Invoke-Command'
        'New-PSSession', 'Enter-PSSession', 'Start-Job', 'Import-Module'
        'Get-PSSession', 'Connect-PSSession', 'Import-PSSession', 'Get-Job', 'Receive-Job', 'Start-ThreadJob'
    )
    $programs = @(
        'whoami', 'hostname', 'systeminfo', 'quser', 'qwinsta', 'net', 'net1', 'nltest'
        'ipconfig', 'netstat', 'arp', 'route', 'ping', 'tracert', 'nslookup', 'netsh'
        'tasklist', 'taskkill', 'sc', 'schtasks', 'reg', 'wmic', 'wevtutil', 'icacls'
        'where', 'find', 'findstr', 'tree', 'more', 'rg', 'fd', 'git'
        'curl', 'wget', 'certutil', 'bitsadmin', 'ssh', 'scp'
        'cmd', 'powershell', 'pwsh', 'wscript', 'cscript', 'wsl', 'bash', 'sh'
        'python', 'python3', 'py', 'node', 'dotnet'
        'getmac', 'nbtstat', 'pathping', 'netdom', 'gpresult', 'dsquery', 'klist'
        'driverquery', 'fsutil', 'mountvol', 'attrib', 'takeown', 'robocopy', 'xcopy', 'fc'
        'tar', '7z', 'makecab', 'expand', 'sftp', 'ftp', 'tftp', 'winrs'
        'pythonw', 'perl', 'ruby', 'deno', 'bun', 'java', 'msbuild'
    )

    $names = $cmdlets + $programs + 'winrm', 'winrm.cmd'
    # Node package managers commonly ship as .cmd and .ps1 launchers on Windows.
    foreach ($launcher in 'npm', 'npx', 'pnpm', 'yarn') {
        $names += $launcher, "$launcher.cmd", "$launcher.ps1"
    }
    $aliasOptions = @{}
    foreach ($alias in (Microsoft.PowerShell.Utility\Get-Alias)) {
        $aliasOptions[$alias.Name] = $alias.Options
        if ($alias.Definition -in $cmdlets) { $names += $alias.Name }
    }
    foreach ($program in $programs) { $names += "$program.exe" }
    foreach ($name in $names) {
        Set-Alias -Name $name -Value Quit-Session -Scope 1 -Option ([int]$aliasOptions[$name]) -Force
    }
}
