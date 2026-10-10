"""Create a reproducible contract for shared simulation code, metadata and PvP rules."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "godot"
RULESET = {
    "id": "pvp-classic-v1", "tick_hz": 30, "state_hz": 10,
    "starting_gold": 240, "human_economy_multiplier": 1.0,
    "hero_pool": [f"H{i:02}" for i in range(1, 7)], "mastery_points": 6,
    "common_skill_slots": 2, "relic_slots": 2, "random_damage_events": False,
    "capital_full_heal_on_evolution": True, "maximum_match_ticks": 72000,
}


def main():
    files = {}
    for path in sorted((PROJECT / "assets/data").glob("*.json")):
        if path.name == "online-manifest.json":
            continue
        files[path.relative_to(PROJECT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    for name in ["game_model.gd", "game_data.gd", "epoch_combat.gd", "epoch_skills.gd", "epoch_environment.gd", "epoch_snapshot_migration.gd"]:
        path = PROJECT / "scripts" / name
        files[path.relative_to(PROJECT).as_posix()] = hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
    for path in sorted((PROJECT / "server").glob("*.gd")):
        files[path.relative_to(PROJECT).as_posix()] = hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
    canonical = lambda value: json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    contract = {"engine": "Godot 4.7.2 ed1daf0bf", "files": files, "ruleset": RULESET}
    result = {"protocol_version": "1.0", "ruleset_id": RULESET["id"], "ruleset_hash": hashlib.sha256(canonical(RULESET)).hexdigest(),
              "simulation_hash": hashlib.sha256(canonical(contract)).hexdigest(), **contract}
    output = PROJECT / "assets/data/online-manifest.json"
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Simulation manifest:", result["simulation_hash"])


if __name__ == "__main__":
    main()
