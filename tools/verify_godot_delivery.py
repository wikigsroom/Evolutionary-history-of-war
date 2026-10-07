"""Verify the shipped Godot archives, atlas frames and bundled font coverage."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import zipfile

from PIL import Image
from fontTools.ttLib import TTFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output/qa/godot-audio"
ASSETS = ROOT / "godot/assets"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    global OUTPUT
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    OUTPUT = args.output.resolve()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    failures = []
    animation = json.loads((ASSETS / "data/animations.json").read_text(encoding="utf-8"))
    frames = 0
    for actor_id, metadata in animation.items():
        for key, palette in [("path", "own"), ("enemyPath", "enemy")]:
            atlas = ASSETS / metadata[key]
            if sha(atlas) != metadata["atlasSha256"][palette]:
                failures.append(f"{actor_id}/{palette}: atlas hash")
            with Image.open(atlas) as image:
                width, height = metadata["frameWidth"], metadata["frameHeight"]
                columns, rows = metadata.get('columns', 6), metadata.get('rows', 5)
                if image.size != (width * columns, height * rows):
                    failures.append(f"{actor_id}/{palette}: atlas dimensions")
                alpha = image.convert("RGBA").getchannel("A")
                for row in range(rows):
                    for column in range(columns):
                        if alpha.crop((column * width, row * height, (column + 1) * width, (row + 1) * height)).getbbox() is None:
                            failures.append(f"{actor_id}/{palette}: empty frame {row * columns + column}")
                        else:
                            frames += 1

    text = "".join(path.read_text(encoding="utf-8") for path in (ROOT / "godot/scripts").glob("*.gd"))
    text += "".join(path.read_text(encoding="utf-8") for path in (ASSETS / "data").glob("*.json"))
    required = {ord(character) for character in re.findall(r"[\u3400-\u4dbf\u4e00-\u9fff]", text)}
    fonts = []
    for path in sorted((ASSETS / "fonts").glob("*.woff2")):
        with TTFont(path) as font:
            missing = sorted(required - set(font.getBestCmap()))
        fonts.append({"name": path.name, "required_chinese_glyphs": len(required), "missing": [chr(value) for value in missing]})
        if missing:
            failures.append(f"{path.name}: {len(missing)} missing glyphs")

    data = sorted((ASSETS / "data").glob("*.json"))
    packages = []
    asset_audit = json.loads((ROOT/'output/qa/ten-eras/assets/asset-audit.json').read_text(encoding='utf-8'))
    if not asset_audit['passed'] or asset_audit['actorsPresent']!=120 or asset_audit['mapsPresent']!=30:
        failures.append('Ten-era runtime inventory incomplete')
    textures = {r['path'] for r in asset_audit['textures']+asset_audit['maps']}
    textures.update(m[k] for m in animation.values() for k in ['path','enemyPath'])
    for path in sorted((ROOT / "godot/build/android").glob("Epoch-Rush-Godot-*.apk")):
        with zipfile.ZipFile(path) as archive:
            crc = archive.testzip()
            differences = []
            for source in data:
                name = "assets/" + source.relative_to(ROOT / "godot").as_posix()
                if name not in archive.namelist() or archive.read(name) != source.read_bytes():
                    differences.append(source.name)
            forbidden = [name for name in archive.namelist() if any(part in name.casefold() for part in ["/qa/", "/toolchain/", ".keystore", "export_presets.cfg"])]
            missing_textures = []
            mismatched_imports = []
            for relative in sorted(textures):
                remap = 'assets/assets/' + relative + '.import'
                plain = 'assets/assets/' + relative
                if remap in archive.namelist():
                    match = re.search(r'path="res://([^\"]+)"', archive.read(remap).decode('utf-8'))
                    imported = match.group(1) if match else ''
                    if not imported or 'assets/'+imported not in archive.namelist():
                        missing_textures.append(relative)
                    elif archive.read('assets/'+imported)!=(ROOT/'godot'/imported).read_bytes():
                        mismatched_imports.append(relative)
                elif plain not in archive.namelist():
                    missing_textures.append(relative)
                elif archive.read(plain)!=(ASSETS/relative).read_bytes():
                    mismatched_imports.append(relative)
            architectures = sorted({name.split("/")[1] for name in archive.namelist() if name.startswith("lib/") and name.endswith(".so")})
            if crc or differences or forbidden or missing_textures or mismatched_imports or architectures != ["arm64-v8a"]:
                failures.append(path.name + ": invalid package content")
            packages.append({"file": path.name, "size": path.stat().st_size, "sha256": sha(path), "checked_data_files": len(data), "checked_textures":len(textures),"missing_textures":missing_textures,"mismatched_imports":mismatched_imports,"data_differences": differences, "forbidden_files": forbidden, "crc_error": crc, "architectures": architectures})
    if len(packages)!=2:failures.append('Expected both release and debug Android packages')

    windows = ROOT / "godot/build/windows"
    included = ["Epoch-Rush-Godot.exe", "README.md", "Godot-LICENSE.txt", "Godot-third-party-notices.txt", "resource-rounded-LICENSE.txt", "smiley-LICENSE.txt", "Audio-CREDITS.txt", "Audio-CC0-1.0.txt"]
    bundle = windows / "Epoch-Rush-Godot-Windows.zip"
    with zipfile.ZipFile(bundle, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name in included:
            archive.write(windows / name, name)
    with zipfile.ZipFile(bundle) as archive:
        if archive.testzip() is not None or sorted(archive.namelist()) != sorted(included):
            failures.append("Windows bundle: invalid archive")
        if archive.read("Epoch-Rush-Godot.exe") != (windows / "Epoch-Rush-Godot.exe").read_bytes():
            failures.append("Windows bundle: executable differs")
    exe = windows / "Epoch-Rush-Godot.exe"
    version = re.search(r'config/version="([^"]+)"', (ROOT / "godot/project.godot").read_text(encoding="utf-8")).group(1)
    report = {"version": version, "passed": not failures, "actors": len(animation), "strips": len(animation) * 2, "nonempty_frames": frames, "fonts": fonts, "android": packages,
              "windows": {"exe_sha256": sha(exe), "exe_bytes": exe.stat().st_size, "zip_sha256": sha(bundle), "zip_bytes": bundle.stat().st_size, "files": included}, "failures": failures}
    (OUTPUT / "package-asset-checks.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "actors": len(animation), "nonempty_frames": frames, "chinese_glyphs": len(required), "android_packages": len(packages), "data_files_per_package": len(data), "failures": failures}, ensure_ascii=False))
    raise SystemExit(bool(failures))


if __name__ == "__main__":
    main()
