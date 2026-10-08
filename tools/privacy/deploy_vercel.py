"""Package and publish the privacy page using native Windows Vercel CLI.

Anonymous deployments expire after 60 minutes unless claimed. Use
--authenticated after official CLI login to publish under your account.
Only the reviewed public website is packaged; CLI state remains private.
"""
from pathlib import Path
import argparse
import json
import os
import re
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "output/privacy-policy/2026-10-08"
SITE = ROOT / "web/privacy-policy"
NODE = Path(r"C:/Users/carzy/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe")
CLI = ROOT / ".local-tools/vercel-cli/node_modules/vercel/dist/index.js"
PUBLIC_FILES = {"index.html", "styles.css", "vercel.json", "privacy-policy.docx", "privacy-policy.md", "assets/knight.png"}


def prepare_production_output():
    """Build a bounded static output instead of relying on framework detection."""
    output = SITE / ".vercel/output"
    static = output / "static"
    static.mkdir(parents=True, exist_ok=True)
    expected = PUBLIC_FILES - {"vercel.json"}
    actual = {path.relative_to(static).as_posix() for path in static.rglob("*") if path.is_file()}
    if not actual <= expected:
        raise SystemExit("Unexpected file in public static output: " + str(actual - expected))
    for relative in sorted(expected):
        destination = static / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        source = SITE / relative
        if destination.exists() and (os.path.samefile(source, destination) or source.read_bytes() == destination.read_bytes()):
            continue
        shutil.copy2(source, destination)
    settings = json.loads((SITE / "vercel.json").read_text(encoding="utf-8"))
    routes = []
    for entry in settings.get("headers", []):
        if entry["source"] != "/(.*)":
            raise SystemExit("Unsupported static header pattern")
        routes.append({"src": "^/.*$", "headers": {item["key"]: item["value"] for item in entry["headers"]}, "continue": True})
    for entry in settings.get("rewrites", []):
        if entry["source"] not in {"/", "/privacy", "/privacy-policy"} or entry["destination"] != "/index.html":
            raise SystemExit("Unexpected policy route")
        routes.append({"src": "^" + re.escape(entry["source"]) + "$", "dest": entry["destination"]})
    routes.append({"handle": "filesystem"})
    (output / "config.json").write_text(json.dumps({"version": 3, "routes": routes}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if {path.relative_to(static).as_posix() for path in static.rglob("*") if path.is_file()} != expected:
        raise SystemExit("Public static output whitelist mismatch")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-only", action="store_true")
    parser.add_argument("--authenticated", action="store_true", help="Use an existing official Vercel login instead of a temporary deployment")
    parser.add_argument("--production", action="store_true", help="Publish to the linked project's production environment")
    parser.add_argument("--scope", help="Vercel team slug or ID")
    args = parser.parse_args()
    if args.production and not args.authenticated:
        parser.error("--production requires --authenticated")
    actual = {p.relative_to(SITE).as_posix() for p in SITE.rglob("*")
              if p.is_file() and p.relative_to(SITE).parts[0] != ".vercel" and p.name not in {".gitignore", ".vercelignore"}}
    if actual != PUBLIC_FILES:
        raise SystemExit("Deployment file whitelist mismatch: " + str(actual.symmetric_difference(PUBLIC_FILES)))
    text = (SITE / "index.html").read_text(encoding="utf-8")
    if any(marker in text for marker in ("{operator_name}", "{privacy_email}", "待确认", "校对稿", "【运营")):
        raise SystemExit("Unresolved document content; deployment blocked.")
    package = WORK / "deployment/privacy-site.tgz"
    package.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(package, "w:gz") as archive:
        for relative in sorted(PUBLIC_FILES):
            archive.add(SITE / relative, arcname="./" + relative, recursive=False)
    print(json.dumps({"package": str(package), "bytes": package.stat().st_size, "files": sorted(PUBLIC_FILES)}, ensure_ascii=False), flush=True)
    if args.package_only:
        return
    if not NODE.exists() or not CLI.exists():
        raise SystemExit("Install the official vercel npm package under .local-tools/vercel-cli before publishing.")
    command = [str(NODE), str(CLI), "deploy", str(SITE), "--yes", "--no-color", "--json"]
    if not args.authenticated:
        command.append("--temporary")
    if args.production:
        prepare_production_output()
        command.extend(["--prod", "--prebuilt"])
    if args.scope:
        command.extend(["--scope", args.scope])
    environment = dict(os.environ)
    environment["VERCEL_TELEMETRY_DISABLED"] = "1"
    result = subprocess.run(command, cwd=ROOT, env=environment, timeout=600, check=True,
                            capture_output=True, text=True, encoding="utf-8")
    try:
        response = json.loads(result.stdout[result.stdout.index("{"):])
    except (json.JSONDecodeError, ValueError):
        raise SystemExit("Vercel CLI returned invalid JSON: " + result.stdout[:500])
    deployment = response.get("deployment", {})
    if response.get("status") != "ok" or not deployment.get("url") or deployment.get("readyState") != "READY":
        raise SystemExit("Deployment did not return a usable URL: " + json.dumps(response, ensure_ascii=False))
    if not args.authenticated and not deployment.get("claimUrl"):
        raise SystemExit("Temporary deployment returned no claim URL.")
    record = {"previewUrl": deployment["url"], "claimUrl": deployment.get("claimUrl"),
              "deploymentId": deployment.get("id"), "readyState": deployment["readyState"],
              "expiresAt": deployment.get("expiresAt"), "message": response.get("message"),
              "production": args.production, "scope": args.scope,
              "aliases": deployment.get("alias", [])}
    if args.production:
        linked_project = json.loads((SITE / ".vercel/project.json").read_text(encoding="utf-8"))
        if linked_project.get("projectName"):
            record["productionUrl"] = "https://" + linked_project["projectName"] + ".vercel.app"
    result_name = "production-result.json" if args.production else "result.json"
    (WORK / "deployment" / result_name).write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(record, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
