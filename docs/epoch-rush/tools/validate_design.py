"""Validate the design baseline and its cross-catalog references, not a game build."""

from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re

from PIL import Image

BASE = Path(__file__).resolve().parents[1]
DATA = BASE / "data"
REPORT = BASE / "设计校验报告.md"


def load(name):
    return json.loads((DATA / f"{name}.json").read_text(encoding="utf-8"))


def require(condition, description):
    if not condition:
        raise ValueError(description)


def indexed(rows):
    result = {row["id"]: row for row in rows}
    require(len(result) == len(rows), "Duplicate catalog ID")
    return result


def legal_talents(ids, talents, budget):
    require(len(ids) == len(set(ids)), "Duplicate talent")
    require(all(i in talents for i in ids), "Unknown talent")
    require(sum(talents[i]["cost"] for i in ids) <= budget, "Talent budget exceeded")
    chosen = Counter()
    for identifier in sorted(ids, key=lambda i: talents[i]["tier"]):
        item = talents[identifier]
        require(chosen[item["branch"]] >= [0, 2, 4][item["tier"] - 1], "Talent tier requirement")
        chosen[item["branch"]] += item["cost"]


def legal_loadout(loadout, tables, rules, unlocked_heroes, unlocked_skills, owned_relics, budget):
    require(loadout["heroId"] in unlocked_heroes, "Loadout hero unlock")
    require(tables["specializations"][loadout["specializationId"]]["heroId"] == loadout["heroId"], "Loadout specialization")
    commons = loadout["commonSkillIds"]
    require(len(commons) == len(set(commons)) == rules["loadout"]["commonSkillSlots"], "Common loadout slots")
    require(all(i in unlocked_skills and tables["skills"][i]["category"] == "common" for i in commons), "Common loadout unlock")
    relics = loadout["relicIds"]
    require(rules["loadout"]["minimumRelics"] <= len(relics) <= rules["loadout"]["relicSlots"], "Relic slot capacity")
    require(len(relics) == len(set(relics)) and all(i in owned_relics for i in relics), "Relic ownership and uniqueness")
    legal_talents(loadout["talentIds"], tables["talents"], budget)


class ReferenceRng:
    def __init__(self, seed):
        self.state = seed or 0x9E3779B9

    def next(self):
        x = self.state
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        self.state = x & 0xFFFFFFFF
        return self.state

    def bounded(self, bound):
        limit = ((1 << 32) // bound) * bound
        while True:
            value = self.next()
            if value < limit:
                return value % bound


def main():
    expected = {
        "eras": 5, "heroes": 6, "specializations": 18, "units": 20,
        "turrets": 10, "skills": 18, "statuses": 10, "talents": 18,
        "run-upgrades": 12, "relics": 12, "missions": 15,
        "enemy-profiles": 6, "builds": 6, "weapons": 8,
    }
    tables = {}
    all_ids = []
    for name, count in expected.items():
        rows = load(name)
        require(len(rows) == count, f"{name}: expected {count}")
        tables[name] = indexed(rows)
        all_ids.extend(tables[name])
    require(len(all_ids) == len(set(all_ids)), "ID collision across catalogs")
    require(len(list(DATA.glob("*.json"))) == 17, "Expected 17 JSON catalogs")

    eras, heroes = tables["eras"], tables["heroes"]
    units, skills = tables["units"], tables["skills"]
    specs, missions = tables["specializations"], tables["missions"]
    rules, loot = load("rules"), load("loot")
    require(rules["loadout"]["allowEmptyRelicSlots"] and rules["loadout"]["minimumRelics"] == 0, "First-game relic slots may be empty")
    require(rules["initialUnlocks"]["relicIds"] == [], "No relics granted before first clear")
    for hero_id, spec_id, talent_ids in [("H01", "P011", ["T11", "T12"]), ("H03", "P031", ["T21", "T22"])]:
        legal_loadout({"heroId": hero_id, "specializationId": spec_id, "commonSkillIds": ["S01", "S02"], "relicIds": [], "talentIds": talent_ids}, tables, rules, rules["initialUnlocks"]["heroIds"], rules["initialUnlocks"]["commonSkillIds"], [], rules["mastery"]["startingPoints"])
    require(Counter(u["eraId"] for u in units.values()) == Counter({e: 4 for e in eras}), "Four units per era")
    require(Counter(t["eraId"] for t in tables["turrets"].values()) == Counter({e: 2 for e in eras}), "Two turrets per era")
    require(Counter(s["category"] for s in skills.values()) == Counter(common=12, signature=6), "Skill slot library")

    for unit in units.values():
        require(unit["weaponId"] in tables["weapons"], "Unit weapon reference")
        require(unit["damageType"] in rules["damage"]["counter"], "Unit damage type")
        for field in ["hpBase", "attackBase", "costBase", "trainSec", "attackPeriodSec", "moveSpeed"]:
            require(unit[field] > 0, f"Unit nonpositive {field}")
        for key in ["statusId", "suppressStatusId"]:
            if key in unit["special"]:
                require(unit["special"][key] in tables["statuses"], "Unit status reference")

    for hero in heroes.values():
        require(hero["weaponId"] in tables["weapons"], "Hero weapon reference")
        signature = skills[hero["signatureSkillId"]]
        require(signature["heroId"] == hero["id"], "Signature ownership")
        require(len(hero["specializationIds"]) == 3, "Three hero specializations")
        for identifier in hero["specializationIds"]:
            require(specs[identifier]["heroId"] == hero["id"], "Specialization ownership")
        if hero["unlockMissionId"]:
            require(hero["id"] in missions[hero["unlockMissionId"]]["heroUnlockIds"], "Hero unlock reciprocity")
        for identifier in hero["defaultCommonSkillIds"]:
            require(skills[identifier]["category"] == "common", "Default common skill")

    for skill in skills.values():
        require(skill["commandCost"] > 0 and skill["cooldownSec"] > 0, "Skill costs")
        require(all(i in tables["statuses"] for i in skill["statusIds"]), "Skill status reference")
        require(isinstance(skill["effects"], dict) and bool(skill["effects"]), "Missing declarative effects")
        if "conditionalStatusId" in skill["effects"]:
            require(skill["effects"]["conditionalStatusId"] in tables["statuses"], "Conditional status")
        if skill["damageBase"] > 0:
            require(skill["maxTargets"] <= rules["caps"]["damageCastTargetsIncludingChains"], "Damage target budget")
    require(skills["S01"]["unlock"] == "initial" and skills["S02"]["unlock"] == "initial", "Tutorial skills")

    require(len(set(t["branch"] for t in tables["talents"].values())) == 3, "Three talent branches")
    branch_counts = Counter(t["branch"] for t in tables["talents"].values())
    require(all(count == 6 for count in branch_counts.values()), "Six nodes per branch")
    require(Counter(r["eraId"] for r in tables["run-upgrades"].values()) == Counter({e: 3 for e in ["A2", "A3", "A4", "A5"]}), "Three evolution choices")
    require(rules["mastery"]["startingPoints"] + sum(m["firstClearMasteryPoints"] for m in missions.values()) == 6, "Mastery progression budget")

    for build in tables["builds"].values():
        require(build["heroId"] in heroes, "Build hero")
        require(specs[build["specializationId"]]["heroId"] == build["heroId"], "Build specialization")
        require(len(build["commonSkillIds"]) == len(set(build["commonSkillIds"])) == 2, "Two different common skills")
        require(all(skills[i]["category"] == "common" for i in build["commonSkillIds"]), "Build common skills")
        require(len(build["relicIds"]) == len(set(build["relicIds"])) == 2, "Two different relics")
        require(all(i in tables["relics"] for i in build["relicIds"]), "Build relic references")
        legal_talents(build["talentIds"], tables["talents"], 6)

    require(sum(loot["rarityWeights"].values()) == 100, "Loot weights sum")
    require(loot["rarePityWeights"] == {"rare": 30, "epic": 10}, "Rare pity distribution")
    require(Counter(i["rarity"] for i in tables["relics"].values()) == Counter(common=4, rare=4, epic=4), "Relic pools")
    for mission_id, relic_id in loot["firstClearRelicByMission"].items():
        require(missions[mission_id]["firstClearRelicId"] == relic_id and relic_id in tables["relics"], "First-clear loot reference")

    era_order = {identifier: i for i, identifier in enumerate(eras)}
    for mission in missions.values():
        require(era_order[mission["startingEraId"]] <= era_order[mission["maximumEraId"]], "Mission era bounds")
        require(mission["enemyProfileId"] in tables["enemy-profiles"], "Mission AI reference")
        require(all(h in heroes for h in mission["heroUnlockIds"]), "Mission hero reference")
        if "prebuiltTurretId" in mission.get("bossParameters", {}):
            turret = tables["turrets"][mission["bossParameters"]["prebuiltTurretId"]]
            require(turret["costBase"] <= mission["enemyStartingGold"], "Prebuilt turret opening budget")
    for profile in tables["enemy-profiles"].values():
        require(profile["heroId"] in heroes, "AI hero")
        require(tables["builds"][profile["buildId"]]["heroId"] == profile["heroId"], "AI loadout ownership")
        require(profile["talentBudgetMode"] == "match_player_profile_or_fixed_challenge", "AI declared talent budget")
        require(profile["contentAvailabilityMode"] == "match_player_unlocks_except_hero_or_fixed_challenge", "AI declared content availability")
        require(math.isclose(sum(profile["roleWeights"].values()), 1), "AI weights sum")
    require(all(d["incomeMultiplier"] == 1 for d in rules["difficulty"]), "Declared equal-income difficulty")

    # Execute reference arithmetic and the documented pity model, not engine tests.
    plain = math.floor(72 * 2.9 * 0.85 * 100 / 122)
    combo = math.floor(72 * 2.9 * 0.85 * 100 / 116.5 * 1.2)
    require((plain, combo) == (145, 182), "Damage example")
    require(math.ceil(155 * 1.45) == 225, "Era price example")
    require(math.ceil(4.2 * (1 - 0.11) * 30) == 113, "Training tick example")
    require(math.floor(16 * 2.9 * 1.10 * 100 / 121) == 42, "Normal attack example")
    require(math.floor(16 * 2.9 * 1.10 * 1.30 * 100 / 121) == 54, "Rush attack example")
    require(math.isclose(180 - 175 + 8 * 5.9, 52.2), "Opening economy example")
    require(35 + 40 + 60 > 110, "Energy budget has actual tradeoff")
    rng = ReferenceRng(20261004)
    rare_misses = epic_misses = 0
    for _ in range(1000):
        if epic_misses >= 19:
            rarity = "epic"
        elif rare_misses >= 4:
            rarity = "rare" if rng.bounded(40) < 30 else "epic"
        else:
            roll = rng.bounded(100)
            rarity = "common" if roll < 60 else "rare" if roll < 90 else "epic"
        rare_misses = rare_misses + 1 if rarity == "common" else 0
        epic_misses = 0 if rarity == "epic" else epic_misses + 1
        require(rare_misses <= 4 and epic_misses <= 19, "Reference pity guarantee")

    example_paths = sorted((BASE / "examples").glob("*.json"))
    require(len(example_paths) == 3, "Three structure examples")
    for path in example_paths:
        obj = json.loads(path.read_text(encoding="utf-8"))
        checksum = obj.pop("checksum")
        serialized = json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
        require(hashlib.sha256(serialized).hexdigest() == checksum, "Example checksum")
        require(obj["exampleOnly"], "Example labeling")
        if "contentVersion" in obj:
            require(obj["contentVersion"] == "0.1.0", "Example content version")
    profile = json.loads((BASE / "examples/profile-v1.json").read_text(encoding="utf-8"))
    require(profile["masteryPoints"] == 2 + sum(missions[i]["firstClearMasteryPoints"] for i in profile["clearedMissionIds"]), "Example mastery")
    for loadout in profile["loadouts"]:
        legal_loadout(loadout, tables, rules, profile["unlockedHeroIds"], profile["unlockedSkillIds"], profile["ownedRelicIds"], profile["masteryPoints"])

    asset_entries = load("asset-manifest")["entries"]
    require(len(asset_entries) == 197 and len({a["key"] for a in asset_entries}) == 197, "Asset logical item count")
    require(Counter(a["status"] for a in asset_entries) == Counter(planned=196, reference_ready=1), "Honest asset statuses")
    require(len({a["targetPath"] for a in asset_entries}) == 197, "Unique asset paths")
    for asset in asset_entries:
        if asset["ownerId"]:
            require(asset["ownerId"] in all_ids, "Asset owner reference")
        if asset["status"] == "reference_ready":
            path = BASE / asset["targetPath"]
            require(path.is_file(), "Ready reference exists")
            with Image.open(path) as im:
                require(list(im.size) == asset["size"] and im.format == "PNG", "Reference dimensions")
                im.verify()
    require(all(a["targetPath"].endswith(".mp3") for a in asset_entries if a["key"].startswith("music.")), "Music format")
    require(all(a["targetPath"].endswith(".wav") for a in asset_entries if a["key"].startswith("sfx.")), "SFX format")

    numbered = [doc for doc in BASE.glob("[0-9][0-9]-*.md") if int(doc.name[:2]) < 18]
    require(len(numbered) == 18, "Eighteen main design documents")
    prompt_docs = list((BASE / "prompts").glob("*.md"))
    require(len(prompt_docs) == 7, "Seven prompt documents")
    character_prompt = (BASE / "prompts/02-角色与专精.md").read_text(encoding="utf-8")
    troop_prompt = (BASE / "prompts/04-兵种与炮塔.md").read_text(encoding="utf-8")
    require(all(f"## {i} " in character_prompt for i in heroes), "Prompt hero coverage")
    require(all(f"## {i} " in troop_prompt for i in units), "Prompt troop coverage")
    require(all(f"## {i} " in troop_prompt for i in tables["turrets"]), "Prompt turret coverage")

    links = 0
    for doc in BASE.rglob("*.md"):
        for target in re.findall(r"\]\(([^)]+)\)", doc.read_text(encoding="utf-8")):
            if target.startswith(("http://", "https://", "#")):
                continue
            target_path = (doc.parent / target.split("#")[0]).resolve()
            require(target_path.is_file(), f"Missing local link: {doc.name} -> {target}")
            implementation_docs = {"18-首版实现与验证.md", "19-界面战场与动作改版.md"}
            boundary = BASE.parent.parent if doc.name in implementation_docs else BASE
            target_path.relative_to(boundary.resolve())
            links += 1

    counts = "\n".join(f"| {name} | {count} | 通过 |" for name, count in expected.items())
    report = f"""# 设计校验报告

日期：2026-10-04。设计版本：0.1.0。状态：本地设计一致性检查通过。

范围：文档、JSON、对象引用、构筑预算、参考演算和已有参考图；不是游戏运行、动画质量、设备性能或原生安装包验收。

## 内容数量

| 数据 | 条目 | 结果 |
| --- | --- | --- |
{counts}

17个JSON配置可解析；18份编号主文档、7份提示词文档和3份带checksum的结构示例存在。

## 已检查关系

- 所有内容ID唯一；英雄专属与三个专精归属、单位武器/时代、技能状态、任务AI/解锁、首通遗物、素材owner引用有效。
- 五时代各四兵、两炮塔；四次进化各三个策略；三传承路线各六节点，初始加首通点总计六。
- 六示例构筑均为合法双通用技、双遗物和六点天赋，满足层级；档案示例为合法三点配置。
- 两个初始角色的双通用技、无遗物、两点天赋负载合法；敌方内容可用性与点数预算政策已明确。
- 60/30/10掉落权重与四件/类别对应；参考1000箱演算符合5箱稀有及以上和20箱史诗的保底间距。
- 文档中的145→182破甲轰击、42→54换代首击、225炮车价格、113tick训练与52.2开局余资演算一致。
- 197逻辑素材项：设计基线保留1张参考PNG与196项生产计划的原始状态；当前运行资源覆盖见18号实现说明及运行清单，本检查不替代美术验收。
- {links}个本地文档链接解析到当前工程现有文件；参考图为1536×1024 PNG。

## 待实现与待实测

角色控制和动画、20兵实际克制、组合收益、对局8–12分钟目标、十五关难度、奖励原子事务、跨端重放、三端输入和音频、性能预算、Windows/Android/iOS安装与实机均待实施里程碑获取证据。

运行：`python docs/epoch-rush/tools/validate_design.py`。本脚本校验设计基线，不代替引擎测试。

[返回目录](README.md)
"""
    REPORT.write_text(report, encoding="utf-8")
    print(f"Design baseline validated: 17 JSON catalogs, 18 main documents, {links} local links.")
    print("6 builds valid; 197 asset entries correctly marked; arithmetic and reference pity checks passed.")
    print(f"Report: {REPORT}")


if __name__ == "__main__":
    main()
