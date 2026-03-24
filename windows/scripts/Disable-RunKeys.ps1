# Disable-RunKeys.ps1
# Author: Dylan Harvey
# Script for disabling common runkeys.

#Requires -RunAsAdministrator

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

foreach ($KeyPath in $RunKeys) {
    if (Test-Path $KeyPath) {
        Write-Host "Processing: $KeyPath" -ForegroundColor Cyan
        
        $DisabledPath = Join-Path $KeyPath "ScriptDisabled"
        if (-not (Test-Path $DisabledPath)) {
            New-Item -Path $DisabledPath -Force | Out-Null
        }

        $Values = Get-ItemProperty -Path $KeyPath
        $ValueNames = $Values.PSObject.Properties.Name | Where-Object { 
            $_ -notmatch "PSPath|PSParentPath|PSChildName|PSDrive|PSProvider|ScriptDisabled" 
        }

        foreach ($Name in $ValueNames) {
            $Data = (Get-ItemProperty -Path $KeyPath -Name $Name).$Name
            Write-Host "  Disabling: $Name" -ForegroundColor Yellow
            
            New-ItemProperty -Path $DisabledPath -Name $Name -Value $Data -PropertyType String -Force | Out-Null
            
            Remove-ItemProperty -Path $KeyPath -Name $Name
        }
    }
}
