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

foreach ($file in $files) {
    Write-Host "Processing $file"

    takeown /F $file | Out-Null
    icacls $file /grant "${identity}:(F)" | Out-Null

    try {
        Remove-Item $file -Force
        Write-Host "Deleted: $file"
    }
    catch {
        Write-Warning "Failed to delete $file : $_"
    }
}