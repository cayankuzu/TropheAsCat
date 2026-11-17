class_name SetPieces
extends Node3D
## The big set pieces of the districts (2026-11-17), in the spirit of the dominoes: one act sets them off
## and the player watches them go.
##
##   The fair (outer Park)    a Ferris wheel on two A-frames: hit it hard enough and the wheel comes off its
##                            axle and rolls east, over the road and through the car park of the Strip.
##   The building site (Yards) a tower crane by the first container plot: knock its mast and it tips away
##                            from the hit, jib first, onto the warehouses, and breaks up where it lands.
##   The square (Old Quarter) a clock tower on the first village green: it topples onto the houses round
##                            the green and breaks into its stones.
##
## Each is a Giant (game/world/setpieces/giant.gd); its stand (the A-frames, the crane's footing) is a static
## body whose hits count towards the giant. The Owner has a line for each, and each one adds chaos heat.

const WHEEL_R := 13.0
const WHEEL_HUB := 15.0
const LINES := {
	"wheel": "That wheel was a gift. ...Why is it rolling? WHY IS IT ROLLING?",
	"crane": "Not the crane. The crane was holding up the skyline. Spiritually.",
	"tower": "That clock has been right twice a day for forty years.",
}

var giants: Array[Giant] = []
var wheel: Giant
var crane: Giant
var tower: Giant

var _main: Node
var _mats := {}


func build(main: Node, city: CityLayout) -> void:
	_main = main
	var block := CityLayout.block_centre(Vector2i(-1, 2))
	wheel = _ferris_wheel(Vector3(block.x + 20.0, 0.0, block.z - 36.0))
	if not city.container_yards.is_empty():
		var cy: Vector3 = city.container_yards[0]
		var c := Vector3(floorf(cy.x / CityLayout.BLOCK) * CityLayout.BLOCK + CityLayout.BLOCK * 0.5, 0.0, floorf(cy.z / CityLayout.BLOCK) * CityLayout.BLOCK + CityLayout.BLOCK * 0.5)
		var base := cy + Vector3(16.0 if cy.x < c.x + 1.0 else -16.0, 0.0, 0.0)
		var to := c - base
		crane = _tower_crane(base, atan2(to.x, to.z))
	if not city.greens.is_empty():
		tower = _clock_tower(city.greens[0])
	for g in [wheel, crane, tower]:
		if g != null:
			giants.append(g)
			g.let_go.connect(_on_let_go)


func released_count() -> int:
	var n := 0
	for g in giants:
		if g.released:
			n += 1
	return n


func _on_let_go(g: Giant) -> void:
	var voice: OwnerVoice = _main.get("owner_voice") if _main != null else null
	if voice != null and is_instance_valid(voice):
		voice.speak(LINES.get(g.title, ""), true)
	var chaos: Chaos = _main.get("chaos") if _main != null else null
	if chaos != null:
		chaos.add(20.0)


# --------------------------------------------------------------------------------------------------
# The Ferris wheel
# --------------------------------------------------------------------------------------------------

func _ferris_wheel(at: Vector3) -> Giant:
	var ground := _ground(at.x, at.z)
	var g := Giant.new()
	g.name = "FerrisWheel"
	g.title = "wheel"
	g.fall = Giant.Fall.ROLL
	g.hold_j = 18000.0     # six swats at the stand, or one car going up next to it
	g.roll_hint = Vector3.RIGHT
	var list: Array[Dictionary] = []
	var white := _mat("white", Color(0.94, 0.94, 0.92), 0.0)
	var bulbs := _mat("bulbs", Color(1.0, 0.86, 0.6), 2.2)
	var n := 24
	var seg := TAU * WHEEL_R / n * 1.04
	for i in n:
		var a := TAU * i / n
		var xf := Transform3D(Basis(Vector3.BACK, a + PI * 0.5), Vector3(cos(a), sin(a), 0.0) * WHEEL_R)
		list.append(_section(_box_mesh(Vector3(seg, 0.45, 0.5), bulbs if i % 2 == 0 else white), Vector3(seg, 0.45, 0.5), xf, 900.0, &"steel", true))
	for i in 12:
		var a := TAU * i / 12.0
		var xf := Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a), sin(a), 0.0) * WHEEL_R * 0.5)
		list.append(_section(_box_mesh(Vector3(WHEEL_R, 0.22, 0.22), white), Vector3(WHEEL_R, 0.22, 0.22), xf, 500.0, &"steel", true))
	var hub := CylinderMesh.new()
	hub.top_radius = 1.0
	hub.bottom_radius = 1.0
	hub.height = 1.8
	hub.material = _mat("hub", Color(0.3, 0.32, 0.36), 0.0)
	var hub_shape := CylinderShape3D.new()
	hub_shape.radius = 1.0
	hub_shape.height = 1.8
	list.append({"mesh": hub, "shape": hub_shape, "xf": Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), "mass": 6000.0, "material": &"steel", "no_collide": true})
	var colours := [Color(0.85, 0.2, 0.2), Color(0.98, 0.78, 0.15), Color(0.2, 0.45, 0.85), Color(0.25, 0.7, 0.4), Color(0.1, 0.6, 0.62), Color(0.92, 0.45, 0.6)]
	for i in 12:
		var a := TAU * (i + 0.5) / 12.0
		var m := _mat("gondola%d" % (i % 6), colours[i % 6], 0.0)
		var xf := Transform3D(Basis.IDENTITY, Vector3(cos(a), sin(a), 0.0) * (WHEEL_R - 1.7) + Vector3(0.0, -0.6, 0.0))
		list.append(_section(_box_mesh(Vector3(1.6, 1.4, 1.4), m), Vector3(1.6, 1.4, 1.4), xf, 700.0, &"sheet_metal", true))
	# It rolls on one smooth disc, not on its corners.
	var disc := CylinderShape3D.new()
	disc.radius = WHEEL_R + 0.22
	disc.height = 1.3
	g.build(list, [[disc, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)]])
	add_child(g)
	g.global_transform = Transform3D(Basis.IDENTITY, Vector3(at.x, ground + WHEEL_HUB, at.z))
	g.home = g.global_transform
	# Two A-frames, one each side of the wheel, from the ground up to the axle.
	var stand := StaticBody3D.new()
	stand.name = "WheelStand"
	stand.collision_layer = Layers.STRUCTURE
	stand.collision_mask = 0
	add_child(stand)
	stand.global_position = Vector3(at.x, ground, at.z)
	var leg_mat := _mat("legs", Color(0.9, 0.9, 0.88), 0.0)
	for side: float in [-1.0, 1.0]:
		for spread: float in [-1.0, 1.0]:
			var foot := Vector3(spread * 9.0, 0.0, side * 1.6)
			var top := Vector3(0.0, WHEEL_HUB, side * 1.2)
			var mid := (foot + top) * 0.5
			var length := foot.distance_to(top)
			var up := (top - foot).normalized()
			var turn := Basis(up.cross(Vector3.BACK).normalized(), up, Vector3.BACK).orthonormalized()
			_stand_part(stand, _box_mesh(Vector3(0.5, length, 0.5), leg_mat), Vector3(0.5, length, 0.5), Transform3D(turn, mid))
	DamageRouter.register_rid(stand.get_rid(), g, 0)
	return g


# --------------------------------------------------------------------------------------------------
# The tower crane
# --------------------------------------------------------------------------------------------------

func _tower_crane(at: Vector3, yaw: float) -> Giant:
	var ground := _ground(at.x, at.z)
	var g := Giant.new()
	g.name = "TowerCrane"
	g.title = "crane"
	g.base_half = 1.0
	g.hold_j = 24000.0
	var list: Array[Dictionary] = []
	var lattice := MaterialDB.surface(&"lattice_yellow")
	for i in 10:
		var xf := Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0 + 4.0 * i, 0.0))
		list.append(_section(_box_mesh(Vector3(2.0, 4.0, 2.0), lattice), Vector3(2.0, 4.0, 2.0), xf, 2500.0, &"sheet_metal"))
	var top := 40.0
	list.append(_section(_box_mesh(Vector3(2.6, 2.4, 3.2), MaterialDB.surface(&"panel_white")), Vector3(2.6, 2.4, 3.2), Transform3D(Basis.IDENTITY, Vector3(0.0, top + 1.2, 0.6)), 3000.0, &"steel"))
	list.append(_section(_box_mesh(Vector3(0.9, 6.0, 0.9), lattice), Vector3(0.9, 6.0, 0.9), Transform3D(Basis.IDENTITY, Vector3(0.0, top + 5.4, 0.0)), 800.0, &"sheet_metal"))
	for i in 9:
		var xf := Transform3D(Basis.IDENTITY, Vector3(0.0, top + 3.0, 4.5 + 5.0 * i))
		list.append(_section(_box_mesh(Vector3(1.3, 1.5, 5.0), lattice), Vector3(1.3, 1.5, 5.0), xf, 1100.0, &"sheet_metal"))
	for i in 3:
		var xf := Transform3D(Basis.IDENTITY, Vector3(0.0, top + 2.8, -3.0 - 4.0 * i))
		list.append(_section(_box_mesh(Vector3(1.6, 1.0, 4.0), lattice), Vector3(1.6, 1.0, 4.0), xf, 900.0, &"sheet_metal"))
	for i in 2:
		var xf := Transform3D(Basis.IDENTITY, Vector3(0.0, top + 1.0, -10.6 - 1.3 * i))
		list.append(_section(_box_mesh(Vector3(2.4, 2.4, 1.2), MaterialDB.surface(&"concrete")), Vector3(2.4, 2.4, 1.2), xf, 7000.0, &"concrete"))
	# The hook on its cable, halfway out along the jib.
	list.append(_section(_box_mesh(Vector3(0.06, 16.0, 0.06), _mat("cable", Color(0.1, 0.1, 0.1), 0.0)), Vector3(0.1, 16.0, 0.1), Transform3D(Basis.IDENTITY, Vector3(0.0, top - 6.0, 26.0)), 200.0, &"steel", true))
	list.append(_section(_box_mesh(Vector3(0.8, 1.2, 0.5), _mat("hook", Color(0.95, 0.75, 0.1), 0.0)), Vector3(0.8, 1.2, 0.5), Transform3D(Basis.IDENTITY, Vector3(0.0, top - 14.6, 26.0)), 600.0, &"steel", true))
	g.build(list)
	add_child(g)
	g.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, ground + 1.0, at.z))
	g.home = g.global_transform
	var stand := StaticBody3D.new()
	stand.name = "CraneFooting"
	stand.collision_layer = Layers.STRUCTURE
	stand.collision_mask = 0
	add_child(stand)
	stand.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, ground, at.z))
	_stand_part(stand, _box_mesh(Vector3(5.0, 1.0, 5.0), MaterialDB.surface(&"concrete")), Vector3(5.0, 1.0, 5.0), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)))
	DamageRouter.register_rid(stand.get_rid(), g, 0)
	return g


# --------------------------------------------------------------------------------------------------
# The clock tower
# --------------------------------------------------------------------------------------------------

func _clock_tower(at: Vector3) -> Giant:
	var ground := _ground(at.x, at.z)
	var g := Giant.new()
	g.name = "ClockTower"
	g.title = "tower"
	g.base_half = 2.5
	g.hold_j = 36000.0
	var list: Array[Dictionary] = []
	var stone := MaterialDB.surface(&"stone")
	for i in 6:
		var xf := Transform3D(Basis.IDENTITY, Vector3(0.0, 2.25 + 4.5 * i, 0.0))
		list.append(_section(_box_mesh(Vector3(5.0, 4.5, 5.0), stone), Vector3(5.0, 4.5, 5.0), xf, 40000.0, &"brick"))
	# The clock storey: a stone block with a clock face on each side, one mesh.
	var clock := ArrayMesh.new()
	var body := BoxMesh.new()
	body.size = Vector3(5.4, 4.6, 5.4)
	var st := SurfaceTool.new()
	st.append_from(body, 0, Transform3D.IDENTITY)
	st.commit(clock)
	clock.surface_set_material(0, MaterialDB.surface(&"stone_warm"))
	var face := CylinderMesh.new()
	face.top_radius = 1.8
	face.bottom_radius = 1.8
	face.height = 0.12
	face.radial_segments = 32
	var st2 := SurfaceTool.new()
	for k in 4:
		var out := Vector3(sin(PI * 0.5 * k), 0.0, cos(PI * 0.5 * k))
		var turn := Basis(Vector3.RIGHT, PI * 0.5) if absf(out.z) > 0.5 else Basis(Vector3.BACK, PI * 0.5)
		st2.append_from(face, 0, Transform3D(turn, out * 2.72))
	st2.commit(clock)
	clock.surface_set_material(1, MaterialDB.surface(&"clock_face"))
	list.append(_section(clock, Vector3(5.4, 4.6, 5.4), Transform3D(Basis.IDENTITY, Vector3(0.0, 27.0 + 2.3, 0.0)), 30000.0, &"brick"))
	list.append(_section(_box_mesh(Vector3(4.6, 3.6, 4.6), MaterialDB.surface(&"stone_warm")), Vector3(4.6, 3.6, 4.6), Transform3D(Basis.IDENTITY, Vector3(0.0, 31.6 + 1.8, 0.0)), 18000.0, &"brick"))
	var roof := CylinderMesh.new()
	roof.top_radius = 0.0
	roof.bottom_radius = 3.9
	roof.height = 7.0
	roof.radial_segments = 4
	roof.rings = 1
	roof.material = MaterialDB.surface(&"roof_slate")
	list.append({"mesh": roof, "shape": _box_shape(Vector3(4.6, 7.0, 4.6)), "xf": Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0.0, 35.2 + 3.5, 0.0)), "mass": 8000.0, "material": &"roof"})
	g.build(list)
	add_child(g)
	g.global_transform = Transform3D(Basis.IDENTITY, Vector3(at.x, ground, at.z))
	g.home = g.global_transform
	return g


# --------------------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------------------

func _section(mesh: Mesh, size: Vector3, xf: Transform3D, mass: float, material: StringName, no_collide: bool = false) -> Dictionary:
	return {"mesh": mesh, "shape": _box_shape(size), "xf": xf, "mass": mass, "material": material, "no_collide": no_collide}


func _stand_part(stand: StaticBody3D, mesh: Mesh, size: Vector3, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	stand.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = _box_shape(size)
	cs.transform = xf
	stand.add_child(cs)


func _box_mesh(size: Vector3, material: Material) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	m.material = material
	return m


func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


func _mat(key: String, c: Color, glow: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.4
	m.metallic = 0.2
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m


func _ground(x: float, z: float) -> float:
	if Game.terrain != null and Game.terrain.has_method(&"get_original_height"):
		return Game.terrain.call(&"get_original_height", x, z)
	return 0.0
