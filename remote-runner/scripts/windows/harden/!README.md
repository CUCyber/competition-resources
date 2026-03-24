# Target `harden`:
Dom't run this target blindly! Check scripts and make sure you won't lock yourself out!!
## `50-Nuke-Firewall.ps1`
Double check allowed IPs! This is a very destructive and strict script. You will lock yourself (and everyone) out if you're not careful!
## `51-Domain-Firewall.ps1`
Double check domain IPs! This creates rules to prevent breaking AD functionality.
## `67-Check-C2.ps1`
A simple one-liner follow up to attempt to find possible C2/RevShell traffic already established or attempting to go outbound
