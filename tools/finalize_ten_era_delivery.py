"""Bind the ten-era delivery to its final packages, runtime proof and source hashes."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / "output/qa/ten-eras"


def read(relative):
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    evidence_paths = [
        "rules-regression.json", "skills-regression.json", "restore-regression.json",
        "assets/asset-audit.json", "assets/visual-review.json", "transitions/native-transition-report.json",
        "windows-embedded/embedded-content.json", "windows-embedded/native/native-visual-report.json",
        "windows-embedded/interactions/interaction-checks.json", "audio/native/audio-regression.json",
        "audio/audio-signal-checks.json", "full-matches/full-battles.json", "performance/performance.json",
        "android-finalization.json", "packages/package-asset-checks.json", "video/showcase-report.json",
    ]
    reports = {name: read("output/qa/ten-eras/" + name) for name in evidence_paths}
    for name in ["rules-regression.json", "skills-regression.json"]:
        report = reports[name]
        assert report["passed"] and all(check["passed"] for check in report["checks"]), name
    assert len(reports["rules-regression.json"]["checks"]) == 420
    assert len(reports["skills-regression.json"]["checks"]) == 203
    assert reports["restore-regression.json"]["passed"] and reports["restore-regression.json"]["checks"] == 45
    transition = reports["transitions/native-transition-report.json"]
    assert transition["passed"] and transition["formsRendered"] == 120
    visual = reports["windows-embedded/native/native-visual-report.json"]
    assert visual["passed"] and len(visual["eras"]) == 10
    assert sum(len(era["maps"]) for era in visual["eras"]) == 30
    assert all(check["groundContact"] and check["correctType"] for era in visual["eras"] for check in era["carriers"])
    assert len(list((QA / "windows-embedded/native").glob("age-*.png"))) == 90
    ui = reports["windows-embedded/interactions/interaction-checks.json"]
    assert ui["checks"] == 159 and not ui["failures"] and ui["touch_input"]
    audio = reports["audio/native/audio-regression.json"]
    assert audio["passed"] and audio["checks"] == 265 and audio["stats"]["missing"] == 0
    signals = reports["audio/audio-signal-checks.json"]
    assert signals["passed"] and signals["native_mix"]["clipped_samples"] == 0
    matches = reports["full-matches/full-battles.json"]
    assert len(matches) == 8 and all(match["winner"] in [0, 1, 2] and match["occupancy_checked_every_tick"]
        and match["ground_overlaps"] == 0 and match["normal_route_jumps"] == 0 for match in matches)
    production = read("output/imagegen/ten-eras/production-state.json")
    assert production["processed"] == 135 and not production["failed"] and not production["blocked"]
    assert len(production["records"]) == 135 and all(row["status"] == "ready" and row["model"] == "gpt-image-2.5" for row in production["records"])

    packages = reports["packages/package-asset-checks.json"]
    assert packages["passed"] and packages["version"] == "0.7.0"
    android = reports["android-finalization.json"]
    assert android["passed"]
    files = []
    win = ROOT / "godot/build/windows"
    for name, key in [("Epoch-Rush-Godot.exe", "exe"), ("Epoch-Rush-Godot-Windows.zip", "zip")]:
        path = win / name
        assert sha(path) == packages["windows"][key + "_sha256"]
        files.append({"path": path.relative_to(ROOT).as_posix(), "bytes": path.stat().st_size, "sha256": sha(path)})
    for package in packages["android"]:
        path = ROOT / "godot/build/android" / package["file"]
        signature = next(row for row in android["packages"] if row["file"] == package["file"])
        assert sha(path) == package["sha256"] == signature["sha256"]
        assert signature["signatureVerified"] and signature["nativePageAlignment"] == 16384
        files.append({"path": path.relative_to(ROOT).as_posix(), "bytes": path.stat().st_size, "sha256": sha(path)})
    embedded = reports["windows-embedded/embedded-content.json"]
    assert embedded["passed"] and embedded["atlasesLoaded"] == 252 and len(embedded["checkedData"]) == 19

    showcase = reports["video/showcase-report.json"]
    assert showcase["passed"] and showcase["frames"] == 4890 and len(showcase["eras"]) == 10
    video = QA / "video/ten-era-showcase.mp4"
    media = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration,size",
        "-show_entries", "stream=codec_type,width,height,sample_rate", "-of", "json", str(video)], text=True))
    assert abs(float(media["format"]["duration"]) - 81.5) < .01
    assert any(stream["codec_type"] == "video" and stream["width"] == 1280 and stream["height"] == 720 for stream in media["streams"])
    assert any(stream["codec_type"] == "audio" and stream["sample_rate"] == "48000" for stream in media["streams"])
    assert video.stat().st_mtime >= (win / "Epoch-Rush-Godot.exe").stat().st_mtime
    menu_video = QA / "video/release-menu.avi"
    assert menu_video.stat().st_mtime >= (win / "Epoch-Rush-Godot.exe").stat().st_mtime
    assert "Done recording movie" in (QA / "release-menu.log").read_text(encoding="utf-8")
    assert "ERR_CANT_OPEN" not in (QA / "release-menu-errors.log").read_text(encoding="utf-8")

    summary = {
        "version": "0.7.0", "status": "delivered", "passed": True,
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(), "engine": "Godot 4.7.2",
        "files": files, "checks": {"rules": 420, "skills": 203, "restore": 45, "commanderPaletteForms": 120,
            "interactions": 159, "nativeAudio": 265, "nativeEraScreenshots": 90, "maps": 30, "completeMatches": 8},
        "production": {"model": "gpt-image-2.5", "readyJobs": 135, "activeActorDefinitions": 120,
            "totalAtlasDefinitionsIncludingLegacy": packages["actors"], "nonemptyFramesIncludingLegacy": packages["nonempty_frames"]},
        "runtimeProof": "Final Windows embedded PCK loaded by matching Godot engine; raw release executable startup recorded separately.",
        "video": {"path": video.relative_to(ROOT).as_posix(), "bytes": video.stat().st_size, "sha256": sha(video), "media": media},
        "performance": reports["performance/performance.json"],
        "evidenceSha256": {name: sha(QA / name) for name in evidence_paths},
        "sourceSha256": {path.relative_to(ROOT).as_posix(): sha(path) for path in sorted(
            list((ROOT / "godot/scripts").glob("*.gd")) + list((ROOT / "godot/assets/data").glob("*.json")))},
        "limitations": ["No connected Android hardware; no hardware performance or gameplay claims.",
            "No native Godot iOS IPA.", "Campaign human difficulty tuning is not complete.",
            "Forced raw release --quit-after reports 4 ObjectDB and 1 resource exit diagnostics.",
            "Future fair-duel proposal is documented, not implemented.",
            "Ambient flyers are animated cutouts; summoned turrets use static cutouts with procedural recoil."],
    }
    (QA / "delivery-summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    checksums = "".join(item["sha256"] + "  " + item["path"] + "\n" for item in files)
    (ROOT / "godot/build/SHA256SUMS-0.7.0.txt").write_text(checksums, encoding="utf-8")

    docs = [ROOT / name for name in ["README.md", "docs/README.md", "docs/epoch-rush/README.md", "godot/README.md",
        "docs/epoch-rush/godot-v0.7-ten-eras-report.md", "docs/epoch-rush/godot-v0.7-ten-eras-worklog.md",
        "docs/epoch-rush/godot-v0.7-gameplay-depth-and-fair-duels.md"]]
    links = 0
    for doc in docs:
        for target in re.findall(r"\]\(([^)]+)\)", doc.read_text(encoding="utf-8")):
            if target.startswith(("https://", "http://", "#", "app://")): continue
            path = Path(target.split("#", 1)[0].strip("<>"))
            if not path.is_absolute(): path = doc.parent / path
            assert path.exists(), f"Missing link in {doc.name}: {target}"
            links += 1
    print(json.dumps({"passed": True, "packages": len(files), "checkedLocalLinks": links,
        "videoSeconds": 81.5, "checks": summary["checks"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
