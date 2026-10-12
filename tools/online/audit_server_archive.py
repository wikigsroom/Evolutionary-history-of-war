"""Read-only inventory of this game's deployment; never read credentials or DB rows."""
import argparse
import contextlib
import hashlib
import io
import json
from pathlib import Path
import urllib.request

from remote_admin import command, connect

ROOT = Path(__file__).resolve().parents[2]
OPERATIONS = {
    "epochrush-online.service": "/etc/systemd/system/epochrush-online.service",
    "epochrush-health.service": "/etc/systemd/system/epochrush-health.service",
    "epochrush-health.timer": "/etc/systemd/system/epochrush-health.timer",
    "epochrush-backup.service": "/etc/systemd/system/epochrush-backup.service",
    "epochrush-backup.timer": "/etc/systemd/system/epochrush-backup.timer",
    "epochrush-logrotate.conf": "/etc/logrotate.d/epochrush",
    "nginx-public.conf": "/www/server/panel/vhost/nginx/jyqx-server.sidcloud.cn.conf",
    "renew-proxy.sh": "/etc/letsencrypt/renewal-hooks/deploy/epochrush-nginx.sh",
    "health.sh": "/opt/epochrush/current/ops/health.sh",
    "backup.sh": "/opt/epochrush/current/ops/backup.sh",
}

REMOTE_SCRIPT = r"""python3 - <<'PY'
from pathlib import Path, PurePosixPath
import hashlib,json,stat,subprocess
operations = __OPERATIONS__
release = Path('/opt/epochrush/current').resolve()
manifest = json.loads((release/'BUNDLE-MANIFEST.json').read_text())
files = {}
for name,entry in manifest['files'].items():
    relative = PurePosixPath(name)
    if relative.is_absolute() or '..' in relative.parts or '\\' in name:
        raise RuntimeError('Unsafe deployment manifest path')
    if name != 'README.md' and not name.startswith(('bin/','referee/','ops/','licenses/')):
        raise RuntimeError('Unexpected deployment manifest entry')
    if any(part in relative.parts for part in ('.godot','pgdata','credentials')):
        raise RuntimeError('Private runtime entry in manifest')
    path = (release/name).resolve()
    if not path.is_relative_to(release):
        raise RuntimeError('Deployment manifest escapes release directory')
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    files[name] = {'bytes':len(data),'sha256':digest,
        'normalized_sha256':hashlib.sha256(data.replace(b'\r\n',b'\n')).hexdigest(),
        'matches_original_package':digest == entry['sha256']}
config = Path('/etc/epochrush/online.env').stat()
print(json.dumps({'server_version':manifest['version'],
    'simulation_hash':manifest['simulation_hash'], 'release_directory':str(release),
    'service_active':subprocess.check_output(['systemctl','is-active','epochrush-online.service'],text=True).strip() == 'active',
    'secret_configuration_permissions':oct(stat.S_IMODE(config.st_mode)),
    'secret_configuration_owner_is_root':config.st_uid == 0,
    'files':files,
    'operations':{name:hashlib.sha256(Path(path).read_bytes().replace(b'\r\n',b'\n')).hexdigest() for name,path in operations.items()}}))
PY
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="124.221.198.220",
                        help="SSH host to audit (default: current Shanghai production host)")
    parser.add_argument("--output", type=Path,
                        default=ROOT / "output/qa/server-archive/deployed-inventory.json")
    args = parser.parse_args()
    client, password = connect(host=args.host)
    try:
        # remote_admin normally streams output. Keep the inventory quiet and
        # persist only the explicitly selected, non-sensitive metadata below.
        with contextlib.redirect_stdout(io.StringIO()):
            observed = json.loads(command(client,
                REMOTE_SCRIPT.replace("__OPERATIONS__", repr(OPERATIONS)),
                password, sudo=True, timeout=45))
    finally:
        client.close()
    for name, digest in observed["operations"].items():
        local = ROOT / "services/online-gateway/deploy/linux" / name
        expected = hashlib.sha256(local.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
        observed["operations"][name] = {"remote_sha256": digest,
            "repository_sha256": expected, "matches_repository": digest == expected}
    for name, row in observed["files"].items():
        if name.startswith("referee/") and not name.endswith("project.godot"):
            local = ROOT / "godot" / name.removeprefix("referee/")
            row["matches_current_source"] = local.is_file() and (
                hashlib.sha256(local.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
                == row["normalized_sha256"])
    with urllib.request.urlopen("https://jyqx-server.sidcloud.cn/v1/bootstrap", timeout=15) as response:
        public = json.load(response)
    observed["public_simulation_hash_matches"] = public["simulation_hash"] == observed["simulation_hash"]
    observed["audit_scope"] = "Hashes, unit state and config permissions only; no DB, logs, secret values or TLS keys read."
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(observed, indent=2) + "\n", encoding="utf-8")
    summary = {"version": observed["server_version"],
        "service_active": observed["service_active"],
        "public_matches": observed["public_simulation_hash_matches"],
        "operations_matching_repository": sum(row["matches_repository"] for row in observed["operations"].values()),
        "source_files_matching": sum(row.get("matches_current_source", False) for row in observed["files"].values()),
        "package_differences": [name for name, row in observed["files"].items() if not row["matches_original_package"]]}
    print(json.dumps(summary, indent=2))
    if not (summary["service_active"] and summary["public_matches"]
            and observed["secret_configuration_owner_is_root"]
            and observed["secret_configuration_permissions"] == "0o600"
            and all(row["matches_repository"] for row in observed["operations"].values())
            and all(row.get("matches_current_source", True) for row in observed["files"].values())
            and observed["files"]["bin/epoch-online"]["matches_original_package"]):
        raise RuntimeError("Deployment differs from archive; inspect the non-sensitive inventory before proceeding")


if __name__ == "__main__":
    main()
