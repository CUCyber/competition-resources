# Author BlueNitrobotX
# PowerShell profile check
   

$profiles = @(
    $PROFILE.AllUsersAllHosts
    $PROFILE.AllUsersCurrentHost
    $PROFILE.CurrentUserAllHosts
    $PROFILE.CurrentUserCurrentHost
)

foreach ($profile in $profiles) {
    try {
        if(Test-Path $profile) {
            Copy-Item -Path $profile -Destination ".\Evidence\"
            Write-Host "Detected profiles copied to .\Evidence\"
            exit 0
        } else {
            Write-Host -ForegroundColor Green "No PowerShell profiles detected."
            exit 2
        }
    }
    catch {
        exit 1
    }
}