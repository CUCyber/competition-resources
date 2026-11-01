# Author BlueNitrobotX

# Enable firewall and set defaults to block
Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Block

# Fetch all relevant firewall rules
Write-Host "Fetching firewall rules..." -ForegroundColor Cyan
$allRules = @(Get-NetFirewallRule -Enabled True -Action Allow -Direction Inbound)
$total = $allRules.Count

if ($total -eq 0) {
    Write-Host "No enabled inbound Allow rules found on this machine." -ForegroundColor Yellow
    exit 2
}

Write-Host "Scanning $total rules...`n" -ForegroundColor Cyan

# Convert profile string to bitmask safely
function Get-ProfileMask {
    param($profile)

    if ($profile -is [int]) { return $profile }

    $mask = 0

    if ($profile -match "Domain")  { $mask = $mask -bor 1 }
    if ($profile -match "Private") { $mask = $mask -bor 2 }
    if ($profile -match "Public")  { $mask = $mask -bor 4 }

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
    $progAny    = ($app.Program -eq $null -or $app.Program -eq "Any" -or $app.Program -eq "System")

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

    if ($localAny -and $remoteAny -and $addrAny -and $progAny -and $profileAny) {

        $results += [PSCustomObject]@{
            Name      = $r.DisplayName
            Direction = $r.Direction
            Profile   = $r.Profile
            Program   = $app.Program
        }

        # Disable rule
        Write-Host "Disabling rule: $($r.DisplayName)"
        Disable-NetFirewallRule -InputObject $r
    }
}

# Summary line
Write-Host "Scan complete. $current rules checked, $($results.Count) match(es) found.`n" -ForegroundColor Cyan

if ($results.Count -gt 0) {
    $results
} else {
    Write-Host "No matching firewall rules found." -ForegroundColor Yellow
}

exit 0