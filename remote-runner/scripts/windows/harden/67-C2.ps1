# 67-C2.ps1
# Author: Dylan Harvey
# Description: One-liner to check for C2 traffic

Get-NetTCPConnection -State Established | Where-Object { $_.RemoteAddress -notlike "127.0.0.1" -and $_.RemoteAddress -notlike "::1" } | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, @{Name="Process";Expression={(Get-Process -Id $_.OwningProcess).ProcessName}} | Format-Table -AutoSize
