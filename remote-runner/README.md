# remote-runner
A tool I created to execute scripts on remote machines. Similar to ansible but designed for a competition (CCDC) like environment.

## /linux/
This directory contains all the individual scripts to be run and parsed by the parent automation script for linux machines.

Will be further subdivided into "targets" (subdirectories)
## /windows/
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
# WARNING/NOTE for WINDOWS: Defender is NOT happy with the impacket install due to examples in the pip package. Disable temporarily or add exception.
```
### Usage
```
usage: runner.py [-h] [-d] [-l LOGFILE] [-t [TARGET]] [-c [{ssh,winrm,smb,detect}]] [-k [KEY]] ip

Remote Runner

positional arguments:
  ip                    Target IP Address

options:
  -h, --help            show this help message and exit
  -d, --debug           Enable debug output
  -l, --log LOGFILE     Logfile path
  -t, --target [TARGET]
                        Scripts target to execute (directory in scripts/) (default: 1)
  -c, --connmethod [{ssh,winrm,smb,detect}]
                        Connection protocol (default: detect)
  -k, --key [KEY]       SSH Private Key or directory to use (default: keys)
```

WIP
