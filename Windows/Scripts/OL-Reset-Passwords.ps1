# Author: Dylan Harvey
# One-Liners for resetting passwords. (WIP)

Set-LocalUser -Name "UsernameHere" -Password (ConvertTo-SecureString "NewPasswordHere" -AsPlainText -Force)

net user $user_name $password

