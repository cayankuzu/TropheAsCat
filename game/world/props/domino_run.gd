class_name DominoRun
extends Node3D
## The Owner's dominoes: a run of giant tiles down the avenue in front of the spot where Trophe lands.
## One swat at the first tile and the whole run goes over, tile after tile; the last one lands on a
## stack of fuel drums in front of a truck. The first minute of the game should hold a chain reaction
## that a single paw can start.
##
## A tile is an ordinary BreakableProp (it can be blown apart, burnt or thrown about like any other
## prop). This node only lays the run, keeps its tiles awake together (a chain must not run into a
## tile that is still parked) and gives each falling tile its consequences: a step in the chain
## counter, a clack, and a blow to whatever it lands on.

const TILE := Vector3(1.1, 2.2, 0.3)      ## Width, height, thickness (metres).
const SPACING := 1.25
const TILE_DEF := {"material": &"tile", "mass": 140.0, "hp": 30000.0, "solid": 0.9}
const WAKE_DISTANCE := 80.0
const SLEEP_DISTANCE := 115.0
const FALLEN_UP := 0.6        ## The tile counts as down when its up axis has sunk this far (53 degrees over).
## Tiles are slick: with ordinary friction a falling tile sticks to the face of the next one and the
## run crawls.
const FRICTION := 0.25
const LAND_ENERGY := 5000.0   ## Joules a falling tile delivers to what it lands on.
const LAND_IMPULSE := 300.0
const PIPS := [[6, 6], [6, 5], [5, 5], [4, 2], [3, 1], [2, 2], [6, 1], [5, 3], [4, 4], [1, 1], [3, 3], [6, 3]]
const SPOTS := {0: [], 1: [4], 2: [0, 8], 3: [0, 4, 8], 4: [0, 2, 6, 8], 5: [0, 2, 4, 6, 8], 6: [0, 2, 3, 5, 6, 8]}
const IVORY := Color(0.95, 0.93, 0.85)
const INK := Color(0.07, 0.07, 0.09)
const FACE_PX := 96

var tiles: Array[BreakableProp] = []
var fallen := 0

var _down := {}            # instance id of a tile -> true once it has fallen
var _awake := false
var _check_in := 0.0
var _centre := Vector3.ZERO
var _radius := 0.0
var _body_mesh: BoxMesh
var _face_mesh: QuadMesh
var _faces: Array[StandardMaterial3D] = []
var _probe := SphereShape3D.new()
var _slick := PhysicsMaterial.new()


func _init() -> void:
	_probe.radius = 0.55
	Timeline.rewind_stopped.connect(_after_rewind)
	_slick.friction = FRICTION
	_body_mesh = BoxMesh.new()
	_body_mesh.size = TILE
	var body := StandardMaterial3D.new()
	body.albedo_color = IVORY
	body.roughness = 0.28
	body.metallic_specular = 0.6
	_body_mesh.material = body
	_face_mesh = QuadMesh.new()
	_face_mesh.size = Vector2(TILE.x * 0.92, TILE.y * 0.95)
	for pair: Array in PIPS:
		var m := StandardMaterial3D.new()
		m.albedo_texture = _face_texture(pair[0], pair[1])
		m.roughness = 0.28
		m.metallic_specular = 0.6
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_faces.append(m)


## Lays `count` tiles from `from` along `heading` (flat, unit length), swaying `sway` metres to either
## side on the way. Returns where the last tile stands.
func lay(from: Vector3, heading: Vector3, count: int, sway: float = 0.0) -> Vector3:
	var side := Vector3.UP.cross(heading)
	var length := maxf(SPACING * (count - 1), 1.0)
	var last := from
	for i in count:
		var s := SPACING * i
		var off := sway * sin(s / length * TAU)
		var slope := sway * cos(s / length * TAU) * TAU / length
		var tangent := (heading + side * slope).normalized()
		last = from + heading * s + side * off
		_add_tile(last, tangent, tiles.size())
	_centre = Vector3.ZERO
	for t in tiles:
		_centre += t.global_position
	_centre /= maxf(tiles.size(), 1.0)
	_radius = 0.0
	for t in tiles:
		_radius = maxf(_radius, t.global_position.distance_to(_centre))
	return last


## The end of the run: fuel drums where the last tile lands, gas bottles among them and a truck across
## the road behind, with a car at each curb if nobody happens to be parked there.
func add_finale(dressing: StreetDressing, last_tile: Vector3, heading: Vector3) -> void:
	var side := Vector3.UP.cross(heading)
	var yaw := atan2(heading.x, heading.z)
	for o: Vector2 in [Vector2(0.0, 2.0), Vector2(-0.85, 2.7), Vector2(0.85, 2.7), Vector2(0.0, 3.4), Vector2(-1.7, 3.5), Vector2(1.7, 3.5)]:
		dressing.add_prop(&"fuel_drum", last_tile + side * o.x + heading * o.y, o.x * 1.7)
	for o: Vector2 in [Vector2(-0.9, 4.2), Vector2(0.9, 4.2)]:
		dressing.add_prop(&"propane", last_tile + side * o.x + heading * o.y, o.x)
	var truck_at := last_tile + heading * 8.5
	dressing.add_vehicle(&"garbage_truck", truck_at, yaw + PI * 0.5)
	var curb := float(TerrainStrata.ROAD_HALF_WIDTH) - 1.3
	for sgn: float in [-1.0, 1.0]:
		var spot: Vector3 = truck_at + side * (curb * sgn) + heading * 1.5
		var taken := false
		for p in dressing.props:
			if p.mass > 500.0 and p.global_position.distance_to(spot) < 6.0:
				taken = true
				break
		if not taken:
			dressing.add_vehicle(&"taxi", spot, yaw)


func _add_tile(at: Vector3, tangent: Vector3, index: int) -> void:
	var model := MeshInstance3D.new()
	model.mesh = _body_mesh
	for sgn: float in [1.0, -1.0]:
		var face := MeshInstance3D.new()
		face.mesh = _face_mesh
		face.material_override = _faces[(index * 5 + (0 if sgn > 0.0 else 7)) % _faces.size()]
		face.position = Vector3(0.0, 0.0, sgn * (TILE.z * 0.5 + 0.004))
		if sgn < 0.0:
			face.rotation.y = PI
		model.add_child(face)
	var tile := BreakableProp.from_model(StringName("domino_%d" % index), TILE_DEF, model)
	tile.prop_id = &"domino"
	tile.physics_material_override = _slick
	add_child(tile)
	var ground := 0.0
	if Game.terrain != null and Game.terrain.has_method(&"get_original_height"):
		ground = Game.terrain.call(&"get_original_height", at.x, at.z)
	tile.global_transform = Transform3D(Basis(Vector3.UP, atan2(tangent.x, tangent.z)), Vector3(at.x, ground + 0.01, at.z))
	tile.reset_physics_interpolation()
	tiles.append(tile)


## A rewind stands tiles up again: they no longer count as fallen.
func _after_rewind() -> void:
	for t in tiles:
		if is_instance_valid(t) and _down.has(t.get_instance_id()) and t.global_basis.y.y >= FALLEN_UP:
			_down.erase(t.get_instance_id())
			fallen -= 1


## Saved games: {tiles: {index: "gone" | 12 floats of the transform of a fallen tile}}.
func save_state() -> Dictionary:
	var out := {}
	for i in tiles.size():
		var t := tiles[i]
		if not is_instance_valid(t) or t.is_broken():
			out[str(i)] = "gone"
		elif _down.has(t.get_instance_id()):
			var x := t.global_transform
			out[str(i)] = [x.basis.x.x, x.basis.x.y, x.basis.x.z, x.basis.y.x, x.basis.y.y, x.basis.y.z,
				x.basis.z.x, x.basis.z.y, x.basis.z.z, x.origin.x, x.origin.y, x.origin.z]
	return {"tiles": out}


## Fallen tiles lie where they fell, without a chain step or a sound; broken ones are gone.
func restore_state(state: Dictionary) -> void:
	var saved: Dictionary = state.get("tiles", {})
	for key: String in saved:
		var i := int(key)
		if i < 0 or i >= tiles.size() or not is_instance_valid(tiles[i]):
			continue
		var t := tiles[i]
		var v: Variant = saved[key]
		if v is Array and (v as Array).size() == 12:
			var a: Array = v
			t.global_transform = Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))
			t.reset_physics_interpolation()
			if not _down.has(t.get_instance_id()):
				_down[t.get_instance_id()] = true
				fallen += 1
		else:
			t.restore_broken()


func _physics_process(delta: float) -> void:
	if tiles.is_empty() or Game.player == null:
		return
	_check_in -= delta
	if _check_in <= 0.0:
		_check_in = 0.3
		var d := Game.player.global_position.distance_to(_centre) - _radius
		if not _awake and d < WAKE_DISTANCE:
			_awake = true
			for t in tiles:
				if is_instance_valid(t):
					t.unpark()
		elif _awake and d > SLEEP_DISTANCE:
			_awake = false
			for t in tiles:
				if is_instance_valid(t) and t.sleeping:
					t.park()
	if not _awake:
		return
	for t in tiles:
		if not is_instance_valid(t) or t.freeze or t.sleeping or _down.has(t.get_instance_id()):
			continue
		if t.global_basis.y.y < FALLEN_UP:
			_down[t.get_instance_id()] = true
			_on_fallen(t)


## A tile has gone over: a step in the chain, a clack, and a blow to whatever is under its top edge
## (the next tile needs no help; a fuel drum, a table or a person does).
func _on_fallen(tile: BreakableProp) -> void:
	fallen += 1
	Progress.report_break()
	var up := tile.global_basis.y
	var dir := Vector3(up.x, 0.0, up.z).normalized()
	var top := tile.global_position + dir * (tile.size.y * 0.85)
	Audio.play_3d(&"impact_wood", top, 0.8)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe
	q.transform = Transform3D(Basis.IDENTITY, top + Vector3.UP * 0.45)
	q.collision_mask = Layers.PROPS | Layers.NPC
	q.exclude = [tile.get_rid()]
	for found: Dictionary in get_world_3d().direct_space_state.intersect_shape(q, 6):
		var collider: Object = found.get("collider")
		if collider is BreakableProp and (collider as BreakableProp).prop_id == &"domino":
			continue
		var hit := DamageHit.point(top, (dir + Vector3.DOWN).normalized(), LAND_ENERGY, LAND_IMPULSE, DamageHit.Kind.BLUNT, Game.player)
		DamageRouter.apply_hit(hit, collider, found.get("rid", RID()))


static func _face_texture(top: int, bottom: int) -> ImageTexture:
	var img := Image.create(FACE_PX, FACE_PX * 2, false, Image.FORMAT_RGB8)
	img.fill(IVORY)
	img.fill_rect(Rect2i(10, FACE_PX - 2, FACE_PX - 20, 4), INK)
	_pips(img, top, 0)
	_pips(img, bottom, FACE_PX)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _pips(img: Image, n: int, y0: int) -> void:
	for spot: int in SPOTS[n]:
		var cx := 24 + 24 * (spot % 3)
		@warning_ignore("integer_division")
		var cy := y0 + 24 + 24 * (spot / 3)
		for y in range(-9, 10):
			for x in range(-9, 10):
				if x * x + y * y <= 81:
					img.set_pixel(cx + x, cy + y, INK)
