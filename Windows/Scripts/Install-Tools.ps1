# Install-Tools.ps1
# Author: Dylan Harvey
# Script to download and install relevant tools for hardening, threathunting, and more
param (
    [switch]$All,
    [switch]$Uninstall
)

[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
$global:ProgressPreference = "SilentlyContinue"

# Add functions for each tool

# Add logic for each tools flag
if ($Uninstall) {

} else {
    
}
