# Credit to BYU and SEMO :)

# Define variables
$SPLUNK_VERSION = "9.1.1"
$SPLUNK_BUILD = "64e843ea36b1"
$SPLUNK_MSI = "splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-x64-release.msi"
$SPLUNK_DOWNLOAD_URL = "https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/windows/${SPLUNK_MSI}"
$INSTALL_DIR = "C:\Program Files\SplunkUniversalForwarder"
$INDEXER_IP = ""
$RECEIVER_PORT = "9997"

$HOSTNAME = $env:computername

# Download Splunk Universal Forwarder MSI
Write-Host "Downloading Splunk Universal Forwarder MSI..."
Invoke-WebRequest -Uri $SPLUNK_DOWNLOAD_URL -OutFile $SPLUNK_MSI

# Install Splunk Universal Forwarder
Write-Host "Installing Splunk Universal Forwarder..."
Start-Process msiexec.exe -ArgumentList "/i $SPLUNK_MSI SPLUNKUSERNAME=splunk SPLUNKPASSWORD=$password USE_LOCAL_SYSTEM=1 RECEIVING_INDEXER=${INDEXER_IP}:${RECEIVER_PORT} AGREETOLICENSE=yes LAUNCHSPLUNK=1 SERVICESTARTTYPE=auto /L*v splunk_log.txt /quiet" -Wait -NoNewWindow

if (Test-Path "${INSTALL_DIR}\bin\splunk.exe") {
    print "Splunk installed successfully"
} else {
    error "Splunk installation failed"
    exit 1
}

# Configure inputs.conf for monitoring
$inputsConfPath = "${INSTALL_DIR}\etc\system\local\inputs.conf"
Write-Host "Configuring inputs.conf for monitoring..."
@"
[default]
host = ${HOSTNAME}

[WinEventLog] 
index = windows
checkpointInterval = 5

[WinEventLog://Security]
disabled = 0
index = main

[WinEventLog://Application]
dsiabled = 0
index = main

[WinEventLog://System]
disabled = 0
index = main

[WinEventLog://DNS Server]
disabled = 0
index = main

[WinEventLog://Directory Service]
disabled = 0
index = main

[WinEventLog://Windows Powershell]
disabled = 0
index = main

[WinEventLog://Microsoft-Windows-Sysmon/Operational]
current_only = 0
disabled = 0
start_from = oldest
renderXml = false
"@ | Out-File -FilePath $inputsConfPath -Encoding ASCII

# Disable KVStore if necessary
$serverConfPath = "${INSTALL_DIR}\etc\system\local\server.conf"
Write-Host "Setting custom hostname for the logs..."
@"
[general]
serverName = $HOSTNAME
hostnameOption = shortname
"@ | Out-File -FilePath $serverConfPath -Encoding ASCII

# Start Splunk Universal Forwarder service
Write-Host "Starting Splunk Universal Forwarder service..."
Start-Process -FilePath "${INSTALL_DIR}\bin\splunk.exe" -ArgumentList "start" -Wait

# Set Splunk Universal Forwarder to start on boot
Write-Host "Setting Splunk Universal Forwarder to start on boot..."
Start-Process -FilePath "${INSTALL_DIR}\bin\splunk.exe" -ArgumentList "enable boot-start" -Wait

Write-Host "Splunk Universal Forwarder installation and configuration complete!"
