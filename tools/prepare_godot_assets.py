"""Copy the approved production assets and data into the native Godot project."""
from pathlib import Path
import json
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
GODOT = ROOT / "godot"
OUT = ROOT / "output/qa/godot-polish"
OUT.mkdir(parents=True, exist_ok=True)
backup = OUT / "baseline-source.zip"
if not backup.exists():
    with zipfile.ZipFile(backup, "w", zipfile.ZIP_DEFLATED) as archive:
        for folder in ["scripts", "scenes", "qa"]:
            for path in (GODOT / folder).rglob("*"):
                if path.is_file() and path.suffix in [".gd", ".tscn", ".uid"]:
                    archive.write(path, path.relative_to(GODOT))
        archive.write(GODOT / "project.godot", "project.godot")

for domain in ["audio", "base", "characters/animations", "characters/turrets", "fx", "ui"]:
    source = ROOT / "public/assets" / domain
    if source.exists():
        shutil.copytree(source, GODOT / "assets" / domain, dirs_exist_ok=True)
for path in (ROOT / "public/fonts").glob("*"):
    if path.is_file():
        shutil.copy2(path, GODOT / "assets/fonts" / path.name)

data_dir = GODOT / "assets/data"
data_dir.mkdir(parents=True, exist_ok=True)
tables = ["eras", "heroes", "units", "skills", "specializations", "talents", "relics",
          "run-upgrades", "turrets", "weapons", "missions", "builds", "enemy-profiles", "rules", "loot", "statuses"]
for table in tables:
    shutil.copy2(ROOT / "docs/epoch-rush/data" / (table + ".json"), data_dir / (table + ".json"))
raw = json.loads((ROOT / "src/content/animation-manifest.json").read_text(encoding="utf-8"))
keys = ["path", "enemyPath", "frameWidth", "frameHeight", "bodyHeight", "anchor", "clips",
        "muzzle", "hit", "bodyRadius", "review", "sourceSha256", "atlasSha256"]
actors = {name: {key: value for key, value in row.items() if key in keys}
          for name, row in raw["actors"].items() if row.get("review") == "accepted"}
(data_dir / "animations.json").write_text(json.dumps(actors, ensure_ascii=False, indent=2), encoding="utf-8")
background = ROOT / "output/imagegen/epoch-rush/godot-polish/night-frontier.png"
if background.exists():
    target = GODOT / "assets/environment/night-frontier.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(background, target)
print(f"Prepared {len(tables)} data tables and {len(actors)} accepted actors; baseline preserved.")
