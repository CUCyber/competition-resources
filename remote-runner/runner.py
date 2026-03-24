#!/usr/bin/env python3
# runner.py
# Author: Dylan Harvey
# Parent automation script for executing scripts on remote machines

import argparse
import logging
import sys

from core.logger_config import setup_logging
from core.utils import validate_ip, get_credentials, detect_best_method, get_ssh_key
from core import runners

def main():
    parser = argparse.ArgumentParser(description="Remote Runner")
    parser.add_argument("-d", "--debug", action="store_true", help="Enable debug output")
    parser.add_argument("-l", "--log", metavar="LOGFILE", default="automation.log", help="Logfile path")

    parser.add_argument("ip", help="Target IP Address")

    parser.add_argument("-t", "--target", nargs="?", default="1", help="Scripts target to execute (directory in scripts/) (default: 1)")
    parser.add_argument("-c", "--connmethod", nargs="?", default="detect", choices=["ssh", "winrm", "smb", "detect"], help="Connection protocol (default: detect)")
    parser.add_argument("-k", "--key", nargs="?", default="keys", help="SSH Private Key or directory to use (default: keys)")

    args = parser.parse_args()
    setup_logging(args.debug, args.log)

    cmd_line = " ".join(sys.argv)
    logging.debug("New execution: <python> %s", cmd_line)

    if not validate_ip(args.ip):
        logging.error("Invalid IP address provided: %s", args.ip)
        sys.exit(1)

    args.key = get_ssh_key(args.key)

    if args.connmethod == "detect":
        args.connmethod = detect_best_method(args.ip)

    username, password = get_credentials(args)

    dispatch = {
        "ssh": runners.run_ssh,
        "winrm": runners.run_winrm,
        "winrms": runners.run_winrm,
        "smb": runners.run_smb,
    }

    logging.success("Setup complete. Starting target %s via %s", args.target, args.connmethod)

    if args.connmethod in dispatch:
        try:
            dispatch[args.connmethod](args, username, password)
        except Exception as e:
            logging.error("Execution failed: %s", e)
            sys.exit(1)

if __name__ == "__main__":
    main()
