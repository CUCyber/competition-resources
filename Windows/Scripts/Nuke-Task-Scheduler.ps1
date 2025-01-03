# Author: Dylan Harvey
# Script for removing task scheduler in its entirety.

# NOTE: May require PSExec even as Administrator due to registry access
#Requires -RunAsAdministrator

# Remove all scheduled tasks
Write-Host "Removing scheduled tasks..." -ForegroundColor Yellow
Remove-Item -Path "$RegPath\Tasks" -Recurse -Force # -ErrorAction SilentlyContinue

# Restart the Task Scheduler service
Write-Host "Restarting Task Scheduler service..." -ForegroundColor Yellow
Stop-Service -Name Schedule -Force
Start-Service -Name Schedule

# Kill task processes (Restart-Service Should handle this; precautionary)
Write-Host "Killing task-related processes..." -ForegroundColor Yellow
Get-Process -Name taskhostw | Stop-Process -Force

Pause