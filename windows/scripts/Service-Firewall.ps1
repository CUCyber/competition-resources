# Service-Firewall.ps1
# Author: Dylan Harvey
# Interactive firewall script that adds rules required for AD and common services
# Note: Designed to be run after Nuke-Firewall.ps1, but technically OK to be run standalone

# === CONFIG ===
$SCOREBOARD_IPs = @("10.3.2.1")              # CHANGE, exact IPs preferable, supports CIDR
$DC_IPs         = @("10.3.4.1", "10.3.4.2")  # CHANGE, exact IPs preferable, supports CIDR
$DM_IPs         = @("10.3.4.0/24")           # CHANGE, exact IPs preferable, supports CIDR
$DOMAIN_IPs     = $DC_IPs + $DM_IPs
$ALL_IPs        = $SCOREBOARD_IPs + $DOMAIN_IPs
$BACKUP_PATH    = ".\firewall_backup_service.wfw"  # Note this is execution directory, not script's directory

$DomainRole = (Get-CimInstance Win32_ComputerSystem).DomainRole
$isDC = $DomainRole -in 4, 5
$isDM = $DomainRole -in 1, 3
$isDomain = $isDC -or $isDM
# Standalone implied (2 or 0)

# NOT MODIFYING THESE AS OF NOW, would require reboot too
# HKLM\Software\Microsoft\Rpc
# Ports: 49152-65535 (default, any range is ok, ex. 5000-10000)
# PortsInternetAvailable: Y
# UseInternetPorts: Y
# TODO: There may be an option built into the FW for this
$RPC_High_Ports = "49152-65535"

# Access for domain only
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

# Access for domain and scoreboard
$Services = @(
    @{ Name="DNS"; Port=53; Proto="UDP" },
    @{ Name="RDP"; Port=3389; Proto="TCP" },
    @{ Name="WinRM/S"; Port=@(5985, 5986); Proto="TCP" },
    @{ Name="SMB"; Port=445; Proto="TCP" },
    @{ Name="Web (HTTP/S)"; Port=@(80, 443); Proto="TCP" },
    @{ Name="Web HTTP Alt"; Port=@(8000, 8008, 8080); Proto="TCP" },
    @{ Name="Web HTTPS Alt"; Port=@(8443, 8444); Proto="TCP" },
    @{ Name="Mail (SMTP)"; Port=@(25, 465, 587); Proto="TCP" },
    @{ Name="Mail (IMAP)"; Port=@(143, 993); Proto="TCP" },
    @{ Name="Mail (POP3)"; Port=@(110, 995); Proto="TCP" },
    @{ Name="SSH"; Port=22; Proto="TCP" },
    @{ Name="MySQL/MariaDB"; Port=3306; Proto="TCP" },
    @{ Name="PostgreSQL"; Port=5432; Proto="TCP" },
    @{ Name="FTP"; Port=@(20, 21); Proto="TCP" },
    @{ Name="SNMP"; Port=@(161, 162); Proto="UDP" }
)

# === HELPERS ===
function Confirm-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "[-] ERROR: This script must be run as Administrator!" -ForegroundColor Red
        exit
    }
}

function Backup-Rules {
    try {
        if (Test-Path -Path $BACKUP_PATH -PathType Leaf) {
            Write-Host "[i] Found existing backup at $BACKUP_PATH, moving to $($BACKUP_PATH).old" -ForegroundColor Yellow
            Move-Item -Path $BACKUP_PATH -Destination "$BACKUP_PATH.old" -Force
        }
        netsh advfirewall export $BACKUP_PATH | Out-Null
        Write-Host "[+] Firewall configuration backed up to: $BACKUP_PATH" -ForegroundColor Green
    } catch {
        Write-Host "[!] BACKUP FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $confirm = Read-Host "Continue without backup? (y/N)"
        if ($confirm -ne "y") { exit }
    }
}

function Add-FirewallRule {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Direction,
        [Parameter(Mandatory=$true)][string]$Action,
        [Parameter(Mandatory=$true)][string[]]$RemoteAddress,
        [string]$Protocol,
        $Port,
        $IcmpType,
        [string]$Description = ""
    )
    
    $params = @{
        DisplayName = $Name
        Direction = $Direction
        Action = $Action
        RemoteAddress = $RemoteAddress
        Description = $Description
        ErrorAction = "Stop"
    }
    if ($Protocol) { $params.Protocol = $Protocol }
    if ($IcmpType) { $params.IcmpType = $IcmpType }
    if ($Port) { 
        if ($Direction -eq "Inbound") { $params.LocalPort = $Port } 
        else { $params.RemotePort = $Port }
    }

    try {
        New-NetFirewallRule @params | Out-Null
        Write-Host "[+] Created: $($params.DisplayName) ($Direction)" -ForegroundColor Green
    } catch {
        Write-Host "[!] Failed: $($params.DisplayName) - $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Test-Listening {
    param($Ports)
    $Active = Get-NetTCPConnection -State Listen | Select-Object -ExpandProperty LocalPort
    foreach ($p in @($Ports)) { if ($p -in $Active) { return $true } }
    return $false
}

# === EXECUTION ===
Confirm-Admin
Backup-Rules

# --- GLOBAL RULES ---
Write-Host "`n[*] Applying Global rules..." -ForegroundColor Magenta
$IcmpTypes = @("3", "8", "11")
Add-FirewallRule -Name "PING-In" -Direction Inbound -Action Allow -RemoteAddress "Any" -Protocol ICMPv4 -IcmpType $IcmpTypes
Add-FirewallRule -Name "PING-Out" -Direction Outbound -Action Allow -RemoteAddress "Any" -Protocol ICMPv4 -IcmpType $IcmpTypes
# Global DNS if machine needs to resolve inet
#Add-FirewallRule -Name "DNS-Out-Global" -Direction Outbound -Action Allow -Protocol UDP -Port 53 -RemoteAddress @("1.1.1.1")
# Global NTP if machine needs to fix clock (time.windows.com -> 168.61.215.74)
#Add-FirewallRule -Name "NTP-Out-Global" -Direction Outbound -Action Allow -Protocol UDP -Port 123 -RemoteAddress @("168.61.215.74")

if ($isDomain) {
    # --- GLOBAL DOMAIN RULES ---
    Write-Host "`n[*] Configuring Domain rules..." -ForegroundColor Magenta
    # If all else fails just enable these lol:
    #Add-FirewallRule -Name "In-All-Domain" -Direction Inbound -Action Allow -RemoteAddress $DOMAIN_IPs
    #Add-FirewallRule -Name "Out-All-Domain" -Direction Outbound -Action Allow -RemoteAddress $DOMAIN_IPs

    Add-FirewallRule -Name "MGMT-In-RDP-Domain" -Direction Inbound -Action Allow -Protocol TCP -Port 3389 -RemoteAddress $DOMAIN_IPs
    Add-FirewallRule -Name "MGMT-Out-RDP-Domain" -Direction Outbound -Action Allow -Protocol TCP -Port 3389 -RemoteAddress $DOMAIN_IPs

    Add-FirewallRule -Name "MGMT-In-WinRM-Domain" -Direction Inbound -Action Allow -Protocol TCP -Port @(5985, 5986) -RemoteAddress $DOMAIN_IPs
    Add-FirewallRule -Name "MGMT-Out-WinRM-Domain" -Direction Outbound -Action Allow -Protocol TCP -Port @(5985, 5986) -RemoteAddress $DOMAIN_IPs

    if ($isDC) {
    # --- DOMAIN CONTROLLER RULES ---
    Write-Host "`n[*] Configuring Domain Controller rules..." -ForegroundColor Magenta
    foreach ($AD_Svc in $AD_Services) {
        foreach ($Proto in @($AD_Svc.Proto)) {
            # Inbound (DM+DC to DC)
            Add-FirewallRule -Name "DC-In-$($AD_Svc.Name)-$Proto" -Direction Inbound -Action Allow -Protocol $Proto -Port $AD_Svc.Port -RemoteAddress $DOMAIN_IPs

            # Outbound (DC to DC)
            Add-FirewallRule -Name "DC-Out-$($AD_Svc.Name)-$Proto" -Direction Outbound -Action Allow -Protocol $Proto -Port $AD_Svc.Port -RemoteAddress $DC_IPs
        }
    }
    # DC to DC (if multi DCs etc.)
    Add-FirewallRule -Name "DC-In-DFS-R" -Direction Inbound -Action Allow -Protocol TCP -Port 5722 -RemoteAddress $DC_IPs
    Add-FirewallRule -Name "DC-Out-DFS-R" -Direction Outbound -Action Allow -Protocol TCP -Port 5722 -RemoteAddress $DC_IPs

    } elseif ($isDM) {
        # --- DOMAIN MEMBER RULES ---
        Write-Host "`n[*] Configuring Domain Member rules..." -ForegroundColor Magenta
        foreach ($AD_Svc in $AD_Services) {
            foreach ($Proto in @($AD_Svc.Proto)) {
                # Outbound (DM to DC)
                Add-FirewallRule -Name "DM-Out-$($AD_Svc.Name)-$Proto" -Direction Outbound -Action Allow -Protocol $Proto -Port $AD_Svc.Port -RemoteAddress $DOMAIN_IPs
            }
        }
        # Inbound (DC to DM)
        Add-FirewallRule -Name "DM-In-RPC-HighPorts" -Direction Inbound -Action Allow -Protocol TCP -Port "49152-65535" -RemoteAddress $DOMAIN_IPs
    }
} else {
    # --- STANDALONE RULES ---
    Write-Host "`n[*] Configuring Standalone rules..." -ForegroundColor Magenta
}

# --- SAFETY REVERT ---
Write-Host "`n--- SAFETY REVERT CHECK ---" -ForegroundColor Yellow
Write-Host "Press 'Y' to KEEP these settings. Otherwise, reverting in 10 seconds..."

$timer = 10
$keepSettings = $false

while ($timer -gt 0) {
    Write-Host "`rReverting in $timer seconds... (Press 'Y' to confirm) " -NoNewline
    if ([console]::KeyAvailable) {
        $key = [console]::ReadKey($true)
        if ($key.Key -eq 'Y') {
            $keepSettings = $true
            break
        } elseif ($key.Key -eq 'N') {
            $keepSettings = $false
            break
        }
    }
    Start-Sleep -Seconds 1
    $timer--
}

if ($keepSettings) {
    Write-Host "`n`nSettings CONFIRMED." -ForegroundColor Green
    Write-Host "Previous settings saved to $BACKUP_PATH"
} else {
    Write-Host "`n`nNO INPUT RECEIVED/TIMED OUT or REJECTED. REVERTING..." -ForegroundColor Red
    netsh advfirewall import $BACKUP_PATH
    Write-Host "Firewall restored to previous state." -ForegroundColor Green
    exit
}

# --- INTERACTIVE GLOBAL SERVICE RULES ---
$configure = Read-Host "`nWould you like to configure Services now? (y/N)"
if ($configure -eq 'y') {
    Write-Host "`n--- Optional Service Configuration ---" -ForegroundColor Cyan
    $ActiveListeners = Get-NetTCPConnection -State Listen | Select-Object -ExpandProperty LocalPort

    foreach ($Svc in $Services) {
        $PortList = $Svc.Port -join ", "
        $isListening = $false
        foreach ($p in @($Svc.Port)) { if ($p -in $ActiveListeners) { $isListening = $true } }

        if ($isListening) {
            $StatusText = "[LISTENING]"
        } else {
            $StatusText = "[CLOSED]"
        }

        Write-Host "Service: $($Svc.Name) (Ports: $PortList) Status: $StatusText"
        
        $choice = Read-Host "Allow this service for Scoreboard and Domain IPs? (y/N)"
        if ($choice -eq 'y') {
            foreach ($Proto in @($Svc.Proto)) {
                Add-FirewallRule -Name "SVC-In-$($Svc.Name)-$Proto" -Direction Inbound -Action Allow -Protocol $Proto -Port $Svc.Port -RemoteAddress $ALL_IPs
            }
        }
    }
}
