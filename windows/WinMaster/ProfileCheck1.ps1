# Author BlueNitrobotX
# PowerShell profile check
   

$profiles = [ordered]@{
    AllUsersAllHosts       = $PROFILE.AllUsersAllHosts
    AllUsersCurrentHost    = $PROFILE.AllUsersCurrentHost
    CurrentUserAllHosts    = $PROFILE.CurrentUserAllHosts
    CurrentUserCurrentHost = $PROFILE.CurrentUserCurrentHost
}

Write-Host "`n====== Check PowerShell Profiles ======`n"

$status = 2
foreach ($entry in $profiles.GetEnumerator()) {
    $path = $entry.Value
    try {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf -ErrorAction Stop)) { continue }
        $evidence = New-Item -Path '.\WinMaster_Evidence' -ItemType Directory -Force -ErrorAction Stop
        Copy-Item -LiteralPath $path -Destination (Join-Path $evidence.FullName "$($entry.Key)-$(Split-Path $path -Leaf)") -ErrorAction Stop
        $disabledName = "$(Split-Path $path -Leaf).disabled"
        if (Test-Path -LiteralPath "$path.disabled") { $disabledName += ".$([guid]::NewGuid())" }
        Rename-Item -LiteralPath $path -NewName $disabledName -ErrorAction Stop
        Write-Host -ForegroundColor Green "Disabled: $path"
        if ($status -eq 2) { $status = 0 }
    }
    catch {
        Write-Error "Failed to back up or disable '$path': $_"
        $status = 1
    }
}
if ($status -eq 2) { Write-Host "No PowerShell profiles detected." }
exit $status