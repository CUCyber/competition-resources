# Compare-Users.ps1
# Author: Dylan Harvey
# Compares the users and groups against provided list(s)

$allUsersFile = ".\all_users.csv"
$normalUsersFile = ".\normal_users.csv"
$adminUsersFile = ".\administrative_users.csv"

$allUsers = Get-Content $allUsersFile
$normalUsers = Get-Content $normalUsersFile
$adminUsers = Get-Content $adminUsersFile
$excludedUsers = @("krbtgt", "^seccdc", "blackteam_adm") # CHANGE AS NEEDED, SUPPORTS REGEX

$role = (Get-WmiObject Win32_ComputerSystem).DomainRole
if ($role -ge 4) {
    # System Users (ALL)
    $systemUsers = Get-LocalUser | Select-Object -ExpandProperty Name
    $systemUsers = $systemUsers | ForEach-Object {
        if ($_ -match ($excludedUsers -join "|")) { Write-Host "Skipping excluded user: $_" -ForegroundColor Magenta } 
        else { $_ }
    }

    $missingUsers = $allUsers | Where-Object { $_ -notin $systemUsers }
    $extraUsers = $systemUsers | Where-Object { $_ -notin $allUsers }

    Write-Host "< Users in '${allUsersFile}' but not on system:" -ForegroundColor Cyan
    $missingUsers | ForEach-Object { Write-Host $_ }

    Write-Host "> Users on system but not in '${allUsersFile}':" -ForegroundColor Cyan
    $extraUsers | ForEach-Object { Write-Host $_ }

    # Normal Users (Users)
    $usersGroupMembers = Get-LocalGroupMember -Group "Users" | Select-Object -ExpandProperty Name | ForEach-Object { ($_ -split '\\')[-1] }
    $usersGroupMembers = $usersGroupMembers | Where-Object { $_ -notmatch ($excludedUsers -join "|") }

    $usersGroupMissing = $normalUsers | Where-Object { $_ -notin $usersGroupMembers}
    $usersGroupExtra = $usersGroupMembers | Where-Object { $_ -notin $normalUsers }

    Write-Host "< Users in '${normalUsersFile}' but not in 'Users' group:" -ForegroundColor Yellow
    $usersGroupMissing | ForEach-Object { Write-Host $_ }

    Write-Host "> Users in 'Users' group but not in '${normalUsersFile}':" -ForegroundColor Yellow
    $usersGroupExtra | ForEach-Object { Write-Host $_ }

    # Administrative Users (Administrators)
    $adminGroupMembers = Get-LocalGroupMember -Group "Administrators" | Select-Object -ExpandProperty Name | ForEach-Object { ($_ -split '\\')[-1] }
    $adminGroupMembers = $adminGroupMembers | Where-Object { $_ -notmatch ($excludedUsers -join "|") }

    $adminGroupMissing = $adminUsers | Where-Object { $_ -notin $adminGroupMembers}
    $adminGroupExtra = $adminGroupMembers | Where-Object { $_ -notin $adminUsers }

    Write-Host "< Users in '${adminUsersFile}' but not in 'Administrators' group:" -ForegroundColor Red
    $adminGroupMissing | ForEach-Object { Write-Host $_ }

    Write-Host "> Users in 'Administrators' group but not in '${adminUsersFile}':" -ForegroundColor Red
    $adminGroupExtra | ForEach-Object { Write-Host $_ }
} elseif ($role -lt 4) {
    # System Users (ALL)
    $systemUsers = Get-ADUser -Filter * | Select-Object -ExpandProperty SamAccountName
    $systemUsers = $systemUsers | ForEach-Object {
        if ($_ -match ($excludedUsers -join "|")) { Write-Host "Skipping excluded user: $_" -ForegroundColor Magenta } 
        else { $_ }
    }

    $missingUsers = $allUsers | Where-Object { $_ -notin $systemUsers }
    $extraUsers = $systemUsers | Where-Object { $_ -notin $allUsers }

    Write-Host "< Users in '${allUsersFile}' but not on system:" -ForegroundColor Cyan
    $missingUsers | ForEach-Object { Write-Host $_ }

    Write-Host "> Users on system but not in '${allUsersFile}':" -ForegroundColor Cyan
    $extraUsers | ForEach-Object { Write-Host $_ }

    # Normal Users (Users)
    $usersGroupMembers = Get-ADGroupMember -Identity "Domain Users" | Select-Object -ExpandProperty SamAccountName | ForEach-Object { ($_ -split '\\')[-1] }
    $usersGroupMembers = $usersGroupMembers | Where-Object { $_ -notmatch ($excludedUsers -join "|") }

    $usersGroupMissing = $normalUsers | Where-Object { $_ -notin $usersGroupMembers}
    $usersGroupExtra = $usersGroupMembers | Where-Object { $_ -notin $normalUsers }

    Write-Host "< Users in '${normalUsersFile}' but not in 'Domain Users' group:" -ForegroundColor Yellow
    $usersGroupMissing | ForEach-Object { Write-Host $_ }

    Write-Host "> Users in 'Domain Users' group but not in '${normalUsersFile}':" -ForegroundColor Yellow
    $usersGroupExtra | ForEach-Object { Write-Host $_ }

    #  Administrative Users (Administrators)
    $adminGroupMembers = Get-ADGroupMember -Identity "Domain Admins" | Select-Object -ExpandProperty SamAccountName | ForEach-Object { ($_ -split '\\')[-1] }
    $adminGroupMembers = $adminGroupMembers | Where-Object { $_ -notmatch ($excludedUsers -join "|") }

    $adminGroupMissing = $adminUsers | Where-Object { $_ -notin $adminGroupMembers}
    $adminGroupExtra = $adminGroupMembers | Where-Object { $_ -notin $adminUsers }

    Write-Host "< Users in '${adminUsersFile}' but not in 'Domain Admins' group:" -ForegroundColor Red
    $adminGroupMissing | ForEach-Object { Write-Host $_ }

    Write-Host "> Users in 'Domain Admins' group but not in '${adminUsersFile}':" -ForegroundColor Red
    $adminGroupExtra | ForEach-Object { Write-Host $_ }
} else { # I've never seen this happen but just in case
    Write-Host "Error determining machine type." -ForegroundColor Red
    exit 2 # Manually envoked exit
}
