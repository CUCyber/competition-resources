# 10-Remove-SSH-Keys.ps1
# Author: Dylan Harvey
# Description: Automated script to backup and remove ssh keys.

$LogFile = "C:\ProgramData\ssh_key_purge.log"
$BackupDir = "C:\ProgramData\ssh_backups"
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$TempStage = Join-Path $env:TEMP "ssh_backup_$Timestamp"
$BackupFile = Join-Path $BackupDir "keys_backup_$Timestamp.zip"

if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

$TargetFiles = @()

$AdminPath = "C:\ProgramData\ssh\administrators_authorized_keys"
if (Test-Path $AdminPath) { $TargetFiles += $AdminPath }

$UserProfiles = Get-ChildItem "C:\Users" -Directory

foreach ($Profile in $UserProfiles) {
    $RelativePaths = @(".ssh\authorized_keys", ".ssh\authorized_keys2")
    
    foreach ($RelPath in $RelativePaths) {
        $FullPath = Join-Path $Profile.FullName $RelPath
        if (Test-Path $FullPath) {
            Write-Host "Found key at $FullPath"
            $TargetFiles += $FullPath
        }
    }
}

if ($TargetFiles.Count -gt 0) {
    try {
        New-Item -ItemType Directory -Path $TempStage -Force | Out-Null

        foreach ($File in $TargetFiles) {
            $CleanPath = $File.Replace(":", "")
            $Destination = Join-Path $TempStage $CleanPath
            $DestinationDir = Split-Path $Destination -Parent
            
            if (-not (Test-Path $DestinationDir)) {
                New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
            }
            
            Copy-Item -Path $File -Destination $Destination
        }

        Compress-Archive -Path "$TempStage\*" -DestinationPath $BackupFile -Force
        
        foreach ($File in $TargetFiles) {
            Remove-Item -Path $File -Force
            $LogEntry = "$(Get-Date): Removed $File"
            Add-Content -Path $LogFile -Value $LogEntry
            Write-Host "Removed: $File"
        }
        
        Remove-Item -Path $TempStage -Recurse -Force
        
        Write-Host "SUCCESS: Keys backed up (with paths) to $BackupFile and removed."
    }
    catch {
        Write-Error "An error occurred: $_"
    }
}
else {
    Write-Host "No SSH keys found."
}
