# Author: Dylan Harvey
# One-Liners for resetting passwords.

# Modern Method (local users only)
Set-LocalUser -Name "UsernameHere" -Password (ConvertTo-SecureString "NewPasswordHere" -AsPlainText -Force)

# Traditional Method
net user $user_name $password

