# 00-Clean-Environment.ps1
# Author: Dylan Harvey
# Automated environment cleaning script for powershell profiles, execution options, and runkeys.

Write-Host "`nProcessing PowerShell Profiles..."
$ProfilePaths = $PROFILE.PSObject.Properties | Where-Object { $_.Name -like "*Host*" } | Select-Object -ExpandProperty Value

foreach ($Path in $ProfilePaths) {
    if (Test-Path $Path) {
        $NewName = $Path + ".ScriptDisabled"
        Write-Host "  Renaming Profile: $Path"
        Rename-Item -Path $Path -NewName "$($Path).ScriptDisabled" -Force
    }
}

Write-Host "`nProcessing IFEO..."
$IfeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
$IfeoBackups = Join-Path $IfeoPath "ScriptDisabled"

if (-not (Test-Path $IfeoBackups)) {
    New-Item -Path $IfeoBackups -Force | Out-Null
}

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
        Write-Host "Processing RunKey: $KeyPath"
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
            Write-Host "  Disabling: $Name"
            New-ItemProperty -Path $DisabledPath -Name $Name -Value $Data -PropertyType String -Force | Out-Null
            Remove-ItemProperty -Path $KeyPath -Name $Name
        }
    }
}
