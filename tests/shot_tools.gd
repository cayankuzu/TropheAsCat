extends Node
## Windowed check of the four tools in the composed world: stands the cat in front of a house, fires
## each tool through bot input, saves a screenshot per tool and prints what each one did.
## Run: Godot --path <P> res://tests/shot_tools.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const D := preload("res://game/destruction/destruction_defs.gd")
const Util := preload("res://tests/city_test_util.gd")
const T0 := 430

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _bot := CatInput.new()
var _closeup: Camera3D
var _damage := {}
var _frame_ms := PackedFloat32Array()
var _last_usec := 0
var _drops_before := 0


func _ready() -> void:
	Progress.sandbox_all_tools = true   # this test needs every tool on the belt
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DamageRouter.damage_applied.connect(func(hit: DamageHit, _t: Object) -> void:
		_damage[hit.kind] = int(_damage.get(hit.kind, 0)) + 1)


func _process(_delta: float) -> void:
	_frame += 1
	var now := Time.get_ticks_usec()
	if _last_usec > 0 and _frame > T0:
		var ms := float(now - _last_usec) / 1000.0
		_frame_ms.append(ms)
		if ms > 60.0:
			print("TOOLS_HITCH f=%d ms=%.0f" % [_frame - T0, ms])
	_last_usec = now
	var f := _frame - T0
	match f:
		0:
			# Stand 12 m in front of the nearest apartment block of the Old Quarter, looking at it.
			_cat = Game.player as CatPlayer
			var spot := Util.stand_before(_main, D.Style.APARTMENT, Vector3(-40.0, 0.0, -40.0), 12.0)
			print("TOOLS_SPOT ", spot)
			_cat.global_position = spot["position"]
			_cat.velocity = Vector3.ZERO
			_cat.reset_physics_interpolation()
			_cat.bot_input = _bot
			_cat.camera.yaw = spot["yaw"]
			_cat.camera.pitch = deg_to_rad(6.0)
			_cat.camera.snap_to_target()
		60:
			print("TOOLS_BELT ", _belt_names())
			_bot.tool_slot = ToolKit.slot_of(&"laser")
		70:
			var hit := _cat.belt.get_current().crosshair_hit()
			print("TOOLS_AIM pos=", hit.get("position"), " structure=", hit.get("collider") == null and not hit.is_empty(), " cat=", _cat.global_position)
			_bot.attack = true
		130:
			_save("tool_laser.png")
		170:
			_bot.attack = false
			var laser := _cat.belt.slots[ToolKit.slot_of(&"laser")] as LaserDotTool
			print("TOOLS_LASER ticks=%d energy=%.0f" % [laser.ticks, laser.energy_dealt])
		190:
			_bot.tool_slot = ToolKit.slot_of(&"wizard_hat")
		196:
			_closeup = Camera3D.new()
			_closeup.fov = 35.0
			add_child(_closeup)
			_closeup.look_at_from_position(_cat.global_position + Vector3(0.7, 0.55, -1.3), _cat.global_position + Vector3(0.0, 0.42, 0.0), Vector3.UP)
			_closeup.make_current()
		200:
			_save("tool_hat_closeup.png")
			_cat.camera.get_camera().make_current()
			_closeup.queue_free()
		205:
			_bot.attack = true     # tap: a small firebolt at the wall
		208:
			_bot.attack = false
		250:
			_cat.camera.pitch = deg_to_rad(-4.0)   # full charge at the lawn in front
			_bot.attack = true
		290:
			_save("tool_charge.png")
		325:
			_bot.attack = false
		342:
			_save("tool_fireball.png")
		362:
			_save("tool_fireball_late.png")
		380:
			var wizard := _cat.belt.slots[ToolKit.slot_of(&"wizard_hat")] as WizardHatTool
			print("TOOLS_WIZARD casts=%d explosions=%d" % [wizard.casts, WorldFX.instance.explosions])
			_cat.camera.pitch = deg_to_rad(6.0)
		400:
			_bot.tool_slot = ToolKit.slot_of(&"hairball")
		410:
			_bot.attack = true
		468:
			_save("tool_hairball.png")
		480:
			_bot.attack = false
			var cannon := _cat.belt.slots[ToolKit.slot_of(&"hairball")] as HairballCannonTool
			print("TOOLS_HAIRBALL shots=%d" % cannon.shots)
		500:
			_bot.tool_slot = ToolKit.slot_of(&"pee")
		510:
			_bot.attack = true
		580:
			# From the side: she stands on her hind legs while the stream runs.
			_closeup = Camera3D.new()
			_closeup.fov = 40.0
			add_child(_closeup)
			var side := _cat.get_facing().cross(Vector3.UP).normalized()
			_closeup.look_at_from_position(_cat.global_position + side * 2.0 + _cat.get_facing() * 0.9 + Vector3.UP * 0.5, _cat.global_position + _cat.get_facing() * 0.9 + Vector3.UP * 0.35, Vector3.UP)
			_closeup.make_current()
		590:
			_save("tool_pee_side.png")
			print("TOOLS_PEE_STAND stand=%.2f" % _cat.get_stand_amount())
			_cat.camera.get_camera().make_current()
			_closeup.queue_free()
		600:
			_save("tool_acid.png")
		620:
			_bot.attack = false
			var pee := _cat.belt.slots[ToolKit.slot_of(&"pee")] as PeeTool
			print("TOOLS_ACID name=%s drops=%d landings=%d pools=%d energy=%.0f" % [pee.tool_name, pee.drops, pee.landings, pee.pool_count(), pee.energy_dealt])
		640:
			# The same tool before the Acid Pee milestone: puddles, no damage.
			Progress.sandbox_all_tools = false
			_drops_before = (_cat.belt.slots[ToolKit.slot_of(&"pee")] as PeeTool).drops
			_cat.camera.pitch = deg_to_rad(-12.0)
		650:
			_bot.attack = true
		700:
			_save("tool_pee_plain.png")
		710:
			_bot.attack = false
			var pee := _cat.belt.slots[ToolKit.slot_of(&"pee")] as PeeTool
			print("TOOLS_PEE_PLAIN name=%s acid=%s drops=+%d puddles=%d" % [pee.tool_name, pee.acid, pee.drops - _drops_before, pee.puddle_count()])
		760:
			print("TOOLS_DAMAGE ", JSON.stringify(_damage))
			var fx := WorldFX.instance
			print("TOOLS_FX sparks=%d smoke=%d fire=%d blobs=%d flashes=%d marks=%d" % [fx.sparks.emitted, fx.smoke.emitted, fx.fire.emitted, fx.blobs.emitted, fx.lights.flashes, fx.marks.placed])
			if Game.structures != null:
				print("TOOLS_STATS ", JSON.stringify(Game.structures.call(&"stats")))
			var sorted := Array(_frame_ms)
			sorted.sort()
			var n := sorted.size()
			if n > 0:
				var sum := 0.0
				for v: float in sorted:
					sum += v
				print("TOOLS_FRAME_MS avg=%.2f p95=%.2f p99=%.2f max=%.2f n=%d" % [sum / n, sorted[int(n * 0.95)], sorted[int(n * 0.99)], sorted[n - 1], n])
			get_tree().quit(0)


func _belt_names() -> Array:
	var names := []
	for t in _cat.belt.slots:
		if t != null:
			names.append(t.tool_name)
	return names


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
