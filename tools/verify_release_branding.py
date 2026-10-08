"""Inspect actual Windows PE icons and both APK launcher resources on native Windows."""
from pathlib import Path
import argparse
import ctypes
from ctypes import wintypes
import io
import json
import re
import struct
import subprocess
import zipfile
from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[1]


def extract_pe_icon(executable):
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.LoadLibraryExW.argtypes = [wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD]
    kernel.LoadLibraryExW.restype = wintypes.HMODULE
    kernel.FindResourceW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p]
    kernel.FindResourceW.restype = ctypes.c_void_p
    kernel.LoadResource.argtypes = [wintypes.HMODULE, ctypes.c_void_p]
    kernel.LoadResource.restype = ctypes.c_void_p
    kernel.LockResource.argtypes = [ctypes.c_void_p]
    kernel.LockResource.restype = ctypes.c_void_p
    kernel.SizeofResource.argtypes = [wintypes.HMODULE, ctypes.c_void_p]
    kernel.SizeofResource.restype = wintypes.DWORD
    kernel.FreeLibrary.argtypes = [wintypes.HMODULE]
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p, wintypes.LPARAM)
    kernel.EnumResourceNamesW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, callback_type, wintypes.LPARAM]
    handle = kernel.LoadLibraryExW(str(executable), None, 2)  # Data only; never execute the EXE.
    if not handle: raise ctypes.WinError(ctypes.get_last_error())
    try:
        names = []
        callback = callback_type(lambda module, kind, name, param: names.append(name) is None)
        kernel.EnumResourceNamesW(handle, 14, callback, 0)
        if not names: raise ValueError("Executable has no icon group")

        def resource(name, kind):
            found = kernel.FindResourceW(handle, name, kind)
            if not found: raise ctypes.WinError(ctypes.get_last_error())
            size = kernel.SizeofResource(handle, found)
            return ctypes.string_at(kernel.LockResource(kernel.LoadResource(handle, found)), size)

        group = resource(names[0], 14)
        count = struct.unpack_from("<H", group, 4)[0]
        offset = 6 + 16 * count
        entries, chunks = [], []
        for index in range(count):
            width, height, colors, reserved, planes, bits, size, resource_id = struct.unpack_from("<BBBBHHIH", group, 6 + 14 * index)
            content = resource(resource_id, 3)
            entries.append(struct.pack("<BBBBHHII", width, height, colors, reserved, planes, bits, len(content), offset))
            chunks.append(content); offset += len(content)
        return struct.pack("<HHH", 0, 1, count) + b"".join(entries) + b"".join(chunks)
    finally:
        kernel.FreeLibrary(handle)


def image_difference(actual, expected):
    source = expected.convert("RGBA").resize(actual.size, Image.Resampling.LANCZOS)
    return sum(ImageStat.Stat(ImageChops.difference(actual.convert("RGB"), source.convert("RGB"))).mean) / 3


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "output/qa/v0.7.1/packages")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    errors, rows = [], []
    expected_icon = Image.open(ROOT / "godot/assets/ui/pixel/app-icon.png").convert("RGBA")
    expected_foreground = Image.open(ROOT / "godot/assets/ui/pixel/launcher-foreground.png").convert("RGBA")
    ico = extract_pe_icon(ROOT / "godot/build/windows/Epoch-Rush-Godot.exe")
    (args.output / "windows-embedded-icon.ico").write_bytes(ico)
    with Image.open(io.BytesIO(ico)) as image:
        sizes = sorted(image.ico.sizes())
        for dimensions in sizes:
            actual = image.ico.getimage(dimensions).convert("RGBA")
            difference = image_difference(actual, expected_icon)
            opaque = actual.getchannel("A").getextrema() == (255, 255)
            if not opaque or difference > 8: errors.append(f"Windows icon differs or is transparent: {dimensions}")
            rows.append({"platform":"Windows", "size":list(dimensions), "opaque":opaque, "mean_rgb_difference":difference})
        image.ico.getimage(max(sizes)).save(args.output / "windows-embedded-icon.png")
    sdk = Path(__import__("os").environ.get("ANDROID_SDK_ROOT", str(Path.home()/"AppData/Local/Android/Sdk")))
    aapt = sdk / "build-tools/35.0.0/aapt.exe"
    for package in sorted((ROOT / "godot/build/android").glob("Epoch-Rush-Godot-*.apk")):
        # aapt on Windows cannot reliably open a Unicode absolute APK path.
        badging = subprocess.run([str(aapt), "dump", "badging", package.name], cwd=package.parent,
                                 capture_output=True, check=True).stdout.decode("utf-8", errors="replace")
        name = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging)
        if not name or name.groups() != ("studio.epochrush.pixelcommand", "10", "0.7.1"):
            errors.append(package.name + ": package version/identity")
        with zipfile.ZipFile(package) as archive:
            for entry in archive.namelist():
                if not entry.startswith("res/mipmap") or not entry.endswith(("/icon.webp","/icon_foreground.webp","/icon_background.webp")): continue
                with Image.open(io.BytesIO(archive.read(entry))) as image:
                    actual = image.convert("RGBA")
                    opaque = actual.getchannel("A").getextrema() == (255, 255)
                    background = entry.endswith("/icon_background.webp")
                    foreground = entry.endswith("/icon_foreground.webp")
                    difference = image_difference(actual, expected_foreground if foreground else expected_icon) if not background else 0
                    if (not foreground and not opaque) or difference > 8:
                        errors.append(package.name + ": launcher artwork mismatch: " + entry)
                    rows.append({"platform":package.name,"resource":entry,"size":list(actual.size),"opaque":opaque,"mean_rgb_difference":difference})
                    if entry == "res/mipmap-xxxhdpi-v4/icon.webp": actual.save(args.output/(package.stem+"-launcher.png"))
            if "res/mipmap-anydpi-v26/themed_icon.xml" not in archive.namelist(): errors.append(package.name+": adaptive icon alias missing")
        rows.append({"platform":package.name,"application_id":name.group(1) if name else None,"version":"0.7.1","version_code":10})
    if not any(row["platform"].endswith("release.apk") for row in rows): errors.append("Release APK was not inspected")
    if not any(row["platform"].endswith("debug.apk") for row in rows): errors.append("Debug APK was not inspected")
    report = {"passed":not errors,"version":"0.7.1","resources":rows,"failures":errors}
    (args.output/"launcher-branding.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"passed":not errors,"checked":len(rows),"failures":errors}, ensure_ascii=False))
    raise SystemExit(bool(errors))


if __name__ == "__main__": main()
