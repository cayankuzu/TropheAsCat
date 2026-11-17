class_name CatProofFX
extends Node3D
## What the player sees when something CAT-PROOF (a tree, an animal) is hit: the Owner's teal hexagon
## ripple at the spot and a small "CAT-PROOF" tag that floats up. Listens to DamageRouter.protected_hit.
## Ripples and tags are pooled, and one target answers at most once every REPLY_GAP seconds, so a beam
## or a blast over a whole avenue stays readable. The boing sound comes from the Audio autoload.

const SHADER := preload("res://game/fx/fx_shield.gdshader")
const FONT_PATH := "res://assets/fonts/JetBrainsMono.ttf"
const TEAL := Color(0.45, 0.95, 0.9)
const POOL := 8
const REPLY_GAP := 0.6
const RIPPLE_SECONDS := 0.55
const TAG_SECONDS := 1.1
const TAG_RISE := 0.55

var answers := 0

var _ripples: Array[MeshInstance3D] = []
var _ripple_age := PackedFloat32Array()
var _tags: Array[Label3D] = []
var _tag_age := PackedFloat32Array()
var _tag_from := PackedVector3Array()
var _next_ripple := 0
var _next_tag := 0
var _last_reply := {}   # target instance id -> seconds


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var material := ShaderMaterial.new()
	material.shader = SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	var font: Font = load(FONT_PATH) as Font if ResourceLoader.exists(FONT_PATH) else null
	for i in POOL:
		var ripple := MeshInstance3D.new()
		ripple.name = "Ripple%d" % i
		ripple.mesh = quad
		ripple.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ripple.visible = false
		add_child(ripple)
		_ripples.append(ripple)
		_ripple_age.append(RIPPLE_SECONDS)
		var tag := Label3D.new()
		tag.name = "Tag%d" % i
		tag.text = "CAT-PROOF"
		if font != null:
			tag.font = font
		tag.font_size = 44
		tag.outline_size = 10
		tag.pixel_size = 0.0007
		tag.fixed_size = true
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.shaded = false
		tag.render_priority = 2
		tag.outline_render_priority = 1
		tag.modulate = TEAL
		tag.outline_modulate = Color(0.02, 0.12, 0.13, 0.85)
		tag.visible = false
		add_child(tag)
		_tags.append(tag)
		_tag_age.append(TAG_SECONDS)
		_tag_from.append(Vector3.ZERO)
	DamageRouter.protected_hit.connect(_on_protected_hit)
	set_process(false)


## Ripple and tag at a world position. strength 0..1 sizes the ripple.
func answer(pos: Vector3, strength: float = 0.5) -> void:
	answers += 1
	var i := _next_ripple
	_next_ripple = (_next_ripple + 1) % POOL
	var size := lerpf(1.3, 3.2, clampf(strength, 0.0, 1.0))
	_ripples[i].global_transform = Transform3D(Basis.from_scale(Vector3.ONE * size), pos)
	_ripples[i].set_instance_shader_parameter(&"progress", 0.0)
	_ripples[i].set_instance_shader_parameter(&"tint", TEAL)
	_ripples[i].visible = true
	_ripple_age[i] = 0.0
	var t := _next_tag
	_next_tag = (_next_tag + 1) % POOL
	_tag_from[t] = pos + Vector3.UP * (size * 0.3)
	_tags[t].global_position = _tag_from[t]
	_tags[t].visible = true
	_tag_age[t] = 0.0
	set_process(true)


func _process(delta: float) -> void:
	var busy := false
	for i in POOL:
		if _ripple_age[i] < RIPPLE_SECONDS:
			_ripple_age[i] += delta
			if _ripple_age[i] >= RIPPLE_SECONDS:
				_ripples[i].visible = false
			else:
				busy = true
				_ripples[i].set_instance_shader_parameter(&"progress", _ripple_age[i] / RIPPLE_SECONDS)
		if _tag_age[i] < TAG_SECONDS:
			_tag_age[i] += delta
			if _tag_age[i] >= TAG_SECONDS:
				_tags[i].visible = false
			else:
				busy = true
				var k := _tag_age[i] / TAG_SECONDS
				_tags[i].global_position = _tag_from[i] + Vector3.UP * (TAG_RISE * (1.0 - pow(1.0 - k, 2.0)))
				var alpha := smoothstep(0.0, 0.12, k) * (1.0 - smoothstep(0.65, 1.0, k))
				_tags[i].modulate = Color(TEAL.r, TEAL.g, TEAL.b, alpha)
				_tags[i].outline_modulate = Color(0.02, 0.12, 0.13, 0.85 * alpha)
	if not busy:
		set_process(false)


func _on_protected_hit(hit: DamageHit, target: Object) -> void:
	if target == null or not is_instance_valid(target):
		return
	var id := target.get_instance_id()
	var now := Time.get_ticks_msec() * 0.001
	if now - float(_last_reply.get(id, -10.0)) < REPLY_GAP:
		return
	if _last_reply.size() > 256:
		_last_reply.clear()
	_last_reply[id] = now
	var pos := hit.position
	var node := target as Node3D
	if hit.radius > 0.0 and node != null:
		# A blast only knows the target's origin (a tree's foot): answer at chest height on the side
		# that faces the blast.
		var base := node.global_position + Vector3.UP * 1.3
		var toward := hit.position - base if hit.direction == Vector3.ZERO else -hit.direction
		toward.y = 0.0
		pos = base + (toward.normalized() * 0.5 if toward.length_squared() > 0.01 else Vector3.ZERO)
	answer(pos, clampf((log(maxf(hit.energy, 10.0)) / log(10.0) - 3.0) / 4.0, 0.0, 1.0))
