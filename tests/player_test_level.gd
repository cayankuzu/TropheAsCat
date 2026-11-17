extends Node3D
## Player test level: flat ground, a 12 m climbing wall, a ramp, steps, a crate pyramid, loose crates,
## an over-limit heavy crate and a damage probe. Geometry is generated here so it can use MaterialDB's
## object-space triplanar materials. Layout (cat spawns at the origin facing -Z):
##   wall      x -5..5,  z -12.6..-11.4, 12 m high
##   ramp      x 7..10,  z -4..-12, rises to 2.7 m toward -Z
##   steps     x -9.5..-6.5, 6 x 0.25 m risers toward -Z from z = -2
##   pyramid   around (5, 0, -5); loose crates near the origin; heavy crate at (-6, 0, -6)
##   probe     3 x 3 m panel centred at (0, 1.5, 10) (receives damage), open lane along +X

const DamageProbe := preload("res://tests/damage_probe.gd")

var crates: Array[RigidBody3D] = []


func _ready() -> void:
	var ground := _static_box("Ground", Vector3(0, -1, 0), Vector3(1100, 2, 1100), Layers.TERRAIN, &"paving")
	# Finer paving than the city default so the stones read at cat scale.
	var paving := (MaterialDB.surface(&"paving") as StandardMaterial3D).duplicate() as StandardMaterial3D
	paving.uv1_scale = Vector3.ONE / 1.3
	(ground.get_child(1) as MeshInstance3D).material_override = paving
	_static_box("Wall", Vector3(0, 6, -12), Vector3(10, 12, 1.2), Layers.STRUCTURE, &"brick")
	var ramp := _static_box("Ramp", Vector3(8.5, 1.227, -8), Vector3(3, 0.3, 8), Layers.STRUCTURE, &"concrete")
	ramp.rotation_degrees.x = 20.0
	for i in 6:
		var h := 0.25 * (i + 1)
		_static_box("Step%d" % i, Vector3(-8, h * 0.5, -2.25 - 0.5 * i), Vector3(3, h, 0.5), Layers.STRUCTURE, &"concrete_light")
	_static_box("StepTop", Vector3(-8, 0.75, -6.5), Vector3(3, 1.5, 2), Layers.STRUCTURE, &"concrete_light")
	_static_box("DamageProbe", Vector3(0, 1.5, 10), Vector3(3, 3, 0.4), Layers.STRUCTURE, &"plaster", DamageProbe.new())
	# Crate pyramid 3-2-1 (0.8 m, 30 kg).
	var s := 0.8
	var idx := 0
	for row in 3:
		for k in 3 - row:
			var x := 5.0 + (k - (2 - row) * 0.5) * (s + 0.02)
			crates.append(_crate("Stack%d" % idx, Vector3(x, s * 0.5 + row * s, -5.0), s, 30.0))
			idx += 1
	crates.append(_crate("Loose0", Vector3(-1.6, 0.25, -2.2), 0.5, 8.0))
	crates.append(_crate("Loose1", Vector3(1.8, 0.35, -2.0), 0.7, 25.0))
	crates.append(_crate("Loose2", Vector3(-3.5, 0.3, 2.5), 0.6, 15.0))
	crates.append(_crate("Loose3", Vector3(3.0, 0.45, 3.0), 0.9, 80.0))
	crates.append(_crate("Loose4", Vector3(0.0, 0.3, -6.0), 0.6, 18.0))
	crates.append(_crate("HeavyCrate", Vector3(-6.0, 0.6, -6.0), 1.2, 600.0))


func _static_box(n: String, pos: Vector3, size: Vector3, layer: int, mat: StringName, body: StaticBody3D = null) -> StaticBody3D:
	if body == null:
		body = StaticBody3D.new()
	body.name = n
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = MaterialDB.surface(mat)
	body.add_child(mi)
	add_child(body)
	return body


func _crate(n: String, pos: Vector3, size: float, mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = n
	body.collision_layer = Layers.PROPS
	body.collision_mask = Layers.SOLID | Layers.PLAYER
	body.mass = mass
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	mi.mesh = mesh
	mi.material_override = MaterialDB.surface(&"wood")
	body.add_child(mi)
	add_child(body)
	return body
