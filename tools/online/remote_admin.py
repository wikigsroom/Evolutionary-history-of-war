"""Native SSH administration with a locally DPAPI-protected operator credential.

The password is read from EPOCH_DEPLOY_PASSWORD only for initial setup. It is
never placed in command arguments, logs, source archives or release artifacts.
"""
import argparse
import base64
import ctypes
import hashlib
import json
import os
from pathlib import Path
import sys
import time

import paramiko

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / "output/deploy/online"


class Blob(ctypes.Structure):
    _fields_ = [("size", ctypes.c_ulong), ("data", ctypes.POINTER(ctypes.c_ubyte))]


def protect(data, decrypt=False):
    backing = ctypes.create_string_buffer(data)
    source = Blob(len(data), ctypes.cast(backing, ctypes.POINTER(ctypes.c_ubyte)))
    result = Blob()
    api = ctypes.windll.crypt32.CryptUnprotectData if decrypt else ctypes.windll.crypt32.CryptProtectData
    if not api(ctypes.byref(source), None, None, None, None, 1, ctypes.byref(result)):
        raise OSError("Windows DPAPI credential protection failed")
    try:
        return ctypes.string_at(result.data, result.size)
    finally:
        ctypes.windll.kernel32.LocalFree(result.data)


def connect(host="43.160.222.104", user="ubuntu"):
    STATE.mkdir(parents=True, exist_ok=True)
    credential = STATE / "ssh-password.dpapi"
    initial = os.environ.get("EPOCH_DEPLOY_PASSWORD")
    if initial:
        credential.write_bytes(protect(initial.encode()))
    if not credential.exists():
        raise RuntimeError("Supply EPOCH_DEPLOY_PASSWORD once for the authorized server")
    password = protect(credential.read_bytes(), decrypt=True).decode()
    client = paramiko.SSHClient()
    # Import only this server's existing pin. An unrelated malformed record in
    # the user's native OpenSSH file must not break or rewrite that file.
    native_hosts = Path.home() / ".ssh/known_hosts"
    existing = paramiko.HostKeys()
    if native_hosts.exists():
        for line in native_hosts.read_text(encoding="utf-8", errors="replace").splitlines():
            if not line.strip() or line.startswith("#"):
                continue
            hosts = line.split()[0]
            if host not in hosts.split(",") and not hosts.startswith("|1|"):
                continue
            entry = paramiko.hostkeys.HostKeyEntry.from_line(line)
            if entry:
                for name in entry.hostnames:
                    existing.add(name, entry.key.get_name(), entry.key)
        matched = existing.lookup(host)
        if matched:
            for algorithm, key in matched.items():
                client.get_host_keys().add(host, algorithm, key)
    pinned = STATE / "known_hosts"
    if pinned.exists():
        client.load_host_keys(str(pinned))
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(host, username=user, password=password, look_for_keys=False,
                   allow_agent=False, timeout=15, auth_timeout=15, banner_timeout=15)
    client.save_host_keys(str(pinned))
    client.get_transport().set_keepalive(15)
    return client, password


def command(client, script, password, sudo=False, timeout=50):
    # This authorized host grants ubuntu passwordless sudo. Never prepend a
    # password to a script stream: sudo may not consume it when NOPASSWD applies.
    command = "sudo -n /bin/bash -s" if sudo else "/bin/bash -s"
    stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    stdin.write("set -euo pipefail\n" + script + "\n")
    stdin.flush()
    stdin.channel.shutdown_write()
    channel = stdout.channel
    deadline = time.monotonic() + timeout
    output, errors = bytearray(), bytearray()
    while not channel.exit_status_ready() or channel.recv_ready() or channel.recv_stderr_ready():
        if channel.recv_ready():
            block = channel.recv(65536); output.extend(block)
            sys.stdout.write(block.decode(errors="replace").replace(password, "[redacted]")); sys.stdout.flush()
        if channel.recv_stderr_ready():
            block = channel.recv_stderr(65536); errors.extend(block)
            sys.stderr.write(block.decode(errors="replace").replace(password, "[redacted]")); sys.stderr.flush()
        if time.monotonic() > deadline:
            channel.close()
            raise TimeoutError("Remote command observation timed out; inspect remote state before retrying")
        time.sleep(.05)
    status = channel.recv_exit_status()
    if status:
        raise RuntimeError("Remote command exited " + str(status))
    return bytes(output)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--script", type=Path)
    parser.add_argument("--sudo", action="store_true")
    parser.add_argument("--timeout", type=int, default=50)
    args = parser.parse_args()
    client, password = connect()
    try:
        if args.script:
            command(client, args.script.read_text(encoding="utf-8"), password, args.sudo, args.timeout)
        else:
            key = client.get_transport().get_remote_server_key()
            print("SSH host fingerprint SHA256:" + base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode().rstrip("="))
            command(client, """uname -m
cat /etc/os-release
printf '\\n--- capacity ---\\n'
nproc
free -m
df -h /
printf '\\n--- listening ---\\n'
ss -lntp
printf '\\n--- services ---\\n'
systemctl list-units --type=service --state=running --no-pager
printf '\\n--- tools ---\\n'
command -v nginx caddy psql pg_lsclusters curl unzip go godot || true
printf '\\n--- sudo ---\\n'
sudo -n true && printf 'sudo-nopasswd\\n' || true
""", password, timeout=40)
    finally:
        client.close()


if __name__ == "__main__":
    main()
