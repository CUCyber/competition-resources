# Based on AD-Hardening.ps1 from BYU, Edited by Aaron Sprouse, Clemson University

Import-Module ActiveDirectory
Import-Module GroupPolicy

$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$ADcomputers = Get-ADComputer -Filter * | Select-Object -ExpandProperty Name

function Prompt-Yes-No {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message
    )

    try {
        do {
            $response = $(Write-Host $Message -ForegroundColor Yellow -NoNewline; Read-Host)
            if ($response -ieq 'y' -or $response -ieq 'n') {
                return $response
            } else {
                Write-Host "Please enter 'y' or 'n'." -ForegroundColor Yellow
            }
        } while ($true)
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Write-Host "Error Occurred..."
    }
}

function Handle-First-Policy-in-GPO {
    try {
    # Install RSAT features
    #Install-WindowsFeature -Name RSAT -IncludeAllSubFeature

    # Define GPO and settings
    $gpoName = $GPOName

    $report = Get-GPOReport -Name $gpoName -ReportType xml

    # Check if there are any settings in the report
    if ($report -like "*Enabled=True*") {
        Write-Host "$gpoName has settings defined." -ForegroundColor Green
    } else {
        Write-Host "$gpoName does not have any settings defined.`n" -ForegroundColor Red
        Write-Host "Press Enter ONLY after doing the following:" -ForegroundColor Yellow
        Read-Host @"
1. Win + R
2. Type gpmc.msc
3. Find Good-GPO
4. Right click and select Edit
5. Navigate to Computer > Policies > Windows Settings > Security Settings > User Rights Assignment
6. Double-click "Generate Security Audits"
7. Check the box
8. Click on the "Add User or Group..." button
9. Type Administrators
10. Apply
"@
    }

    # Get the GPO's GUID
    $gpo = Get-GPO -Name $gpoName
    $gpoId = $gpo.Id

    # Construct full path
    $fullPath = "\\$($env:USERDNSDOMAIN)\sysvol\$($env:USERDNSDOMAIN)\Policies\{$gpoId}\Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf"

    # Backup the file
    Copy-Item -Path $fullPath -Destination "${fullPath}.backup"

   # Read the content of the file
    $lines = Get-Content $fullPath

    # Define the permission setting
    $permission = "SeRemoteInteractiveLogonRight = Domain Admins,*S-1-5-32-555"

    # Check if the section exists
    if ($lines -contains "[Privilege Rights]") {
        # Get the index of the section
        $index = $lines.IndexOf("[Privilege Rights]") + 1

        # Insert the permission setting after the section
        $lines = $lines[0..$index] + $permission + $lines[($index + 1)..$lines.Length]
    } else {
        # If the section doesn't exist, append the section and the permission at the end
        $lines += "[Privilege Rights]", $permission
    }

    # Write the content back to the file
    $lines | Set-Content -Path $fullPath
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Write-Host "Error Occurred..."
    }
}

function Global-Gpupdate {
    try {
        # Invoke gpupdate on each computer
        Invoke-Command -ComputerName $ADcomputers -ScriptBlock {
            gpupdate /force
        } -AsJob  # Executes as background jobs to avoid waiting for each to finish
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Write-Host "Error Occurred..."
    }
}

function Create-Good-GPO {
    try {
        Write-Host "Creating GPO named '$GPOName'..." -ForegroundColor Green
        $newGPO = New-GPO -Name $GPOName

        Write-Host "Fetching distinguished name of the domain..." -ForegroundColor Green
        $domainDN = (Get-ADDomain).DistinguishedName

        Write-Host "Linking GPO to the domain..." -ForegroundColor Green
        New-GPLink -Name $GPOName -Target $domainDN
		Write-Host "GPO linked successfully!" -ForegroundColor Green

        Write-Host "Setting permissions for GPO..." -ForegroundColor Green
        # Get the SID of the current user
        $userSID = (New-Object System.Security.Principal.NTAccount($CurrentUser)).Translate([System.Security.Principal.SecurityIdentifier]).Value

        # Set permissions for the creating user (full control)
		try {
			Set-GPPermissions -Name $GPOName -TargetName $CurrentUser -TargetType User -PermissionLevel GpoEdit
			Write-Host "Permissions set successfully." -ForegroundColor Green
		} catch {
			Write-Host "Error setting permissions -- $_" -ForegroundColor Yellow
		}
		Write-Host "Go configure the GPO, specifically to deny the 'Apply Group Policy' for current user, before continuing" -ForegroundColor Black -BackgroundColor Yellow
		Read-Host " "
		Set-GPLink -Name $GPOName -Target $domainDN -Enforced Yes
		Write-Host "GPO fully and successfully configured and enforced!" -ForegroundColor Green
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Write-Host "Error Occurred..."
    }
}

function Configure-Secure-GPO {
    try {
        Handle-First-Policy-in-GPO

        # Define configurations
        $configurations = @{
            "Prevent Windows from Storing LAN Manager Hash" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa"
                "ValueName" = "NoLMHash"
                "Value" = 1
                "Type" = "DWORD"
            }
            "Disable Guest Account" = @{
                "Key" = "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
                "ValueName" = "AllowGuest"
                "Value" = 0
                "Type" = "DWORD"
            }
            "Disable Anonymous SID Enumeration" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa"
                "ValueName" = "RestrictAnonymousSAM"
                "Value" = 1
                "Type" = "DWORD"
            }
            "Enable Event Logs" = @{
                "Key" = "HKLM\System\CurrentControlSet\Services\Eventlog\Application"
                "ValueName" = "AutoBackupLogFiles"
                "Value" = 1
                "Type" = "DWORD"
            }
            "Disable Anonymous Account in Everyone Group" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa"
                "ValueName" = "EveryoneIncludesAnonymous"
                "Value" = 0
                "Type" = "DWORD"
            }
            "Enable User Account Control" = @{
                "Key" = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
                "ValueName" = "EnableLUA"
                "Value" = 1
                "Type" = "DWORD"
            }
            "Disable WDigest UseLogonCredential" = @{
                "Key" = "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\SecurityProviders\WDigest"
                "ValueName" = "UseLogonCredential"
                "Value" = 0
                "Type" = "DWORD"
            }
            "Disable WDigest Negotiation" = @{
                "Key" = "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\SecurityProviders\WDigest"
                "ValueName" = "Negotiate"
                "Value" = 0
                "Type" = "DWORD"
            }
            "Enable LSASS protection" = @{
                "Key" = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\LSA"
                "ValueName" = "RunAsPPL"
                "Value" = 1
                "Type" = "DWORD"
            }
            "Disable Restricted Admin" = @{
                "Key" = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\LSA"
                "ValueName" = "DisableRestrictedAdmin"
                "Value" = 1
                "Type" = "DWORD"
            }
        #other best practice keys
            "Configure SecurityLevel" = @{
                "Key" = "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole"
                "ValueName" = "SecurityLevel"
                "Type" = "DWORD"
                "Value" = 0
            }
            "Configure SetCommand" = @{
                "Key" = "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole"
                "ValueName" = "SetCommand"
                "Type" = "DWORD"
                "Value" = 0
            }
            "Configure AllocateCDRoms" = @{
                "Key" = "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
                "ValueName" = "AllocateCDRoms"
                "Type" = "String"
                "Value" = "1"
            }
            "Configure AllocateFloppies" = @{
                "Key" = "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
                "ValueName" = "AllocateFloppies"
                "Type" = "String"
                "Value" = "1"
            }
            "Configure CachedLogonsCount" = @{
                "Key" = "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
                "ValueName" = "CachedLogonsCount"
                "Type" = "String"
                "Value" = "0"
            }
            "Configure ForceUnlockLogon" = @{
                "Key" = "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
                "ValueName" = "ForceUnlockLogon"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure ConsentPromptBehaviorAdmin" = @{
                "Key" = "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System"
                "ValueName" = "ConsentPromptBehaviorAdmin"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure ConsentPromptBehaviorUser" = @{
                "Key" = "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System"
                "ValueName" = "ConsentPromptBehaviorUser"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure DisableCAD" = @{
                "Key" = "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System"
                "ValueName" = "DisableCAD"
                "Type" = "DWORD"
                "Value" = 0
            }
            "Configure EnableLUA" = @{
                "Key" = "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System"
                "ValueName" = "EnableLUA"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure FilterAdministratorToken" = @{
                "Key" = "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System"
                "ValueName" = "FilterAdministratorToken"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure NoConnectedUser" = @{
                "Key" = "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System"
                "ValueName" = "NoConnectedUser"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure PromptOnSecureDesktop" = @{
                "Key" = "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System"
                "ValueName" = "PromptOnSecureDesktop"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure ForceKeyProtection" = @{
                "Key" = "HKLM\Software\Policies\Microsoft\Cryptography"
                "ValueName" = "ForceKeyProtection"
                "Type" = "DWORD"
                "Value" = 2
            }
            "Configure AuthenticodeEnabled" = @{
                "Key" = "HKLM\Software\Policies\Microsoft\Windows\Safer\CodeIdentifiers"
                "ValueName" = "AuthenticodeEnabled"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure AuditBaseObjects" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa"
                "ValueName" = "AuditBaseObjects"
                "Type" = "DWORD"
                "Value" = 0
            }
            "Configure DisableDomainCreds" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa"
                "ValueName" = "DisableDomainCreds"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure EveryoneIncludesAnonymous" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa"
                "ValueName" = "EveryoneIncludesAnonymous"
                "Type" = "DWORD"
                "Value" = 0
            }
            "Configure Enabled" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa\FIPSAlgorithmPolicy"
                "ValueName" = "Enabled"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure FullPrivilegeAuditing" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa"
                "ValueName" = "FullPrivilegeAuditing"
                "Type" = "Binary"
                "Value" = 0
            }
            "Configure LimitBlankPasswordUse" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa"
                "ValueName" = "LimitBlankPasswordUse"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure NTLMMinClientSec" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa\MSV1_0"
                "ValueName" = "NTLMMinClientSec"
                "Type" = "DWORD"
                "Value" = 537395200
            }
            "Configure NTLMMinServerSec" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa\MSV1_0"
                "ValueName" = "NTLMMinServerSec"
                "Type" = "DWORD"
                "Value" = 537395200
            }
            "Configure NoLMHash" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa"
                "ValueName" = "NoLMHash"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure RestrictAnonymous" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa"
                "ValueName" = "RestrictAnonymous"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure RestrictAnonymousSAM" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa"
                "ValueName" = "RestrictAnonymousSAM"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure RestrictRemoteSAM" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa"
                "ValueName" = "RestrictRemoteSAM"
                "Type" = "String"
                "Value" = "O:BAG:BAD:(A;;RC;;;BA)"
            }
            "Configure SCENoApplyLegacyAuditPolicy" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa"
                "ValueName" = "SCENoApplyLegacyAuditPolicy"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure SubmitControl" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Lsa"
                "ValueName" = "SubmitControl"
                "Type" = "DWORD"
                "Value" = 0
            }
            "Configure AddPrinterDrivers" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Print\Providers\LanMan Print Services\Servers"
                "ValueName" = "AddPrinterDrivers"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure Winreg Exact Paths" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\SecurePipeServers\Winreg\AllowedExactPaths"
                "ValueName" = "Machine"
                "Type" = "MultiString"
                "Value" =  ""
            }
            "Configure Winreg Allowed Paths" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\SecurePipeServers\Winreg\AllowedPaths"
                "ValueName" = "Machine"
                "Type" = "MultiString"
                "Value" = ""
            }
            "Configure ProtectionMode" = @{
                "Key" = "HKLM\System\CurrentControlSet\Control\Session Manager"
                "ValueName" = "ProtectionMode"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure EnableSecuritySignature" = @{
                "Key" = "HKLM\System\CurrentControlSet\Services\LanManServer\Parameters"
                "ValueName" = "EnableSecuritySignature"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure RequireSecuritySignature" = @{
                "Key" = "HKLM\System\CurrentControlSet\Services\LanManServer\Parameters"
                "ValueName" = "RequireSecuritySignature"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure RestrictNullSessAccess" = @{
                "Key" = "HKLM\System\CurrentControlSet\Services\LanManServer\Parameters"
                "ValueName" = "RestrictNullSessAccess"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure EnablePlainTextPassword" = @{
                "Key" = "HKLM\System\CurrentControlSet\Services\LanmanWorkstation\Parameters"
                "ValueName" = "EnablePlainTextPassword"
                "Type" = "DWORD"
                "Value" = 0
            }
            "Configure EnableSecuritySignature Workstation" = @{
                "Key" = "HKLM\System\CurrentControlSet\Services\LanmanWorkstation\Parameters"
                "ValueName" = "EnableSecuritySignature"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure RequireSecuritySignature Workstation" = @{
                "Key" = "HKLM\System\CurrentControlSet\Services\LanmanWorkstation\Parameters"
                "ValueName" = "RequireSecuritySignature"
                "Type" = "DWORD"
                "Value" = 1
            }
            "Configure LDAPClientIntegrity" = @{
                "Key" = "HKLM\System\CurrentControlSet\Services\LDAP"
                "ValueName" = "LDAPClientIntegrity"
                "Type" = "DWORD"
                "Value" = 2
            }
        }



        $successfulConfigurations = 0
        $failedConfigurations = @()

        # Loop through configurations
        foreach ($configName in $configurations.Keys) {
            $config = $configurations[$configName]
            $keyPath = $config["Key"]

            # Check if key path exists
            #if (-not (Test-Path "Registry::$keyPath")) {
            #    $failedConfigurations += $configName
            #    continue
            #}

            # Set GPO registry value
            Set-GPRegistryValue -Name $GPOName -Key $config["Key"] -ValueName $config["ValueName"] -Value $config["Value"] -Type $config["Type"]
            $successfulConfigurations++
        }

        Write-Host "$successfulConfigurations configurations successfully applied." -ForegroundColor Green

        if ($failedConfigurations.Count -gt 0) {
            Write-Host "`nConfigurations that couldn't be applied due to missing registry key paths:" -ForegroundColor Red
            $failedConfigurations
        } else {
            Write-Host "All configurations applied successfully." -ForegroundColor Green
        }

		Write-Host "Applying gpupdate across all machines on the domain" -ForegroundColor Magenta
        Global-Gpupdate
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Write-Host "Error Occurred..."
    }
}
###################################### MAIN ######################################

$GPOName = 'test'

# Create Blank GPO
$confirmation = Prompt-Yes-No -Message "Enter the 'Create Blank GPO with Correct Permissions' function? (y/n)"
if ($confirmation.toLower() -eq "y") {
    Write-Host "`n***Creating Blank GPO and applying to Root of domain...***" -ForegroundColor Magenta
	Create-Good-GPO
} else {
    Write-Host "Skipping..." -ForegroundColor Red
}


$confirmation = Prompt-Yes-No -Message "Enter the 'Configure Secure GPO' function? (y/n)"
if ($confirmation.toLower() -eq "y") {
    Write-Host "`n***Configuring Secure GPO***" -ForegroundColor Magenta
    Configure-Secure-GPO
} else {
    Write-Host "Skipping..." -ForegroundColor Red
}

#Set Execution Policy back to Restricted
$confirmation = Prompt-Yes-No -Message "Set Execution Policy back to Restricted? (y/n)"
if ($confirmation.toLower() -eq "y") {
    try {
        Write-Host "`n***Setting Execution Policy back to Restricted...***" -ForegroundColor Magenta
        Set-ExecutionPolicy Restricted
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Write-Host "Error Occurred..."
    }
} else {
    Write-Host "Skipping..." -ForegroundColor Red
}

Write-Host "`n***Script Completed!!!***" -ForegroundColor Green