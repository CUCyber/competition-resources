# Author: Dylan Harvey
# One-Liners for resetting passwords.

# Modern Method (Local)
Set-LocalUser -Name $username -Password (ConvertTo-SecureString $password -AsPlainText -Force)
# Modern Method (Domain)
Set-ADAccountPassword -Identity $username -NewPassword (ConvertTo-SecureString $password -AsPlainText -Force)

# Traditional Method
net user $username $password
