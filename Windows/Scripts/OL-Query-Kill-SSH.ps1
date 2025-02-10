# Author: Dylan Harvey
# One-Liners for querying and killing SSH sessions.

# All logged on users
Get-CimInstance -ClassName Win32_LogonSession | Get-CimAssociatedInstance -Association Win32_LoggedOnUser

# Only SSH Users
Get-CimInstance -ClassName Win32_Process -Filter "Name = 'sshd.exe'" | Get-CimAssociatedInstance -Association Win32_SessionProcess | Get-CimAssociatedInstance -Association Win32_LoggedOnUser | Where-Object {$_.Name -ne 'SYSTEM'}

# Owners of sshd processes
Get-CimInstance Win32_Process -Filter "Name = 'sshd.exe'" | Invoke-CimMethod -MethodName GetOwner | Where-Object User -ne System

