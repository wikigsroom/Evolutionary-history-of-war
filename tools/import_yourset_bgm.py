"""Import the owner's Yourset tracks with native FFmpeg; never modify the MP3s."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TRACKS = [
    ("yourset-01", "Yourset - 黑历史 Infetar A1.mp3", "黑历史 Infetar A1"),
    ("yourset-02", "Yourset - Sirirankok 修复版.mp3", "Sirirankok 修复版"),
    ("yourset-03", "Yourset - Loth.mp3", "Loth"),
    ("yourset-04", "Yourset - Be A Single Dog Again.mp3", "Be A Single Dog Again"),
]
TARGET_LUFS = -19
TARGET_TP = -2


def run(arguments):
    return subprocess.run(arguments, capture_output=True, check=True)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def probe(path):
    return json.loads(run(["ffprobe", "-v", "error", "-show_format", "-show_streams", "-of", "json", str(path)]).stdout)


def measure(path):
    output = run(["ffmpeg", "-hide_banner", "-nostdin", "-i", str(path), "-map", "0:a:0", "-af",
                  f"loudnorm=I={TARGET_LUFS}:TP={TARGET_TP}:LRA=11:print_format=json", "-f", "null", "-"])
    return json.loads(re.findall(r'\{\s*"input_i".*?\}', output.stderr.decode("utf-8", errors="replace"), re.S)[-1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("C:/Users/carzy/Downloads/yourset-old"))
    parser.add_argument("--report", type=Path, default=ROOT / "output/qa/v0.7.1/audio/yourset-import.json")
    args = parser.parse_args()
    assets = ROOT / "godot/assets/audio"
    shared = ROOT / "public/assets/audio"
    for _, filename, _ in TRACKS:
        if not (args.source / filename).is_file(): raise FileNotFoundError(filename)
    catalog = json.loads((assets / "catalog.json").read_text(encoding="utf-8"))
    rows = []
    for key, filename, title in TRACKS:
        source = args.source / filename
        original_hash = digest(source)
        source_probe = probe(source)
        source_loudness = measure(source)
        normalization = (f"loudnorm=I={TARGET_LUFS}:TP={TARGET_TP}:LRA=11:"
                         f"measured_I={source_loudness['input_i']}:measured_TP={source_loudness['input_tp']}:"
                         f"measured_LRA={source_loudness['input_lra']}:measured_thresh={source_loudness['input_thresh']}:"
                         f"offset={source_loudness['target_offset']}:linear=true")
        destination = assets / "music" / (key + ".ogg")
        destination.parent.mkdir(parents=True, exist_ok=True)
        run(["ffmpeg", "-v", "error", "-nostdin", "-y", "-i", str(source), "-map", "0:a:0", "-vn",
             "-map_metadata", "-1", "-af", normalization, "-ar", "48000", "-ac", "2", "-c:a", "libvorbis", "-q:a", "5",
             "-metadata", "artist=Yourset", "-metadata", "title=" + title, str(destination)])
        encoded = probe(destination)
        mastered = measure(destination)
        duration = float(encoded["format"]["duration"])
        source_duration = float(source_probe["format"]["duration"])
        audio_stream = next(stream for stream in encoded["streams"] if stream["codec_type"] == "audio")
        assert audio_stream["sample_rate"] == "48000" and audio_stream["channels"] == 2
        assert abs(duration - source_duration) < .1, "Track was truncated"
        assert abs(float(mastered["input_i"]) - TARGET_LUFS) < 1, "Loudness is outside target"
        assert float(mastered["input_tp"]) < -1, "Encoded track exceeds the true-peak limit"
        assert digest(source) == original_hash, "Original source must remain unchanged"
        entry = {"path": "res://assets/audio/music/" + key + ".ogg", "loop": False, "kind": "playlist_bgm",
                 "title": title, "artist": "Yourset", "license": "user-provided", "source_filename": filename,
                 "source_sha256": original_hash, "source_duration": source_duration, "duration": duration,
                 "sample_rate": 48000, "channels": 2, "target_lufs": TARGET_LUFS, "sha256": digest(destination),
                 "source_loudness": source_loudness, "mastered_loudness": mastered}
        catalog["music"][key] = entry
        shared.joinpath("music").mkdir(parents=True, exist_ok=True)
        shutil.copyfile(destination, shared / "music" / destination.name)
        rows.append({"id": key, **entry, "bytes": destination.stat().st_size})
        print(f"{key}: {duration:.3f}s, {mastered['input_i']} LUFS, {mastered['input_tp']} dBTP", flush=True)
    catalog["version"] = 3
    catalog["bgm_playlist"] = [key for key, _, _ in TRACKS]
    catalog["playlist_policy"] = {"shuffle": "each track once per bag", "avoid_adjacent_repeat": True,
                                  "crossfade_seconds": 2, "shared_across_menu_and_eras": True,
                                  "random_generator": "audio-private; independent of simulation"}
    for directory in [assets, shared]:
        (directory / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    credits = (assets / "Audio-CREDITS.txt").read_text(encoding="utf-8").split("\nYourset playlist / 用户提供曲目")[0].rstrip()
    credits = re.sub(r"^(?:Legacy recordings and SFX only — )*CC0-1.0 public-domain dedication:",
                     "Legacy recordings and SFX only — CC0-1.0 public-domain dedication:", credits, count=1, flags=re.M)
    credits += ("\n\nYourset playlist / 用户提供曲目 (v0.7.1)\n"
                "Artist: Yourset. Sources supplied by the project owner; separate from the CC0 recordings above.\n"
                "本次四首曲目由项目所有者指定提供；不属于上方 CC0 素材，不授予独立素材再分发许可。\n"
                "Full-length stereo 48 kHz Ogg Vorbis; two-pass -19 LUFS / -2 dBTP mastering.\n")
    for row in rows:
        credits += f"\n{row['source_filename']}\nSource SHA-256: {row['source_sha256']}\nOgg SHA-256: {row['sha256']}\n"
    for directory in [assets, shared]: (directory / "Audio-CREDITS.txt").write_text(credits, encoding="utf-8")
    report = {"passed": True, "originals_unchanged": True, "full_length": True, "tracks": rows,
              "policy": catalog["playlist_policy"]}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__": main()
