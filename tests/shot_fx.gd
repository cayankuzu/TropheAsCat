extends Node3D
## Windowed check of the world's effect layers (2026-11-17): a fireball, sparks, smoke and acid blobs in
## front of a camera. Run it on the Compatibility renderer too (--rendering-driver opengl3, the browser
## demo's renderer), where FxLayer simulates the particles on the CPU. Saves tests/out/fx_<renderer>.png and
## prints FX_RESULT with the layers' emitted counts.
## Run: Godot --path <P> res://tests/shot_fx.tscn --resolution 1280x720 [--rendering-driver opengl3]

var _frame := 0
var _fx: WorldFX


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.55, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	ground.mesh = plane
	add_child(ground)
	_fx = WorldFX.new()
	add_child(_fx)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 4.0, 14.0)
	cam.look_at(Vector3(0.0, 2.5, 0.0), Vector3.UP)
	cam.make_current()


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 3:
		_fx.explosion(Vector3(0.0, 0.5, 0.0), 3.5)
		for i in 30:
			_fx.puff(Vector3(-5.0 + randf(), 0.5, 0.0), Vector3(randf() - 0.5, 1.5, randf() - 0.5), WorldFX.SOOT, 4.0, 1.0, 3.0)
			_fx.flame(Vector3(5.0 + randf() * 0.5, 0.3, 0.0), Vector3(0.0, 1.5, 0.0), 1.2, 0.8, 0.3)
		_fx.splash(Vector3(0.0, 0.2, 4.0), Vector3.UP, 20, WorldFX.ACID)
	elif _frame == 18:
		var tag := RenderingServer.get_current_rendering_method()
		get_viewport().get_texture().get_image().save_png("res://tests/out/fx_%s.png" % tag)
		var ok := _fx.sparks.emitted > 0 and _fx.smoke.emitted > 0 and _fx.fire.emitted > 0 and _fx.blobs.emitted > 0
		print("FX_RESULT ok=%s renderer=%s cpu=%s sparks=%d smoke=%d fire=%d blobs=%d" % [ok, tag, _fx.smoke.cpu, _fx.sparks.emitted, _fx.smoke.emitted, _fx.fire.emitted, _fx.blobs.emitted])
		get_tree().quit()
