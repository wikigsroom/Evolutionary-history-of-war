"""Safely deploy a native Linux authority release with bounded, reversible steps.

The release is verified and imported in an isolated directory before the live
service is stopped; admission is drained, the current symlink is changed
atomically, and health failures roll back to the previous release.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shlex
import stat
import tarfile
from pathlib import Path, PurePosixPath

from remote_admin import command, connect

VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def inspect_archive(path: Path, version: str) -> tuple[str, str]:
    if not path.is_file():
        raise RuntimeError(f"Archive does not exist: {path}")
    manifest = None
    with tarfile.open(path, "r:gz") as archive:
        for member in archive.getmembers():
            rel = PurePosixPath(member.name)
            if rel.is_absolute() or ".." in rel.parts or "\\" in member.name:
                raise RuntimeError(f"Unsafe archive path: {member.name}")
            if member.issym() or member.islnk():
                raise RuntimeError(f"Links are not allowed: {member.name}")
            if member.name == "Epoch-Rush-Server/BUNDLE-MANIFEST.json":
                manifest = json.load(archive.extractfile(member))
    if manifest is None:
        raise RuntimeError("BUNDLE-MANIFEST.json is missing")
    if str(manifest.get("version")) != version:
        raise RuntimeError(f"Archive version {manifest.get('version')} != {version}")
    simulation = str(manifest.get("simulation_hash", ""))
    if not re.fullmatch(r"[0-9a-f]{64}", simulation):
        raise RuntimeError("Invalid simulation hash in bundle manifest")
    return sha256(path), simulation


def shell(version: str, archive_sha: str, simulation_sha: str,
          remote_archive: str, public_url: str) -> str:
    q = shlex.quote
    release = f"/opt/epochrush/releases/{version}"
    return f'''#!/usr/bin/env bash
set -Eeuo pipefail
VERSION={q(version)}
EXPECTED_ARCHIVE_SHA={q(archive_sha)}
EXPECTED_SIMULATION_SHA={q(simulation_sha)}
REMOTE_ARCHIVE={q(remote_archive)}
RELEASE={q(release)}
RELEASES=/opt/epochrush/releases
CURRENT=/opt/epochrush/current
STAGE=$(mktemp -d "$RELEASES/.staging-$VERSION.XXXXXX")
DRAIN=/var/lib/epochrush/draining.flag
PREVIOUS="$(readlink -f "$CURRENT" 2>/dev/null || true)"
DRAINING=0
SWITCHED=0
STOPPED=0
rollback() {{
  set +e
  if [ "$STOPPED" -eq 1 ]; then
    if [ -n "$PREVIOUS" ] && [ -d "$PREVIOUS" ]; then
      if [ "$SWITCHED" -eq 1 ]; then ln -sfn "$PREVIOUS" "$CURRENT"; fi
      systemctl daemon-reload >/dev/null 2>&1 || true
      systemctl start epochrush-online.service >/dev/null 2>&1 || true
    fi
  fi
  if [ "$DRAINING" -eq 1 ]; then rm -f -- "$DRAIN"; fi
  rm -rf -- "$STAGE"
  rm -f -- "$REMOTE_ARCHIVE"
}}
trap rollback ERR

echo DEPLOY_STEP archive-check
test "$(sha256sum "$REMOTE_ARCHIVE" | awk '{{print $1}}')" = "$EXPECTED_ARCHIVE_SHA"
mkdir -p "$RELEASES"
rm -rf -- "$STAGE"
mkdir -p "$STAGE"
tar --extract --gzip --file "$REMOTE_ARCHIVE" --directory "$STAGE" --no-same-owner
test -f "$STAGE/Epoch-Rush-Server/BUNDLE-MANIFEST.json"

echo DEPLOY_STEP manifest-check
python3 - "$STAGE/Epoch-Rush-Server/BUNDLE-MANIFEST.json" "$STAGE/Epoch-Rush-Server" "$VERSION" "$EXPECTED_SIMULATION_SHA" <<'PY'
import hashlib,json,pathlib,sys
manifest_path,root_name,version,simulation=sys.argv[1:]
root=pathlib.Path(root_name).resolve()
data=json.loads(pathlib.Path(manifest_path).read_text())
if str(data.get('version')) != version or data.get('simulation_hash') != simulation:
    raise SystemExit('bundle identity mismatch')
for relative,entry in data.get('files',{{}}).items():
    path=(root/relative).resolve()
    if not path.is_relative_to(root) or not path.is_file():
        raise SystemExit('unsafe or missing manifest path: '+relative)
    if hashlib.sha256(path.read_bytes()).hexdigest() != entry.get('sha256'):
        raise SystemExit('manifest hash mismatch: '+relative)
print(json.dumps({{'version':version,'simulation_hash':simulation,'files':len(data.get('files',{{}}))}}))
PY

echo DEPLOY_STEP referee-preflight
chown -R epochrush:epochrush "$STAGE/Epoch-Rush-Server/referee"
install -d -o epochrush -g epochrush -m 0750 /var/lib/epochrush/deploy-logs
PREFLIGHT_LOG=/var/lib/epochrush/deploy-logs/preflight-$VERSION.log
runuser -u epochrush -- env HOME=/var/lib/epochrush XDG_DATA_HOME=/var/lib/epochrush/data XDG_CONFIG_HOME=/var/lib/epochrush/config \
  timeout --signal=TERM --kill-after=8s 30s python3 - \
  /opt/epochrush/runtime/Godot_v4.7.2-stable_linux.x86_64 "$STAGE/Epoch-Rush-Server/referee" >"$PREFLIGHT_LOG" 2>&1 <<'PY'
import os, socket, subprocess, sys
godot, project = sys.argv[1:]
listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listener.bind(('127.0.0.1', 0))
listener.listen(1)
listener.settimeout(15)
env = os.environ.copy()
env['EPOCH_WORKER_PORT'] = str(listener.getsockname()[1])
process = subprocess.Popen([godot, '--headless', '--path', project,
                            '--script', 'res://server/server_main.gd', '--',
                            '--epoch-match=deployment-preflight'], env=env,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
try:
    connection, _ = listener.accept()
    print('REFEREE_READY', flush=True)
    connection.close()
except Exception:
    if process.poll() is None:
        process.terminate()
    output = process.communicate(timeout=8)[0].decode('utf-8', errors='replace')
    print(output, end='')
    raise SystemExit(1)
finally:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    listener.close()
PY
if ! grep -q '^REFEREE_READY$' "$PREFLIGHT_LOG"; then
  echo "Referee preflight failed; live service was left untouched. Log: $PREFLIGHT_LOG" >&2
  exit 1
fi
if [ -e "$RELEASE" ]; then echo "Release already exists: $RELEASE" >&2; exit 1; fi

echo DEPLOY_STEP drain
install -o epochrush -g epochrush -m 0600 /dev/null "$DRAIN"
DRAINING=1
for attempt in $(seq 1 180); do
  health=$(curl --fail --silent --max-time 3 http://127.0.0.1:28187/healthz)
  active=$(printf '%s' "$health" | python3 -c 'import json,sys; print(int(json.load(sys.stdin).get("active_matches",-1)))')
  echo "DRAIN_STATUS attempt=$attempt active_matches=$active"
  if [ "$active" -eq 0 ]; then break; fi
  if [ "$attempt" -eq 180 ]; then echo "Timed out waiting for active matches" >&2; exit 1; fi
  sleep 1
done

echo DEPLOY_STEP backup
timeout --signal=TERM --kill-after=10s 120s systemctl start epochrush-backup.service

echo DEPLOY_STEP switch
STOPPED=1
systemctl stop epochrush-online.service
for attempt in $(seq 1 30); do
  if ! systemctl is-active --quiet epochrush-online.service; then break; fi
  if [ "$attempt" -eq 30 ]; then echo "Old service did not stop" >&2; exit 1; fi
  sleep 1
done
mv -- "$STAGE/Epoch-Rush-Server" "$RELEASE"
chown -R root:root "$RELEASE"
chmod -R a+rX "$RELEASE"
chmod 0755 "$RELEASE/bin/epoch-online"
ln -sfn "$RELEASE" "$CURRENT"
SWITCHED=1
systemctl daemon-reload
systemctl start epochrush-online.service

echo DEPLOY_STEP health
for attempt in $(seq 1 60); do
  if systemctl is-active --quiet epochrush-online.service && curl --fail --silent --max-time 3 http://127.0.0.1:28187/healthz >/dev/null; then break; fi
  if [ "$attempt" -eq 60 ]; then echo "New service failed loopback health" >&2; exit 1; fi
  sleep 1
done
local_bootstrap=$(curl --fail --silent --max-time 5 http://127.0.0.1:28187/v1/bootstrap)
python3 -c 'import json,sys; body=json.load(sys.stdin); sys.exit(0 if body.get("simulation_hash")==sys.argv[1] else "local bootstrap hash mismatch")' "$EXPECTED_SIMULATION_SHA" <<<"$local_bootstrap"
public_bootstrap=$(curl --fail --silent --max-time 10 {q(public_url.rstrip('/') + '/v1/bootstrap')})
python3 -c 'import json,sys; body=json.load(sys.stdin); sys.exit(0 if body.get("simulation_hash")==sys.argv[1] else "public bootstrap hash mismatch")' "$EXPECTED_SIMULATION_SHA" <<<"$public_bootstrap"
rm -f -- "$DRAIN"
DRAINING=0
trap - ERR
rm -rf -- "$STAGE"
rm -f -- "$REMOTE_ARCHIVE"
echo "DEPLOY_SUCCESS version=$VERSION simulation_hash=$EXPECTED_SIMULATION_SHA"
'''

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--host", default="124.221.198.220")
    parser.add_argument("--public-url", default="https://jyqx-server.sidcloud.cn")
    parser.add_argument("--timeout", type=int, default=360)
    args = parser.parse_args()
    if not VERSION_RE.fullmatch(args.version):
        raise SystemExit("--version must be numeric semver")
    if not re.fullmatch(r"https://[A-Za-z0-9.-]+", args.public_url.rstrip("/")):
        raise SystemExit("--public-url must be https")
    archive = args.archive.resolve()
    archive_sha, simulation_sha = inspect_archive(archive, args.version)
    remote_archive = f"/tmp/epochrush-{args.version}-{archive_sha[:12]}.tar.gz"
    print(json.dumps({"host":args.host,"version":args.version,"archive":str(archive),
                      "sha256":archive_sha,"simulation_hash":simulation_sha},ensure_ascii=False))
    client,password=connect(host=args.host)
    try:
        sftp=client.open_sftp()
        try:
            sftp.put(str(archive), remote_archive)
            sftp.chmod(remote_archive, stat.S_IRUSR|stat.S_IWUSR)
        finally:
            sftp.close()
        output=command(client, shell(args.version,archive_sha,simulation_sha,remote_archive,args.public_url),
                       password, sudo=True, timeout=args.timeout)
        print(output.decode("utf-8",errors="replace"),end="")
    finally:
        client.close()

if __name__ == "__main__":
    main()

\n