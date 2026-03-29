# core/constants.py

PORT_TIMEOUT = 2

PROTOCOLS = {
    "winrm": 5985,
    "ssh": 22,
    "winrms": 5986,
    "smb": 445
}

USERNAME_VAR = "REMOTE_USERNAME"
PASSWORD_VAR = "REMOTE_PASSWORD"

SH_PATH = "/bin/sh"
BASH_PATH = "/bin/bash"
CMD_PATH = "C:\\Windows\\System32\\cmd.exe"
PS_PATH = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
