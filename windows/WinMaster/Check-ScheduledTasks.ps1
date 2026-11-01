# Author BlueNitrobotX
# Find potentially malicious Scheduled Tasks (Ghost tasks)

try {
    $taskArr = @(Get-ScheduledTask | Where-Object {$_.TaskPath -eq '\'} | Select-Object TaskName, TaskPath, State)
    $taskCount = $taskArr.Length
    Write-Host $taskArr
}
catch {
    return 1
}

if($taskCount -eq 0) {
    return 2
} else {
    return 0
}