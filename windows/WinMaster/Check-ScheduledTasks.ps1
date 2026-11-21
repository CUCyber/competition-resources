# Author BlueNitrobotX
# Find potentially malicious Scheduled Tasks (Ghost tasks)

Write-Host "`n====== Scanning Scheduled Tasks ======`n"

try {
    $taskArr = @(
        Get-ScheduledTask -ErrorAction Stop |
            Where-Object { $_.TaskPath -eq '\' } |
            ForEach-Object {
                $info = Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue
                [PSCustomObject]@{
                    TaskName    = $_.TaskName
                    State       = $_.State
                    RunAs       = $_.Principal.UserId
                    Action      = ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)".Trim() }) -join '; '
                }
            }
    )
    $taskCount = $taskArr.Count
}
catch {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Scheduled tasks in root path '\': $taskCount" -ForegroundColor Cyan

if ($taskCount -eq 0) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] No tasks found in the root path.`n" -ForegroundColor Yellow
    exit 2
}

Write-Host ""

# Output list of found items
foreach ($taskItem in $taskArr) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $($taskItem.TaskName)" -ForegroundColor Yellow
    Write-Host " - State:  $($taskItem.State)"
    Write-Host " - RunAs:  $($taskItem.RunAs)"
    Write-Host " - Action: $($taskItem.Action)"
    Write-Host ""

}

Write-Host ""

exit 0
