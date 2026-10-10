"""Collect validated native client/server artifacts and their SHA-256 receipts."""
import hashlib
import json
import pathlib
import shutil
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
VERSION = "0.8.0"
DEST = ROOT / "output/releases" / ("v" + VERSION)
QA = ROOT / "docs/qa" / ("v" + VERSION)


def read_report(path):
    report = json.loads(path.read_text(encoding="utf-8-sig"))
    if report.get("failed") or report.get("passed") is False:
        raise RuntimeError("Validation failed: " + str(path.relative_to(ROOT)))
    checks = report.get("checks", [])
    if isinstance(checks, list) and any(not check.get("passed") for check in checks):
        raise RuntimeError("A required check failed: " + str(path.relative_to(ROOT)))
    return report


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(chunk)
    return checksum.hexdigest()


def main():
    QA.mkdir(parents=True, exist_ok=True)
    DEST.mkdir(parents=True, exist_ok=True)
    for name, count in [("server-bundle.json", 10), ("server-bundle-integration.json", 23),
                        ("native-client-playable.json", 19), ("native-faults.json", 10)]:
        source = ROOT / "output/qa/online" / name
        report = read_report(source)
        if len(report["checks"]) != count:
            raise RuntimeError("Unexpected validation count: " + name)
        shutil.copy2(source, QA / name)
    android = read_report(ROOT / "output/qa/online/packages/online-android.json")
    branding = read_report(ROOT / "output/qa/online/packages/launcher-branding.json")
    if not android.get("passed") or not branding.get("passed"):
        raise RuntimeError("Android or branding validation is incomplete")
    raw_go = (ROOT / "output/qa/online/go-control.jsonl").read_bytes()
    go_text = raw_go.decode("utf-16" if raw_go.startswith(b"\xff\xfe") else "utf-8-sig")
    go_events = [json.loads(line) for line in go_text.splitlines() if line.strip()]
    go_passes = [event["Test"] for event in go_events if event.get("Action") == "pass" and event.get("Test")]
    if len(go_passes) != 7 or any(event.get("Action") == "fail" for event in go_events):
        raise RuntimeError("Go control checks did not pass")
    go_lines = [line for line in go_text.splitlines() if line.strip()]
    (QA / "go-control.jsonl").write_text("\n".join(go_lines) + "\n", encoding="utf-8", newline="\n")
    for name in ["client_playable-embedded", "core_contract-source", "interaction_regression-source", "difficulty_capital-source"]:
        source = ROOT / "output/qa/online" / (name + ".log")
        text = source.read_text(encoding="utf-8-sig")
        if "SCRIPT ERROR:" in text or "Parse Error:" in text:
            raise RuntimeError("Godot validation log contains errors: " + name)
        (QA / (name + ".txt")).write_text(text, encoding="utf-8")
    artifacts = [
        ROOT / "godot/build/windows/Epoch-Rush-Godot.exe",
        ROOT / "godot/build/windows/Epoch-Rush-Godot-Windows.zip",
        ROOT / "godot/build/android/Epoch-Rush-Godot-debug.apk",
        ROOT / "godot/build/android/Epoch-Rush-Godot-release.apk",
        DEST / "server/Epoch-Rush-Server-0.8.0-Windows-x64.zip",
    ]
    packages = {package["platform"]: package for package in android["packages"]}
    server = read_report(DEST / "server/server-package.json")
    receipt = {"version": VERSION, "android_version_code": 13, "artifacts": []}
    for source in artifacts:
        if not source.is_file():
            raise RuntimeError("Missing artifact: " + source.name)
        sha256 = digest(source)
        if source.suffix == ".apk":
            platform = "debug" if "debug" in source.name else "release"
            if sha256 != packages[platform]["sha256"]:
                raise RuntimeError("APK changed after package inspection")
        if "Server-" in source.name and sha256 != server["sha256"]:
            raise RuntimeError("Server ZIP changed after packaging")
        if source.suffix == ".zip":
            with zipfile.ZipFile(source) as archive:
                if archive.testzip():
                    raise RuntimeError("Corrupt ZIP: " + source.name)
        destination = DEST / source.name
        shutil.copy2(source, destination)
        if digest(destination) != sha256:
            raise RuntimeError("Release copy does not match validated source")
        receipt["artifacts"].append({"name": source.name, "bytes": destination.stat().st_size, "sha256": sha256})
    encoded = json.dumps(receipt, indent=2) + "\n"
    (DEST / "release-artifacts.json").write_text(encoded, encoding="utf-8")
    (QA / "release-artifacts.json").write_text(encoded, encoding="utf-8")
    (DEST / "SHA256SUMS.txt").write_text("".join(item["sha256"] + "  " + item["name"] + "\n" for item in receipt["artifacts"]), encoding="utf-8")
    print("Five validated native artifacts and SHA256SUMS ready:", DEST)


if __name__ == "__main__":
    main()
