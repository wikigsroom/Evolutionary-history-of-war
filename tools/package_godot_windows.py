"""Package an exported Windows game with the required third-party notices.

Run after Godot export. Uses only Python's standard library and never signs files.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import zipfile


ROOT = Path(__file__).resolve().parents[1]
FILES = {
    "README.md": ROOT / "godot/docs/distribution/README.md",
    "Godot-LICENSE.txt": ROOT / "godot/docs/distribution/Godot-LICENSE.txt",
    "Godot-third-party-notices.txt": ROOT / "godot/docs/distribution/Godot-third-party-notices.txt",
    "resource-rounded-LICENSE.txt": ROOT / "godot/assets/fonts/resource-rounded-LICENSE.txt",
    "smiley-LICENSE.txt": ROOT / "godot/assets/fonts/smiley-LICENSE.txt",
    "Audio-CREDITS.txt": ROOT / "godot/assets/audio/Audio-CREDITS.txt",
    "Audio-CC0-1.0.txt": ROOT / "godot/assets/audio/Audio-CC0-1.0.txt",
}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=ROOT / "godot/build/windows")
    parser.add_argument("--exe", type=Path, help="Exported executable; defaults to DIRECTORY/Epoch-Rush-Godot.exe")
    args = parser.parse_args()
    directory = args.directory.resolve()
    executable = (args.exe or directory / "Epoch-Rush-Godot.exe").resolve()
    if not executable.is_file():
        parser.error("Export the Windows executable before packaging: " + str(executable))
    missing = [str(path.relative_to(ROOT)) for path in FILES.values() if not path.is_file()]
    if missing:
        parser.error("Missing notices: " + ", ".join(missing))
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / "Epoch-Rush-Godot.exe"
    if target.resolve() != executable:
        shutil.copy2(executable, target)
    for name, source in FILES.items():
        shutil.copy2(source, directory / name)
    included = ["Epoch-Rush-Godot.exe", *FILES]
    bundle = directory / "Epoch-Rush-Godot-Windows.zip"
    with zipfile.ZipFile(bundle, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name in included:
            archive.write(directory / name, name)
    with zipfile.ZipFile(bundle) as archive:
        if archive.testzip() or sorted(archive.namelist()) != sorted(included):
            raise RuntimeError("Windows bundle failed archive verification")
        with archive.open("Epoch-Rush-Godot.exe") as source:
            digest = hashlib.sha256()
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != sha256(target):
            raise RuntimeError("Bundled executable differs from the export")
    files = [target, bundle]
    (directory / "SHA256SUMS.txt").write_text(
        "".join(f"{sha256(path)}  {path.name}\n" for path in files), encoding="utf-8"
    )
    print(json.dumps({"passed": True, "directory": str(directory), "bundle": bundle.name,
                      "files": len(included), "exe_sha256": sha256(target),
                      "zip_sha256": sha256(bundle)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
