# Remove-SSH-Keys.ps1
# Author: Dylan Harvey
# Removes all ssh keys on the system (and notifies when/where they are removed)

$excludedUsers = @("krbtgt", "ansible", "blackteam_adm", "^seccdc") # CHANGE
$groupPath = "C:\ProgramData\ssh\administrators_authorized_keys"
$sshPaths = @(Get-ChildItem -Path "C:\Users\" -Directory -Recurse -Force -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq ".ssh"} | Select-Object FullName)
$sshPaths | ForEach-Object {
    if (Test-Path "$($_.FullName)\authorized_keys") {
        Write-Host "Found key file at '$($_.FullName)\authorized_keys'." -ForegroundColor Cyan
        try {
            Remove-Item "$($_.FullName)\authorized_keys" -Force
            Write-Host "Removed key file at '$($_.FullName)\authorized_keys'." -ForegroundColor Green
        } catch {
            Write-Host "Failed to remove key file at '$($_.FullName)\authorized_keys'." -ForegroundColor Red
        }
    }
}
if (Test-Path $groupPath) {
    Write-Host "Found group key file at '$groupPath'" -ForegroundColor Cyan
    try {
        Remove-Item "$groupPath" -Force
        Write-Host "Removed group key file at '$groupPath'" -ForegroundColor Green
    } catch {
        Write-Host "Failed to remove group key file at '$($_.FullName)\authorized_keys'." -ForegroundColor Red
    }   
}
