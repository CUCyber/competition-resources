# Author BlueNitrobotX
# PowerShell profile check
   

$profiles = @(
    $PROFILE.AllUsersAllHosts
    $PROFILE.AllUsersCurrentHost
    $PROFILE.CurrentUserAllHosts
    $PROFILE.CurrentUserCurrentHost
)

Write-Host "`n====== Check PowerShell Profiles ======`n"

foreach ($profile in $profiles) {
    try {
        # If profiles are found, copy them to the evidence directory and report them
        if(Test-Path $profile) {
            Copy-Item -Path $profile -Destination ".\Evidence\"
            Write-Host -ForegroundColor Cyan "[$(Get-Date -Format 'HH:mm:ss')] Profiles found and copied to .\Evidence\`n"

            # Try to disable all found profiles
            try {
                $PROFILE.PSObject.Properties |
                    Where-Object { $_.Name -match 'AllUsers|CurrentUser' } |
                    ForEach-Object {
                        $path = $_.Value
                        if(Test-Path $path) {
                            Rename-Item -Path $path -NewName "$(Split-Path $path -Leaf).disabled"
                            Write-Host -ForegroundColor Green "[$(Get-Date -Format 'HH:mm:ss')] Disabled: $path"
                        }
                    }
            }
            catch {
                Write-Host -ForegroundColor Red "[$(Get-Date -Format 'HH:mm:ss')] Failed to disable: $path`n"
                exit 1
            }
           

            exit 0
        } else {
            Write-Host -ForegroundColor Green "[$(Get-Date -Format 'HH:mm:ss')] No PowerShell profiles detected.`n"
            exit 2
        }
    }
    catch {
        exit 1
    }
}