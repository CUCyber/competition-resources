# 51-Domain-Firewall.ps1
# Author: Dylan Harvey
# Description: Automated firewall script that adds rules required for AD

# === CONFIG ===
$SCOREBOARD_IPs = @("10.3.2.1")              # CHANGE, exact IPs preferable, supports CIDR
$DC_IPs         = @("10.3.4.1", "10.3.4.2")  # CHANGE, exact IPs preferable, supports CIDR
$DM_IPs         = @("10.3.4.0/24")           # CHANGE, exact IPs preferable, supports CIDR
$DOMAIN_IPs     = $DC_IPs + $DM_IPs
$ALL_IPs        = $SCOREBOARD_IPs + $DOMAIN_IPs
$BACKUP_PATH    = "C:\firewall_backup_domain.wfw"

$DomainRole = (Get-CimInstance Win32_ComputerSystem).DomainRole
$isDC = $DomainRole -in 4, 5
$isDM = $DomainRole -in 1, 3
$isDomain = $isDC -or $isDM

# TODO: There may be an option built into the FW for this
$RPC_High_Ports = "49152-65535"

$AD_Services = @(
    @{ Name="AD-DNS"; Port=53; Proto="UDP" },
    @{ Name="AD-Kerberos"; Port=88; Proto=@("TCP", "UDP") },
    @{ Name="AD-Web"; Port=@(80, 443); Proto="TCP" },
    @{ Name="AD-RPC-EPM"; Port=135; Proto=@("TCP", "UDP") },
    @{ Name="AD-LDAP"; Port=@(389, 636); Proto=@("TCP", "UDP") },
    @{ Name="AD-GC"; Port=@(3268, 3269); Proto=@("TCP", "UDP") },
    @{ Name="AD-SMB"; Port=445; Proto="TCP" },
    @{ Name="AD-Kpwd"; Port=464; Proto=@("TCP", "UDP") },
    @{ Name="AD-NTP"; Port=123; Proto="UDP" },
    @{ Name="AD-Ephemeral-RPC"; Port=$RPC_High_Ports; Proto="TCP" }
)

# === EXECUTION ===
Write-Host "[*] Backing up firewall rules..."
if (Test-Path -Path $BACKUP_PATH -PathType Leaf) {
    Write-Host "WARNING: Found existing backup at $BACKUP_PATH, moving to $($BACKUP_PATH).old"
    Move-Item -Path $BACKUP_PATH -Destination "$($BACKUP_PATH).old" -Force
}
netsh advfirewall export $BACKUP_PATH

# --- GLOBAL RULES ---
Write-Host "[*] Applying Global rules..."
$IcmpTypes = @("3", "8", "11")
New-NetFirewallRule -DisplayName "PING-In" -Direction Inbound -Action Allow -RemoteAddress "Any" -Protocol ICMPv4 -IcmpType $IcmpTypes
New-NetFirewallRule -DisplayName "PING-Out" -Direction Outbound -Action Allow -RemoteAddress "Any" -Protocol ICMPv4 -IcmpType $IcmpTypes
# Global DNS if machine needs to resolve inet
#New-NetFirewallRule -DisplayName "DNS-Out-Global" -Direction Outbound -Action Allow -Protocol UDP -RemotePort 53 -RemoteAddress @("1.1.1.1")
# Global NTP if machine needs to fix clock (time.windows.com -> 168.61.215.74)
#New-NetFirewallRule -DisplayName "NTP-Out-Global" -Direction Outbound -Action Allow -Protocol UDP -RemotePort 123 -RemoteAddress @("168.61.215.74")

if ($isDomain) {
    # --- GLOBAL DOMAIN RULES ---
    Write-Host "`n[*] Configuring Domain rules..."
    # If all else fails just enable these lol:
    #New-NetFirewallRule -DisplayName "In-All-Domain" -Direction Inbound -Action Allow -RemoteAddress $DOMAIN_IPs
    #New-NetFirewallRule -DisplayName "Out-All-Domain" -Direction Outbound -Action Allow -RemoteAddress $DOMAIN_IPs

    New-NetFirewallRule -DisplayName "MGMT-In-RDP-Domain" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 -RemoteAddress $DOMAIN_IPs
    New-NetFirewallRule -DisplayName "MGMT-Out-RDP-Domain" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 3389 -RemoteAddress $DOMAIN_IPs

    New-NetFirewallRule -DisplayName "MGMT-In-WinRM-Domain" -Direction Inbound -Action Allow -Protocol TCP -LocalPort @(5985, 5986) -RemoteAddress $DOMAIN_IPs
    New-NetFirewallRule -DisplayName "MGMT-Out-WinRM-Domain" -Direction Outbound -Action Allow -Protocol TCP -RemotePort @(5985, 5986) -RemoteAddress $DOMAIN_IPs

    if ($isDC) {
    # --- DOMAIN CONTROLLER RULES ---
    Write-Host "`n[*] Configuring Domain Controller rules..."
    foreach ($AD_Svc in $AD_Services) {
        foreach ($Proto in @($AD_Svc.Proto)) {
            # Inbound (DM+DC to DC)
            New-NetFirewallRule -DisplayName "DC-In-$($AD_Svc.Name)-$Proto" -Direction Inbound -Action Allow -Protocol $Proto -LocalPort $AD_Svc.Port -RemoteAddress $DOMAIN_IPs

            # Outbound (DC to DC)
            New-NetFirewallRule -DisplayName "DC-Out-$($AD_Svc.Name)-$Proto" -Direction Outbound -Action Allow -Protocol $Proto -RemotePort $AD_Svc.Port -RemoteAddress $DC_IPs
        }
    }
    # DC to DC (if multi DCs etc.)
    New-NetFirewallRule -DisplayName "DC-In-DFS-R" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5722 -RemoteAddress $DC_IPs
    New-NetFirewallRule -DisplayName "DC-Out-DFS-R" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 5722 -RemoteAddress $DC_IPs

    } elseif ($isDM) {
        # --- DOMAIN MEMBER RULES ---
        Write-Host "`n[*] Configuring Domain Member rules..."
        foreach ($AD_Svc in $AD_Services) {
            foreach ($Proto in @($AD_Svc.Proto)) {
                # Outbound (DM to DC)
                New-NetFirewallRule -DisplayName "DM-Out-$($AD_Svc.Name)-$Proto" -Direction Outbound -Action Allow -Protocol $Proto -RemotePort $AD_Svc.Port -RemoteAddress $DOMAIN_IPs
            }
        }
        # Inbound (DC to DM)
        New-NetFirewallRule -DisplayName "DM-In-RPC-HighPorts" -Direction Inbound -Action Allow -Protocol TCP -LocalPort "49152-65535" -RemoteAddress $DOMAIN_IPs
    }
}
