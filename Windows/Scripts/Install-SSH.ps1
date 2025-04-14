# Install-SSH.ps1
# Author: Dylan Harvey
# Downloads and installs SSH, with option to uninstall.
param (
    [switch]$Uninstall
)

[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
$global:ProgressPreference = "SilentlyContinue"

function Install-SSH {
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
    Start-Process "powershell.exe" -ArgumentList "C:\Program Files\OpenSSH\install-sshd.ps1" -Wait

    Write-Host "Creating firewall rule..."
    New-NetFirewallRule -Name sshd -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    
    Write-Host "Starting ssh server..." 
    Start-Service -Name sshd
    Set-Service -Name sshd -StartupType Automatic
}

function Uninstall-SSH {
    Write-Host "Stopping SSH Server..." -ForegroundColor Yellow
    Stop-Service -Name sshd

    Write-Host "Running uninstall script..."
    Start-Process "powershell.exe" -ArgumentList "C:\Program Files\OpenSSH\uninstall-sshd.ps1" -Wait

    Write-Host "Removing leftover files..."
    Remove-Item "C:\Program Files\OpenSSH" -Recurse -Force

    Write-Host "Removing firewall rule..."
    Remove-NetFirewallRule -Name sshd
}

if ($Uninstall) {
    Write-Host "Uninstalling SSH..."
    Uninstall-SSH
    Write-Host "Uninstallation complete!" -ForegroundColor Green
} else {
    Write-Host "Installing SSH..."
    Install-SSH
    Write-Host "Installation complete!" -ForegroundColor Green
}
