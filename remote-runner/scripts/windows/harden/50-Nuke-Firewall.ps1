# 50-Firewall.ps1
# Author: Dylan Harvey
# Description: Automated firewall hardening script to lock down machines, can be destructive
# YOU WILL NEED TO MANUALLY ADD RULES FOR SERVICES AND/OR DOMAIN

# === CONFIG ===
$AllowIPs             = @("10.2.0.0/24")         # CHANGE, exact IPs preferable, supports CIDR, be careful with VPNs masquerade, empty list means any!
$DisableExistingRules = $true                    # DESTRUCTIVE ACTION!!! WILL BREAK SERVICES
$InboundAction        = "Block"                  # default Block
$OutboundAction       = "Block"                  # default Allow (Block super strict, will break services but also stop C2+RevShell)
$BACKUP_PATH          = "C:\firewall_backup.wfw"
$BLUE_RULE_NAME       = "BLUE_MGMT"
$BLACK_RULE_NAME      = "BTA"
$BLACK_TEAM_EXE       = "C:\Program Files\BTA\bta.exe"  # Double check path
$PROTECTED_RULES      = @($BLUE_RULE_NAME, $BLACK_RULE_NAME)

Write-Host "[*] Backing up firewall rules..."
if (Test-Path -Path $BACKUP_PATH -PathType Leaf) {
    Write-Host "WARNING: Found existing backup at $BACKUP_PATH, moving to $($BACKUP_PATH).old"
    Move-Item -Path $BACKUP_PATH -Destination "$($BACKUP_PATH).old" -Force
}
netsh advfirewall export $BACKUP_PATH

Write-Host "[*] Enabling firewall for all profiles..."
Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True
Set-NetFirewallProfile -Profile Domain, Public, Private -DefaultInboundAction $InboundAction -DefaultOutboundAction $OutboundAction

Write-Host "[*] Allowing IPs..."
New-NetFirewallRule -DisplayName $BLACK_RULE_NAME -Direction Outbound -Program $BLACK_TEAM_EXE -Action Allow -Description "Black team pls don't hate us"
New-NetFirewallRule -DisplayName $BLUE_RULE_NAME -Direction Inbound -Action Allow -RemoteAddress $AllowIPs -Description "Blue Team Inbound"
New-NetFirewallRule -DisplayName $BLUE_RULE_NAME -Direction Outbound -Action Allow -RemoteAddress $AllowIPs -Description "Blue Team Outbound"

if ($DisableExistingRules) {
    Write-Host "[*] Disabling existing rules..."
    Get-NetFirewallRule | Where-Object { $_.DisplayName -notin $PROTECTED_RULES -and $_.Enabled -eq 'True' } | Disable-NetFirewallRule
}
