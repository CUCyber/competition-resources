# Author: Dylan Harvey (modified from Joshua Wright's Original, see URL)
# Script for finding hidden services. (WIP)
# https://www.sans.org/blog/defense-spotlight-finding-hidden-windows-services/

Compare-Object `
    -ReferenceObject (Get-Service | 
        Select-Object -ExpandProperty Name |
        ForEach-Object { $_ -replace "_[0-9a-f]{2,8}$" } ) `
    -DifferenceObject (Get-ChildItem -path hklm:\system\currentcontrolset\services |
        ForEach-Object { $_.Name -Replace "HKEY_LOCAL_MACHINE\\","HKLM:\" } |
        Where-Object { Get-ItemProperty -Path "$_" -name objectname -erroraction 'ignore' } |
        ForEach-Object { $_.substring(40) }) -PassThru |
    Where-Object { $_.sideIndicator -eq "=>" }

    