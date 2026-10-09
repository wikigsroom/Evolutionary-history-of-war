"""Export the approved wordmark as verified PNGs for store submission."""
from pathlib import Path
import argparse
import hashlib
import json

from PIL import Image
from PIL.PngImagePlugin import PngInfo

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "public/brand/game-logo.png"
DEFAULT_OUTPUT = ROOT / "docs/media/logo-upload"
MAX_BYTES = 4_000_000
EXPORTS = [(2880, 960, 2), (1440, 480, 1)]


def export_logo(output: Path) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    with Image.open(SOURCE) as source:
        if source.format != "PNG":
            raise ValueError("The approved source must be PNG.")
        master = source.convert("RGBA")
    bounds = master.getchannel("A").getbbox()
    if bounds is None or master.getchannel("A").getextrema()[0] != 0:
        raise ValueError("The wordmark must have content and a transparent background.")
    content = master.crop(bounds)
    rows = []
    for width, height, scale in EXPORTS:
        ink = content.resize(
            (content.width * scale, content.height * scale), Image.Resampling.NEAREST
        )
        if ink.width >= width or ink.height >= height:
            raise ValueError("The export canvas must leave room around the whole wordmark.")
        offset = ((width - ink.width) // 2, (height - ink.height) // 2)
        canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        # Direct paste preserves every RGBA pixel, including the existing outline.
        canvas.paste(ink, offset)
        destination = output / f"game-logo-transparent-{width}x{height}.png"
        metadata = PngInfo()
        metadata.add(b"sRGB", b"\x00")
        canvas.save(destination, format="PNG", optimize=True, compress_level=9,
                    pnginfo=metadata)
        with Image.open(destination) as encoded:
            encoded.verify()
        with Image.open(destination) as encoded:
            encoded.load()
            alpha = encoded.getchannel("A")
            if encoded.format != "PNG" or encoded.mode != "RGBA":
                raise ValueError("The export must be a transparent RGBA PNG.")
            if not (encoded.width >= 1280 or encoded.height >= 720):
                raise ValueError("Neither minimum dimension is satisfied.")
            if destination.stat().st_size > MAX_BYTES:
                raise ValueError("The PNG exceeds the 4 MB upload limit.")
            if encoded.tobytes() != canvas.tobytes():
                raise ValueError("PNG encoding changed the approved artwork.")
            if alpha.getextrema() != (0, 255):
                raise ValueError("True transparent background is missing.")
            corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
            if any(alpha.getpixel(corner) != 0 for corner in corners):
                raise ValueError("The logo touches a canvas corner.")
            rows.append({
                "file": destination.name,
                "format": encoded.format,
                "mode": encoded.mode,
                "size": list(encoded.size),
                "bytes": destination.stat().st_size,
                "integer_scale": scale,
                "content_bounds": list(alpha.getbbox()),
                "alpha_range": list(alpha.getextrema()),
                "png_pixels_match_expected": True,
                "dimension_rule_passed": True,
                "file_size_rule_passed": True,
                "sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
            })
    report = {
        "game_name": "纪元急袭",
        "source": SOURCE.relative_to(ROOT).as_posix(),
        "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "source_content_bounds": list(bounds),
        "requirements": {
            "format": "PNG",
            "max_bytes": MAX_BYTES,
            "minimum_dimensions": "width >= 1280 OR height >= 720",
            "background": "transparent RGBA",
            "visible_text": ["纪元急袭"],
        },
        "resampling": "nearest neighbor at integer scale; lossless PNG",
        "files": rows,
    }
    (output / "logo-upload-verification.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    print(json.dumps(export_logo(args.output), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
