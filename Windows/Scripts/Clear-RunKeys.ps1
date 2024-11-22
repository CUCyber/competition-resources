# Author: Dylan Harvey
# Script for removing common runkeys. (WIP)

#Requires -RunAsAdministrator

$RunKeys = @(
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
)

# Clear all values in the keys
foreach ($Key in $RunKeys) {
    Remove-ItemProperty -Path $Key -Name * -ErrorAction SilentlyContinue
}

