# core/utils.py

import socket
import ipaddress
import logging
import os
from .constants import PROTOCOLS, USERNAME_VAR, PASSWORD_VAR, PORT_TIMEOUT

def load_credentials(path=".env") -> dict:
    """
    Loads username and password.
    Priority: OS Environment Vars > .env file > None
    """
    logging.debug("Loading Credentials...")
    creds = {
        USERNAME_VAR: os.environ.get(USERNAME_VAR),
        PASSWORD_VAR: os.environ.get(PASSWORD_VAR)
    }

    if creds[USERNAME_VAR] and creds[PASSWORD_VAR]:
        logging.debug("Creds found in environment variables: %s", creds)
        return creds

    if os.path.exists(path):
        with open(path) as dotenv:
            for line in dotenv:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue

                key, val = line.split("=", 1)
                key = key.strip()
                val = val.strip().strip('"').strip("'")
                
                if key in [USERNAME_VAR, PASSWORD_VAR]:
                    if not creds.get(key) and val != "":
                        creds[key] = val
        if creds[USERNAME_VAR] and creds[PASSWORD_VAR]:
            logging.debug("Creds found in .env file: %s", creds)
    
    return creds

def get_credentials(args) -> (str, str):
    logging.debug("Getting Credentials...")
    creds = load_credentials()
    username = creds[USERNAME_VAR]
    password = creds[PASSWORD_VAR]

    if not username:
        username = input(f"Enter username for {args.ip}: ")
    logging.info("Using username: %s", username)
    if not password:
        password = input(f"Enter password for {username}: ")
    logging.info("Using password: %s", password)

    return (username, password)

def check_port(ip: str, port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(PORT_TIMEOUT)
        try:
            s.connect((ip, port))
            logging.debug("Port %d is OPEN", port)
            return True
        except socket.timeout:
            logging.debug("Port %d FAILED: Timeout", port)
        except ConnectionRefusedError:
            logging.debug("Port %d FAILED: Connection Refused", port)
        except Exception as e:
            logging.debug("Port %d FAILED: Unexpected error: %s", port, e)

        return False

def validate_ip(ip_str: str) -> bool:
    try:
        ipaddress.ip_address(ip_str)
        return True
    except ValueError:
        return False

def detect_best_method(ip: str) -> str:
    logging.info("Detecting best connection method for %s...", ip)

    for proto, port in PROTOCOLS.items():
        if check_port(ip, port):
            if proto == "ssh":
                banner = get_ssh_banner(ip)
                os_hint = identify_os_by_banner(banner)
                logging.success("Found %s (Banner suggests: %s)", proto, os_hint)
            else:
                logging.success("Found %s listening on port %d", proto, port)

            return proto

    logging.warning("No services detected. Defaulting to ssh.")
    return "ssh"

def get_ssh_banner(ip: str, port: int = 22, timeout: int = 2) -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect((ip, port))
            banner = s.recv(1024).decode().strip()
            return banner
    except Exception as e:
        logging.debug("Failed to grab SSH banner: {e}")
        return ""

def identify_os_by_banner(banner: str) -> str:
    banner = banner.lower()
    if "windows" in banner:
        return "windows"
    if any(tag in banner for tag in ["ubuntu", "debian", "centos", "redhat", "ssh-2.0-openssh"]):
        return "linux"
    return "unknown"

def get_ssh_key(key_input: str) -> str:
    if not key_input:
        return None

    if os.path.isfile(key_input):
        logging.debug("Using specified SSH key file: %s", key_input)
        return key_input

    if os.path.isdir(key_input):
        logging.debug("Scanning directory %s for keys...", key_input)
        for filename in os.listdir(key_input):
            if not filename.endswith(".pub") and not filename.startswith("."):
                path = os.path.join(key_input, filename)
                logging.debug("Found ssh key in: %s", path)
                return path

    logging.warning("No valid SSH key found at: %s", key_input)
    return None
