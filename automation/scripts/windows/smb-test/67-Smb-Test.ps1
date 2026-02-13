$path = "C:\smb_command.log"
$date = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$user = whoami
$note = "[$date] Log updated by $user"
$note | Out-File -FilePath $path -Append
