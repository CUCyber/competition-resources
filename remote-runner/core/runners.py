# core/runners.py

import base64
import logging
import os
import re
import winrm
from .constants import SH_PATH, CMD_PATH, PS_PATH
from fabric import Connection, Config
from paramiko.ssh_exception import AuthenticationException
from impacket.smbconnection import SMBConnection
from impacket.dcerpc.v5 import transport, scmr

def run_ssh(args, username: str, password: str) -> None:
    ip = args.ip
    logging.info("Attempting SSH connection to %s...", ip)

    connect_kwargs = {
        "password": password,
        "look_for_keys": False,  # no ~/.ssh/ fallback
        "allow_agent": False,
        "timeout": 10,
        "auth_timeout": 5,
        "banner_timeout": 5
    }

    if args.key:
        logging.info("Using SSH Key: %s", args.key)
        connect_kwargs["key_filename"] = args.key

    config = Config(overrides={
        "connect_timeout": 10,
        "load_ssh_configs": False
        })

    try:
        with Connection(
            host=ip,
            user=username,
            connect_kwargs=connect_kwargs,
            config=config
        ) as c:
            logging.debug("Connection established. Identifying environment...")

            # Check credentials OK
            try:
                whoami = c.run("whoami", hide=True).stdout.strip()
                logging.success("Logged in as %s", whoami)
            except AuthenticationException:
                logging.error("Authentication failed for user '%s'. Check your key/username/password.", username)
                return
            except Exception:
                pass

            is_windows, is_linux = False, False
            win_ver_str, lin_ver_str = "Unknown", "Unknown"

            # OS Detection
            try:
                res_win = c.run(f"{CMD_PATH} /c echo %OS%", hide=True, warn=True, timeout=5)
                if res_win.ok and "Windows" in res_win.stdout:
                    is_windows, win_ver_str = True, res_win.stdout.strip()

                res_win = c.run(f"{CMD_PATH} /c ver", hide=True, warn=True, timeout=5)
                if res_win.ok and "Windows" in res_win.stdout:
                    is_windows, win_ver_str = True, res_win.stdout.strip()
            except Exception:
                pass

            try:
                res_lin = c.run("[ -d / ] && echo 'unix'", hide=True, timeout=5)
                if res_lin.ok and "unix" in res_lin.stdout:
                    is_linux, lin_ver_str = True, res_lin.stdout.strip()

                res_lin = c.run("uname -a", hide=True, warn=True, timeout=5)
                if res_lin.ok:
                    is_linux, lin_ver_str = True, res_lin.stdout.strip()
            except Exception:
                pass

            # OS Logic
            if is_windows and not is_linux:
                logging.info("Remote system confirmed as Windows; Version: %s", win_ver_str)
                execute_windows_ssh(c, args, password)
            elif is_linux and not is_windows:
                logging.info("Remote system confirmed as Linux; Version: %s", lin_ver_str)
                execute_linux_ssh(c, args, password)
            else:
                msg = "Franken-OS" if is_windows and is_linux else "Indeterminate OS (no response or failed auth)"
                logging.warning(f"{msg}! Windows: {win_ver_str} | Linux: {lin_ver_str}")
                choice = input("Select OS to target [linux/windows] (default linux): ").lower().strip()
                is_windows = (choice == "windows")
                is_linux = not is_windows
                execute_windows_ssh(c, args, password) if is_windows else execute_linux_ssh(c, args, password)

    except Exception as e:
        logging.error("SSH Execution failed: %s", e)
        raise e

def execute_linux_ssh(connection, args, password: str) -> None:
    local_target_dir = os.path.join("scripts", "linux", args.target)
    if not os.path.exists(local_target_dir):
        logging.error("Local target directory not found: %s", local_target_dir)
        return

    for filename in sorted(os.listdir(local_target_dir)):
        local_path = os.path.join(local_target_dir, filename)

        if filename.startswith("."):
            continue

        with open(local_path, 'r') as f:
            script_content = f.read()

        exec_res = None

        if filename.endswith(".sh"):
            logging.info("Executing %s via sh...", filename)
            escaped_content = script_content.replace("'", "'\\''")
            cmd = f"printf '%s\\n' '{password}' | /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /usr/bin/sudo -S {SH_PATH} -c '{escaped_content}'"
            exec_res = connection.run(cmd, hide=True, warn=True)

        if exec_res is not None:
            if exec_res.ok:
                logging.success("Script %s Output:\n%s", filename, exec_res.stdout.strip())
            else:
                logging.error("Script %s failed (Code %s)", filename, exec_res.exited)
                if exec_res.stderr:
                    logging.error("STDERR: %s", exec_res.stderr.strip())

            logging.debug("Result stdout: %s", exec_res.stdout.strip())
            logging.debug("Result stderr: %s", exec_res.stderr.strip())

def execute_windows_ssh(connection, args, password: str) -> None:
    local_target_dir = os.path.join("scripts", "windows", args.target)
    if not os.path.exists(local_target_dir):
        logging.error("Local target directory not found: %s", local_target_dir)
        return

    for filename in sorted(os.listdir(local_target_dir)):
        local_path = os.path.join(local_target_dir, filename)

        if filename.startswith("."):
            continue

        with open(local_path, 'r') as f:
            script_content = f.read()

        exec_res = None

        if filename.endswith(".ps1"):
            logging.info("Executing %s script via powershell...", filename)
            encoded_script = base64.b64encode(script_content.encode('utf-16-le')).decode('ascii')
            cmd = f"{PS_PATH} -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {encoded_script}"
            exec_res = connection.run(cmd, hide=True, warn=True)

        if exec_res is not None:
            if exec_res.ok:
                logging.success("Script %s Output:\n%s", filename, exec_res.stdout.strip())
            else:
                logging.error("Script %s failed (Code %s)", filename, exec_res.exited)
                if exec_res.stderr:
                    logging.error("STDERR: %s", exec_res.stderr.strip())

            logging.debug("Result stdout: %s", exec_res.stdout.strip())
            logging.debug("Result stderr: %s", exec_res.stderr.strip())


def run_winrm(args, username: str, password: str) -> None:
    ip = args.ip
    target = args.target
    logging.info("Attempting WinRM connection to %s...", ip)
    attempts = [  # Doing HTTP first since more likely to be up
        (5985, 'ntlm', 'http'),
        (5985, 'basic', 'http'),
        (5986, 'ntlm', 'https'),
        (5986, 'basic', 'https'),
    ]

    session = None
    active_config = None

    for port, auth_type, scheme in attempts:
        endpoint = f"{scheme}://{ip}:{port}/wsman"
        logging.debug("Trying WinRM: %s auth via %s", auth_type, endpoint)

        try:
            s = winrm.Session(
                endpoint,
                auth=(username, password),
                transport=auth_type,
                server_cert_validation="ignore",
                read_timeout_sec=10,
                operation_timeout_sec=5
            )

            whoami = s.run_cmd("whoami")
            if whoami.status_code == 0:
                logging.success("Logged in as %s", whoami.std_out.decode().strip())
                logging.success("Connected via %s (%s)", endpoint, auth_type)
                session = s
                active_config = f"{scheme}/{auth_type}"
                break
        except Exception as e:
            logging.debug("Failed %s/%s: %s", scheme, auth_type, str(e))
    
    if not session:
        logging.error("All WinRM connection attempts failed for %s", ip)
        return

    try:
        res_ver_cmd = session.run_cmd("ver")
        res_ver_ps = session.run_cmd(f"{PS_PATH} -NoProfile -NonInteractive -ExecutionPolicy Bypass '(Get-CimInstance Win32_OperatingSystem).Caption'")
        if res_ver_ps.status_code == 0:
            logging.info("Windows Version: %s", res_ver_ps.std_out.decode().strip())
            if res_ver_cmd.status_code == 0:
                logging.info("Ver via cmd: %s", res_ver_cmd.std_out.decode().strip())

        local_target_dir = os.path.join("scripts", "windows", target)
        if not os.path.exists(local_target_dir):
            logging.error("Local target directory not found: %s", local_target_dir)
            return

        for filename in sorted(os.listdir(local_target_dir)):
            if not filename.startswith(".") and filename.endswith(".ps1"):
                local_path = os.path.join(local_target_dir, filename)
                logging.info("Executing %s via WinRM...", filename)

                with open(local_path, 'r') as f:
                    script_content = f.read()

                encoded_script = base64.b64encode(script_content.encode('utf-16-le')).decode('ascii')
                result = session.run_cmd(f"{PS_PATH} -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {encoded_script}")

                if result.status_code == 0:
                    logging.success("Script %s Output:\n%s", filename, result.std_out.decode().strip())
                else:
                    error_output = result.std_err.decode().strip()
                    logging.error("Script %s Output:\n%s", filename, clean_clixml(error_output))
                
                logging.debug("Result stdout: %s", result.std_out.decode().strip())
                logging.debug("Result stderr: %s", result.std_err.decode().strip())

    except Exception as e:
        logging.error("WinRM Execution failed: %s", e)

def run_smb(args, username: str, password: str) -> None:
    ip = args.ip
    target = args.target
    logging.info("Attempting SMB connection to %s...", ip)

    local_target_dir = os.path.join("scripts", "windows", target)
    if not os.path.exists(local_target_dir):
        logging.error("Local target directory not found: %s", local_target_dir)
        return

    try:
        smb = SMBConnection(ip, ip)
        smb.login(username, password)

        os_info = smb.getServerOS()
        logging.success("SMB Login Successful. OS: %s", os_info)

        remote_share = "ADMIN$"

        for filename in sorted(os.listdir(local_target_dir)):
            if not filename.startswith(".") and filename.endswith(".ps1"):
                local_path = os.path.join(local_target_dir, filename)
                remote_name = f"{filename}"

                logging.info("Uploading %s to %s...", filename, remote_share)
                with open(local_path, 'rb') as f:
                    smb.putFile(remote_share, remote_name, f.read)
                
                full_remote_path = f"C:\\Windows\\{remote_name}"
                cmd = f'{CMD_PATH} /c {PS_PATH} -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{full_remote_path}"'

                logging.info("Executing %s via SCM...", remote_name)
                execute_remote_command(ip, username, password, cmd)

                try:
                    smb.deleteFile(remote_share, remote_name)
                    logging.debug("Cleaned up %s", remote_name)
                except:
                    logging.warning("Failed to cleanup %s", remote_name)

    except Exception as e:
        logging.error("SMB Execution failed: %s", e)

def execute_remote_command(ip: str, user: str, pwd: str, command: str) -> None:
    """
    Helper to interact with the Service Control Manager (SCM).
    Creates, starts, and deletes a service to execute a command.
    """
    string_binding = f'ncacn_np:{ip}[\\pipe\\svcctl]'
    rpc_transport = transport.DCERPCTransportFactory(string_binding)
    rpc_transport.set_credentials(user, pwd)

    try:
        dce = rpc_transport.get_dce_rpc()
        dce.connect()
        dce.bind(scmr.MSRPC_UUID_SCMR)

        scm_handle = scmr.hROpenSCManagerW(dce)['lpScHandle']

        svc_name = "CCDC_BLUE_Task"

        svc_handle = scmr.hRCreateServiceW(dce, scm_handle, svc_name, svc_name, lpBinaryPathName=command)['lpServiceHandle']

        try:
            logging.debug("Starting temporary service...")
            scmr.hRStartServiceW(dce, svc_handle)
        except Exception as e:
            # Service may "fail" since it doesn't talk back to SCM, but command will run!
            logging.debug("Service start result (Expected error for non-interactive): %s", e)

        scmr.hRDeleteService(dce, svc_handle)
        scmr.hRCloseServiceHandle(dce, svc_handle)
        scmr.hRCloseServiceHandle(dce, scm_handle)
        dce.disconnect()

    except Exception as e:
        logging.error("SCM RPC Error: %s", e)

def clean_clixml(raw_output: str) -> str:
    if not raw_output.startswith("#< CLIXML"):
        return raw_output
    
    matches = re.findall(r'<ToString>(.*?)</ToString>', raw_output)
    if matches:
        clean_messages = []
        for msg in matches:
            if msg not in clean_messages and "System.Management.Automation" not in msg:
                clean_messages.append(msg)
        return "\n".join(clean_messages)
    
    return raw_output
