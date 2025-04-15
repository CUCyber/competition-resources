# Install-SSH.ps1
# Author: Dylan Harvey
# Downloads and installs SSH, with option to uninstall.
param (
    [switch]$Uninstall
)

[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
$global:ProgressPreference = "SilentlyContinue"

function Install-SSH {
    Write-Host "Installing SSH..."
    # Obtains the url for the latest release
    $url = "https://github.com/PowerShell/Win32-OpenSSH/releases/latest/"
    $request = [System.Net.WebRequest]::Create($url)
    $request.AllowAutoRedirect=$false
    $response=$request.GetResponse()
    $latest = $([String]$response.GetResponseHeader("Location")).Replace("tag","download") + "/OpenSSH-Win64.zip"  

    Write-Host "Downloading the latest OpenSSH Server..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $latest -OutFile "ssh.zip" 
    # Creates a folder to store the OpenSSH binaries, will error if folder already exists
    New-Item -ItemType Directory -Path "C:\Program Files\OpenSSH" | Out-Null

    Expand-Archive "ssh.zip" -DestinationPath "C:\Program Files\OpenSSH"

    Get-ChildItem -Path "C:\Program Files\OpenSSH\*" -Recurse | Move-Item -Destination "C:\Program Files\OpenSSH" -Force
    Get-ChildItem -Path "C:\Program Files\OpenSSH\OpenSSH-*" -Directory | Remove-Item -Force -Recurse

    Write-Host "Running install script..." -ForegroundColor Magenta
    Start-Process powershell.exe -ArgumentList "C:\Program Files\OpenSSH\install-sshd.ps1" -Wait

    Write-Host "Creating firewall rule..." -ForegroundColor Magenta
    New-NetFirewallRule -Name sshd -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    
    Write-Host "Starting ssh server..." -ForegroundColor Magenta
    Start-Service -Name sshd
    Set-Service -Name sshd -StartupType Automatic

    Write-Host "SSH installation complete!" -ForegroundColor Green
}

function Uninstall-SSH {
    Write-Host "Uninstalling SSH..."
    
    Write-Host "Stopping SSH Server..." -ForegroundColor Yellow
    Stop-Service -Name sshd

    Write-Host "Running uninstall script..." -ForegroundColor Magenta
    Start-Process powershell.exe -ArgumentList "C:\Program Files\OpenSSH\uninstall-sshd.ps1" -Wait

    Write-Host "Removing leftover files..." -ForegroundColor Magenta
    Remove-Item -Path "C:\Program Files\OpenSSH" -Recurse -Force

    Write-Host "Removing firewall rule..." -ForegroundColor Magenta
    Remove-NetFirewallRule -Name sshd

    Write-Host "SSH uninstallation complete!" -ForegroundColor Green
}

if ($Uninstall) {
    Uninstall-SSH
} else {
    Install-SSH
}
