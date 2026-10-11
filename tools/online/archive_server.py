"""Archive server source from Git objects only, with a path allowlist and secret checks."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
CORE = {"game_model", "game_data", "epoch_combat", "epoch_skills",
        "epoch_environment", "epoch_snapshot_migration"}
PREFIXES = ("server/", "services/online-gateway/", "godot/server/",
            "tools/online/", "docs/qa/server-archive/")
EXACT = {".gitignore", ".gitattributes",
         "godot/docs/distribution/Godot-LICENSE.txt",
         "godot/docs/distribution/Godot-third-party-notices.txt",
         "docs/qa/v0.8.1/server-bundle.json",
         "docs/qa/v0.8.1/server-bundle-integration.json",
         "docs/qa/v0.8.1/server-operations.json"}
PRIVATE_NAMES = {"online.env", "known_hosts", "id_rsa", "id_ed25519", "authorized_keys",
                 ".pgpass", ".pg_service.conf", ".netrc", ".git-credentials",
                 "credentials.xml", "local.credentials", "export_presets.cfg"}
PRIVATE_SUFFIXES = (".dpapi", ".pem", ".key", ".pfx", ".p12", ".jks",
                    ".keystore", ".dump", ".sqlite", ".sqlite3", ".db",
                    ".db-wal", ".db-shm", ".db-journal", ".sqlite-wal", ".sqlite-shm",
                    ".sqlite3-wal", ".sqlite3-shm",
                    ".exe", ".dll", ".so", ".log", ".pid", ".pck",
                    ".credentials.json", ".credentials.xml")
SECRET_PATTERNS = {
    "private key": re.compile(rb"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----"),
    "GitHub token": re.compile(rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})"),
    "AWS access key": re.compile(rb"(?:AKIA|ASIA)[A-Z0-9]{16}"),
    "OpenAI key": re.compile(rb"sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,}"),
}
DSN = re.compile(rb"(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|rediss?)://[^\s/:@\"']+:([^@\s\"']+)@", re.I)
ENV_SECRET = re.compile(rb"(?m)^\s*(?:EPOCH_DEPLOY_PASSWORD|OPENAI_API_KEY|AWS_SECRET_ACCESS_KEY|VERCEL_TOKEN|GITHUB_TOKEN)\s*=\s*([^\r\n]+)")


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def selected(name):
    path = PurePosixPath(name)
    return (name in EXACT or name.startswith(PREFIXES)
        or (path.parent.as_posix() == "godot/assets/data" and path.suffix == ".json")
        or (path.parent.as_posix() == "godot/scripts" and path.name.removesuffix(".uid").removesuffix(".gd") in CORE)
        or (name.startswith("docs/epoch-rush/online-") and path.suffix in {".md", ".json"}))


def placeholder(value):
    value = value.strip().strip(b"\"'")
    return (not value or (value.startswith(b"__") and value.endswith(b"__"))
        or (value.startswith(b"${") and value.endswith(b"}"))
        or re.fullmatch(rb"\$[A-Za-z_][A-Za-z0-9_]*", value) is not None)


def validate(name, content):
    path = PurePosixPath(name)
    basename = path.name.lower()
    if path.is_absolute() or ".." in path.parts or "\\" in name:
        raise RuntimeError("Unsafe Git archive path")
    if (basename in PRIVATE_NAMES or basename.endswith(PRIVATE_SUFFIXES)
            or basename.endswith((".env", ".sql.gz")) or ".dump." in basename
            or ((basename.startswith(".env") or ".env." in basename) and not basename.endswith(".env.example"))
            or name.startswith(("server/data/", "services/online-gateway/data/"))
            or set(part.lower() for part in path.parts) & {"output", ".local-tools", "pgdata", "pg_wal", "runtime", "data-private", "backups", "logs", "credentials", ".ssh", ".godot", "__pycache__"}):
        raise RuntimeError("Private/runtime file rejected: " + name)
    if b"\x00" in content:
        raise RuntimeError("Binary file rejected from server source: " + name)
    for kind, pattern in SECRET_PATTERNS.items():
        if pattern.search(content):
            raise RuntimeError(kind + " signature rejected in " + name)
    if any(not placeholder(match.group(1)) for match in DSN.finditer(content)):
        raise RuntimeError("Literal database credential rejected in " + name)
    if any(not placeholder(match.group(1)) for match in ENV_SECRET.finditer(content)):
        raise RuntimeError("Literal secret environment value rejected in " + name)


def index_files():
    entries = []
    for record in git("ls-files", "--stage", "-z").split(b"\0"):
        if not record:
            continue
        metadata, name_bytes = record.split(b"\t", 1)
        mode, oid, stage = metadata.split()
        name = name_bytes.decode("utf-8")
        if not selected(name):
            continue
        if mode not in {b"100644", b"100755"} or stage != b"0":
            raise RuntimeError("Only resolved regular source files can be archived: " + name)
        entries.append((name, oid))
    if not entries:
        return {}
    # Read staged blobs with one native Git process, never a directory scan.
    result = subprocess.check_output(["git", "cat-file", "--batch"], cwd=ROOT,
        input=b"".join(oid + b"\n" for _, oid in entries))
    stream = io.BytesIO(result)
    files = {}
    for name, oid in entries:
        header = stream.readline().strip().split()
        if len(header) != 3 or header[0] != oid or header[1] != b"blob":
            raise RuntimeError("Git blob inventory failed")
        content = stream.read(int(header[2]))
        if stream.read(1) != b"\n":
            raise RuntimeError("Git blob boundary failed")
        files[name] = content
    return files


def committed_files(ref):
    names = [name.decode("utf-8") for name in git("ls-tree", "-r", "--name-only", "-z", ref).split(b"\0")
             if name and selected(name.decode("utf-8"))]
    files = {}
    with tarfile.open(fileobj=io.BytesIO(git("archive", "--format=tar", ref, "--", *names))) as archive:
        for member in archive:
            if member.isdir():
                continue
            if not member.isfile() or not selected(member.name):
                raise RuntimeError("Unexpected Git archive member")
            files[member.name] = archive.extractfile(member).read()
    return files


def check(files):
    required = {"server/archive.json", "server/referee-project.godot",
                "services/online-gateway/go.mod", "services/online-gateway/go.sum",
                "services/online-gateway/migrations/001_online.sql",
                "godot/server/server_main.gd", "godot/assets/data/online-manifest.json"}
    required.update("godot/scripts/" + name + ".gd" for name in CORE)
    if required - files.keys():
        raise RuntimeError("Missing required server source: " + ", ".join(sorted(required - files.keys())))
    for name, content in files.items():
        validate(name, content)
    manifest = json.loads(files["godot/assets/data/online-manifest.json"])
    for name, digest in manifest["files"].items():
        content = files["godot/" + name]
        if name.endswith(".gd"):
            content = content.replace(b"\r\n", b"\n")
        if hashlib.sha256(content).hexdigest() != digest:
            raise RuntimeError("Simulation manifest mismatch: " + name)
    canonical = lambda value: json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    contract = {key: manifest[key] for key in ("engine", "files", "ruleset")}
    if (hashlib.sha256(canonical(contract)).hexdigest() != manifest["simulation_hash"]
            or hashlib.sha256(canonical(manifest["ruleset"])).hexdigest() != manifest["ruleset_hash"]):
        raise RuntimeError("Simulation contract hash mismatch")
    locked = json.loads(files["server/archive.json"])
    if locked["simulation_hash"] != manifest["simulation_hash"]:
        raise RuntimeError("Server archive lock and simulation manifest differ")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-index", action="store_true", help="Validate staged source without producing a ZIP")
    parser.add_argument("--ref", default="HEAD", help="Committed source ref to archive")
    args = parser.parse_args()
    commit = None if args.check_index else git("rev-parse", "--verify", args.ref + "^{commit}").decode().strip()
    files = index_files() if args.check_index else committed_files(commit)
    simulation = check(files)
    if args.check_index:
        print(json.dumps({"checked_index_files": len(files), "simulation_hash": simulation["simulation_hash"],
                          "allowlist_and_secret_checks": "passed"}))
        return
    manifest = {"source_commit": commit, "simulation_hash": simulation["simulation_hash"],
        "files": {name: {"bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()}
                  for name, content in sorted(files.items())}}
    output = ROOT / "output/archives/server" / commit[:12]
    output.mkdir(parents=True, exist_ok=True)
    target = output / ("Epoch-Rush-Server-Source-" + commit[:12] + ".zip")
    def entry(name, content, archive):
        # Stable timestamps make the same committed snapshot yield the same ZIP.
        info = zipfile.ZipInfo("Epoch-Rush-Server-Source/" + name, (1980, 1, 1, 0, 0, 0))
        info.create_system = 3
        info.external_attr = 0o100644 << 16
        archive.writestr(info, content, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, content in sorted(files.items()):
            entry(name, content, archive)
        entry("SERVER-SOURCE-MANIFEST.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", archive)
    with zipfile.ZipFile(target) as archive:
        if archive.testzip():
            raise RuntimeError("Server source ZIP CRC failure")
        for name, row in manifest["files"].items():
            if hashlib.sha256(archive.read("Epoch-Rush-Server-Source/" + name)).hexdigest() != row["sha256"]:
                raise RuntimeError("Server source ZIP hash failure: " + name)
    receipt = {"source_commit": commit, "files": len(files), "path": target.relative_to(ROOT).as_posix(),
               "bytes": target.stat().st_size, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
               "crc_and_all_entry_hashes": "passed"}
    (output / "source-archive.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt))


if __name__ == "__main__":
    main()
