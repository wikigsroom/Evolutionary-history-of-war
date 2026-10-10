class_name BattlePerspective
extends RefCounted

# All rendering uses own side 0. Entity IDs stay in server space.
const COORDINATES = ["x", "previousX", "toX", "fromX", "startX", "targetX", "originX", "from", "to", "destination"]
const DIRECTIONS = ["facing", "direction", "hitDirection", "vx"]

static func project(value, seat: int):
	if seat == 0: return value.duplicate(true) if value is Dictionary or value is Array else value
	if value is Array:
		var result = []
		for child in value: result.append(project(child, seat))
		return result
	if not value is Dictionary: return value
	var result = {}
	for key in value:
		var item = value[key]
		if key in COORDINATES and (item is float or item is int): result[key] = 1600.0 - float(item)
		elif key in DIRECTIONS and (item is float or item is int): result[key] = -float(item)
		elif key == "side" and int(item) in [0, 1]: result[key] = 1 - int(item)
		elif key == "winner" and int(item) in [0, 1]: result[key] = 1 - int(item)
		else: result[key] = project(item, seat)
	return result

static func server_action(action: Dictionary, seat: int) -> Dictionary:
	var result = action.duplicate(true)
	result.erase("side")
	if seat == 1 and result.has("x"): result["x"] = 1600.0 - float(result["x"])
	return result
