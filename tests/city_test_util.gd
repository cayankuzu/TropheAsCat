extends RefCounted
## Helpers for the windowed tests that need a spot in the composed city (res://game/main.tscn).


## A place to stand `distance` metres in front of the building of `style` nearest to `from`, looking at
## it: {bid, position, yaw, wall, centre}, or {} when the city has no such building. The four sides are
## tried; a side that is clear of other buildings and off the streets (no parked cars or lamp posts in
## the way) is preferred.
static func stand_before(main: Node, style: int, from: Vector3, distance: float) -> Dictionary:
	var city := main.get("city") as CityLayout
	var sm := Game.structures as StructureManager
	if city == null or sm == null:
		return {}
	var lot := city.nearest_lot(style, from)
	if lot.is_empty():
		return {}
	var bid: int = lot["bid"]
	var rect := sm.building_footprint(bid)
	var c := rect.get_center()
	var fallback := {}
	for dir: Vector2 in [Vector2(0.0, 1.0), Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(-1.0, 0.0)]:
		var half := (rect.size.y if dir.y != 0.0 else rect.size.x) * 0.5
		var p := c + dir * (half + distance)
		var clear := true
		for other in sm.building_count():
			if other != bid and sm.building_footprint(other).grow(3.0).has_point(p):
				clear = false
				break
		if not clear:
			continue
		var look := Vector3(-dir.x, 0.0, -dir.y)
		var spot := {
			"bid": bid, "position": Vector3(p.x, 1.0, p.y), "yaw": atan2(-look.x, -look.z),
			"wall": Vector3(c.x + dir.x * half, 0.0, c.y + dir.y * half), "centre": Vector3(c.x, 0.0, c.y),
		}
		var road := float(TerrainStrata.ROAD_SPACING)
		var off_street := absf(p.x - roundf(p.x / road) * road) > 14.5 and absf(p.y - roundf(p.y / road) * road) > 14.5
		if off_street:
			return spot
		if fallback.is_empty():
			fallback = spot
	return fallback


## The middle of the wall of a building that faces +z, at a height: where the tests set off their blasts.
static func wall_point(bid: int, height: float) -> Vector3:
	var rect := (Game.structures as StructureManager).building_footprint(bid)
	return Vector3(rect.get_center().x, height, rect.end.y + 0.5)
