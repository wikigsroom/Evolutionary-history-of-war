extends RefCounted

const PRIVATE_EVENTS = ["queue", "cancel", "research", "error"]

static func make(model, seat: int, events: Array) -> Dictionary:
	var enemy = model.sides[1 - seat]
	var public_enemy = {"eraId": enemy["eraId"], "loadout": {"heroId": enemy["loadout"]["heroId"], "specializationId": enemy["loadout"]["specializationId"], "commonSkillIds": [], "relicIds": [], "talentIds": []},
		"stance": enemy["stance"], "turrets": enemy["turrets"].duplicate(true), "kills": enemy["kills"]}
	var filtered = []
	for event in events:
		if int(event.get("side", -1)) != seat and (event["type"] in PRIVATE_EVENTS or (event["type"] == "item" and event.get("data", {}).get("itemId") == "chrono-crate")): continue
		filtered.append(event.duplicate(true))
	return {"seat": seat, "tick": model.tick, "winner": model.winner,
		"own": model.sides[seat].duplicate(true), "enemy": public_enemy,
		"entities": model.entities.duplicate(true), "projectiles": model.projectiles.duplicate(true),
		"fields": model.fields.duplicate(true), "cast_targets": model.cast_targets.duplicate(true),
		"scene": model.environment.scene.duplicate(true), "events": filtered, "event_cursor": model.next_id - 1}
