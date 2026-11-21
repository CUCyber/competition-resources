# Author BlueNitrobotX
# Quick firewall blacklist updater
#Requires -RunAsAdministrator


$ErrorActionPreference = 'Stop'
$ips = @()

Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Updating firewall blacklist`n"
Write-Host 'Enter IPs to blacklist (blank line to finish):'


# Collect individual addresses. A blank line finishes input.
do {
    $entry = Read-Host
    if ([string]::IsNullOrWhiteSpace($entry)) { break }

    $text = $entry.Trim()
    $address = $null

    # Require full dotted-decimal IPv4 or a valid IPv6 address.
    if ([ipaddress]::TryParse($text, [ref]$address) -and
        ($address.AddressFamily -ne 'InterNetwork' -or $text -eq $address.ToString())) {
        $ips += $address.ToString()
    } else {
        Write-Warning "Skipping invalid IP: '$entry'"
    }
} while ($true)
if ($ips.Count -eq 0) { return }


# Keep simultaneous runs from overwriting each other's additions.
$lock = [System.Threading.Mutex]::new($false, 'Global\WinMaster-Blocklist-Update')
$locked = $false
try {
    try { $locked = $lock.WaitOne(15000) }
    catch [System.Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { throw 'Blacklist is busy. Try again.' }

    # Read both managed rules so previously blocked addresses are preserved.
    $names = 'WinMaster-Blocklist-Inbound', 'WinMaster-Blocklist-Outbound'
    $rules = @(Get-NetFirewallRule -PolicyStore PersistentStore | Where-Object { $_.Name -in $names })
    foreach ($rule in $rules) {
        $old = ($rule | Get-NetFirewallAddressFilter).RemoteAddress
        if ($rule.Name -ne "WinMaster-Blocklist-$($rule.Direction)" -or
            $rule.Action -ne 'Block' -or -not $old -or $old -contains 'Any') {
            throw "Check the direction, action and addresses of '$($rule.Name)'."
        }
        $ips += $old
    }
    $ips = @($ips | Sort-Object -Unique)

    # Update existing rules, including the outbound blocklist if previously configured.
    foreach ($rule in $rules) {
        Set-NetFirewallRule -Name $rule.Name -RemoteAddress $ips -Profile Any -Enabled True
    }
    foreach ($direction in 'Inbound', 'Outbound') {
        $name = "WinMaster-Blocklist-$direction"
        if ($name -notin $rules.Name) {
            New-NetFirewallRule -Name $name -DisplayName "WinMaster IP blocklist ($direction)" `
                -Direction $direction -Action Block -RemoteAddress $ips -Profile Any | Out-Null
        }
    }
} finally {
    if ($locked) { $lock.ReleaseMutex() }
    $lock.Dispose()
}

Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Firewall blacklist updated`n"
