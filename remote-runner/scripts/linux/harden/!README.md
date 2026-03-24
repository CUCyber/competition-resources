# Target `harden`:
DO NOT RUN THIS TARGET BLINDLY!
ENSURE NO SCORED USERS AND MODIFY BOTH SCRIPTS ACCORDINGLY FOR YOUR OWN USER(S)
## `00-reset-perms.sh`
Resets `/etc/sudoers/`, make sure to update with what you need to avoid getting locked out!
## `99-lock-users.sh`
Locks all users, make sure to exclude yourself!

NOTE: Be careful using these they have not been thoroughly tested and may or may not brick your machine
