# Nuke-Firewall.ps1
# Author: Dylan Harvey
# Interactive firewall hardening script that locks down machine
# WARNING: WILL BREAK SCORED SERVICES
# YOU WILL NEED TO MANUALLY ADD RULES FOR SERVICES AND/OR DOMAIN, RUN Service-Firewall.ps1 NEXT TO ASSIST

# === CONFIG ===
$AllowIPs             = @("10.2.0.0/24")         # CHANGE, exact IPs preferable, supports CIDR, be careful with VPNs masquerade, empty list means any!
$DisableExistingRules = $true                    # DESTRUCTIVE ACTION!!! WILL BREAK SERVICES
$InboundAction        = "Block"                  # default Block
$OutboundAction       = "Block"                  # default Allow (Block super strict, will break services but also stop C2+RevShell)
$BACKUP_PATH          = ".\firewall_backup.wfw"  # Note this is execution directory, not script's directory
$BLUE_RULE_NAME       = "BLUE_MGMT"
$BLACK_RULE_NAME      = "BTA"
$BLACK_TEAM_EXE       = "C:\Program Files\BTA\bta.exe"  # Double check path
$PROTECTED_RULES      = @($BLUE_RULE_NAME, $BLACK_RULE_NAME)

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
            Move-Item -Path $BACKUP_PATH -Destination "$($BACKUP_PATH).old" -Force
        }
        netsh advfirewall export $BACKUP_PATH | Out-Null
        Write-Host "[+] Firewall configuration backed up to: $BACKUP_PATH" -ForegroundColor Green
    } catch {
        Write-Host "[!] BACKUP FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $confirm = Read-Host "Continue without backup? (y/N)"
        if ($confirm -ne "y") { exit }
    }
}

function Enable-Logging {
    try {
        Write-Host "[*] Enabling all profile logging..." -ForegroundColor Magenta
        netsh advfirewall set allprofiles logging allowedconnections enable | Out-Null
        netsh advfirewall set allprofiles logging droppedconnections enable | Out-Null
        Write-Host "[+] Firewall logging enabled successfully" -ForegroundColor Green
    } catch {
        Write-Host "[!] Failed to enable logging: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Enable-Firewall {
    try {
        Write-Host "[*] Enabling firewall..." -ForegroundColor Magenta
        Write-Host "[i] Setting Default Policy to $InboundAction In / $OutboundAction Out" -ForegroundColor Cyan
        Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True
        Set-NetFirewallProfile -Profile Domain, Public, Private -DefaultInboundAction $InboundAction -DefaultOutboundAction $OutboundAction
        Write-Host "[+] Firewall enabled and policy applied successfully" -ForegroundColor Green
    } catch {
        Write-Host "[!] Failed to enable logging: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# === EXECUTION ===
Confirm-Admin
Backup-Rules
Enable-Logging
Enable-Firewall

try {
    New-NetFirewallRule -DisplayName $BLACK_RULE_NAME -Direction Outbound -Program $BLACK_TEAM_EXE -Action Allow -Description "Black team pls don't hate us" -ErrorAction Stop | Out-Null
    Write-Host "[+] Created: $BLACK_RULE_NAME (Outbound)" -ForegroundColor Green
} catch {
    Write-Host "[!] Failed to create BTA rule: $($_.Exception.Message)" -ForegroundColor Red
}

try {
    Write-Host "[*] Applying rules..." -ForegroundColor Magenta
    New-NetFirewallRule -DisplayName $BLUE_RULE_NAME -Direction Inbound -Action Allow -RemoteAddress $AllowIPs -Description "Blue Team Inbound" -ErrorAction Stop | Out-Null
    New-NetFirewallRule -DisplayName $BLUE_RULE_NAME -Direction Outbound -Action Allow -RemoteAddress $AllowIPs -Description "Blue Team Outbound" -ErrorAction Stop | Out-Null
    Write-Host "[+] Created Rules Successfully" -ForegroundColor Green
} catch {
    Write-Host "[!] Failed to create rules: $($_.Exception.Message)" -ForegroundColor Red
}


if ($DisableExistingRules) {
    Write-Host "[*] Disabling all existing rules..." -ForegroundColor Magenta
    Get-NetFirewallRule | Where-Object { $_.DisplayName -notin $PROTECTED_RULES -and $_.Enabled -eq 'True' } | Disable-NetFirewallRule
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
        }
    }
    Start-Sleep -Seconds 1
    $timer--
}

if ($keepSettings) {
    Write-Host "`n`n[+] Settings CONFIRMED." -ForegroundColor Green
} else {
    Write-Host "`n`n[!] NO CONFIRMATION. REVERTING..." -ForegroundColor Red
    netsh advfirewall import $BACKUP_PATH | Out-Null
    Write-Host "[+] Firewall restored to previous state." -ForegroundColor Green
    exit
}
