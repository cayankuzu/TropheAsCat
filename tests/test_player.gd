extends Node
## Bot-driven tests for the player cat. Run headless as a scene with a fixed timestep:
##   Godot --headless --path <P> res://tests/test_player.tscn --fixed-fps 60 [-- soak=300 only=climb,grab]
## Suites: setup gaits jumps landing terrain climb grab swat tools integrity void lava soak perf leaks.
## (The --script entry point cannot be used: it compiles before autoloads such as Game exist.)
## Writes res://tests/out/player_metrics.json and exits with 0 when every check passed. GDScript
## warnings are checked separately by res://tests/lint_scripts.tscn.

const LEVEL := preload("res://tests/player_test_level.tscn")
const DT := 1.0 / 60.0

class FakeLavaTerrain extends Node:
	var center := Vector3(40, 0, 40)
	var radius := 2.0
	func is_lava_at(p: Vector3) -> bool:
		return Vector2(p.x - center.x, p.z - center.z).length() < radius and p.y < 0.5

## Stand-in for the destruction module's rubble contract: wake_rubble(rid) either returns the dynamic
## body at once ("now"), makes one appear near the rubble on the next physics tick ("next_tick"), or
## fails ("never").
class FakeDebris extends Node:
	var mode := "now"
	var body: RigidBody3D
	var rubble: StaticBody3D
	var calls := 0
	func wake_rubble(_rid: RID) -> Variant:
		calls += 1
		if mode == "never":
			return null
		var at := rubble.global_position
		rubble.global_position += Vector3(0, -50, 0)   # the static piece is replaced by the dynamic one
		if mode == "now":
			_swap_in(at)
			return body
		_swap_in.call_deferred(at)
		return null
	func _swap_in(at: Vector3) -> void:
		body.global_position = at
		body.linear_velocity = Vector3.ZERO
		body.freeze = false

var level: Node3D
var cat: CatPlayer
var bot := CatInput.new()
var metrics := {}
var checks: Array = []
var failures := 0
var blasts: Array[DamageHit] = []
var soak_seconds := 300.0
var only: PackedStringArray = []


func _ready() -> void:
	seed(1234)   # sky-drop spots, throw spin and lava launch angles use the global RNG
	for a in OS.get_cmdline_user_args():
		if a.begins_with("soak="):
			soak_seconds = float(a.substr(5))
		elif a.begins_with("only="):
			only = a.substr(5).split(",")
	level = LEVEL.instantiate()
	add_child(level)
	cat = level.get_node("Cat")
	cat.bot_input = bot
	DamageRouter.blast.connect(func(h: DamageHit) -> void: blasts.append(h))
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	await _ticks(30)
	var suites := ["setup", "gaits", "jumps", "landing", "terrain", "climb", "grab", "swat", "tools", "integrity", "void", "lava", "soak", "perf", "leaks"]
	for s in suites:
		if only.is_empty() or only.has(s):
			print("--- ", s)
			await call("_test_" + s)
	metrics["checks"] = checks
	metrics["failures"] = failures
	metrics["wall_time_s"] = (Time.get_ticks_msec() - t0) / 1000.0
	var f := FileAccess.open("res://tests/out/player_metrics.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(metrics, "  ", false))
	f.close()
	print("RESULT failures=%d checks=%d" % [failures, checks.size()])
	get_tree().quit(1 if failures > 0 else 0)


# --- helpers -------------------------------------------------------------------------------------

func _check(n: String, ok: bool, detail: String) -> void:
	checks.append({"name": n, "passed": ok, "detail": detail})
	if not ok:
		failures += 1
	print("%s %s: %s" % ["PASS" if ok else "FAIL", n, detail])


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Rendered (idle) frames: unlike physics ticks they keep coming at a constant rate in slow motion.
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _reset(pos: Vector3, yaw_deg: float) -> void:
	bot.clear()
	if cat.grab.is_holding():
		cat.grab.release(Vector3.ZERO)
	cat.global_position = pos
	cat.velocity = Vector3.ZERO
	cat._speed = 0.0
	cat._charging = false
	cat._pounce = false
	cat._sky_drop = false
	cat._set_mode(CatPlayer.Mode.AIR)
	cat.camera.yaw = deg_to_rad(yaw_deg)
	cat.camera.pitch = deg_to_rad(-11.0)
	cat._facing = Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Vector3.FORWARD
	cat.reset_physics_interpolation()


func _settle() -> void:
	for i in 120:
		await get_tree().physics_frame
		if cat.mode == CatPlayer.Mode.GROUND and cat.get_horizontal_speed() < 0.05 and i > 10:
			return


func _place_crate(n: String, pos: Vector3) -> RigidBody3D:
	var c: RigidBody3D = level.get_node(n)
	c.global_position = pos
	c.rotation = Vector3.ZERO
	c.linear_velocity = Vector3.ZERO
	c.angular_velocity = Vector3.ZERO
	c.reset_physics_interpolation()
	return c


func _hspeed() -> float:
	return Vector2(cat.velocity.x, cat.velocity.z).length()


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- suites --------------------------------------------------------------------------------------

func _test_setup() -> void:
	_check("registered", Game.player == cat, "Game.player is the cat")
	_check("layers", cat.collision_layer == Layers.PLAYER and cat.collision_mask == Layers.WALKABLE, "layer PLAYER, mask WALKABLE")
	_check("protected", cat.is_in_group(&"protected"), "cat in group protected")
	var lib := CatAnimLibrary.get_library(null)
	var clips := {}
	for n in lib.get_animation_list():
		var a := lib.get_animation(n)
		clips[String(n)] = {"length": snappedf(a.length, 0.001), "loop": a.loop_mode}
	metrics["clips"] = clips
	var loops_ok := true
	for n in ["idle", "walk", "trot", "gallop", "stalk", "climb", "swim"]:
		loops_ok = loops_ok and lib.get_animation(n).loop_mode == Animation.LOOP_LINEAR
	_check("anim_loops", loops_ok, "%d clips; locomotion clips loop" % clips.size())
	var tree := cat.animator.tree
	var have := {}
	for p in tree.get_property_list():
		have[p["name"]] = true
	var missing: Array = []
	for u in ["parameters/sm/playback", "parameters/sm/move/blend_position", "parameters/sm/move/gallop/ts/scale",
			"parameters/sm/stalk/stalk/ts/scale", "parameters/sm/air/blend_position", "parameters/sm/climb/ts/scale",
			"parameters/sm/swim/ts/scale", "parameters/sm/charge/ts/scale", "parameters/sm/land/ts/scale",
			"parameters/sm/pounce_land/ts/scale", "parameters/swat/request", "parameters/swat_ts/scale"]:
		if not have.has(u):
			missing.append(u)
	_check("anim_params", missing.is_empty(), "missing=%s" % str(missing))
	metrics["model"] = {
		"scale": CatPlayer.MODEL_SCALE, "withers_m": snappedf(0.500 * CatPlayer.MODEL_SCALE, 0.001),
		"nose_to_tail_tip_m": snappedf(0.998 * CatPlayer.MODEL_SCALE, 0.001), "ears_top_m": snappedf(0.678 * CatPlayer.MODEL_SCALE, 0.001),
		"collision_radius_m": CatPlayer.RADIUS, "forward_axis_model": "+Z (turned 180 deg in Visual)",
	}


func _gait_run(label: String, setup: Callable, seconds: float, target: float) -> Dictionary:
	_reset(Vector3(0, 0.05, 40), -90.0)   # facing +X down the open lane
	await _settle()
	var start := cat.global_position
	bot.move = Vector2(0, 1)
	setup.call()
	var t90 := -1.0
	var samples: Array[float] = []
	var n := int(seconds / DT)
	for i in n:
		await get_tree().physics_frame
		var hs := _hspeed()
		if t90 < 0.0 and hs >= target * 0.9:
			t90 = i * DT
		if i >= n - 60:
			samples.append(hs)
	var avg := 0.0
	for s in samples:
		avg += s
	avg /= maxf(samples.size(), 1)
	var dist := _flat_dist(cat.global_position, start)
	bot.clear()
	await _ticks(40)
	var r := {"steady_speed": snappedf(avg, 0.01), "distance_m": snappedf(dist, 0.01), "seconds": seconds, "t_to_90pct_s": snappedf(t90, 0.01), "target": target}
	_check("gait_" + label, absf(avg - target) < target * 0.06, "steady %.2f m/s (target %.1f), %.1f m in %.0f s, 90%% at %.2f s" % [avg, target, dist, seconds, t90])
	return r


func _test_gaits() -> void:
	var g := {}
	g["walk"] = await _gait_run("walk", func() -> void: bot.walk = true, 3.0, cat.walk_speed)
	g["trot"] = await _gait_run("trot", func() -> void: pass, 3.0, cat.trot_speed)
	g["gallop"] = await _gait_run("gallop", func() -> void: bot.sprint = true, 4.0, cat.gallop_speed)
	g["stalk"] = await _gait_run("stalk", func() -> void: bot.crouch = true, 3.0, cat.stalk_speed)
	# Turn response: from a trot, reverse direction; time until moving the other way at 90% speed.
	_reset(Vector3(0, 0.05, 40), -90.0)
	await _settle()
	bot.move = Vector2(0, 1)
	await _ticks(90)
	bot.move = Vector2(0, -1)
	var t := 0.0
	for i in 120:
		await get_tree().physics_frame
		if cat.velocity.x < -cat.trot_speed * 0.9:
			t = i * DT
			break
	g["trot_reverse_s"] = snappedf(t, 0.01)
	_check("turn_reverse", t > 0.0 and t < 1.2, "trot 180-degree reversal back to 90%% speed in %.2f s" % t)
	bot.clear()
	await _ticks(30)
	metrics["gaits"] = g


func _test_jumps() -> void:
	var j := {}
	# Standing jump (tap).
	_reset(Vector3(0, 0.05, 40), -90.0)
	await _settle()
	var y0 := cat.global_position.y
	bot.jump = true
	var apex := y0
	for k in 40:   # held: the full jump (a tap is a short hop); the apex is measured while it is held too
		await get_tree().physics_frame
		apex = maxf(apex, cat.global_position.y)
	bot.jump = false
	for i in 120:
		await get_tree().physics_frame
		apex = maxf(apex, cat.global_position.y)
		if cat.mode == CatPlayer.Mode.GROUND and i > 10:
			break
	j["standing_jump_height_m"] = snappedf(apex - y0, 0.01)
	_check("jump_standing", absf((apex - y0) - cat.jump_height) < 0.15, "apex %.2f m (target %.1f)" % [apex - y0, cat.jump_height])
	# Running jump at gallop.
	_reset(Vector3(0, 0.05, 40), -90.0)
	await _settle()
	bot.move = Vector2(0, 1)
	bot.sprint = true
	await _ticks(150)
	var take := cat.global_position
	bot.jump = true
	await _ticks(1)
	apex = take.y
	var landed := false
	for i in 200:
		await get_tree().physics_frame
		apex = maxf(apex, cat.global_position.y)
		if i > 3 and cat.mode == CatPlayer.Mode.GROUND:
			landed = true
			break
	var run_dist := _flat_dist(cat.global_position, take)
	j["gallop_jump_distance_m"] = snappedf(run_dist, 0.01)
	j["gallop_jump_height_m"] = snappedf(apex - take.y, 0.01)
	_check("jump_gallop", landed and run_dist > 8.0, "held running jump at gallop: %.1f m far, %.2f m high" % [run_dist, apex - take.y])
	bot.clear()
	await _ticks(60)
	# Variable jump height: a running jump released after 3 ticks is cut short.
	var apexes: Array[float] = []
	for hold_ticks: int in [40, 3]:
		_reset(Vector3(0, 0.05, 40), -90.0)
		await _settle()
		bot.move = Vector2(0, 1)
		await _ticks(60)   # trotting, faster than charge_max_speed: Space jumps on press
		var y_take := cat.global_position.y
		bot.jump = true
		var top := y_take
		for i in 160:
			if i == hold_ticks:
				bot.jump = false
			await get_tree().physics_frame
			top = maxf(top, cat.global_position.y)
			if i > 3 and cat.mode == CatPlayer.Mode.GROUND:
				break
		bot.jump = false
		apexes.append(top - y_take)
		bot.clear()
		await _ticks(30)
	j["jump_full_vs_cut_m"] = [snappedf(apexes[0], 0.01), snappedf(apexes[1], 0.01)]
	_check("jump_cut", apexes[1] < apexes[0] * 0.7 and apexes[1] > 0.2, "held %.2f m, released after 3 ticks %.2f m" % [apexes[0], apexes[1]])
	# Full-charge pounce.
	_reset(Vector3(0, 0.05, 40), -90.0)
	await _settle()
	take = cat.global_position
	bot.crouch = true   # a pounce is charged crouching
	bot.jump = true
	await _ticks(int((cat.pounce_charge_time + cat.pounce_tap_time + 0.2) / DT))
	bot.jump = false
	bot.crouch = false
	apex = take.y
	landed = false
	var flight := 0
	for i in 240:
		await get_tree().physics_frame
		apex = maxf(apex, cat.global_position.y)
		flight += 1
		if i > 3 and cat.mode == CatPlayer.Mode.GROUND:
			landed = true
			break
	var pd := _flat_dist(cat.global_position, take)
	j["pounce_height_m"] = snappedf(apex - take.y, 0.01)
	j["pounce_distance_m"] = snappedf(pd, 0.01)
	j["pounce_flight_s"] = snappedf(flight * DT, 0.01)
	_check("pounce_full", landed and absf(apex - take.y - cat.pounce_max_height) < 0.4 and absf(pd - cat.pounce_max_distance) < 1.0,
		"full charge: %.2f m high, %.2f m far, %.2f s flight" % [apex - take.y, pd, flight * DT])
	_check("pounce_land_anim", cat.animator.get_state() == &"pounce_land", "state after pounce landing = %s" % cat.animator.get_state())
	await _ticks(60)
	# Coyote time: run off the 1.5 m step platform, press jump 4 ticks after leaving.
	_reset(Vector3(-8, 1.6, -5.8), 0.0)
	await _settle()
	bot.move = Vector2(0, 1)
	var left_at := -1
	for i in 120:
		await get_tree().physics_frame
		if cat.mode == CatPlayer.Mode.AIR:
			left_at = i
			break
	await _ticks(4)
	bot.jump = true
	await _ticks(1)
	var coyote_ok := cat.velocity.y > 5.0
	bot.jump = false
	_check("coyote_time", left_at >= 0 and coyote_ok, "jump 4 ticks (67 ms) after leaving the ledge: vy=%.1f" % cat.velocity.y)
	bot.clear()
	await _settle()
	# Jump buffer: press jump ~6 ticks before touching down.
	_reset(Vector3(0, 3.0, 40), -90.0)
	await _ticks(1)
	var buffered := false
	for i in 200:
		await get_tree().physics_frame
		var below := cat.global_position.y
		if cat.mode == CatPlayer.Mode.AIR and cat.velocity.y < 0.0 and below < 0.05 + absf(cat.velocity.y) * DT * 6.0:
			bot.jump = true
		if bot.jump and cat.mode == CatPlayer.Mode.AIR and cat.velocity.y > 5.0:
			buffered = true
			break
	bot.clear()
	_check("jump_buffer", buffered, "jump pressed ~0.1 s before landing fires on touchdown")
	await _settle()
	metrics["jumps"] = j


func _test_landing() -> void:
	var b0 := blasts.size()
	_reset(Vector3(0, 15.0, 40), -90.0)
	for i in 240:
		await get_tree().physics_frame
		if cat.mode == CatPlayer.Mode.GROUND:
			break
	var impact: float = cat.stats.get("last_impact", 0.0)
	await _ticks(2)
	var st := cat.animator.get_state()
	_check("heavy_landing", impact > 25.0 and st == &"land" and blasts.size() > b0,
		"15 m fall: impact %.1f m/s, anim=%s, landing blasts +%d" % [impact, st, blasts.size() - b0])
	metrics["landing_15m_impact_mps"] = snappedf(impact, 0.1)
	await _settle()


func _test_terrain() -> void:
	# Steps: 6 x 0.25 m risers then a 1.5 m platform.
	_reset(Vector3(-8, 0.05, -0.6), 0.0)
	await _settle()
	bot.move = Vector2(0, 1)
	var t := -1.0
	for i in 300:
		await get_tree().physics_frame
		if cat.global_position.y > 1.45 and cat.mode == CatPlayer.Mode.GROUND:
			t = i * DT
			break
	bot.clear()
	_check("steps", t > 0.0, "climbed 6 steps to the 1.5 m platform in %.2f s (step-ups=%d)" % [t, cat.stats["step_ups"]])
	metrics["steps_time_s"] = snappedf(t, 0.01)
	await _settle()
	# Ramp: 20 degrees up to 2.7 m.
	_reset(Vector3(8.5, 0.05, -2.8), 0.0)
	await _settle()
	bot.move = Vector2(0, 1)
	var top := 0.0
	t = -1.0
	for i in 300:
		await get_tree().physics_frame
		top = maxf(top, cat.global_position.y)
		if cat.global_position.y > 2.4 and t < 0.0:
			t = i * DT
	bot.clear()
	_check("ramp", t > 0.0, "walked up the 20-degree ramp past 2.4 m in %.2f s (max %.2f m)" % [t, top])
	metrics["ramp_time_s"] = snappedf(t, 0.01)
	await _settle()


func _test_climb() -> void:
	var c := {}
	_reset(Vector3(0, 0.05, -9.4), 0.0)   # 2 m in front of the 12 m wall, facing it
	await _settle()
	bot.move = Vector2(0, 1)
	var t_climb := -1.0
	var t_top := -1.0
	var max_mantle := 0.0
	var mantle_t := 0.0
	for i in int(12.0 / DT):
		await get_tree().physics_frame
		if t_climb < 0.0 and cat.mode == CatPlayer.Mode.CLIMB:
			t_climb = i * DT
		mantle_t = mantle_t + DT if cat.mode == CatPlayer.Mode.MANTLE else 0.0
		max_mantle = maxf(max_mantle, mantle_t)
		if cat.global_position.y > 11.9 and cat.mode == CatPlayer.Mode.GROUND:
			t_top = i * DT
			break
	bot.clear()
	c["start_climb_s"] = snappedf(t_climb, 0.01)
	c["wall_top_s"] = snappedf(t_top, 0.01)
	c["mantle_duration_s"] = snappedf(max_mantle, 0.01)
	_check("climb_wall_12m", t_top > 0.0 and t_top <= 10.0, "reached the top of the 12 m wall and mantled in %.2f s (climb began %.2f s)" % [t_top, t_climb])
	await _ticks(30)
	_check("on_top_stable", cat.mode == CatPlayer.Mode.GROUND and cat.global_position.y > 11.9, "standing on the wall top at y=%.2f" % cat.global_position.y)
	# Wall jump.
	_reset(Vector3(-2, 0.05, -9.8), 0.0)
	await _settle()
	bot.move = Vector2(0, 1)
	for i in 120:
		await get_tree().physics_frame
		if cat.mode == CatPlayer.Mode.CLIMB and cat.global_position.y > 2.0:
			break
	bot.move = Vector2.ZERO
	bot.jump = true
	await _ticks(2)
	bot.jump = false
	var vz := cat.velocity.z
	_check("wall_jump", cat.mode == CatPlayer.Mode.AIR and vz > 4.0 and cat.velocity.y > 4.0, "wall jump velocity %s" % str(cat.velocity))
	bot.clear()
	await _settle()
	# Surface vanishes mid-climb: a temporary wall is removed under the cat.
	var tmp := StaticBody3D.new()
	tmp.collision_layer = Layers.STRUCTURE
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 8, 0.6)
	cs.shape = box
	tmp.add_child(cs)
	tmp.position = Vector3(30, 4, 30)
	level.add_child(tmp)
	_reset(Vector3(30, 0.05, 31.6), 0.0)
	await _settle()
	bot.move = Vector2(0, 1)
	for i in 180:
		await get_tree().physics_frame
		if cat.mode == CatPlayer.Mode.CLIMB and cat.global_position.y > 3.0:
			break
	var was_climbing := cat.mode == CatPlayer.Mode.CLIMB
	tmp.queue_free()
	await _ticks(3)
	_check("climb_surface_lost", was_climbing and cat.mode == CatPlayer.Mode.AIR, "climbing=%s, after removal mode=%d" % [was_climbing, cat.mode])
	bot.clear()
	await _settle()
	# Climb down to the ground: back on all fours on the near side, facing away from the wall.
	_reset(Vector3(3, 0.05, -9.4), 0.0)
	await _settle()
	bot.move = Vector2(0, 1)
	for i in 240:
		await get_tree().physics_frame
		if cat.mode == CatPlayer.Mode.CLIMB and cat.global_position.y > 2.5:
			break
	var top_y := cat.global_position.y
	bot.move = Vector2(0, -1)
	var down_t := -1.0
	for i in 360:
		await get_tree().physics_frame
		if cat.mode == CatPlayer.Mode.GROUND:
			down_t = i * DT
			break
	bot.clear()
	await _ticks(5)
	var away := cat.get_facing().z > 0.7
	c["climb_down_s"] = snappedf(down_t, 0.01)
	_check("climb_down", down_t > 0.0 and cat.global_position.y < 0.2 and cat.global_position.z > -11.5 and away,
		"from y=%.1f down to y=%.2f in %.2f s, facing away from the wall=%s" % [top_y, cat.global_position.y, down_t, away])
	await _settle()
	# Drop off the wall (crouch): lets go, falls clear and lands.
	_reset(Vector3(-3, 0.05, -9.4), 0.0)
	await _settle()
	bot.move = Vector2(0, 1)
	for i in 240:
		await get_tree().physics_frame
		if cat.mode == CatPlayer.Mode.CLIMB and cat.global_position.y > 3.0:
			break
	bot.move = Vector2.ZERO
	bot.crouch = true
	await _ticks(2)
	bot.crouch = false
	var let_go := cat.mode == CatPlayer.Mode.AIR
	var landed_t := -1.0
	for i in 180:
		await get_tree().physics_frame
		if cat.mode == CatPlayer.Mode.GROUND:
			landed_t = i * DT
			break
	_check("climb_drop", let_go and landed_t > 0.0 and cat.global_position.z > -11.3, "let go=%s, landed after %.2f s at z=%.2f" % [let_go, landed_t, cat.global_position.z])
	bot.clear()
	await _settle()
	# Vault a thin 1.5 m fence that has no top to stand on.
	var fence := StaticBody3D.new()
	fence.collision_layer = Layers.STRUCTURE
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(4, 1.5, 0.12)
	fcs.shape = fbox
	fence.add_child(fcs)
	level.add_child(fence)
	fence.global_position = Vector3(20, 0.75, -30)
	_reset(Vector3(20, 0.05, -28.6), 0.0)
	await _settle()
	bot.move = Vector2(0, 1)
	var over_t := -1.0
	var max_y := 0.0
	for i in 300:
		await get_tree().physics_frame
		max_y = maxf(max_y, cat.global_position.y)
		if cat.mode == CatPlayer.Mode.GROUND and cat.global_position.z < -30.3:
			over_t = i * DT
			break
	bot.clear()
	c["fence_vault_s"] = snappedf(over_t, 0.01)
	_check("fence_vault", over_t > 0.0, "over the 1.5 m fence and on the ground behind it in %.2f s (peak y %.2f)" % [over_t, max_y])
	fence.queue_free()
	await _settle()
	# Low obstacles are stepped over, not climbed.
	metrics["climb"] = c


func _test_grab() -> void:
	var g := {}
	var crate := _place_crate("Loose1", Vector3(0, 0.36, 7.4))
	_reset(Vector3(0, 0.05, 6.2), 180.0)   # facing +Z: crate then the damage probe behind it
	await _settle()
	bot.grab = true
	await _ticks(2)
	bot.grab = false
	await _ticks(50)
	var holding := cat.grab.is_holding() and cat.grab.held == crate
	var lift := crate.global_position.y - cat.global_position.y
	_check("grab", holding and lift > 0.8, "holding %s, %.2f m above the paws, stand=%.2f" % [crate.name, lift, cat.get_stand_amount()])
	var glow := crate.get_node_or_null("TelekinesisGlow") != null
	_check("grab_glow", glow, "telekinetic light attached while held")
	var probe: Node = level.get_node("DamageProbe")
	var hits0: int = probe.hits.size()
	cat.camera.pitch = deg_to_rad(-4.0)
	bot.attack = true
	await _ticks(36)
	bot.attack = false
	await _ticks(1)
	var v := crate.linear_velocity.length()
	_check("throw", not cat.grab.is_holding() and v > 12.0, "thrown at %.1f m/s (charge %.0f%%)" % [v, cat.grab.charge * 100.0])
	# Track the flight; a hit seen at tick k was computed in tick k-1 from the speed sampled at tick k-2.
	var speeds: Array[float] = [v]
	var path: Array = []
	for i in 90:
		await get_tree().physics_frame
		speeds.append(crate.linear_velocity.length())
		path.append(crate.global_position.snapped(Vector3.ONE * 0.01))
		if probe.hits.size() > hits0:
			break
	var dealt: Array = probe.hits.slice(hits0)
	var energy := 0.0 if dealt.is_empty() else (dealt[0] as DamageHit).energy
	var v_imp := speeds[maxi(speeds.size() - 3, 0)]
	var expect := 0.5 * crate.mass * v_imp * v_imp
	_check("throw_damage", not dealt.is_empty() and (dealt[0] as DamageHit).kind == DamageHit.Kind.BLUNT and absf(energy - expect) < expect * 0.2,
		"probe hit %d time(s): %.0f J BLUNT vs 0.5*m*v^2 = %.0f J at impact speed %.1f m/s (release %.1f m/s)" % [dealt.size(), energy, expect, v_imp, v])
	g["throw_speed_mps"] = snappedf(v, 0.1)
	g["impact_speed_mps"] = snappedf(v_imp, 0.1)
	g["impact_energy_j"] = snappedf(energy, 1.0)
	g["flight_path"] = path
	await _ticks(30)
	# Over the mass limit.
	_place_crate("HeavyCrate", Vector3(-6, 0.61, -6))
	_reset(Vector3(-6, 0.05, -4.6), 0.0)
	await _settle()
	bot.grab = true
	await _ticks(2)
	bot.grab = false
	await _ticks(5)
	_check("grab_mass_limit", not cat.grab.is_holding(), "600 kg crate refused (limit %.0f kg)" % cat.grab.mass_limit)
	# Drop (E again) sets the body down.
	_place_crate("Loose0", Vector3(-1.6, 0.26, -2.2))
	_reset(Vector3(-1.6, 0.05, -1.0), 0.0)
	await _settle()
	bot.grab = true
	await _ticks(2)
	bot.grab = false
	await _ticks(40)
	var had := cat.grab.is_holding()
	bot.grab = true
	await _ticks(2)
	bot.grab = false
	await _ticks(5)
	_check("grab_drop", had and not cat.grab.is_holding(), "E toggles hold / drop")
	metrics["grab"] = g
	await _settle()


func _test_swat() -> void:
	var crate := _place_crate("Loose4", Vector3(0, 0.31, -6.0))
	_reset(Vector3(0, 0.05, -5.15), 0.0)
	await _settle()
	bot.attack = true
	await _ticks(2)
	bot.attack = false
	await _ticks(20)
	var v := crate.linear_velocity.length()
	_check("swat_crate", v > 3.0, "18 kg crate knocked to %.1f m/s (300 N*s)" % v)
	var probe: Node = level.get_node("DamageProbe")
	var h0: int = probe.hits.size()
	_reset(Vector3(0, 0.05, 9.25), 180.0)
	await _settle()
	bot.attack = true
	await _ticks(2)
	bot.attack = false
	await _ticks(20)
	var got: Array = probe.hits.slice(h0)
	var ok := got.size() == 1 and absf((got[0] as DamageHit).energy - 3000.0) < 1.0 and (got[0] as DamageHit).kind == DamageHit.Kind.BLUNT
	_check("swat_damage", ok, "probe received %d hit(s): %s" % [got.size(), str(got.map(func(h: DamageHit) -> String: return "%.0f J / %.0f Ns" % [h.energy, h.impulse]))])
	metrics["swat"] = {"crate_speed_mps": snappedf(v, 0.1)}
	await _settle()


func _test_tools() -> void:
	var belt := cat.belt
	_check("tool_paw_slot1", belt.current_slot == 0 and belt.get_current() is PawTool, "slot 1 = %s" % belt.get_current().tool_name)
	var dummy := CatTool.new()
	dummy.tool_name = "Dummy"
	belt.set_tool(3, dummy)
	# The pee sits in slot 2 from the start: Tab from the paw lands on it, the next Tab skips the empty
	# slot 3 and lands on the dummy.
	bot.tool_cycle = 1
	await _ticks(2)
	var after_cycle := belt.current_slot
	bot.tool_cycle = 1
	await _ticks(2)
	var after_second := belt.current_slot
	bot.tool_slot = 0
	await _ticks(2)
	_check("tool_cycle", after_cycle == 1 and belt.slots[1] is PeeTool and after_second == 3 and belt.current_slot == 0,
		"Tab -> slot %d, Tab -> slot %d, key 1 -> slot %d" % [after_cycle + 1, after_second + 1, belt.current_slot + 1])
	belt.set_tool(3, null)
	dummy.queue_free()


## Temporary test body (freed by the test that made it).
func _make_crate(n: String, pos: Vector3, size: float, mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = n
	body.collision_layer = Layers.PROPS
	body.collision_mask = Layers.SOLID | Layers.PLAYER
	body.mass = mass
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	mi.mesh = mesh
	body.add_child(mi)
	level.add_child(body)
	body.global_position = pos
	return body


func _press_grab() -> void:
	bot.grab = true
	await _ticks(2)
	bot.grab = false


## Paths the builder's suite did not cover: aiming with a held body or an occluder in the camera ray,
## the rubble wake contract, held bodies frozen or removed by another system, protected bodies,
## re-thrown bodies, blast shake and Game.player after the cat is freed.
func _test_integrity() -> void:
	var g := {}
	# 1. Throw while looking up with a big held body: the aim ray must not stop on the held body.
	var big := _make_crate("ReviewBig", Vector3(0, 0.46, 61.3), 0.9, 80.0)
	_reset(Vector3(0, 0.05, 60.0), 180.0)   # facing +Z, open ground ahead
	await _settle()
	await _press_grab()
	await _ticks(60)
	var held_ok := cat.grab.held == big
	cat.camera.pitch = deg_to_rad(20.0)
	await _ticks(20)
	var aim_dir := cat.camera.get_aim_direction()
	var aim_gap := cat.camera.get_aim_point().distance_to(big.global_position)
	bot.attack = true   # a quick tap throw: the body is still in front, not drawn back over the head
	await _ticks(2)
	bot.attack = false
	await _ticks(1)
	var tv := big.linear_velocity
	var fwd_ok := tv.length() > 5.0 and tv.normalized().dot(aim_dir) > 0.6
	g["throw_up_dir_dot"] = snappedf(tv.normalized().dot(aim_dir), 0.01)
	_check("throw_aim_held_body", held_ok and fwd_ok, "held=%s, 0.9 m crate tap-thrown looking 20 deg up: v=%s, dot(v, aim)=%.2f; aim point was %.1f m from the held body" % [held_ok, str(tv.snapped(Vector3.ONE * 0.1)), g["throw_up_dir_dot"], aim_gap])
	await _ticks(90)
	big.queue_free()

	# 2. Something between the camera and the cat (an NPC is not in the spring arm's mask) must not
	#    become the aim point behind the cat.
	_reset(Vector3(0, 0.05, 80.0), 180.0)
	await _settle()
	await _ticks(30)
	var cam := cat.camera.get_camera()
	var cdir := cat.camera.get_aim_direction()
	var occ := StaticBody3D.new()
	occ.collision_layer = Layers.NPC
	var ocs := CollisionShape3D.new()
	var obox := BoxShape3D.new()
	obox.size = Vector3.ONE * 0.4
	ocs.shape = obox
	occ.add_child(ocs)
	level.add_child(occ)
	occ.global_position = cam.global_position + cdir * 0.6
	await _ticks(2)
	var ap := cat.camera.get_aim_point()
	var ahead := (ap - cat.get_chest_position()).dot(cdir)
	_check("aim_ignores_occluder_behind_cat", ahead > 0.5, "occluder 0.6 m in front of the camera: aim point %.1f m ahead of the cat" % ahead)
	occ.queue_free()

	# 3. Rubble contract: wake_rubble returns the body at once, or it appears on the next tick.
	var fake := FakeDebris.new()
	add_child(fake)
	var old_debris: Node = Game.debris
	Game.debris = fake
	var rubble := StaticBody3D.new()
	rubble.collision_layer = Layers.RUBBLE
	var rcs := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(0.5, 0.4, 0.5)
	rcs.shape = rbox
	rubble.add_child(rcs)
	level.add_child(rubble)
	fake.rubble = rubble
	fake.body = _make_crate("ReviewRubble", Vector3(0, -40, 100), 0.5, 20.0)
	fake.body.freeze = true
	for m: String in ["now", "next_tick"]:
		fake.mode = m
		fake.body.freeze = true
		fake.body.global_position = Vector3(0, -40, 100)
		rubble.global_position = Vector3(0, 0.24, 101.0)
		_reset(Vector3(0, 0.05, 100.0), 180.0)
		await _settle()
		await _press_grab()
		await _ticks(6)
		var got := cat.grab.held == fake.body
		_check("rubble_grab_" + m, got, "wake_rubble mode %s: holding the woken body=%s (calls %d)" % [m, got, fake.calls])
		cat.grab.release(Vector3.ZERO)
		await _ticks(10)
	# A failed wake must not leave a stale target: later grabs far away must not reach back to it.
	fake.mode = "never"
	fake.body.freeze = true
	fake.body.global_position = Vector3(0, -40, 100)
	rubble.global_position = Vector3(0, 0.24, 101.0)
	_reset(Vector3(0, 0.05, 100.0), 180.0)
	await _settle()
	await _press_grab()
	await _ticks(10)
	var lure := _make_crate("ReviewLure", Vector3(-1.0, 0.26, 101.6), 0.5, 10.0)
	_reset(Vector3(30, 0.05, 100.0), 90.0)   # 30 m away, facing -X into open ground
	await _settle()
	await _press_grab()
	await _ticks(6)
	_check("rubble_no_stale_grab", not cat.grab.is_holding(), "after a failed wake, a grab 30 m away holds %s" % (str(cat.grab.held.name) if cat.grab.is_holding() else "nothing"))
	if cat.grab.is_holding():
		cat.grab.release(Vector3.ZERO)
	Game.debris = old_debris
	fake.queue_free()
	rubble.queue_free()
	fake.body.queue_free()
	lure.queue_free()
	await _ticks(2)

	# 4. A held body that another system freezes (rubble budget) or frees is let go cleanly.
	var fz := _make_crate("ReviewFreeze", Vector3(0, 0.26, 121.2), 0.5, 10.0)
	_reset(Vector3(0, 0.05, 120.0), 180.0)
	await _settle()
	await _press_grab()
	await _ticks(30)
	var had := cat.grab.held == fz
	fz.freeze = true
	await _ticks(3)
	_check("held_body_frozen", had and not cat.grab.is_holding() and fz.get_node_or_null("TelekinesisGlow") == null,
		"held=%s; after freeze holding=%s glow=%s" % [had, cat.grab.is_holding(), fz.get_node_or_null("TelekinesisGlow") != null])
	fz.freeze = false
	if cat.grab.is_holding():
		cat.grab.release(Vector3.ZERO)
	await _ticks(20)
	await _press_grab()
	await _ticks(30)
	had = cat.grab.held == fz
	fz.queue_free()
	await _ticks(3)
	await _ticks(30)
	_check("held_body_freed", had and not cat.grab.is_holding() and cat.get_stand_amount() < 0.5,
		"held=%s; after free holding=%s stand=%.2f" % [had, cat.grab.is_holding(), cat.get_stand_amount()])
	await _settle()

	# 5. Protected bodies (animals) are never grabbed.
	var pet := _make_crate("ReviewAnimal", Vector3(0, 0.26, 141.2), 0.5, 10.0)
	pet.add_to_group(&"protected")
	_reset(Vector3(0, 0.05, 140.0), 180.0)
	await _settle()
	await _press_grab()
	await _ticks(6)
	_check("grab_protected_refused", not cat.grab.is_holding(), "protected body held=%s" % cat.grab.is_holding())
	pet.queue_free()

	# 6. A body re-thrown before its watcher finished keeps reporting contacts, then gets its original
	#    contact settings back.
	var rt := _make_crate("ReviewRethrow", Vector3(5, 0.26, 141.2), 0.5, 10.0)
	await _ticks(5)
	var mon0 := rt.contact_monitor
	var max0 := rt.max_contacts_reported
	var ccd0 := rt.continuous_cd
	var w1 := ThrownBodyWatcher.attach(rt, cat)
	await _ticks(5)
	ThrownBodyWatcher.attach(rt, cat)
	w1.set("_age", 100.0)   # the first watcher would finish this very tick
	await _ticks(3)
	var monitoring := rt.contact_monitor
	await _ticks(60)
	var watchers := 0
	for c in rt.get_children():
		if c is ThrownBodyWatcher:
			watchers += 1
	_check("rethrow_contact_settings", monitoring and watchers == 0 and rt.contact_monitor == mon0 and rt.max_contacts_reported == max0 and rt.continuous_cd == ccd0,
		"monitoring while re-thrown=%s; after: watchers=%d contact_monitor=%s (was %s) max_contacts=%d (was %d) continuous_cd=%s (was %s)" % [monitoring, watchers, rt.contact_monitor, mon0, rt.max_contacts_reported, max0, rt.continuous_cd, ccd0])
	rt.queue_free()

	# 6b. The thrower is freed while its thrown body is still flying (level swap, despawned thrower):
	#     the impact is still dealt, with no error.
	var thrower := StaticBody3D.new()
	level.add_child(thrower)
	var orphan := _make_crate("ReviewOrphanThrow", Vector3(8, 2.0, 141.2), 0.5, 10.0)
	var ow := ThrownBodyWatcher.attach(orphan, thrower)
	orphan.linear_velocity = Vector3(0, -9, 0)
	thrower.queue_free()
	await _ticks(30)
	var orphan_hits := ow.hits_dealt if is_instance_valid(ow) else -1
	_check("watcher_freed_thrower", orphan_hits >= 1, "thrown body whose thrower was freed dealt %d hit(s)" % orphan_hits)
	await _ticks(40)
	orphan.queue_free()

	# 6c. A small body thrown at full speed (32 m/s = 0.53 m per tick) at a 5 cm pane must hit it, not
	#     tunnel through without dealing damage.
	var pane: StaticBody3D = (load("res://tests/damage_probe.gd") as GDScript).new()
	pane.collision_layer = Layers.STRUCTURE
	var pcs := CollisionShape3D.new()
	var pbox := BoxShape3D.new()
	pbox.size = Vector3(3, 3, 0.05)
	pcs.shape = pbox
	pane.add_child(pcs)
	level.add_child(pane)
	pane.global_position = Vector3(-10, 1.5, 150)
	var pebble := _make_crate("ReviewPebble", Vector3(-10, 1.5, 146.0), 0.12, 1.0)
	pebble.gravity_scale = 0.0
	await _ticks(2)
	ThrownBodyWatcher.attach(pebble, cat)
	pebble.linear_velocity = Vector3(0, 0, 32.0)
	await _ticks(20)
	var pane_hits: int = pane.get("hits").size()
	var stayed := pebble.global_position.z < 150.0
	_check("throw_no_tunnel", pane_hits >= 1 and stayed, "12 cm body at 32 m/s vs a 5 cm pane: %d hit(s), ended at z=%.2f (pane at 150)" % [pane_hits, pebble.global_position.z])
	pebble.queue_free()
	pane.queue_free()

	# 7. Blasts shake the camera with distance falloff.
	_reset(Vector3(0, 0.05, 160.0), 180.0)
	await _settle()
	cat.camera.trauma = 0.0
	DamageRouter.apply_blast(DamageHit.blast(cat.global_position + Vector3(4, 0, 0), 4.0, 60000.0, 2000.0), cat.get_world_3d())
	var near_t := cat.camera.trauma
	cat.camera.trauma = 0.0
	DamageRouter.apply_blast(DamageHit.blast(cat.global_position + Vector3(150, 0, 0), 4.0, 60000.0, 2000.0), cat.get_world_3d())
	var far_t := cat.camera.trauma
	_check("blast_shake", near_t > 0.3 and far_t == 0.0, "trauma from a 60 kJ blast at 4 m %.2f, at 150 m %.2f" % [near_t, far_t])
	cat.camera.trauma = 0.0

	# 8. Game.player must not dangle after the registered cat is freed (level unload / reload).
	var extra: CatPlayer = (load("res://game/player/cat.tscn") as PackedScene).instantiate()
	extra.bot_input = CatInput.new()
	level.add_child(extra)
	extra.global_position = Vector3(0, 0.1, 180.0)
	await _ticks(2)
	var was_extra := Game.player == extra
	extra.queue_free()
	await _ticks(2)
	var dangling := typeof(Game.player) == TYPE_OBJECT and not is_instance_valid(Game.player) and not is_same(Game.player, null)
	g["game_player_after_free"] = "type=%d valid=%s" % [typeof(Game.player), is_instance_valid(Game.player)]
	_check("game_player_released", was_extra and not dangling, "second cat registered=%s; after it is freed Game.player %s" % [was_extra, "dangles (freed instance)" if dangling else "is cleared"])
	Game.register_player(cat)

	# 9. Overlapping hit-stops (player-driven cats only): the first one ending must not cancel the second.
	cat.bot_input = null
	cat._hit_stop(0.1, 0.2)
	await _frames(3)
	cat._hit_stop(0.3, 0.3)
	await _frames(10)   # the first (6 frames) has ended, the second (18 frames) is still running
	var mid := Engine.time_scale
	await _frames(20)
	var after := Engine.time_scale
	cat.bot_input = bot
	_check("hit_stop_overlap", is_equal_approx(mid, 0.3) and is_equal_approx(after, 1.0), "time scale while the second hit-stop runs %.2f, after both %.2f" % [mid, after])

	# 10. Trotting into a light body nudges it, but never a protected one (an animal).
	var pushed := {}
	for prot: bool in [false, true]:
		var nudge := _make_crate("ReviewNudge", Vector3(0, 0.26, 202.0), 0.5, 2.0)
		if prot:
			nudge.add_to_group(&"protected")
		_reset(Vector3(0, 0.05, 199.0), 180.0)
		await _settle()
		var n0 := nudge.global_position
		bot.move = Vector2(0, 1)
		await _ticks(90)
		bot.clear()
		await _ticks(10)
		pushed[prot] = _flat_dist(nudge.global_position, n0)
		nudge.queue_free()
		await _ticks(2)
	_check("push_on_contact", pushed[false] > 0.1, "trotting (5 m/s) into a 2 kg box shoves it %.2f m" % pushed[false])
	_check("push_protected_refused", pushed[true] < 0.02, "the same box in group protected moved %.3f m" % pushed[true])

	# 11. Cost of building the derived animation library (once per session, on the first cat spawn).
	var src: AnimationPlayer = cat.get_node("Visual/Model").find_child("AnimationPlayer", true, false)
	var cached: AnimationLibrary = CatAnimLibrary._cache
	CatAnimLibrary._cache = null
	var t0 := Time.get_ticks_usec()
	CatAnimLibrary.get_library(src)
	g["anim_library_build_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	CatAnimLibrary._cache = cached
	print("anim library build %.1f ms" % g["anim_library_build_ms"])
	metrics["integrity"] = g
	await _settle()


## Nodes and objects must not pile up: no orphan nodes, watchers and glow lights gone once idle.
func _test_leaks() -> void:
	bot.clear()
	if cat.grab.is_holding():
		cat.grab.release(Vector3.ZERO)
	await _ticks(int(ThrownBodyWatcher.MAX_LIFETIME / DT) + 30)
	var watchers := get_tree().root.find_children("ThrownBodyWatcher*", "", true, false).size()
	var lights := get_tree().root.find_children("TelekinesisGlow*", "", true, false).size()
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	metrics["leaks"] = {"watchers": watchers, "glow_lights": lights, "orphan_nodes": orphans,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)), "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))}
	_check("no_leaked_nodes", watchers == 0 and lights == 0 and orphans == 0, "after the suite: watchers %d, glow lights %d, orphan nodes %d" % [watchers, lights, orphans])


func _test_void() -> void:
	var b0 := blasts.size()
	_reset(Vector3(10, -70, 10), 0.0)
	await _ticks(2)
	var p := cat.global_position
	var ok_pos := p.y > 240.0 and absf(p.x) <= 450.0 and absf(p.z) <= 450.0
	_check("void_teleport", ok_pos, "y<-60 -> dropped to %s" % str(p))
	# Steer a little on the way down.
	bot.move = Vector2(0.4, 0.8)
	var t := 0.0
	var landed := false
	for i in int(20.0 / DT):
		await get_tree().physics_frame
		t += DT
		if cat.mode == CatPlayer.Mode.GROUND:
			landed = true
			break
	bot.clear()
	await _ticks(1)
	var up: Vector3 = (cat.get_node("Visual") as Node3D).global_basis.y.normalized()
	var blast_ok := blasts.size() > b0
	var e := 0.0
	if blast_ok:
		e = blasts[blasts.size() - 1].energy
	_check("void_landing", landed and blast_ok, "fell %.1f s, landed at %s, impact %.1f m/s, blast %.0f kJ" % [t, str(cat.global_position.snapped(Vector3.ONE * 0.1)), cat.stats.get("last_impact", 0.0), e / 1000.0])
	await _ticks(20)
	up = (cat.get_node("Visual") as Node3D).global_basis.y.normalized()
	_check("void_on_feet", up.dot(Vector3.UP) > 0.95, "visual up after landing %s" % str(up.snapped(Vector3.ONE * 0.01)))
	# Edge of the world.
	_reset(Vector3(565, 2.0, 0), 0.0)
	await _ticks(2)
	_check("edge_teleport", absf(cat.global_position.x) <= 450.0 and cat.global_position.y > 240.0, "|x|>560 -> %s" % str(cat.global_position.snapped(Vector3.ONE)))
	metrics["void"] = {"fall_time_s": snappedf(t, 0.01), "blast_energy_j": snappedf(e, 1.0), "impact_mps": cat.stats.get("last_impact", 0.0)}
	_reset(Vector3(0, 0.1, 40), -90.0)
	await _settle()


func _test_lava() -> void:
	var fake := FakeLavaTerrain.new()
	add_child(fake)
	var old: Node = Game.terrain
	Game.terrain = fake
	_reset(Vector3(40, 0.05, 44), 0.0)
	await _settle()
	bot.move = Vector2(0, 1)
	var vy := 0.0
	for i in 120:
		await get_tree().physics_frame
		if cat.stats["lava_launches"] > 0:
			vy = cat.velocity.y
			break
	bot.clear()
	var spun := false
	var landed := false
	for i in int(6.0 / DT):
		await get_tree().physics_frame
		spun = spun or cat._spin_speed > 0.0
		if cat.mode == CatPlayer.Mode.GROUND:
			landed = true
			break
	Game.terrain = old
	fake.queue_free()
	_check("lava_launch", vy > 30.0 and spun and landed, "launched at vy=%.1f m/s with spin, landed=%s" % [vy, landed])
	await _settle()


func _test_soak() -> void:
	# Randomised play in segments of 3-8 s. Each segment picks a behaviour: free random input, running
	# at the wall (climb / wall jump / drop), grabbing and throwing crates, steps and ramp, pounces,
	# standing and swatting. Crates are put back every 60 s and the cat is pulled into the void every
	# 60 s. Watchdogs: never inside a collider > 0.2 s, always finite, no mantle > 1 s, no 3 s air hover.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var ticks := int(soak_seconds / DT)
	var probe_shape := SphereShape3D.new()
	probe_shape.radius = CatPlayer.RADIUS - 0.04
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe_shape
	q.collision_mask = Layers.WALKABLE
	var space := cat.get_world_3d().direct_space_state
	var crate_home := {}
	for c in level.crates:
		crate_home[c] = c.global_transform
	var inside_t := 0.0
	var max_inside := 0.0
	var nonfinite := 0
	var stuck_air := 0
	var air_ys: Array[float] = []
	var mode_time := {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0}
	var max_mode_run := {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0}
	var run_mode := -1
	var run_t := 0.0
	# Wall time between consecutive ticks (headless runs unthrottled, so this is the whole frame's CPU
	# cost). Performance.TIME_PHYSICS_PROCESS / TIME_PROCESS are not usable here: they hold the maximum
	# of the last wall-clock second and change only once per second.
	var frame_ms: Array[float] = []
	var behaviours := {}
	var s0 := cat.stats.duplicate()
	_reset(Vector3(0, 0.05, 0), 0.0)
	var seg_end := 0
	var next_change := 0
	var behaviour := "random"
	var t_prev := Time.get_ticks_usec()
	for i in ticks:
		if i >= seg_end:
			seg_end = i + rng.randi_range(180, 480)
			behaviour = _pick_behaviour(rng)
			behaviours[behaviour] = int(behaviours.get(behaviour, 0)) + 1
			_start_behaviour(behaviour, rng)
			next_change = i
		if i >= next_change:
			next_change = i + rng.randi_range(9, 72)
			_drive_behaviour(behaviour, rng)
		if i % 3600 == 1800:
			if cat.grab.is_holding():
				cat.grab.release(Vector3.ZERO)
			for c: RigidBody3D in crate_home:
				c.global_transform = crate_home[c]
				c.linear_velocity = Vector3.ZERO
				c.angular_velocity = Vector3.ZERO
			cat.global_position = Vector3(rng.randf_range(-50, 50), -65, rng.randf_range(-50, 50))
		await get_tree().physics_frame
		var t_now := Time.get_ticks_usec()
		frame_ms.append((t_now - t_prev) / 1000.0)
		t_prev = t_now
		var pos := cat.global_position
		if not pos.is_finite() or not cat.velocity.is_finite():
			nonfinite += 1
		q.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP * CatPlayer.RADIUS)
		var ex: Array[RID] = [cat.get_rid()]
		if cat.grab.is_holding():
			ex.append(cat.grab.held.get_rid())
		q.exclude = ex
		var inside := cat.mode != CatPlayer.Mode.MANTLE and not space.intersect_shape(q, 1).is_empty()
		inside_t = inside_t + DT if inside else 0.0
		max_inside = maxf(max_inside, inside_t)
		if inside and is_equal_approx(inside_t, DT * 3.0):
			var hits := space.intersect_shape(q, 4)
			var names := hits.map(func(h: Dictionary) -> String: return str(h.get("collider").name) if h.get("collider") != null else "rid")
			print("OVERLAP tick=%d behaviour=%s mode=%d pos=%s vel=%s with=%s holding=%s stand=%.2f" % [i, behaviour, cat.mode,
				str(pos.snapped(Vector3.ONE * 0.01)), str(cat.velocity.snapped(Vector3.ONE * 0.01)), str(names), cat.grab.is_holding(), cat.get_stand_amount()])
		mode_time[cat.mode] += DT
		if cat.mode == run_mode:
			run_t += DT
		else:
			run_mode = cat.mode
			run_t = 0.0
		max_mode_run[cat.mode] = maxf(max_mode_run[cat.mode], run_t)
		if cat.mode == CatPlayer.Mode.AIR:
			air_ys.append(pos.y)
			if air_ys.size() >= 180:
				var lo := air_ys[0]
				var hi := air_ys[0]
				for y in air_ys:
					lo = minf(lo, y)
					hi = maxf(hi, y)
				if hi - lo < 0.05:
					stuck_air += 1
					air_ys.clear()
				else:
					air_ys.remove_at(0)
		else:
			air_ys.clear()
	bot.clear()
	var deltas := {}
	for k in ["depenetrations", "safe_resets", "nonfinite", "sky_drops", "climbs", "mantles", "jumps", "pounces", "throws", "landing_blasts", "step_ups", "wall_jumps", "lava_launches"]:
		deltas[k] = int(cat.stats[k]) - int(s0.get(k, 0))
	metrics["soak"] = {
		"seconds": soak_seconds, "ticks": ticks, "max_inside_collider_s": snappedf(max_inside, 0.001), "nonfinite_ticks": nonfinite,
		"stuck_air_events": stuck_air, "behaviour_segments": behaviours,
		"mode_time_s": {"ground": snappedf(mode_time[0], 0.1), "air": snappedf(mode_time[1], 0.1), "climb": snappedf(mode_time[2], 0.1), "mantle": snappedf(mode_time[3], 0.1)},
		"longest_mantle_s": snappedf(max_mode_run[3], 0.01), "longest_climb_s": snappedf(max_mode_run[2], 0.01), "events": deltas,
		"frame_wall_ms": _stats(frame_ms),
	}
	_check("soak_inside_collider", max_inside <= 0.2, "longest continuous overlap %.3f s over %.0f s" % [max_inside, soak_seconds])
	_check("soak_finite", nonfinite == 0, "non-finite ticks %d" % nonfinite)
	_check("soak_no_stuck_mantle", max_mode_run[3] < 1.0, "longest mantle %.2f s" % max_mode_run[3])
	_check("soak_no_air_hover", stuck_air == 0, "3 s air hovers %d" % stuck_air)
	# The pee is on the belt from the start, so the random runs now spend part of their time standing and
	# peeing: it has to show up in the coverage, and climbs and throws are asked for a little less often
	# than before it existed (they were > 10 and >= 4).
	var pee := cat.belt.slots[ToolKit.slot_of(&"pee")] as PeeTool
	var pee_drops := pee.drops if pee != null else 0
	var cover_ok := int(deltas["climbs"]) >= 8 and int(deltas["mantles"]) > 2 and int(deltas["throws"]) >= 3 and int(deltas["sky_drops"]) >= 4 and pee_drops > 0
	if soak_seconds < 120.0:
		cover_ok = true
	_check("soak_coverage", cover_ok, "events %s, pee drops %d" % [str(deltas), pee_drops])
	_check("soak_safety_net", int(deltas["safe_resets"]) == 0, "watchdog safe resets %d, depenetrations %d" % [deltas["safe_resets"], deltas["depenetrations"]])


## First of `at`, 0.6 m and 1.2 m above it where the cat's sphere does not overlap anything.
func _free_spot(at: Vector3) -> Vector3:
	var shape := SphereShape3D.new()
	shape.radius = CatPlayer.RADIUS + 0.02
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = Layers.WALKABLE
	q.exclude = [cat.get_rid()]
	for h in [0.0, 0.6, 1.2, 2.0]:
		q.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (CatPlayer.RADIUS + h))
		if cat.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			return at + Vector3.UP * h
	return at + Vector3.UP * 3.0


func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var v := values.duplicate()
	v.sort()
	var sum := 0.0
	for x in v:
		sum += x
	return {"avg": snappedf(sum / v.size(), 0.001), "p50": snappedf(v[int(v.size() * 0.5)], 0.001),
		"p99": snappedf(v[int(v.size() * 0.99)], 0.001), "max": snappedf(v[v.size() - 1], 0.001)}


## The cat's own CPU cost per frame: wall time of headless frames with the cat galloping in circles,
## against the same frames with the cat's processing switched off (blocks interleaved A/B/A/B to cancel
## drift from other processes). Covers the controller, AnimationTree, skeleton, pose modifier and
## camera; GPU skinning and rendering are not part of a headless run.
func _test_perf() -> void:
	_reset(Vector3(0, 0.05, 260.0), 0.0)
	await _settle()
	bot.move = Vector2(0.35, 1.0)
	bot.sprint = true
	await _ticks(60)
	# Variants: everything on; AnimationTree paused; pose modifier off; the whole cat off.
	var variants := ["full", "no_anim_tree", "no_pose_modifier", "off"]
	var samples := {}
	for v: String in variants:
		samples[v] = [] as Array[float]
	for round_i in 3:
		for v: String in variants:
			cat.process_mode = Node.PROCESS_MODE_DISABLED if v == "off" else Node.PROCESS_MODE_INHERIT
			cat.animator.tree.active = v != "no_anim_tree"
			cat.pose.active = v != "no_pose_modifier"
			await _ticks(5)
			var arr: Array[float] = samples[v]
			var t_prev := Time.get_ticks_usec()
			for i in 250:
				await get_tree().physics_frame
				var t_now := Time.get_ticks_usec()
				arr.append((t_now - t_prev) / 1000.0)
				t_prev = t_now
	cat.process_mode = Node.PROCESS_MODE_INHERIT
	cat.animator.tree.active = true
	cat.pose.active = true
	bot.clear()
	var st := {}
	for v: String in variants:
		st[v] = _stats(samples[v])
	var base: float = st["off"]["p50"]
	var cost_p50: float = st["full"]["p50"] - base
	var cost_avg: float = st["full"]["avg"] - st["off"]["avg"]
	var tree_ms: float = st["full"]["p50"] - st["no_anim_tree"]["p50"]
	var pose_ms: float = st["full"]["p50"] - st["no_pose_modifier"]["p50"]
	metrics["perf"] = {"frames_each": (samples["full"] as Array).size(), "frame_ms": st,
		"cat_cost_ms_p50": snappedf(cost_p50, 0.001), "cat_cost_ms_avg": snappedf(cost_avg, 0.001),
		"anim_tree_ms_p50": snappedf(tree_ms, 0.001), "pose_modifier_ms_p50": snappedf(pose_ms, 0.001)}
	_check("perf_cat_cost", cost_p50 < 2.0, "cat CPU per frame while galloping in circles: median %.3f ms, mean %.3f ms (AnimationTree %.3f ms, pose modifier %.3f ms, the rest %.3f ms)" % [cost_p50, cost_avg, tree_ms, pose_ms, cost_p50 - tree_ms - pose_ms])
	await _settle()


func _pick_behaviour(rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	if r < 0.3:
		return "random"
	if r < 0.5:
		return "wall"
	if r < 0.67:
		return "crates"
	if r < 0.79:
		return "steps"
	if r < 0.9:
		return "pounce"
	return "stand"


func _start_behaviour(b: String, rng: RandomNumberGenerator) -> void:
	bot.clear()
	if cat.grab.is_holding() and b != "crates":
		cat.grab.release(Vector3.ZERO)
	var at := Vector3.INF
	var yaw := rng.randf_range(-PI, PI)
	match b:
		"wall":
			at = Vector3(rng.randf_range(-4.0, 4.0), 0.05, rng.randf_range(-10.6, -7.0))
			yaw = rng.randf_range(-0.4, 0.4)
		"crates":
			var c: RigidBody3D = level.crates[rng.randi_range(0, level.crates.size() - 1)]
			var off := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.9, 1.8)
			at = Vector3(c.global_position.x + off.x, 0.05, c.global_position.z + off.z)
			yaw = atan2(off.x, off.z)
		"steps":
			if rng.randf() < 0.5:
				at = Vector3(rng.randf_range(-9.0, -7.0), 0.05, rng.randf_range(0.5, 2.5))
			else:
				at = Vector3(rng.randf_range(7.5, 9.5), 0.05, rng.randf_range(-2.5, -0.5))
			yaw = rng.randf_range(-0.3, 0.3)
	if at.is_finite():
		cat.global_position = _free_spot(at)
		cat.velocity = Vector3.ZERO
		cat._set_mode(CatPlayer.Mode.AIR)
		cat.reset_physics_interpolation()
		cat.camera.yaw = yaw


func _drive_behaviour(b: String, rng: RandomNumberGenerator) -> void:
	match b:
		"random":
			var a := rng.randf() * TAU
			var mag: float = [0.0, 0.5, 1.0, 1.0][rng.randi_range(0, 3)]
			bot.move = Vector2(cos(a), sin(a)) * mag
			bot.sprint = rng.randf() < 0.3
			bot.walk = rng.randf() < 0.08
			bot.crouch = rng.randf() < 0.08
			bot.jump = rng.randf() < 0.25
			bot.aim = rng.randf() < 0.08
			bot.stand = rng.randf() < 0.05
			bot.attack = rng.randf() < 0.12
			bot.grab = rng.randf() < 0.06
			bot.interact = rng.randf() < 0.02
			if rng.randf() < 0.03:
				bot.tool_cycle = 1
			cat.camera.yaw += rng.randf_range(-1.2, 1.2)
			cat.camera.pitch = rng.randf_range(-0.9, 0.4)
		"wall":
			var lat := rng.randf_range(-0.7, 0.7) if rng.randf() < 0.3 else 0.0
			bot.move = Vector2(lat, 1.0 if rng.randf() < 0.85 else -1.0)
			bot.sprint = rng.randf() < 0.4
			bot.jump = rng.randf() < 0.12
			bot.crouch = rng.randf() < 0.04
			cat.camera.yaw += rng.randf_range(-0.3, 0.3)
		"crates":
			bot.move = Vector2.ZERO if rng.randf() < 0.6 else Vector2(0, 0.5)
			bot.grab = rng.randf() < 0.35
			bot.attack = cat.grab.is_holding() and rng.randf() < 0.6
			cat.camera.yaw += rng.randf_range(-0.8, 0.8)
			cat.camera.pitch = rng.randf_range(-0.5, 0.3)
		"steps":
			bot.move = Vector2(rng.randf_range(-0.3, 0.3), 1.0)
			bot.sprint = rng.randf() < 0.5
			bot.jump = rng.randf() < 0.15
		"pounce":
			bot.move = Vector2.ZERO
			bot.jump = not bot.jump
			cat.camera.yaw += rng.randf_range(-1.5, 1.5)
		"stand":
			bot.stand = rng.randf() < 0.6
			bot.aim = rng.randf() < 0.5
			bot.attack = rng.randf() < 0.4
			bot.grab = rng.randf() < 0.1
			var a := rng.randf() * TAU
			bot.move = Vector2(cos(a), sin(a)) if rng.randf() < 0.5 else Vector2.ZERO
			cat.camera.yaw += rng.randf_range(-0.6, 0.6)
