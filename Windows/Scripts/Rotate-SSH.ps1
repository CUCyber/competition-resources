# Author: Dylan Harvey
# Script for rotating SSH keys. (WIP v0.1)
# TODO: All Users, File Permissions?

$CurrentDir = Get-Location
$NewPubKeyPath = "$CurrentDir\cyberKey.pub"
$AuthKeysPath = "$env:USERPROFILE\.ssh\authorized_keys"

# Ensure authorized_keys exists
if (-Not (Test-Path $AuthKeysPath)) {
    New-Item -ItemType File -Path $AuthKeysPath -Force | Out-Null
    Write-Host "No authorized_keys found. Created a new one at $AuthKeysPath"
}

# Read new public key
if (Test-Path $NewPubKeyPath) {
    $NewPubKey = Get-Content $NewPubKeyPath
    Write-Host "New public key found."
} else {
    Write-Host "Error: No public key file not found at $NewPubKeyPath"
    return
}

# Removes all old keys and adds new key
Set-Content -Path $AuthKeysPath -Value $NewPubKey
Write-Host "authorized_keys cleared and updated."

# Update permissions on authorized_keys file?
# icacls?

Pause