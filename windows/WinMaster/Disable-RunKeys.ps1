# Disable-RunKeys.ps1
# Author: Dylan Harvey - Modified by BlueNitrobotX
# Script for disabling common runkeys.

# List of RunKey locations to check
$RunKeys = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunServices",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunServicesOnce",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunServices",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunServicesOnce",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"
)

Write-Host "`n====== Checking RunKeys ======`n"

# Check each keypath
foreach ($KeyPath in $RunKeys) {
    # Only process the item if it exists
    if (Test-Path $KeyPath) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Processing: $KeyPath"
        
        # Create ScriptDisabled path
        $DisabledPath = Join-Path $KeyPath "ScriptDisabled"
        # Double check and force creation upon failure
        if (-not (Test-Path $DisabledPath)) {
            New-Item -Path $DisabledPath -Force | Out-Null
        }

        # Check the keypath and get all the names
        $Values = Get-ItemProperty -Path $KeyPath
        $ValueNames = $Values.PSObject.Properties.Name | Where-Object { 
            $_ -notmatch "PSPath|PSParentPath|PSChildName|PSDrive|PSProvider|ScriptDisabled" 
        }

        # Print report for each name
        foreach ($Name in $ValueNames) {
            $Data = (Get-ItemProperty -Path $KeyPath -Name $Name).$Name
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] - Disabling: $Name" -ForegroundColor Yellow
            
            New-ItemProperty -Path $DisabledPath -Name $Name -Value $Data -PropertyType String -Force | Out-Null
            
            Remove-ItemProperty -Path $KeyPath -Name $Name
        }
    }
}

Write-Host -ForegroundColor Cyan "`n[$(Get-Date -Format 'HH:mm:ss')] Check complete.`n"
