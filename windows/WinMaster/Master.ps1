# Author BlueNitrobotX
# Master Script 

# TODO:
#
# Look into implementing the following Sysinternals tools into the misc stage:
# - AccessChk.exe
# - Streams.exe
#
# Create new Active Directory hardening script
# - Create GPOs (patch nosferatu, disable rdp shadowing??)
#
# Create a database/webserver backup script (also generic system files)
# - Detect and backup any databases and webservers on the machine

# Disable write permissions for WinMaster directory?  YES DO THIS
# Prevent failures if system does not have internet access

# Detection only scripts (for now, some will be updated):
# - Check-Services2 (COMPLETE)
# - Find-PII-Light (COMPLETE)
# - Find-PII-Heavy (COMPLETE)
# - Get-Report (COMPLETE)
# - FindWindowsTamper (COMPLETE)

# Detection and Remediation scripts:
# - CheckFirewall5 (COMPLETE)
# - Disable-RunKeys (COMPLETE)
# - ProfileCheck1 (COMPLETE)
# - Check-ScheduledTasks (COMPLETE)

# Automatic Remediation Scripts
# - rmbin2 (COMPLETE)

# Remediation scripts that should be interactive:
# - Find-HiddenServices (interactive if you don't include: -actionParam "[action]")
# - Find-IISWebshells (interactive with: -Action Review)


# EXIT CODE LEGEND:
# 0 - Success
# 1 - Failure
# 2 - Nothing found


# === Helper Functions ===
function Test-LsaProtected {
    $ppl = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name RunAsPPL -ErrorAction SilentlyContinue).RunAsPPL
    $pol = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name RunAsPPL -ErrorAction SilentlyContinue).RunAsPPL
    $configured = ($ppl -in 1, 2) -or ($pol -in 1, 2)
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $evt  = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Wininit'; Id = 12 } `
                -MaxEvents 1 -ErrorAction SilentlyContinue

    if ($evt) { return ($evt.TimeCreated -ge $boot) }   # proof LSASS started protected this boot
    return $configured                                  # no event (log rolled over): fall back to the registry
}



# ======= BEGIN STAGE 1: Script Validation =======
Set-Location -LiteralPath $PSScriptRoot -ErrorAction Stop

$sigcheck = Join-Path $PSScriptRoot 'SysinternalsSuite\sigcheck64.exe'

Write-Host "[$(Get-Date -Format "HH:mm:ss")] Starting Stage 1..."

# Instantiate variables & create directories
if(-not (Test-Path -Path ".\WinMaster_Backups" -PathType Container)) {
    New-Item -Path ".\WinMaster_Backups" -ItemType Directory -ErrorAction Stop | Out-Null
}

if(-not (Test-Path -Path ".\WinMaster_Evidence" -PathType Container)) {
    try {
        # Create Evidence Directory
        New-Item -Name "WinMaster_Evidence" -ItemType Directory -ErrorAction Stop | Out-Null
    }
    catch {
        # Error handling
        Write-Host "Failed to create .\WinMaster_Evidence directory" -ForegroundColor Red -BackgroundColor DarkRed
        exit 1
    }
}

# Create Old Evidence Directory
if(-not (Test-Path -Path ".\OLD-WinMaster_Evidence" -PathType Container)) {   
    try {    
        # Create Evidence Directory
        New-Item -Name "OLD-WinMaster_Evidence" -ItemType Directory -ErrorAction Stop | Out-Null
    }
    catch {   
        # Error handling
        Write-Host "Failed to create .\OLD-WinMaster_Evidence directory" -ForegroundColor Red -BackgroundColor DarkRed
        exit 1
    }
} else {
    # Move any evidence from previous runs into .\WinMaster\OLD-WinMaster_Evidence
    $evidenceItems = Get-ChildItem -Path ".\WinMaster_Evidence" -File
    $oldEvidenceItems = Get-ChildItem -Path ".\OLD-WinMaster_Evidence"
    if($oldEvidenceItems.Count -eq 0) {
            if($evidenceItems.Count -gt 0) {
                foreach($evidenceItem in $evidenceItems) {
                    Move-Item -Path $evidenceItem.FullName -Destination ".\OLD-WinMaster_Evidence"
                }
            } 
    }
}

# Instantiate boolean and array vars
$scriptCheck = $true;
$scriptList = @(
    ".\ProfileCheck1.ps1",
    ".\Disable-RunKeys.ps1",
    ".\Get-Report.ps1",
    ".\Check-Services2.ps1",
    ".\Find-PII-Light.ps1",
    ".\Find-PII-Heavy.ps1",
    ".\Find-WindowsTamper.ps1",
    ".\CheckFirewall5.ps1",
    ".\Find-HiddenServices.ps1",
    ".\Check-ScheduledTasks.ps1",
    ".\Install-Sysinternals.ps1",
    ".\rmbin2.ps1",
    ".\Find-IISWebshells.ps1",
    ".\Reset-Passwords.ps1",
    ".\SysinternalsSuite\PsExec64.exe",
    ".\SysinternalsSuite\sigcheck64.exe"
)

# Check that each script exists in working directory
foreach($scriptListItem in $scriptList) {
    if(-not (Test-Path -Path $scriptListItem -PathType Leaf)) {
        Write-Host -ForegroundColor Red "Failed to find $scriptListItem!"
        $scriptCheck = $false
    }
}

# If at least 1 check fails, throw an error
if(-not $scriptCheck) {
    Write-Host -BackgroundColor DarkRed -ForegroundColor Red "1 or more scripts could not be found!"
    exit 1
}

# ======= END STAGE 1: Script Validation =======






# ======= BEGIN STAGE 2: Privileges Check =======

Write-Host "[$(Get-Date -Format "HH:mm:ss")] Starting Stage 2..."

# Check that this script is running as system
if([System.Security.Principal.WindowsIdentity]::GetCurrent().Name -ne "NT AUTHORITY\SYSTEM") {
        # Error handling
        Write-Host -BackgroundColor DarkRed -ForegroundColor Red "FAILED TO OBTAIN SYSTEM PRIVILEGES"
        exit 1
}

# ======= END STAGE 2: Privileges Check =======






# ======= BEGIN STAGE 3: Start Non-Interactive Scripts =======

Write-Host "[$(Get-Date -Format "HH:mm:ss")] Starting Stage 3..."


# Variables to keep track of sub-script exit codes/statuses
$profileDetected = $false
$hiddenServicesFound = $false
$suspiciousServicesFound = $false
$suspiciousScheduledTasksFound = $false
$suspiciousExecutablesFound = $false
$suspiciousFirewallRulesFound = $false


# Create hash table to keep track of each script's process
$processes = @{}

Write-Host -ForegroundColor Cyan "Running ProfileCheck1.ps1, review log in .\WinMaster_Evidence\$($env:COMPUTERNAME)-ProfileCheck1.txt"
$processes["ProfileCheck1"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\ProfileCheck1.ps1' `
    -RedirectStandardOutput ".\WinMaster_Evidence\$($env:COMPUTERNAME)-ProfileCheck1.txt" `
    -RedirectStandardError ".\WinMaster_Evidence\ERROR-$($env:COMPUTERNAME)-ProfileCheck1.txt" `
    -PassThru

if($LASTEXITCODE -eq 0) {
    $profileDetected = $true
}

Write-Host -ForegroundColor Cyan "Running Disable-RunKeys.ps1, review log in .\WinMaster_Evidence\$($env:COMPUTERNAME)-Disable-RunKeys.txt"
$processes["Disable-RunKeys"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\Disable-RunKeys.ps1' `
    -RedirectStandardOutput ".\WinMaster_Evidence\$($env:COMPUTERNAME)-Disable-RunKeys.txt" `
    -RedirectStandardError ".\WinMaster_Evidence\ERROR-$($env:COMPUTERNAME)-Disable-RunKeys.txt" `
    -PassThru

Write-Host -ForegroundColor Cyan "Running Get-Report.ps1, saving report to .\WinMaster_Evidence\$($env:COMPUTERNAME)-report.txt"
$processes["Get-Report"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\Get-Report.ps1' `
    -RedirectStandardError ".\WinMaster_Evidence\ERROR-$($env:COMPUTERNAME)-Get-Report.txt" `
    -PassThru

Write-Host -ForegroundColor Cyan "Running Check-Services2.ps1, review log in .\WinMaster_Evidence\$($env:COMPUTERNAME)-Check-Services2.txt"
$processes["Check-Services"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\Check-Services2.ps1' `
    -RedirectStandardOutput ".\WinMaster_Evidence\$($env:COMPUTERNAME)-Check-Services2.txt" `
    -RedirectStandardError ".\WinMaster_Evidence\ERROR-$($env:COMPUTERNAME)-Check-Services2.txt" `
    -PassThru

Write-Host -ForegroundColor Cyan "Running Find-PII-Light.ps1, review log in .\WinMaster_Evidence\$($env:COMPUTERNAME)-Find-PII-Light.txt"
$processes["Find-PII-Light"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\Find-PII-Light.ps1' `
    -RedirectStandardOutput ".\WinMaster_Evidence\$($env:COMPUTERNAME)-Find-PII-Light.txt" `
    -RedirectStandardError ".\WinMaster_Evidence\ERROR-$($env:COMPUTERNAME)-Find-PII-Light.txt" `
    -PassThru

Write-Host -ForegroundColor Cyan "Running Find-WindowsTamper.ps1, review log in .\WinMaster_Evidence\$($env:COMPUTERNAME)-Find-WindowsTamper.txt"
$processes["Check-WindowsTamper"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\Find-WindowsTamper.ps1', '-OutputPath', '.\WinMaster_Evidence', '-DeepScan', '-ShowInfo', '-DeepVerify', '-NoExport' `
    -RedirectStandardOutput ".\WinMaster_Evidence\$($env:COMPUTERNAME)-Find-WindowsTamper.txt" `
    -RedirectStandardError ".\WinMaster_Evidence\ERROR-$($env:COMPUTERNAME)-Find-WindowsTamper.txt" `
    -PassThru

Write-Host -ForegroundColor Cyan "Running CheckFirewall5.ps1, review log in .\WinMaster_Evidence\$($env:COMPUTERNAME)-CheckFirewall5.txt"
$processes["CheckFirewall5"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\CheckFirewall5.ps1' `
    -RedirectStandardOutput ".\WinMaster_Evidence\$($env:COMPUTERNAME)-CheckFirewall5.txt" `
    -RedirectStandardError ".\WinMaster_Evidence\ERROR-$($env:COMPUTERNAME)-CheckFirewall5.txt" `
    -PassThru

#Write-Host -ForegroundColor Cyan "Running Find-HiddenServices.ps1, review log in .\WinMaster_Evidence\$env:HOSTNAME-Find-HiddenServices.txt"
#$processes["Find-HiddenServices"] = Start-Process powershell.exe `
#    -WindowStyle Hidden `
#    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass','-actionParam', '2', '-File', '.\Find-HiddenServices.ps1' `
#    -RedirectStandardOutput ".\WinMaster_Evidence\$env:HOSTNAME-Find-HiddenServices.txt" `
#    -RedirectStandardError ".\WinMaster_Evidence\ERROR-$env:HOSTNAME-Find-HiddenServices.txt" `
#    -PassThru

Write-Host -ForegroundColor Cyan "Running Check-ScheduledTasks.ps1, review log in .\WinMaster_Evidence\$($env:COMPUTERNAME)-Check-ScheduledTasks.txt"
$processes["Check-ScheduledTasks"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\Check-ScheduledTasks.ps1' `
    -RedirectStandardOutput ".\WinMaster_Evidence\$($env:COMPUTERNAME)-Check-ScheduledTasks.txt" `
    -RedirectStandardError ".\WinMaster_Evidence\ERROR-$($env:COMPUTERNAME)-Check-ScheduledTasks.txt" `
    -PassThru

if($LASTEXITCODE -eq 0) {
    $suspiciousScheduledTasksFound = $true
}

#Write-Host -ForegroundColor Cyan "Running Find-IISWebshells.ps1, review log in .\WinMaster_Evidence\$env:HOSTNAME-Find-IISWebshells.txt"
#$processes["Check-ScheduledTasks"] = Start-Process powershell.exe `
#    -WindowStyle Hidden `
#    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Action', 'Review', '-File', '.\Find-IISWebshells.ps1' `
#    -RedirectStandardOutput ".\WinMaster_Evidence\$env:HOSTNAME-Find-IISWebshells.txt" `
#    -RedirectStandardError ".\WinMaster_Evidence\ERROR-$env:HOSTNAME-Find-IISWebshells.txt" `
#    -PassThru

# Non-script miscellaneous fixes
Write-Host -ForegroundColor Cyan "Checking common Windows Folders with sigcheck64.exe"
$processes["sigcheck-windows"] = Start-Process -FilePath $sigcheck `
    -WindowStyle Hidden `
    -ArgumentList '-e', '-u', '-r', '-accepteula', 'C:\Windows' `
    -RedirectStandardOutput ".\WinMaster_Evidence\$($env:COMPUTERNAME)-sigcheck-windows.txt" `
    -RedirectStandardError ".\WinMaster_Evidence\ERROR-$($env:COMPUTERNAME)-sigcheck-windows.txt" `
    -PassThru
$processes["sigcheck-system"] = Start-Process -FilePath $sigcheck `
    -WindowStyle Hidden `
    -ArgumentList '-e', '-u', '-r', '-accepteula', 'C:\Windows\System' `
    -RedirectStandardOutput ".\WinMaster_Evidence\$($env:COMPUTERNAME)-sigcheck-system.txt" `
    -RedirectStandardError ".\WinMaster_Evidence\ERROR-$($env:COMPUTERNAME)-sigcheck-system.txt" `
    -PassThru
$processes["sigcheck-system32"] = Start-Process -FilePath $sigcheck `
    -WindowStyle Hidden `
    -ArgumentList '-e', '-u', '-r', '-accepteula', 'C:\Windows\System32' `
    -RedirectStandardOutput ".\WinMaster_Evidence\$($env:COMPUTERNAME)-sigcheck-system32.txt" `
    -RedirectStandardError ".\WinMaster_Evidence\ERROR-$($env:COMPUTERNAME)-sigcheck-system32.txt" `
    -PassThru
$processes["sigcheck-drivers"] = Start-Process -FilePath $sigcheck `
    -WindowStyle Hidden `
    -ArgumentList '-e', '-u', '-r', '-accepteula', 'C:\Windows\System32\Drivers' `
    -RedirectStandardOutput ".\WinMaster_Evidence\$($env:COMPUTERNAME)-sigcheck-drivers.txt" `
    -RedirectStandardError ".\WinMaster_Evidence\ERROR-$($env:COMPUTERNAME)-sigcheck-drivers.txt" `
    -PassThru

# ======= END STAGE 3: Start Non-Interactive Scripts =======






# ======= BEGIN STAGE 4: Interactive Password Resetting =======

Write-Host "[$(Get-Date -Format "HH:mm:ss")] Starting Stage 4..."

# Run the interactive password resetting script in the current PowerShell process/scope
. ".\Reset-Passwords.ps1"

# ======= END STAGE 4: Interactive Password Resetting =======






# ======= BEGIN STAGE 5: Check For Non-Interactive Script Errors =======

Write-Host "[$(Get-Date -Format "HH:mm:ss")] Starting Stage 5..."

$targetDirectory = ".\WinMaster_Evidence"
$errorCount = 0

$finishedServiceCount = 0 # out of 10

# Check if any of the background scripts are still running
Write-Host -ForeGroundColor Cyan "Checking background scripts for completion, process will repeat every 10 seconds until done"
while($processes.Count -gt 0) {
    foreach($scriptName in @($processes.Keys)) {
        $process = $processes[$scriptName]

        if($process.HasExited) {
            $processes.Remove($scriptname)
            $finishedServiceCount++
        }
        else {
            Write-Host "$scriptName is still running."
        }
    }

    if($processes.Count -gt 0) {
        Start-Sleep -Seconds 10
    }
}

Write-Host -ForegroundColor Cyan "All background scripts complete."

# Delete empty evidence files
foreach ($file in Get-ChildItem -Path $targetDirectory -File) {
    if ($file.Length -eq 0) {
        Remove-Item -Path $file.FullName -Force
    }
}

# Count the number of error files in the evidence folder
foreach ($file in Get-ChildItem -Path $targetDirectory -File) {
    if($file.Name -match "^ERROR") {
        $errorCount++
    }
}

Write-Host -ForegroundColor Yellow "$errorCount Non-Interactive scripts encountered errors."

# ======= END STAGE 5: Check For Non-Interactive Script Errors =======






# ======= BEGIN STAGE 6: Alerts =======

Write-Host "[$(Get-Date -Format "HH:mm:ss")] Starting Stage 6...`n"

Write-Host -ForegroundColor Cyan "================================"
Write-Host -ForegroundColor Cyan "         System Alerts:"
Write-Host -ForegroundColor Cyan "================================"

# Alert on detected powershell profiles
if($profileDetected) {
    Write-Host -ForegroundColor Red "* Custom powershell profile(s) detected"
} else {
    Write-Host -ForegroundColor Green "* No custom powershell profiles detected"
}

if($suspiciousScheduledTasksFound) {
    Write-Host -ForegroundColor DarkYellow "* Potentially suspicious scheduled tasks detected"
} else {
    Write-Host -ForegroundColor Green "* No suspicious scheduled tasks detected"
}

# Alert on detected ssh
if(Get-Service -Name sshd -ErrorAction SilentlyContinue) {
    Write-Host -ForegroundColor Yellow "* Service sshd is installed"
}

# Alert on secure boot not being enabled
if(-not (confirm-securebootuefi)) {
    Write-Host -ForegroundColor Yellow "* Secure boot is not enabled"
} else {
    Write-Host -ForegroundColor Green "* Secure boot is already enabled"
}

# Alert on LSA protection being inactive (nosferatu possible)
if(-not (Test-LsaProtected)) {
    Write-Host -ForegroundColor DarkRed "* Lsa protection not enabled: possible nosferatu exploit"
} else {
    Write-host -ForegroundColor Green "* Lsa protection is enabled: nosferatu exploit not possible"
}

# Alert on webservers (IIS)
$iisFound = [bool](Get-Service -Name W3SVC -ErrorAction SilentlyContinue)
if($iisFound) {
    Write-Host -ForegroundColor Yellow "* IIS (W3SVC) is installed"
}

# Alert on SMB shares (excluding built-in admin shares like C$, ADMIN$, IPC$)
$shares = @(Get-SmbShare -Special $false -ErrorAction SilentlyContinue)
$sharesFound = $shares.Count -gt 0
if($sharesFound) {
    foreach($share in $shares) {
        Write-Host -ForegroundColor Yellow "* SMB share found: $($share.Path)"
    }
}

# ======= END STAGE 6: Alerts =======






# ======= BEGIN STAGE 7: Remediation =======

Write-Host "[$(Get-Date -Format "HH:mm:ss")] Starting Stage 7...`n"

# Prompt user for input
do {
    $doRemediation = Read-Host "Execute automatic remediation module? (y/n): "
} until ( ($doRemediation -eq 'y') -or ($doRemediation -eq 'n') )



# If user enters 'y', do remediation, otherwise skip
if($doRemediation -eq 'y') {


    # Items that must be remediated manually
    # - hidden services
    # - suspicious services
    # - suspicious executables

    # Disable Scheduled Task Service
    try {
        Stop-Service -name Schedule
        Set-Service -name Schedule -startuptype disabled
        Write-Host -ForegroundColor Green "Disabled: Scheduled Task service"
    }
    catch {
        Write-Host -ForegroundColor Red "Failed to disable: Scheduled Task service"
    }

    # Disable Print Spooler Service
    try {
        Set-Service Spooler -StartupType Disabled
        Stop-Service Spooler
        Write-Host -ForegroundColor Green "Disabled: Print Spooler service"
    }
    catch {
        Write-Host -ForegroundColor Red "Failed to disable: Print Spooler"
    }

    # Disable powershell profiles if any found
    if($profileDetected -and (Test-Path -LiteralPath $PROFILE)) {
        try {
            Rename-Item $PROFILE "$($PROFILE).disabled"
            Write-Host -ForegroundColor Green "Disabled: Powershell profiles"
        }
        catch {
            Write-Host -ForegroundColor Red "Failed to disable: Powershell profiles"
        }
    }
    
    # Disable test signing
    try {
        bcdedit /set testsigning off
        if ($LASTEXITCODE -ne 0) { throw "bcdedit failed with exit code $LASTEXITCODE" }
        Write-Host -ForegroundColor Green "Disabled: test signing"
    }
    catch {
        Write-Host -ForegroundColor Red "Failed to disable: test signing"
    }

    # Patch nosferatu
    try {
        reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v RunAsPPL /t REG_DWORD /d 1 /f
        if ($LASTEXITCODE -ne 0) { throw "reg add failed with exit code $LASTEXITCODE" }
        Write-Host -ForegroundColor Green "Patched: Nosferatu"
    }
    catch {
        Write-Host -ForegroundColor Red "Failed to patch: Nosferatu"
    }

    # Disable RDP shadowing
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "Shadow" -Value 0 -Type DWord
        Write-Host -ForegroundColor Green "Disabled: RDP Shadowing"
    }
    catch {
        Write-Host -ForegroundColor Red "Failed to disable: RDP shadowing"
    }

    # Web backup (if IIS exists)
    if($iisFound) {
        try {
            Import-Module WebAdministration -ErrorAction Stop

            # IIS stores this itself under C:\Windows\System32\inetsrv\backup\<Name>
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
            Backup-WebConfiguration -Name "$($env:COMPUTERNAME)-WebConfigBackup-$stamp" -ErrorAction Stop

            # Copy the site content into the WinMaster backup folder (timestamped so re-runs don't nest)
            $dest = ".\WinMaster_Backups\inetpub-$stamp"
            Copy-Item -Recurse -Path "C:\inetpub" -Destination $dest -ErrorAction Stop

            Write-Host -ForegroundColor Green "Web backup complete"
        }
        catch {
            Write-Host -ForegroundColor Red "Web backup failed: $($_.Exception.Message)"
        }
    }

    # Set up defensive powershell profile
    #try {
    #    New-Item -Path $PROFILE.AllUsersAllHosts -ItemType File -Force | Out-Null
    #    Copy-Item .\rizz.ps1 $PROFILE.AllUsersAllHosts -Force
    #    Write-Host -ForegroundColor Green "Activated: Defensive powershell profile"
    #}
    #catch {
    #    Write-Host -ForegroundColor Red "Failed to Activate: Defensive powershell profile"
    #}



# Skip if user enters 'n'
} else {
    Write-Host -ForegroundColor Blue "Skipping automated remediation..."
}

# ======= END STAGE 7: Remediation =======



# NEED TO HAVE A LIST OF REMINDERS FOR THE USER, SINCE NOT EVERYTHING DETECTED WILL BE REMEDIATED (unless you change behavior)


Write-Host -BackgroundColor White -ForegroundColor Black "`nTASKS COMPLETED (probably), PLEASE REVIEW LOGS IN .\WinMaster_Evidence`n"

exit 0