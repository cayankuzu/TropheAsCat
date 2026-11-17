extends Node
## Autoload "Audio": every sound in the game goes through here.
##
## A sound kind is a folder under res://assets/audio/sfx/; every file in it is a variation. Unknown kinds
## are ignored silently. Per-file loudness trims (dB) come from res://game/audio/bank_gains.json.
## Besides the API below, this node listens to the world itself (blasts, destroyed elements, collapsing
## clusters, the cat landing or throwing, digging, cat-proof hits) so other modules need no audio code.

const SFX_ROOT := "res://assets/audio/sfx/"
const MUSIC_ROOT := "res://assets/audio/music/"
const GAINS_PATH := "res://game/audio/bank_gains.json"
const POOL_3D := 28
const POOL_UI := 6
const MUSIC_DB := -15.0

const DEFAULTS := {"db": -6.0, "unit": 12.0, "far": 250.0, "voices": 4, "gap": 0.05, "pitch": 0.08}
const KINDS := {
	&"explosion": {"db": 2.0, "unit": 45.0, "far": 1200.0, "voices": 5, "gap": 0.07},
	&"boom": {"db": 0.0, "unit": 60.0, "far": 1500.0, "voices": 3, "gap": 0.15, "pitch": 0.05},
	&"collapse_large": {"db": 1.0, "unit": 50.0, "far": 1200.0, "voices": 2, "gap": 1.2, "pitch": 0.06},
	&"collapse_small": {"db": -2.0, "unit": 28.0, "far": 600.0, "voices": 4, "gap": 0.18},
	&"rumble": {"db": -3.0, "unit": 60.0, "far": 1200.0, "voices": 2, "gap": 2.0, "pitch": 0.04},
	&"impact_concrete": {"db": -5.0, "unit": 14.0, "far": 300.0, "voices": 6, "gap": 0.04, "pitch": 0.12},
	&"impact_glass": {"db": -7.0, "unit": 12.0, "far": 250.0, "voices": 5, "gap": 0.05, "pitch": 0.12},
	&"impact_metal": {"db": -7.0, "unit": 14.0, "far": 300.0, "voices": 4, "gap": 0.06, "pitch": 0.1},
	&"impact_wood": {"db": -7.0, "unit": 12.0, "far": 250.0, "voices": 4, "gap": 0.06, "pitch": 0.1},
	&"impact_ceramic": {"db": -7.0, "unit": 10.0, "far": 200.0, "voices": 4, "gap": 0.05, "pitch": 0.12},
	&"car_crash": {"db": -2.0, "unit": 25.0, "far": 500.0, "voices": 2, "gap": 0.3},
	&"fire_whoosh": {"db": -4.0, "unit": 14.0, "far": 300.0, "voices": 4, "gap": 0.08},
	&"laser_zap": {"db": -10.0, "unit": 8.0, "far": 150.0, "voices": 2, "gap": 0.1},
	&"laser_loop": {"db": -12.0, "unit": 8.0, "far": 150.0},
	&"acid_loop": {"db": -9.0, "unit": 8.0, "far": 150.0},
	&"fire_loop": {"db": -8.0, "unit": 10.0, "far": 200.0},
	&"cat_purr": {"db": -10.0, "unit": 4.0, "far": 60.0},
	&"whoosh": {"db": -9.0, "unit": 8.0, "far": 120.0, "voices": 3, "gap": 0.08, "pitch": 0.15},
	&"hairball_fire": {"db": -5.0, "unit": 8.0, "far": 150.0, "voices": 3, "gap": 0.1, "pitch": 0.12},
	&"dig": {"db": -8.0, "unit": 10.0, "far": 200.0, "voices": 3, "gap": 0.12, "pitch": 0.12},
	&"cat_meow": {"db": -6.0, "unit": 6.0, "far": 120.0, "voices": 2, "gap": 0.25, "pitch": 0.1},
	&"cat_hiss": {"db": -8.0, "unit": 6.0, "far": 100.0, "voices": 1, "gap": 0.6},
	&"cat_land": {"db": -8.0, "unit": 8.0, "far": 150.0, "voices": 2, "gap": 0.15, "pitch": 0.1},
	&"cat_proof_boing": {"db": -8.0, "unit": 10.0, "far": 200.0, "voices": 2, "gap": 0.2, "pitch": 0.1},
	&"pigeon": {"db": -10.0, "unit": 8.0, "far": 150.0, "voices": 3, "gap": 0.2, "pitch": 0.1},
	&"footstep": {"db": -24.0, "unit": 3.0, "far": 40.0, "voices": 3, "gap": 0.07, "pitch": 0.15},
	&"ui_click": {"db": -12.0},
	&"owner_chime": {"db": -10.0},
}
const ALIASES := {
	&"porcelain_shatter": &"impact_ceramic", &"impact_brick": &"impact_concrete", &"impact_plaster": &"impact_concrete",
	&"ui_unlock": &"owner_chime", &"pigeon_flap": &"pigeon", &"glitch": &"ui_click",
}
const MOODS := {
	&"lounge": ["local_forecast_elevator", "lobby_time", "bossa_antigua", "hep_cats"],
	&"chaos": ["volatile_reaction"],
	&"intro": ["sneaky_snitch"],
	&"none": [],
}

var _bank: Dictionary = {}        # StringName -> Array[AudioStream]
var _gain: Dictionary = {}        # StringName -> PackedFloat32Array
var _cfg_cache: Dictionary = {}
var _last_idx: Dictionary = {}
var _last_time: Dictionary = {}
var _active: Dictionary = {}      # StringName -> playing voices
var _pool: Array[AudioStreamPlayer3D] = []
var _ui_pool: Array[AudioStreamPlayer] = []
var _loops: Dictionary = {}       # id -> AudioStreamPlayer3D
var _next_loop := 1
var _music: AudioStreamPlayer
var _music_mood: StringName = &"none"
var _music_list: Array[String] = []
var _music_i := 0
var _duck := 0.0
var _amb_park: AudioStreamPlayer
var _amb_wind: AudioStreamPlayer
var _hooked: Dictionary = {}
var _destroyed_pts := PackedVector3Array()
var _destroyed_count := 0
var _last_centroid := Vector3.ZERO
var _step_left := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_scan_bank()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.bus = &"SFX"
		p.finished.connect(_on_voice_finished.bind(p))
		add_child(p)
		_pool.append(p)
	for i in POOL_UI:
		var u := AudioStreamPlayer.new()
		u.bus = &"UI"
		add_child(u)
		_ui_pool.append(u)
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	_music.volume_db = MUSIC_DB
	_music.finished.connect(_next_track)
	add_child(_music)
	_amb_park = _make_bed(&"park_loop")
	_amb_wind = _make_bed(&"wind_loop")
	if DisplayServer.get_name() != "headless":
		set_music_mood(&"lounge")


## One-shot positional sound. Intensity 0..2 scales the volume (1 is the normal level of the kind).
func play_3d(kind: StringName, position: Vector3, intensity: float = 1.0) -> void:
	kind = ALIASES.get(kind, kind)
	if not _bank.has(kind):
		return
	var cfg := _cfg(kind)
	var now := Time.get_ticks_msec() * 0.001
	var gap: float = cfg["gap"]
	if now - float(_last_time.get(kind, -100.0)) < gap:
		return
	var voices: int = cfg["voices"]
	if int(_active.get(kind, 0)) >= voices:
		return
	var p := _free_voice()
	if p == null:
		return
	var streams: Array = _bank[kind]
	var trims: PackedFloat32Array = _gain[kind]
	var idx := _pick(kind, streams.size())
	var pitch: float = cfg["pitch"]
	var db: float = cfg["db"]
	p.stream = streams[idx]
	p.volume_db = db + trims[idx] + linear_to_db(clampf(intensity, 0.05, 2.0))
	p.pitch_scale = 1.0 + randf_range(-pitch, pitch)
	p.unit_size = cfg["unit"]
	p.max_distance = cfg["far"]
	p.position = position
	p.set_meta(&"kind", kind)
	_active[kind] = int(_active.get(kind, 0)) + 1
	_last_time[kind] = now
	p.play()


## Non-positional sound (UI, the chime of the Owner, stingers).
func play_ui(kind: StringName, volume_db: float = 0.0) -> void:
	kind = ALIASES.get(kind, kind)
	if not _bank.has(kind):
		return
	for u in _ui_pool:
		if not u.playing:
			var streams: Array = _bank[kind]
			var db: float = _cfg(kind)["db"]
			u.stream = streams[_pick(kind, streams.size())]
			u.volume_db = volume_db + db
			u.play()
			return


## Starts a positional loop parented to the given node and returns its id (-1 if the kind is unknown).
func start_loop(kind: StringName, parent: Node3D) -> int:
	kind = ALIASES.get(kind, kind)
	if not _bank.has(kind) or parent == null:
		return -1
	var streams: Array = _bank[kind]
	var cfg := _cfg(kind)
	var db: float = cfg["db"]
	var p := AudioStreamPlayer3D.new()
	p.stream = _looped(streams[0])
	p.volume_db = db
	p.unit_size = cfg["unit"]
	p.max_distance = cfg["far"]
	p.bus = &"SFX"
	parent.add_child(p)
	p.play()
	var id := _next_loop
	_next_loop += 1
	_loops[id] = p
	return id


func stop_loop(id: int) -> void:
	if not _loops.has(id):
		return
	# The emitter the loop hangs on may already be gone (a burning wreck that broke up), and with it
	# the player: an untyped read keeps a freed instance from raising an error here.
	var entry: Variant = _loops[id]
	_loops.erase(id)
	if not is_instance_valid(entry):
		return
	var p := entry as AudioStreamPlayer3D
	if p.is_inside_tree():
		var tw := p.create_tween()
		tw.tween_property(p, "volume_db", -60.0, 0.15)
		tw.tween_callback(p.queue_free)
	else:
		p.queue_free()


## Music moods: lounge, chaos, intro, none.
func set_music_mood(mood: StringName) -> void:
	if mood == _music_mood:
		return
	_music_mood = mood
	_music_list.clear()
	var names: Array = MOODS.get(mood, [])
	for n: String in names:
		var path := MUSIC_ROOT + n + ".mp3"
		if ResourceLoader.exists(path):
			_music_list.append(path)
	_music_list.shuffle()
	_music_i = 0
	if _music_list.is_empty():
		_music.stop()
	else:
		_next_track()


func has_kind(kind: StringName) -> bool:
	return _bank.has(ALIASES.get(kind, kind))


func _next_track() -> void:
	if _music_list.is_empty():
		return
	_music.stream = load(_music_list[_music_i % _music_list.size()]) as AudioStream
	_music_i += 1
	_music.volume_db = MUSIC_DB
	_music.play()


func _process(delta: float) -> void:
	_hook()
	_flush_destroyed()
	_duck = maxf(_duck - delta, 0.0)
	if _music.playing:
		_music.volume_db = move_toward(_music.volume_db, MUSIC_DB - (8.0 if _duck > 0.0 else 0.0), delta * 24.0)
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam != null:
		var h := cam.global_position.y
		_amb_wind.volume_db = lerpf(-36.0, -12.0, clampf((h - 15.0) / 120.0, 0.0, 1.0))
		_amb_park.volume_db = lerpf(-24.0, -42.0, clampf((h - 10.0) / 80.0, 0.0, 1.0))
	var player := Game.player
	if player != null and is_instance_valid(player) and player.has_method(&"get_horizontal_speed"):
		var speed: float = player.call(&"get_horizontal_speed")
		var grounded: bool = player.call(&"is_grounded")
		if not grounded or speed < 0.6:
			_step_left = 0.0
		else:
			_step_left -= delta * speed
			if _step_left <= 0.0:
				_step_left = 0.55 + speed * 0.05
				play_3d(&"footstep", player.global_position, clampf(speed / 8.0, 0.4, 1.3))


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_M and Game.player != null:
		play_3d(&"cat_meow", Game.player.global_position + Vector3.UP * 0.3, 1.0)


func _setup_buses() -> void:
	for bus_name: StringName in [&"Music", &"SFX", &"Ambience", &"UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, &"Master")
	if AudioServer.get_bus_effect_count(0) == 0 and ClassDB.class_exists(&"AudioEffectHardLimiter"):
		var lim := ClassDB.instantiate(&"AudioEffectHardLimiter") as AudioEffect
		lim.set(&"ceiling_db", -0.5)
		AudioServer.add_bus_effect(0, lim)


func _scan_bank() -> void:
	var gains: Dictionary = {}
	if FileAccess.file_exists(GAINS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GAINS_PATH))
		if parsed is Dictionary:
			gains = parsed
	var root := DirAccess.open(SFX_ROOT)
	if root == null:
		return
	for kind_dir in root.get_directories():
		var d := DirAccess.open(SFX_ROOT + kind_dir)
		if d == null:
			continue
		var names := {}
		for f in d.get_files():
			var base := f.trim_suffix(".import")
			var ext := base.get_extension().to_lower()
			if ext == "wav" or ext == "ogg" or ext == "mp3":
				names[base] = true
		var keys := names.keys()
		keys.sort()
		var streams: Array[AudioStream] = []
		var trims := PackedFloat32Array()
		for base: String in keys:
			var s := load(SFX_ROOT + kind_dir + "/" + base) as AudioStream
			if s != null:
				streams.append(s)
				trims.append(float(gains.get(kind_dir + "/" + base, 0.0)))
		if not streams.is_empty():
			_bank[StringName(kind_dir)] = streams
			_gain[StringName(kind_dir)] = trims


func _cfg(kind: StringName) -> Dictionary:
	if _cfg_cache.has(kind):
		return _cfg_cache[kind]
	var c: Dictionary = DEFAULTS.duplicate()
	var o: Dictionary = KINDS.get(kind, {})
	for k: String in o:
		c[k] = o[k]
	_cfg_cache[kind] = c
	return c


func _pick(kind: StringName, n: int) -> int:
	if n <= 1:
		return 0
	var idx := randi() % n
	if idx == int(_last_idx.get(kind, -1)):
		idx = (idx + 1) % n
	_last_idx[kind] = idx
	return idx


func _free_voice() -> AudioStreamPlayer3D:
	for p in _pool:
		if not p.playing:
			return p
	return null


func _on_voice_finished(p: AudioStreamPlayer3D) -> void:
	var kind: StringName = p.get_meta(&"kind", &"")
	_active[kind] = maxi(int(_active.get(kind, 0)) - 1, 0)


func _looped(s: AudioStream) -> AudioStream:
	var d := s.duplicate() as AudioStream
	if d is AudioStreamWAV:
		var w := d as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	elif d is AudioStreamOggVorbis:
		(d as AudioStreamOggVorbis).loop = true
	elif d is AudioStreamMP3:
		(d as AudioStreamMP3).loop = true
	return d


func _make_bed(kind: StringName) -> AudioStreamPlayer:
	var b := AudioStreamPlayer.new()
	b.bus = &"Ambience"
	b.volume_db = -60.0
	add_child(b)
	if _bank.has(kind) and DisplayServer.get_name() != "headless":
		var streams: Array = _bank[kind]
		b.stream = _looped(streams[0])
		b.play()
	return b


func _hook() -> void:
	if not _hooked.has(&"router"):
		_hooked[&"router"] = true
		DamageRouter.blast.connect(_on_blast)
		DamageRouter.protected_hit.connect(_on_protected)
		DamageRouter.damage_applied.connect(_on_damage)
	_hook_node(&"structures", Game.structures, {
		&"element_destroyed": _on_element_destroyed, &"cluster_detached": _on_cluster,
		&"building_toppled": _on_topple, &"storey_failed": _on_topple,
	})
	_hook_node(&"debris", Game.debris, {&"impact": _on_debris_impact})
	_hook_node(&"player", Game.player, {&"landed": _on_landed, &"threw": _on_threw, &"dropped_from_sky": _on_sky_drop})
	_hook_node(&"terrain", Game.terrain, {&"dug": _on_dug})


func _hook_node(key: StringName, node: Node, signals: Dictionary) -> void:
	if node == null or not is_instance_valid(node) or _hooked.get(key) == node.get_instance_id():
		return
	_hooked[key] = node.get_instance_id()
	for sig: StringName in signals:
		var fn: Callable = signals[sig]
		if node.has_signal(sig) and not node.is_connected(sig, fn):
			node.connect(sig, fn)


func _on_blast(hit: DamageHit) -> void:
	var e := maxf(hit.energy, 1.0)
	var k := clampf(inverse_lerp(4.3, 7.0, log(e) / log(10.0)), 0.0, 1.0)
	if e < 4.0e4:
		play_3d(&"cat_land", hit.position, 0.6 + k)
		return
	play_3d(&"explosion", hit.position, 0.45 + k)
	if e > 4.0e5:
		play_3d(&"boom", hit.position, 0.5 + k)
		_duck = 1.2
	if e > 3.0e6:
		play_3d(&"rumble", hit.position, 0.8)


func _on_protected(hit: DamageHit, _target: Object) -> void:
	play_3d(&"cat_proof_boing", hit.position, 1.0)


## A debris body landed hard: the sound of its own material, louder for more energy.
func _on_debris_impact(position: Vector3, energy: float, material: StringName) -> void:
	var kind: StringName = &"impact_concrete"
	match MaterialDB.base_of(material):
		&"steel", &"metal_rusty", &"sheet_metal":
			kind = &"impact_metal"
		&"wood":
			kind = &"impact_wood"
		&"glass":
			kind = &"impact_glass"
		&"tile", &"roof":
			kind = &"impact_ceramic"
	play_3d(kind, position, clampf(energy / 40000.0, 0.3, 1.4))


func _on_damage(hit: DamageHit, _target: Object) -> void:
	if hit.kind == DamageHit.Kind.BLUNT and hit.energy > 1500.0:
		play_3d(&"impact_concrete", hit.position, clampf(hit.energy / 20000.0, 0.3, 1.4))


func _on_element_destroyed(bid: int, e: int, _cause: int) -> void:
	_destroyed_count += 1
	var s := Game.structures
	if _destroyed_pts.size() < 12 and s != null and s.has_method(&"element_world_transform"):
		var xf: Transform3D = s.call(&"element_world_transform", bid, e)
		_destroyed_pts.append(xf.origin)


func _flush_destroyed() -> void:
	if _destroyed_count == 0:
		return
	var n := _destroyed_count
	_destroyed_count = 0
	if _destroyed_pts.is_empty():
		return
	var c := Vector3.ZERO
	for p in _destroyed_pts:
		c += p
	c /= float(_destroyed_pts.size())
	_last_centroid = c
	if n >= 40:
		play_3d(&"collapse_large", c, 1.0)
		play_3d(&"rumble", c, 0.7)
	elif n >= 5:
		play_3d(&"collapse_small", c, clampf(float(n) / 20.0, 0.5, 1.3))
	else:
		play_3d(&"impact_concrete", _destroyed_pts[0], 0.9)
	_destroyed_pts.clear()


func _on_cluster(body: RigidBody3D, _bid: int, ids: PackedInt32Array) -> void:
	if is_instance_valid(body):
		var kind: StringName = &"collapse_small" if ids.size() < 30 else &"collapse_large"
		play_3d(kind, body.global_position, clampf(float(ids.size()) / 25.0, 0.6, 1.4))


func _on_topple(_bid: int, _storey: int) -> void:
	play_3d(&"collapse_large", _last_centroid, 1.2)
	play_3d(&"rumble", _last_centroid, 1.0)
	_duck = 1.5


func _on_landed(speed: float) -> void:
	if speed > 3.0 and Game.player != null:
		play_3d(&"cat_land", Game.player.global_position, clampf(speed / 14.0, 0.3, 1.5))


func _on_threw(body: RigidBody3D, _velocity: Vector3) -> void:
	if is_instance_valid(body):
		play_3d(&"whoosh", body.global_position, 1.0)


func _on_sky_drop(at: Vector3) -> void:
	play_3d(&"whoosh", at, 1.2)


func _on_dug(center: Vector3, radius: float, _layer: StringName) -> void:
	if radius < 2.5:
		play_3d(&"dig", center, clampf(radius, 0.4, 1.2))
