# /automation
This directory contains all the code and tools required to run the system-agnostic automations/initial 30-min plan runner.
## /linux
This directory contains all the individual scripts to be run and parsed by the parent automation script for linux machines.

Will be further subdivided into "targets" (subdirectories)
## /windows
This directory contains all the individual scripts to be run and parsed by the parent automation script for windows machines.

Will be further subdivided into "targets" (subdirectories)
## Guide
This is a brief but hopefully useful guide on how to use this tool:
### Setup
First, setup a venv:
```sh
python3 -m venv .venv
```
Then, activate the venv:
```sh
# Linux:
source ./.venv/bin/activate
# Windows:
.\.venv\Scripts\activate
```
Lastly, install required packages:
```sh
pip install -r requirements.txt
```
### Usage
```
usage: automation.py [-h] [-d] [-l LOGFILE] [-t [TARGET]] [-c [{ssh,winrm,smb,detect}]] ip

Automation Runner

positional arguments:
  ip                    Target IP Address

options:
  -h, --help            show this help message and exit
  -d, --debug           Enable debug output
  -l, --log LOGFILE     Logfile path
  -t, --target [TARGET]
                        Scripts target to execute (directory in scripts/) (default: first)
  -c, --connmethod [{ssh,winrm,smb,detect}]
                        Connection protocol (default: detect)
```

WIP
