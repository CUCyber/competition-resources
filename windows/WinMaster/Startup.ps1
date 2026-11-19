# Author BlueNitrobotX
# Escalation and startup script for WinMaster

$pathSIS = Join-Path $PSScriptRoot 'SysinternalsSuite'
$psexec = Join-Path $pathSIS 'PsExec64.exe'
$installer = Join-Path $PSScriptRoot 'Install-Sysinternals.ps1'
$pathM = Join-Path $PSScriptRoot 'Master.ps1'
$installArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -pathParam "{1}"' -f $installer, $pathSIS

# Check that Sysinternals is installed, and install it if needed.
# Test for the executable we actually need, not just the folder, so a partial install is retried.
if(-not (Test-Path -Path $psexec -PathType Leaf)) {

    Write-Host -ForegroundColor Cyan "Attempting to install Sysinternals"

    if(-not (Test-Path -Path $installer -PathType Leaf)) {
        Write-Host -ForegroundColor Red -BackgroundColor DarkRed "Cannot find $installer"
        exit 1
    }

    try {

        # Run the installation script in this console (not hidden) so download errors are visible.
        # Start-Process only throws if it cannot launch powershell.exe, so the exit code is checked below.
        $inst = Start-Process powershell.exe `
            -NoNewWindow `
            -ArgumentList $installArgs `
            -Wait `
            -PassThru `
            -ErrorAction Stop
        $null = $inst.Handle
    }
    catch {

        # Error handling
        Write-Host -ForegroundColor Red -BackgroundColor DarkRed "Failed to launch the Sysinternals installer: $($_.Exception.Message)"
        exit 1
    }

    if($inst.ExitCode -ne 0 -or -not (Test-Path -Path $psexec -PathType Leaf)) {
        Write-Host -ForegroundColor Red -BackgroundColor DarkRed "Failed to install Sysinternals (installer exit code: $($inst.ExitCode))"
        exit 1
    }
}

# Check that this script is running as system
if([System.Security.Principal.WindowsIdentity]::GetCurrent().Name -ne "NT AUTHORITY\SYSTEM") {

    $seshid = (Get-Process -Id $PID).SessionId

    # Try to use PsExec to run the master script as system.
    # (No Set-ExecutionPolicy here: -ExecutionPolicy Bypass below already covers the child process,
    #  and Set-ExecutionPolicy needs admin, prompts, and permanently weakens the machine.)
    try {
        $psexecProc = Start-Process `
            -FilePath $psexec `
            -Verb RunAs `
            -ArgumentList @(
                "-accepteula"
                "-s"
                "-i $seshid"
                "powershell.exe"
                "-NoProfile"
                "-ExecutionPolicy Bypass"
                "-NoExit"
                "-File"
                ('"{0}"' -f $pathM)
            ) `
            -Wait `
            -PassThru `
            -ErrorAction Stop
    }
    catch {

        # Error handling (UAC declined, PsExec blocked by AV, etc.)
        Write-Host -BackgroundColor DarkRed -ForegroundColor Red "FAILED TO OBTAIN SYSTEM PRIVILEGES: $($_.Exception.Message)"
        exit 1
    }

    if($psexecProc.ExitCode -ne 0) {
        Write-Host -ForegroundColor Yellow "PsExec exited with code $($psexecProc.ExitCode); check the Master window/log for errors."
    }

    # End this process once successfully elevated the master script
    exit 0

} else {

    # Start master script if already system
    & $pathM

    exit 0
}