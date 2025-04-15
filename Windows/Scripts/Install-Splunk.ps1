# Install-Splunk.ps1
# Author: Dylan Harvey (Modified from BYU and SEMO's Original)
# Downloads and installs splunk on a windows machine.
param (
    [switch]$Uninstall
)

[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
$global:ProgressPreference = "SilentlyContinue"

# Global Vars
$SPLUNK_VERSION = "9.1.1"
$SPLUNK_BUILD = "64e843ea36b1"
$SPLUNK_MSI = "splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-x64-release.msi"
$SPLUNK_DOWNLOAD_URL = "https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/windows/${SPLUNK_MSI}"
$INSTALL_DIR = "C:\Program Files\SplunkUniversalForwarder"
$INDEXER_IP = "" # SET THIS
$RECEIVER_PORT = "9997"

$HOSTNAME = $env:computername

function Install-Splunk {
    Write-Host "Installing Splunk..."
    Write-Host "Downloading Splunk Universal Forwarder MSI..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $SPLUNK_DOWNLOAD_URL -OutFile $SPLUNK_MSI

    Write-Host "Installing Splunk Universal Forwarder..." -ForegroundColor Magenta
    Start-Process msiexec.exe -ArgumentList "/i $SPLUNK_MSI SPLUNKUSERNAME=splunk SPLUNKPASSWORD=$password USE_LOCAL_SYSTEM=1 RECEIVING_INDEXER=${INDEXER_IP}:${RECEIVER_PORT} AGREETOLICENSE=yes LAUNCHSPLUNK=1 SERVICESTARTTYPE=auto /L*v splunk_log.txt /quiet" -Wait -NoNewWindow

    if (Test-Path "${INSTALL_DIR}\bin\splunk.exe") {
        Write-Host "Splunk installed successfully!" -ForegroundColor Green
    } else {
        Write-Host "Splunk installation failed." -ForegroundColor Red
        exit 2
    }

    $inputsConfPath = "${INSTALL_DIR}\etc\system\local\inputs.conf"
    Write-Host "Configuring inputs.conf for monitoring..." -ForegroundColor Magenta
@"
[default]
host = ${HOSTNAME}

[WinEventLog] 
index = windows
checkpointInterval = 5

[WinEventLog://Security]
disabled = 0
index = windows

[WinEventLog://Application]
dsiabled = 0
index = windows

[WinEventLog://System]
disabled = 0
index = windows

[WinEventLog://DNS Server]
disabled = 0
index = windows

[WinEventLog://Directory Service]
disabled = 0
index = windows

[WinEventLog://Windows Powershell]
disabled = 0
index = windows

[WinEventLog://Microsoft-Windows-Sysmon/Operational]
disabled = 0
index = windows
"@ | Out-File -FilePath $inputsConfPath -Encoding ASCII
    # May want in sysmon inputconfs (if it works)
    # current_only = 0
    # start_from = oldest
    # renderXml = false

    # Disable KVStore if necessary
    $serverConfPath = "${INSTALL_DIR}\etc\system\local\server.conf"
    Write-Host "Setting custom hostname for the logs..." -ForegroundColor Magenta
@"
[general]
serverName = $HOSTNAME
hostnameOption = shortname
"@ | Out-File -FilePath $serverConfPath -Encoding ASCII

    Write-Host "Starting Splunk Universal Forwarder..." -ForegroundColor Magenta
    Start-Process -FilePath "${INSTALL_DIR}\bin\splunk.exe" -ArgumentList "start" -Wait -NoNewWindow

    Write-Host "Setting Splunk Universal Forwarder to start on boot..." -ForegroundColor Magenta
    Start-Process -FilePath "${INSTALL_DIR}\bin\splunk.exe" -ArgumentList "enable boot-start" -Wait -NoNewWindow

    Write-Host "Splunk Universal Forwarder installation and configuration complete!" -ForegroundColor Green
    Write-Host "Splunk installation complete!" -ForegroundColor Green
}

function Uninstall-Splunk {
    Write-Host "Uninstalling Splunk..."
    Write-Host "Stopping Splunk Universal Forwarder..." -ForegroundColor Yellow
    Start-Process -FilePath "${INSTALL_DIR}\bin\splunk.exe" -ArgumentList "stop" -Wait -NoNewWindow

    Write-Host "Setting Splunk Universal Forwarder to NOT start on boot..." -ForegroundColor Magenta
    Start-Process -FilePath "${INSTALL_DIR}\bin\splunk.exe" -ArgumentList "disable boot-start" -Wait -NoNewWindow

    Write-Host "Uninstalling Splunk Universal Forwarder..." -ForegroundColor Magenta
    Start-Process msiexec.exe -ArgumentList "/x $SPLUNK_MSI /L*v uninstall_splunk_log.txt /quiet" -Wait -NoNewWindow

    Write-Host "Splunk uninstallation complete!" -ForegroundColor Green
}

if ($Uninstall) {
    Uninstall-Splunk
} else {
    Install-Splunk
}
