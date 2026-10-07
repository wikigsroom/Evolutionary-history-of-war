"""Prepare README screenshots, annotated guides and GIFs from native Godot captures."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "docs/media/v0.7.0"
NATIVE = ROOT / "output/qa/ten-eras/windows-embedded/native"
NAVY = (11, 21, 39)
PAPER = (236, 213, 161)
CYAN = (104, 213, 237)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def font(size, bold=False):
    candidates = [Path("C:/Windows/Fonts") / ("msyhbd.ttc" if bold else "msyh.ttc"),
                  Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc")]
    for path in candidates:
        if path.exists(): return ImageFont.truetype(str(path), size)
    raise RuntimeError("A CJK font is required to render bilingual diagram labels.")


def annotated(source, destination, entries, points):
    image = Image.open(source).convert("RGB")
    rows = (len(entries) + 1) // 2
    canvas = Image.new("RGB", (image.width, image.height + 40 + rows * 94), NAVY)
    canvas.paste(image, (0, 0))
    draw = ImageDraw.Draw(canvas)
    for number, (x, y) in enumerate(points, 1):
        draw.ellipse((x-16, y-16, x+16, y+16), fill=NAVY, outline=CYAN, width=3)
        draw.text((x, y), str(number), font=font(19, True), fill=CYAN, anchor="mm")
    for number, (chinese, english) in enumerate(entries, 1):
        x = 24 + ((number-1) % 2) * 628
        y = image.height + 18 + ((number-1) // 2) * 94
        draw.rounded_rectangle((x, y, x+608, y+80), radius=12, fill=(19, 36, 59), outline=(57, 90, 124), width=2)
        draw.text((x+14, y+8), f"{number}  {chinese}", font=font(20, True), fill=PAPER)
        draw.text((x+14, y+42), english, font=font(17), fill=CYAN)
    canvas.save(destination, optimize=True)


def gallery():
    names = [("石器部落", "Stone Age"), ("青铜城邦", "Bronze City-States"), ("古典帝国", "Classical Empire"),
             ("中世纪王国", "Medieval Kingdom"), ("火药列阵", "Gunpowder Lines"), ("工业战壕", "Industrial Trenches"),
             ("二战钢盔", "World War II"), ("现代机械化", "Modern Mechanized"), ("无人战术", "Unmanned Warfare"), ("轨道文明", "Orbital Civilization")]
    board = Image.new("RGB", (1600, 374), NAVY)
    draw = ImageDraw.Draw(board)
    for age, (chinese, english) in enumerate(names, 1):
        image = Image.open(NATIVE / f"age-{age:02d}-field.png").crop((0, 80, 1280, 510)).convert("RGB")
        image.thumbnail((316, 107), Image.Resampling.LANCZOS)
        x = ((age-1) % 5) * 320
        y = ((age-1) // 5) * 187
        board.paste(image, (x+2, y+3))
        draw.text((x+9, y+114), f"{age:02d} {chinese}", font=font(18, True), fill=PAPER)
        draw.text((x+9, y+146), english, font=font(15), fill=CYAN)
    board.save(MEDIA / "ten-era-gallery.jpg", quality=94)


def gif(source, start, duration, destination):
    filters = ("[0:v]fps=12,scale=768:-1:flags=lanczos,split[a][b];"
               "[a]palettegen=max_colors=192:stats_mode=diff[p];"
               "[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(start), "-t", str(duration), "-i", str(source),
                    "-filter_complex", filters, "-loop", "0", str(destination)], check=True)
    if destination.stat().st_size > 10 * 1048576:
        raise RuntimeError("README GIF exceeds the size budget: " + destination.name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", type=Path, default=ROOT / "output/qa/ten-eras/video/ten-era-showcase.mp4")
    parser.add_argument("--skip-gifs", action="store_true")
    args = parser.parse_args()
    MEDIA.mkdir(parents=True, exist_ok=True)
    for age, name in [(1, "battle-stone"), (4, "battle-medieval"), (8, "battle-modern"), (10, "battle-orbital")]:
        shutil.copyfile(NATIVE / f"age-{age:02d}-impact.png", MEDIA / (name + ".png"))
    annotated(MEDIA / "menu-home.png", MEDIA / "menu-guide.png", [
        ("出征：难度、开始与继续", "Battle: difficulty, start and resume"),
        ("战役：二十关远征", "Campaign: twenty missions"),
        ("整军：主将、专精与构筑", "Loadout: commander, specialization and build"),
        ("图鉴：十时代兵种与演练", "Codex: ten eras and same-era practice"),
        ("设置：声音、动态与全屏", "Settings: audio, motion and fullscreen"),
    ], [(635, 17), (760, 17), (885, 17), (1010, 17), (1135, 17)])
    annotated(MEDIA / "battle-modern.png", MEDIA / "battle-guide.png", [
        ("军资、交战经验与军令", "Gold, combat XP and command"),
        ("五张本时代招募兵卡", "Five recruitment cards for your era"),
        ("训练进度、等待与取消", "Training progress, blocked exits and refunds"),
        ("战鼓、烟幕与时序补给", "War drum, smoke and temporal supplies"),
        ("研究、炮塔、奇袭与进化", "Research, turrets, era strike and evolution"),
        ("指挥官技能与三种站位", "Commander skills and three stances"),
        ("小地图与镜头定位", "Minimap and camera controls"),
        ("自动交战与实体占位", "Automatic combat with body occupancy"),
    ], [(446, 36), (34, 552), (64, 680), (606, 549), (866, 551), (1240, 559), (1083, 104), (800, 265)])
    gallery()
    clips = [("medieval-battle.gif", 26.0, 6.0), ("modern-strike.gif", 58.7, 6.8), ("orbital-strike.gif", 74.5, 6.5)]
    if not args.skip_gifs:
        if not args.video.is_file(): raise FileNotFoundError("Supply a native showcase recording with --video.")
        for name, start, duration in clips: gif(args.video, start, duration, MEDIA / name)
    files = []
    for path in sorted(MEDIA.iterdir()):
        if path.suffix.lower() not in [".png", ".jpg", ".gif"]: continue
        with Image.open(path) as image:
            row = {"file": path.name, "bytes": path.stat().st_size, "sha256": digest(path), "size": list(image.size)}
            if path.suffix == ".gif":
                row["frames"] = image.n_frames
                row["durationMs"] = sum(image.seek(i) or image.info.get("duration", 0) for i in range(image.n_frames))
                assert image.n_frames > 15
            files.append(row)
    manifest = {"version": "0.7.0", "preparedAtUtc": datetime.now(timezone.utc).isoformat(),
        "source": "Native Godot 4.7.2 rendering of the v0.7.0 Windows embedded PCK; scripted era practice.",
        "annotation": "Only menu-guide, battle-guide and gallery add explanatory labels to original game captures.",
        "gifs": {"fps": 12, "width": 768, "loop": True, "audio": False, "clips": clips}, "files": files}
    executable = ROOT / "godot/build/windows/Epoch-Rush-Godot.exe"
    if executable.exists(): manifest["windowsEmbeddedPckSha256"] = digest(executable)
    if args.video.exists(): manifest["sourceVideoSha256"] = digest(args.video)
    (MEDIA / "media-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"files": len(files), "gifs": len(clips), "totalMiB": round(sum(row["bytes"] for row in files)/1048576, 2)}, ensure_ascii=False))


if __name__ == "__main__": main()
