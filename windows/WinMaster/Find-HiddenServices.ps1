# Find-HiddenServices.ps1
# Author: Dylan Harvey (modified from Joshua Wright's Original, see URL) - Modified by BlueNitrobotX
# Script for finding hidden services.
# https://www.sans.org/blog/defense-spotlight-finding-hidden-windows-services/

# Locates potentially unwanted hidden services
# Idea: a hidden service is absent from the Service Control Manager's list (Get-Service) but still
# has a key under HKLM\SYSTEM\CurrentControlSet\Services. Compare the two lists.

param(
    [String]$actionParam
)

$servicesKey = 'HKLM:\SYSTEM\CurrentControlSet\Services'

# --- List 1: services the Service Control Manager will show us -----------------------------------
# Per-user services get a random suffix (e.g. CDPUserSvc_3b7d9) that doesn't exist in the registry, so strip it.
# @() guarantees an array (never $null), which is what Compare-Object needs.
$scmNames = @(
    Get-Service |
        Select-Object -ExpandProperty Name |
        ForEach-Object { $_ -replace "_[0-9a-f]{2,8}$" }
)

# --- List 2: service keys present in the registry ------------------------------------------------
# Enumerate the keys first, with -ErrorAction Stop so a failure tells us the real reason.
try {
    $allKeys = @(Get-ChildItem -LiteralPath $servicesKey -ErrorAction Stop)
}
catch {
    Write-Warning "Could not read $servicesKey : $($_.Exception.Message)"
    Write-Warning "Try running from an elevated PowerShell prompt."
    return
}

if ($allKeys.Count -eq 0) {
    Write-Warning "$servicesKey was readable but returned no subkeys. Cannot compare."
    return
}

# Keep only keys that have an ObjectName value (i.e. look like services); PSChildName is just the key's name.
# -LiteralPath stops characters like [ ] in a key name being treated as wildcards.
$regNames = @(
    $allKeys |
        Where-Object { Get-ItemProperty -LiteralPath $_.PSPath -Name ObjectName -ErrorAction Ignore } |
        ForEach-Object { $_.PSChildName }
)

if ($regNames.Count -eq 0) {
    Write-Warning "Read $($allKeys.Count) keys under $servicesKey but none had an ObjectName value. Cannot compare."
    return
}

# --- Compare: names only in the registry ('=>') are candidate hidden services ---------------------
# Wrapped in @() so .Count is reliable for 0, 1 or many results.
$hiddenServices = @(
    Compare-Object -ReferenceObject $scmNames -DifferenceObject $regNames -PassThru |
        Where-Object { $_.sideIndicator -eq "=>" }
)

# None found
if ($hiddenServices.Count -eq 0) {
    Write-Host "No hidden services found."
    return
}

# Hidden services found
Write-Host "Hidden services detected:"
$hiddenServices | ForEach-Object { Write-Host $_}

# Removes these services on a case by case basis
foreach ($service in $hiddenServices) {

    if($actionParam -eq '1', '2', 'A', 'S') {
        $action = Read-Host -Prompt "Action for service '$service' (1: Remove, 2: Keep, A: Remove ALL, S: Skip ALL)"
    }
    $action = $actionParam

    if ($action -eq "1") {
        Write-Host "Removing service: $service"
        Stop-Service -ServiceName $service
        sc.exe delete $service | Out-Null
        Write-Host "Service: $service successfully removed."
    } 
    elseif ($action -eq "2") {
        Write-Host "Found hidden service: $service"
    } 
    elseif ($action -eq "S") {
        Write-Host "Skipping all hidden services..."
        break
    } 
    elseif ($action -eq "A") {
        Write-Host "Removing all hidden services..."
        foreach ($srv in $hiddenServices) {
            Write-Host "Removing service: $srv"
            Stop-Service -Name $srv -Force -ErrorAction SilentlyContinue
            sc.exe delete $srv | Out-Null
            Write-Host "Service: $srv removed."
        }
        break
    } 
    else {
        Write-Host "Invalid Option. Skipping Service: $service"
    }
}