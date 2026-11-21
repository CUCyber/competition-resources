# Author BlueNitrobotX

$files = @(
    "C:\Windows\System32\sethc.exe",
    "C:\Windows\System32\Utilman.exe",
    "C:\Windows\System32\osk.exe",
    "C:\Windows\System32\Narrator.exe",
    "C:\Windows\System32\Magnify.exe",
    "C:\Windows\System32\DisplaySwitch.exe"
)

$identity = "$($env:USERDOMAIN)\$($env:USERNAME)"

Write-Host "`n====== Accessibility Binary Removal ======`n"

foreach ($file in $files) {
    
    # Modify file perms to avoid random windows goofy
    takeown /F $file 2>&1 | Out-Null
    icacls $file /grant "${identity}:(F)" 2>&1 | Out-Null

    try {
        Remove-Item -LiteralPath $file -Force -ErrorAction Stop
        Write-Host -ForegroundColor Green "[$(Get-Date -Format "HH:mm:ss")] Deleted: $file"
    }
    catch {
        Write-Host -ForegroundColor Red "[$(Get-Date -Format "HH:mm:ss")] Failed to delete $file : $_"
    }
}

Write-Host ""