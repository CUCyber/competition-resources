#Requires -RunAsAdministrator

function Install-SSH {
    # obtains the url for the latest release
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = 'https://github.com/PowerShell/Win32-OpenSSH/releases/latest/'
    $request = [System.Net.WebRequest]::Create($url)
    $request.AllowAutoRedirect=$false
    $response=$request.GetResponse()
    $latest = $([String]$response.GetResponseHeader("Location")).Replace('tag','download') + '/OpenSSH-Win64.zip'  

    echo "Downloading the latest OpenSSH Server.."
    curl -URI $latest -OutFile 'ssh.zip' 

    # creates a folder to store the OpenSSH binaries, will error if folder already exists
    New-Item -itemType Directory -Path 'C:\Program Files\OpenSSH'

    # extracts the downloaded zip to the binary folder
    Expand-Archive 'ssh.zip' -DestinationPath "C:\Program Files\OpenSSH"

    # if the zip extracted a folder, moves all items in that folder to the root of the OpenSSH directory
    # clean up the extracted folder if needed
    Get-ChildItem -Path 'C:\Program Files\OpenSSH\*' -Recurse | Move-Item -Destination 'C:\Program Files\OpenSSH' -Force
    Get-ChildItem -Path 'C:\Program Files\OpenSSH\OpenSSH-*' -Directory | Remove-Item -Force -Recurse

    # runs installation script
    & 'C:\Program Files\OpenSSH\install-sshd.ps1'

    # sets up inbound firewall rule
    New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22

    # starts the ssh server and sets its launch type to automatic
    net start sshd
    Set-Service sshd -StartupType Automatic
}

function Uninstall-SSH {
    # runs uninstall script
    & 'C:\Program Files\OpenSSH\uninstall-sshd.ps1'
    
    # deletes the OpenSSH directory recursively
    Remove-Item 'C:\Program Files\OpenSSH' -Recurse -Force
    
    # removes the sshd firewall rule
    Remove-NetFirewallRule -Name sshd 
}

Install-SSH