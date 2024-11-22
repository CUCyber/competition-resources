# Author: Dylan Harvey
# Script for nuking task scheduler off the map. (WIP)

#Requires -RunAsAdministrator

# Remove all scheduled tasks
Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks" -Recurse -Force

# Restart the Task Scheduler service
Restart-Service -Name Schedule

# Kill task processes (Restart Should handle this; precautionary)
Get-Process -Name taskhostw | Stop-Process -Force

