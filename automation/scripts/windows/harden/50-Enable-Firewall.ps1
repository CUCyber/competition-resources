# 50-Enable-Firewall.ps1
# Author: Dylan Harvey
# Description: Automated firewall hardening script. 

Write-Host "[*] Starting Firewall Hardening..."

try {
    Set-NetFirewallProfile -All -Enabled True
    Write-Host "[+] Firewall enabled for all profiles."

    Set-NetFirewallProfile -All -DefaultInboundAction Block -DefaultOutboundAction Allow
    Write-Host "[+] Default policy set to Block Inbound / Allow Outbound."

    $logPath = "C:\Windows\System32\LogFiles\Firewall\pfirewall.log"
    Set-NetFirewallProfile -All -LogFileName $logPath -LogAllowed False -LogBlocked True
    Write-Host "[+] Logging for blocked packets enabled at $logPath."

    Write-Host "[*] Firewall hardening complete."
} catch {
    Write-Host "[!] Failed to harden firewall: $($_.Exception.Message)"
    exit 2
}
