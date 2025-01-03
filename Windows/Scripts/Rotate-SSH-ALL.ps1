# Author: Dylan Harvey
# Script for rotating SSH keys for ALL USERS

$CurrentDir = Get-Location
$NewPubKeyPath = "$CurrentDir\cyberKey.pub"
$UserProfiles = Get-ChildItem "C:\Users"

# Read new public key
if (Test-Path $NewPubKeyPath) {
    $NewPubKey = Get-Content $NewPubKeyPath
    Write-Host "New public key found."
} else {
    Write-Host "Error: No public key file not found at $NewPubKeyPath"
    return
}

# Check each users's .ssh directory
foreach ($UserProfile in $UserProfiles) {
    $AuthKeysPath = "$($UserProfile.FullName)\.ssh\authorized_keys"

    # Ensure authorized_keys exists
    if (-Not (Test-Path $AuthKeysPath)) {
        New-Item -ItemType File -Path $AuthKeysPath -Force | Out-Null
        Write-Host "No authorized_keys found. Created a new one at $AuthKeysPath"
    }

    # Removes all old keys and adds new key
    Set-Content -Path $AuthKeysPath -Value $NewPubKey
    Write-Host "authorized_keys cleared and updated for user $UserProfile"
}

Pause