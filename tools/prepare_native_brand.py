"""Use the approved opaque knight icon and exact transparent wordmark in Godot."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / "public/brand/game-logo.png"
with Image.open(source).convert("RGBA") as wordmark:
    bounds = wordmark.getchannel("A").getbbox()
    assert bounds is not None and wordmark.getpixel((0, 0))[3] == 0
    content = wordmark.crop(bounds)
    texture = Image.new("RGBA", (content.width + 32, content.height + 32))
    texture.paste(content, (16, 16))
    destination = ROOT / "godot/assets/ui/brand/game-logo.png"
    destination.parent.mkdir(parents=True, exist_ok=True)
    texture.save(destination)
with Image.open(ROOT / "public/app-icon.png") as icon:
    assert icon.convert("RGBA").getchannel("A").getextrema() == (255, 255)
    icon.convert("RGB").resize((512, 512), Image.Resampling.LANCZOS).save(ROOT / "godot/assets/ui/pixel/app-icon.png")
manifest = {"name": "纪元急袭", "logo_master": "public/brand/game-logo.png", "logo_alpha_crop": list(bounds),
            "runtime_padding": 16, "runtime_size": list(texture.size),
            "logo_master_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "runtime_logo_sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
            "opaque_icon_sha256": hashlib.sha256((ROOT / "godot/assets/ui/pixel/app-icon.png").read_bytes()).hexdigest()}
(destination.parent / "branding.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(manifest, ensure_ascii=False))
