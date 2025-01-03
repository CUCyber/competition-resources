# Author: Dylan Harvey
# A simple version of the reset passwords script that randomly resets all users except a specified list, rather than using a CSV
# NOTE: Ensure to reset Administrator/your account again on your own to avoid lockouts!

function New-Password {
    param (
        [ValidateRange(12, 128)]
        [int]$Length = 15
    )

    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()-_=+[]{}|;:,.<>?'

    1..$Length | ForEach-Object { $password += $chars[$(Get-Random -Maximum $chars.Length)] }
    return $password
}

$excludedUsers = @("krbtgt", "scoring", "gold-team") # UPDATE AS NEEDED, exclude critial windows users and/or scoring accounts etc.
$users = Get-LocalUser | Where-Object { $excludedUsers -notcontains $_.Name }

foreach ($user in $users) {
    try {
        net user $($user.Name) $newPassword
        Write-Output "Password for user $($user.Name) has been reset."
    } catch {
        Write-Output "Failed to reset password for user $($user.Name): $($_.Exception.Message)"
    }
}

Pause