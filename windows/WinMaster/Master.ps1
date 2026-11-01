# Author BlueNitrobotX
# Master Script 

# TODO:
# Automatically process script results and give the user a summary/list of helpful info
# - Improve evidence collection of all scripts (CHECK OTHERS)
#   - Add timestamps to non-interactive scripts' outputs
#
# Improve/finish Check-ScheduledTasks
#
# Look into implementing the following Sysinternals tools into the misc stage:
# - AccessChk.exe
# - Streams.exe
#
# Create new Active Directory hardening script
#
#
# Create a database/webserver backup script
# - Detect and backup any databases and webservers on the machine
#
#
# Rewrite in rust or python or compile into an exe
# Add execution flags (if possible)
# Add remote execution (With WinRM maybe)
#   - Add capacity for mass network execution & enumeration from a remote jump box/your device
#      - Implement support for "Evidence" directories for every inputted machine

# Implement nosferatu patch: insert DWORD key with value 1 at Computer\HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Lsa
# Disable RDP shadowing
# Disable write permissions for WinMaster directory?



# Detection only scripts (for now, some will be updated):
# - Find-WindowsTamper, ProfileCheck, Check-ScheduledTasks, Check-Services2, Find-HiddenServices, Find-PII-Light, Get-Report

# Detection and Remediation scripts:
# - CheckFirewall5, Disable-RunKeys


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

Write-Host "Starting Stage 1..."

Set-Location "C:\WinMaster"

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
    # Move any evidence from previous runs into C:\WinMaster\OLD-WinMaster_Evidence
    $evidenceItems = Get-ChildItem -Path "C:\WinMaster\WinMaster_Evidence" -File
    $oldEvidenceItems = Get-ChildItem -Path "C:\WinMaster\OLD-WinMaster_Evidence"
    if($oldEvidenceItems.Count -eq 0) {
            if($evidenceItems.Count -gt 0) {
                foreach($evidenceItem in $evidenceItems) {
                    Move-Item -Path $evidenceItem.FullName -Destination "C:\WinMaster\OLD-WinMaster_Evidence"
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
    ".\Find-WindowsTamper.ps1",
    ".\CheckFirewall5.ps1",
    ".\Find-HiddenServices.ps1",
    ".\Check-ScheduledTasks.ps1",
    ".\Install-Sysinternals.ps1",
    ".\rmbin2.ps1"
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

Write-Host "Starting Stage 2..."

# Check that this script is running as system
if([System.Security.Principal.WindowsIdentity]::GetCurrent().Name -ne "NT AUTHORITY\SYSTEM") {
        # Error handling
        Write-Host -BackgroundColor DarkRed -ForegroundColor Red "FAILED TO OBTAIN SYSTEM PRIVILEGES"
        exit 1
}

# ======= END STAGE 2: Privileges Check =======






# ======= BEGIN STAGE 3: Start Non-Interactive Scripts =======

Write-Host "Starting Stage 3..."


# Variables to keep track of sub-script exit codes/statuses
$profileDetected = $false
$hiddenServicesFound = $false
$suspiciousServicesFound = $false
$suspiciousScheduledTasksFound = $false
$suspiciousExecutablesFound = $false
$suspiciousFirewallRulesFound = $false


# Create hash table to keep track of each script's process
$processes = @{}

Write-Host -ForegroundColor Cyan "Running ProfileCheck1.ps1, review log in .\WinMaster_Evidence\ProfileCheck1.txt"
$processes["ProfileCheck1"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\ProfileCheck1.ps1' `
    -RedirectStandardOutput '.\WinMaster_Evidence\ProfileCheck1.txt' `
    -RedirectStandardError '.\WinMaster_Evidence\ERROR-ProfileCheck1.txt' `
    -PassThru

if($LASTEXITCODE -eq 0) {
    $profileDetected = $true
}

Write-Host -ForegroundColor Cyan "Running Disable-RunKeys.ps1, review log in .\WinMaster_Evidence\Disable-RunKeys.txt"
$processes["Disable-RunKeys"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\Disable-RunKeys.ps1' `
    -RedirectStandardOutput '.\WinMaster_Evidence\Disable-RunKeys.txt' `
    -RedirectStandardError '.\WinMaster_Evidence\ERROR-Disable-RunKeys.txt' `
    -PassThru

Write-Host -ForegroundColor Cyan "Running Get-Report.ps1, saving report to .\WinMaster_Evidence\report.txt"
$processes["Get-Report"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\Get-Report.ps1' `
    -RedirectStandardError '.\WinMaster_Evidence\ERROR-Get-Report.txt' `
    -PassThru

Write-Host -ForegroundColor Cyan "Running Check-Services2.ps1, review log in .\WinMaster_Evidence\Check-Services2.txt"
$processes["Check-Services"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\Check-Services2.ps1', '-ExcludeFile', '.\allowlist.txt' `
    -RedirectStandardOutput '.\WinMaster_Evidence\Check-Services2.txt' `
    -RedirectStandardError '.\WinMaster_Evidence\ERROR-Check-Services2.txt' `
    -PassThru

Write-Host -ForegroundColor Cyan "Running Find-PII-Light.ps1, review log in .\WinMaster_Evidence\Find-PII-Light.txt"
$processes["Find-PII-Light"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\Find-PII-Light.ps1' `
    -RedirectStandardOutput '.\WinMaster_Evidence\Find-PII-Light.txt' `
    -RedirectStandardError '.\WinMaster_Evidence\ERROR-Find-PII-Light.txt' `
    -PassThru

Write-Host -ForegroundColor Cyan "Running Find-WindowsTamper.ps1, review log in .\WinMaster_Evidence\Find-WindowsTamper.txt"
$processes["Check-WindowsTamper"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\Find-WindowsTamper.ps1', '-OutputPath', '.\WinMaster_Evidence', '-DeepScan', '-ShowInfo', '-DeepVerify', '-NoExport' `
    -RedirectStandardOutput '.\WinMaster_Evidence\Find-WindowsTamper.txt' `
    -RedirectStandardError '.\WinMaster_Evidence\ERROR-Find-WindowsTamper.txt' `
    -PassThru

Write-Host -ForegroundColor Cyan "Running CheckFirewall5.ps1, review log in .\WinMaster_Evidence\CheckFirewall5.txt"
$processes["CheckFirewall5"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\CheckFirewall5.ps1' `
    -RedirectStandardOutput '.\WinMaster_Evidence\CheckFirewall5.txt' `
    -RedirectStandardError '.\WinMaster_Evidence\ERROR-CheckFirewall5.txt' `
    -PassThru

Write-Host -ForegroundColor Cyan "Running Find-HiddenServices.ps1, review log in .\WinMaster_Evidence\Find-HiddenServices.txt"
$processes["Find-HiddenServices"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass','-actionParam', '2', '-File', '.\Find-HiddenServices.ps1' `
    -RedirectStandardOutput '.\WinMaster_Evidence\Find-HiddenServices.txt' `
    -RedirectStandardError '.\WinMaster_Evidence\ERROR-Find-HiddenServices.txt' `
    -PassThru

Write-Host -ForegroundColor Cyan "Running Check-ScheduledTasks.ps1, review log in .\WinMaster_Evidence\Check-ScheduledTasks.txt"
$processes["Check-ScheduledTasks"] = Start-Process powershell.exe `
    -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\Check-ScheduledTasks.ps1' `
    -RedirectStandardOutput '.\WinMaster_Evidence\Check-ScheduledTasks.txt' `
    -RedirectStandardError '.\WinMaster_Evidence\ERROR-Check-ScheduledTasks.txt' `
    -PassThru

if($LASTEXITCODE -eq 0) {
    $suspiciousScheduledTasksFound = $true
}

# Non-script miscellaneous fixes
Write-Host -ForegroundColor Cyan "Checking common Windows Folders with sigcheck.exe"
$processes["sigcheck-windows"] = Start-Process C:\SysinternalsSuite\sigcheck.exe `
    -WindowStyle Hidden `
    -ArgumentList '-e', '-u', '-r', '-accepteula', 'C:\Windows' `
    -RedirectStandardOutput '.\WinMaster_Evidence\sigcheck-windows.txt' `
    -RedirectStandardError '.\WinMaster_Evidence\ERROR-sigcheck-windows.txt' `
    -PassThru
$processes["sigcheck-system"] = Start-Process C:\SysinternalsSuite\sigcheck.exe `
    -WindowStyle Hidden `
    -ArgumentList '-e', '-u', '-r', '-accepteula', 'C:\Windows\System' `
    -RedirectStandardOutput '.\WinMaster_Evidence\sigcheck-system.txt' `
    -RedirectStandardError '.\WinMaster_Evidence\ERROR-sigcheck-system.txt' `
    -PassThru
$processes["sigcheck-system32"] = Start-Process C:\SysinternalsSuite\sigcheck.exe `
    -WindowStyle Hidden `
    -ArgumentList '-e', '-u', '-r', '-accepteula', 'C:\Windows\System32' `
    -RedirectStandardOutput '.\WinMaster_Evidence\sigcheck-system32.txt' `
    -RedirectStandardError '.\WinMaster_Evidence\ERROR-sigcheck-system32.txt' `
    -PassThru
$processes["sigcheck-drivers"] = Start-Process C:\SysinternalsSuite\sigcheck.exe `
    -WindowStyle Hidden `
    -ArgumentList '-e', '-u', '-r', '-accepteula', 'C:\Windows\System32\Drivers' `
    -RedirectStandardOutput '.\WinMaster_Evidence\sigcheck-drivers.txt' `
    -RedirectStandardError '.\WinMaster_Evidence\ERROR-sigcheck-drivers.txt' `
    -PassThru

# ======= END STAGE 3: Start Non-Interactive Scripts =======






# ======= BEGIN STAGE 4: Interactive Password Resetting =======

Write-Host "Starting Stage 4..."

# Run the interactive password resetting script in the current PowerShell process/scope
. ".\Reset-Passwords.ps1"

# ======= END STAGE 4: Interactive Password Resetting =======






# ======= BEGIN STAGE 5: Check For Non-Interactive Script Errors =======

Write-Host "Starting Stage 5..."

$targetDirectory = ".\WinMaster_Evidence"
$errorCount = 0

$finishedServiceCount = 0 # out of 10

# Check if any of the background scripts are still running
Write-Host -ForeGroundColor Cyan "Checking background scripts for completion, process will repeat every 10 seconds until done"
while($processes.Count -gt 0) {
    foreach ($scriptName in @($processes.Keys)) {
        $process = $processes[$scriptName]

        if ($process.HasExited) {
            $processes.Remove($scriptname)
            $finishedServiceCount++
        }
        else {
            Write-Host "$scriptName is still running."
        }
    }

    if ($processes.Count -gt 0) {
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

Write-Host -ForegroundColor Cyan "================================"
Write-Host -ForegroundColor Cyan "         System Alerts:"
Write-Host -ForegroundColor Cyan "================================"

# Alert on detected powershell profiles
if($profileDetected) {
    Write-Host -ForegroundColor Red "* Custom powershell profile(s) detected"
}

if($suspiciousScheduledTasksFound) {
    Write-Host -ForegroundColor DarkYellow "* Potentially suspicious scheduled tasks detected"
}

# Alert on detected ssh
if( (Get-Service -Name sshd -ErrorAction SilentlyContinue) -or (Get-Service -Name ssh-agent -ErrorAction SilentlyContinue) ) {
    Write-Host -ForegroundColor Yellow "* Service sshd is installed"
}

# Alert on secure boot not being enabled
if(-not (confirm-securebootuefi)) {
    Write-Host -ForegroundColor Yellow "* Secure boot is not enabled"
}

# Alert on LSA protection being inactive (nosferatu possible)
if(-not (Test-LsaProtected)) {
    Write-Host -ForegroundColor DarkRed "* Lsa protection not enabled: possible nosferatu exploit"
}

# ======= END STAGE 6: Alerts =======






# ======= BEGIN STAGE 7: Remediation =======


# Prompt user for input
$doRemediation = Read-Host "`n Scan complete. When evidence has been collected, enter `"y`" to begin remediation or `"n`" to skip"
do {
    $doRemediation = Read-Host "Enter `"y`" to begin automatated remediation or `"n`" to skip"
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
        Write-Host -ForegroundColor Green "Disabled: Scheduled Task Service"
    }
    catch {
        Write-Host -ForegroundColor Red "Failed to disable: Scheduled Task Service"
    }

    # Disable Print Spooler Service
    try {
        Set-Service Spooler -StartupType Disabled
        Stop-Service Spooler
        Write-Host -ForegroundColor Green "Disabled: Print Spooler Service"
    }
    catch {
        Write-Host -ForegroundColor Red "Failed to disable: Print Spooler"
    }

    # Disable powershell profiles if any found
    if($profileDetected) {
        try {
            Rename-Item $PROFILE "$($PROFILE).disabled"
            Write-Host -ForegroundColor Green "Disabled: Powershell Profiles"
        }
        catch {
            Write-Host -ForegroundColor Red "Failed to disable: Powershell Profiles"
        }
    }
    
    # Disable test signing
    try {
        bcedit /set testsigning off
        Write-Host -ForegroundColor Green "Disabled: test signing"
    }
    catch {
        Write-Host -ForegroundColor Red "Failed to disable: test signing"
    }

    # Patch nosferatu
    try {
        reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v RunAsPPL /t REG_DWORD /d 1 /f
        Write-Host -ForegroundColor Green "Patched: Nosferatu"
    }
    catch {
        Write-Host -ForegroundColor Red "Failed to patch: Nosferatu"
    }


# Skip if user enters 'n'
} else {
    Write-Host -ForegroundColor Blue "Skipping automated remediation..."
}

# ======= END STAGE 7: Remediation =======



# NEED TO HAVE A LIST OF REMINDERS FOR THE USER, SINCE NOT EVERYTHING DETECTED WILL BE REMEDIATED (unless you change behavior)


Write-Host -BackgroundColor White -ForegroundColor Black "`nTASKS COMPLETED (probably), PLEASE REVIEW LOGS IN .\WinMaster_Evidence`n"

exit 0