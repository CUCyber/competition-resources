# Author: Dylan Harvey
# lists all the curent users, state, etc. in a nice format. (and groups)

# Function to format user details
function Get-UserDetails {
    param ([Microsoft.PowerShell.Commands.LocalUser]$user)

    $details = @{}
    $details["Name"] = $user.Name
    $details["Enabled"] = $user.Enabled
    $details["Last Logon"] = $user.LastLogon
    $details["Password Changeable"] = $user.PasswordChangeable
    $details["Password Required"] = $user.PasswordRequired
    $details["Account Locked"] = $user.AccountLockedOut
    return $details
}

# List all users with details
Write-Host "Detailed User Information:"
Get-LocalUser | ForEach-Object {
    $userDetails = Get-UserDetails $_
    Write-Host "---------------------------"
    Write-Host "Name: $($userDetails['Name'])"
    Write-Host "Enabled: $($userDetails['Enabled'])"
    Write-Host "Last Logon: $($userDetails['Last Logon'])"
    Write-Host "Password Changeable: $($userDetails['Password Changeable'])"
    Write-Host "Password Required: $($userDetails['Password Required'])"
    Write-Host "Account Locked: $($userDetails['Account Locked'])"
}

# List all groups with members
Write-Host "`nGroups and Members:"
Get-LocalGroup | ForEach-Object {
    Write-Host "---------------------------"
    Write-Host "Group: $($_.Name)"
    $members = Get-LocalGroupMember -Group $_.Name
    if ($members) {
        $members | ForEach-Object { Write-Host "  Member: $($_.Name)" }
    } else {
        Write-Host "  No members in this group."
    }
}

pause