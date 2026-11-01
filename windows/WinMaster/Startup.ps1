# Author BlueNitrobotX
# Escalation and startup script for WinMaster

# Check that Sysinternals is installed, and install it if needed
if(-not(Test-Path -Path "C:\SysinternalsSuite" -PathType Container)) {
    
    Write-Host -ForegroundColor Cyan "Attempting to install Sysinternals"
        
    try {
        
        # Run the installation script
        #Set-ExecutionPolicy unrestricted
        Start-Process powershell.exe `
            -WindowStyle Hidden `
            -ArgumentList '-NoProfile', '-File', '-ExecutionPolicy Bypass', '.\Install-Sysinternals.ps1' `
            -Wait
    }
    catch {
        
        # Error handling
        Write-Host -ForegroundColor Red -BackgroundColor DarkRed "Failed to install Sysinternals"
        exit 1
    }
}

# Check that this script is running as system
if([System.Security.Principal.WindowsIdentity]::GetCurrent().Name -ne "NT AUTHORITY\SYSTEM") {
    
    $seshid = (Get-Process -Id $PID).SessionId

    # Try to use PsExec to run the master script as system
    try {
        Set-ExecutionPolicy unrestricted
        Start-Process `
            -FilePath "C:\SysinternalsSuite\PsExec64.exe" `
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
                "C:\WinMaster\Master.ps1"
            ) `
            -Wait `
            -PassThru
    }
    catch {

        # Error handling
        Write-Host -BackgroundColor DarkRed -ForegroundColor Red "FAILED TO OBTAIN SYSTEM PRIVILEGES"
        exit 1
    }

    # End this process once successfully elevated the master script
    exit 0
}