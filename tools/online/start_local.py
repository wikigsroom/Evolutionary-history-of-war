"""Start native PostgreSQL and the gateway, with durable data under ignored output/."""
import argparse
import json
import os
import pathlib
import secrets
import hashlib
import shutil
import subprocess
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
RUNTIME = ROOT / ".local-tools/online"
STATE = ROOT / "output/online-local"
CONFIG = STATE / "local.credentials.json"
NATIVE_FLAGS = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def run(args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, creationflags=NATIVE_FLAGS, **kwargs)


def configuration():
    STATE.mkdir(parents=True, exist_ok=True)
    if CONFIG.exists():
        return json.loads(CONFIG.read_text(encoding="utf-8"))
    config = {"db_port": 54329, "db_password": secrets.token_hex(32), "http_port": 28187}
    CONFIG.write_text(json.dumps(config), encoding="utf-8")
    return config


def database_url(config):
    return f"postgres://epoch:{config['db_password']}@127.0.0.1:{config['db_port']}/postgres?sslmode=disable"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lan", action="store_true", help="Listen on LAN instead of loopback")
    parser.add_argument("--test", action="store_true", help="Run Go tests with the actual local database")
    parser.add_argument("--restart", action="store_true", help="Restart only this workspace's verified gateway")
    parser.add_argument("--no-build", action="store_true", help="Use an already built gateway")
    args = parser.parse_args()
    config = configuration()
    # PostgreSQL's Windows initdb still mishandles some non-ASCII install paths.
    # Use a native ASCII cache, not a VM/container or a remapped system environment.
    native_root = pathlib.Path(os.environ["LOCALAPPDATA"]) / "EpochRushOnline" / hashlib.sha256(str(ROOT).encode()).hexdigest()[:12]
    native_root.mkdir(parents=True, exist_ok=True)
    if not (native_root / "pgsql/bin/postgres.exe").exists():
        shutil.copytree(RUNTIME / "pgsql", native_root / "pgsql", dirs_exist_ok=True)
    pg = native_root / "pgsql/bin"
    data = native_root / "pgdata"
    if not data.exists():
        password_file = native_root / "init-password.tmp"
        password_file.write_text(config["db_password"], encoding="utf-8")
        try:
            run([pg / "initdb.exe", "-D", data, "-U", "epoch", "-A", "scram-sha-256", "--pwfile", password_file, "--encoding", "UTF8", "--locale", "C"], stdout=subprocess.DEVNULL)
        finally:
            password_file.unlink(missing_ok=True)
    status = subprocess.run([str(pg / "pg_ctl.exe"), "-D", str(data), "status"], capture_output=True, creationflags=NATIVE_FLAGS)
    if status.returncode != 0:
        run([pg / "pg_ctl.exe", "-D", data, "-l", STATE / "postgres.log", "-o", f"-p {config['db_port']} -h 127.0.0.1", "start", "-w"], stdout=subprocess.DEVNULL)
    environment = os.environ.copy()
    environment["EPOCH_DATABASE_URL"] = database_url(config)
    go = RUNTIME / "go/bin/go.exe"
    service = ROOT / "services/online-gateway"
    if args.test:
        run([go, "test", "-count=1", "-v", "./..."], cwd=service, env=environment)
        return
    binary = STATE / "epoch-online.exe"
    if not args.no_build or not binary.exists():
        run([go, "build", "-o", binary, "."], cwd=service)
    url = f"http://127.0.0.1:{config['http_port']}"
    try:
        with urllib.request.urlopen(url + "/healthz", timeout=2) as response:
            if response.status == 200:
                if not args.restart:
                    print("Existing gateway healthy:", url)
                    return
                pid = int((STATE / "gateway.pid").read_text(encoding="ascii"))
                expected_path = str(binary).replace("'", "''")
                command = f"$p=Get-CimInstance Win32_Process -Filter 'ProcessId={pid}'; if ($p.ExecutablePath -eq '{expected_path}') {{ Stop-Process -Id {pid} }} else {{ exit 2 }}"
                run(["powershell.exe", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", command], stdout=subprocess.DEVNULL)
                time.sleep(0.25)
    except Exception:
        pass
    log = open(STATE / "gateway.log", "ab", buffering=0)
    process = subprocess.Popen([str(binary), "--listen", f"{'0.0.0.0' if args.lan else '127.0.0.1'}:{config['http_port']}",
                               "--drain-file",str(STATE/"draining.flag"),
                               "--project", str(ROOT / "godot"), "--godot", str(ROOT / "godot/toolchain/editor/Godot_v4.7.2-stable_win64_console.exe")],
                               cwd=ROOT, env=environment, stdout=log, stderr=log, creationflags=NATIVE_FLAGS)
    (STATE / "gateway.pid").write_text(str(process.pid), encoding="ascii")
    for _ in range(40):
        if process.poll() is not None:
            raise RuntimeError("Gateway exited; inspect output/online-local/gateway.log")
        try:
            with urllib.request.urlopen(url + "/healthz", timeout=1) as response:
                if response.status == 200:
                    print("Native PostgreSQL ready; gateway healthy:", url)
                    print("Gateway PID:", process.pid)
                    return
        except Exception:
            time.sleep(0.25)
    raise RuntimeError("Gateway startup did not reach health check")


if __name__ == "__main__":
    main()
