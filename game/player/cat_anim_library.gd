class_name CatAnimLibrary
extends RefCounted
## Builds the runtime AnimationLibrary for the hero cat from the GLB clips (built once, cached).
##
## The GLB ships 12 non-looping clips. This derives what the AnimationTree needs:
##  * full loops (idle, walk, trot, gallop, stalk, climb, swim) with LOOP_LINEAR,
##  * sub-clips cut out of longer performances (landing, pounce pin, swat, butt wiggle),
##  * single-key pose clips used as blend-space points (air rise/apex/fall, crouch).
## Leap_Jump bakes its jump height into the hips track; the air poses and the landing clamp the hips
## to standing height because the CharacterBody3D already provides the vertical motion.

const SRC := {
	&"idle": &"Cat_Idle",
	&"walk": &"Cat_Walk",
	&"trot": &"Cat_Trot",
	&"gallop": &"Cat_Gallop_Run",
	&"stalk": &"Cat_Stalk_Hunt",
	&"climb": &"Cat_Climb_Tree",
	&"swim": &"Cat_Swim",
	&"hiss": &"Cat_Hiss_Defensive",
	&"lick": &"Cat_Lick_Paw",
}
const LOOPED: Array[StringName] = [&"idle", &"walk", &"trot", &"gallop", &"stalk", &"climb", &"swim"]
const HIPS_BONE := "hips_106"
const HIPS_STAND_Y := 0.443   ## Hips height of the idle pose, model units.
const FPS := 30.0

## Natural ground speed of each loop at playback rate 1, in model units per second (measured from paw
## stance phases by tests/inspect_gaits.gd). Multiply by the model scale for metres per second.
const NATURAL_SPEED := {
	&"walk": 0.60, &"trot": 1.05, &"gallop": 2.50, &"stalk": 0.20, &"climb": 0.68, &"swim": 0.90,
}

static var _cache: AnimationLibrary = null


static func get_library(source: AnimationPlayer) -> AnimationLibrary:
	if _cache != null:
		return _cache
	var lib := AnimationLibrary.new()
	for key: StringName in SRC:
		var a: Animation = source.get_animation(SRC[key]).duplicate(true)
		a.loop_mode = Animation.LOOP_LINEAR if LOOPED.has(key) else Animation.LOOP_NONE
		lib.add_animation(key, a)
	var leap: Animation = source.get_animation(&"Cat_Leap_Jump")
	var pounce: Animation = source.get_animation(&"Cat_Pounce_Attack")
	var bite: Animation = source.get_animation(&"Cat_Bite_Attack")
	lib.add_animation(&"land", _subclip(leap, 1.58, 2.08, Animation.LOOP_NONE, true))   # from touchdown
	lib.add_animation(&"air_rise", _pose(leap, 1.12, true))
	lib.add_animation(&"air_apex", _pose(leap, 1.28, true))
	lib.add_animation(&"air_fall", _pose(leap, 1.44, true))
	lib.add_animation(&"crouch", _pose(pounce, 0.45, false))
	lib.add_animation(&"wiggle", _subclip(pounce, 0.55, 1.35, Animation.LOOP_PINGPONG, false))
	lib.add_animation(&"pounce_land", _subclip(pounce, 1.66, 2.95, Animation.LOOP_NONE, false))
	lib.add_animation(&"swat", _subclip(bite, 0.30, 1.30, Animation.LOOP_NONE, false))
	_cache = lib
	return lib


## Copy of src between t0 and t1, resampled at FPS. pin_hips keeps the hips at standing height.
static func _subclip(src: Animation, t0: float, t1: float, loop: Animation.LoopMode, pin_hips: bool) -> Animation:
	var a := Animation.new()
	a.length = t1 - t0
	a.loop_mode = loop
	a.step = 1.0 / FPS
	var n := int(ceil((t1 - t0) * FPS))
	for ti in src.get_track_count():
		var nt := _clone_track_header(src, ti, a, loop != Animation.LOOP_NONE)
		if nt < 0:
			continue
		var is_hips_pos := pin_hips and _is_hips_position(src, ti)
		for k in n + 1:
			var t := minf(t0 + float(k) / FPS, t1)
			_insert_sample(src, ti, a, nt, t, t - t0, is_hips_pos)
	return a


## One-key looping clip holding the pose of src at time t.
static func _pose(src: Animation, t: float, pin_hips: bool) -> Animation:
	var a := Animation.new()
	a.length = 0.1
	a.loop_mode = Animation.LOOP_LINEAR
	for ti in src.get_track_count():
		var nt := _clone_track_header(src, ti, a, true)
		if nt < 0:
			continue
		_insert_sample(src, ti, a, nt, t, 0.0, pin_hips and _is_hips_position(src, ti))
	return a


static func _clone_track_header(src: Animation, ti: int, dst: Animation, loop_wrap: bool) -> int:
	var type := src.track_get_type(ti)
	if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_SCALE_3D:
		return -1
	var nt := dst.add_track(type)
	dst.track_set_path(nt, src.track_get_path(ti))
	dst.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
	dst.track_set_interpolation_loop_wrap(nt, loop_wrap)
	return nt


static func _insert_sample(src: Animation, ti: int, dst: Animation, nt: int, t: float, t_dst: float, pin_hips: bool) -> void:
	match src.track_get_type(ti):
		Animation.TYPE_POSITION_3D:
			var p: Vector3 = src.position_track_interpolate(ti, t)
			if pin_hips:
				p.y = minf(p.y, HIPS_STAND_Y)   # drop the baked jump height, keep landing squash
			dst.position_track_insert_key(nt, t_dst, p)
		Animation.TYPE_ROTATION_3D:
			dst.rotation_track_insert_key(nt, t_dst, src.rotation_track_interpolate(ti, t))
		Animation.TYPE_SCALE_3D:
			dst.scale_track_insert_key(nt, t_dst, src.scale_track_interpolate(ti, t))


static func _is_hips_position(src: Animation, ti: int) -> bool:
	return src.track_get_type(ti) == Animation.TYPE_POSITION_3D and String(src.track_get_path(ti)).ends_with(":" + HIPS_BONE)
