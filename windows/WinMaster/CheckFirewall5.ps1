# Author BlueNitrobotX

# Enable firewall and set defaults to block
Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Block

Write-Host "`n====== Auditing Firewall ======`n"

# Fetch all relevant firewall rules
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Fetching firewall rules..." -ForegroundColor Cyan
$allRules = @(Get-NetFirewallRule -Enabled True -Action Allow -Direction Inbound)
$total = $allRules.Count

if ($total -eq 0) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] No enabled inbound Allow rules found on this machine." -ForegroundColor Yellow
    exit 2
}

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Scanning $total rules...`n" -ForegroundColor Cyan

# Convert profile string to bitmask safely
function Get-ProfileMask {
    param($profileValue)

    $text = "$profileValue"

    if ($text -match "Any") { return 7 }

    $mask = 0
    if ($text -match "Domain")  { $mask = $mask -bor 1 }
    if ($text -match "Private") { $mask = $mask -bor 2 }
    if ($text -match "Public")  { $mask = $mask -bor 4 }

    return $mask
}

$results = @()
$current = 0

foreach ($r in $allRules) {
    $current++

    $p   = Get-NetFirewallPortFilter        -AssociatedNetFirewallRule $r
    $a   = Get-NetFirewallAddressFilter     -AssociatedNetFirewallRule $r
    $app = Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $r

    # Normalize values for safer comparisons
    $localAny   = ($p.LocalPort  -eq $null -or @($p.LocalPort)  -contains "Any")
    $remoteAny  = ($p.RemotePort -eq $null -or @($p.RemotePort) -contains "Any")
    $addrAny    = ($a.RemoteAddress -eq $null -or @($a.RemoteAddress) -contains "Any")

    $profileMask = Get-ProfileMask $r.Profile
    $profileAny  = ($profileMask -eq 7)   # Domain + Private + Public

    # Skip UWP/MSIX rules (Package != $null)
    if ($r.Package -ne $null) { continue }

    # Skip service-based rules
    if ($r.Service -ne $null -and $r.Service -ne "") { continue }

    # Skip rules with no real program path
    # (UWP apps show "System" or "Any")
    $isRealExe = ($app.Program -and $app.Program -match "\\.*\.exe$")
    if (-not $isRealExe) { continue }

    if ($localAny -and $remoteAny -and $addrAny -and $profileAny) {

        $results += [PSCustomObject]@{
            Name      = $r.DisplayName
            Direction = $r.Direction
            Profile   = $r.Profile
            Program   = $app.Program
        }

        # Disable rule
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Disabling rule: $($r.DisplayName)"
        Disable-NetFirewallRule -InputObject $r
    }
}

# Summary line
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Scan complete. $current rules checked, $($results.Count) match(es) found.`n" -ForegroundColor Cyan

if ($results.Count -gt 0) {
    $results
}

exit 0