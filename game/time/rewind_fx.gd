class_name RewindFX
extends CanvasLayer
## What a rewind looks and sounds like: the picture cools and loses colour, scan lines and a slow
## tracking band roll over it with a slight colour split (a tape played backwards, never green rain),
## "<< REWIND  -3.4 s" in the Owner's teal monospace with a bar of how far back it can go, and a
## tape-rewind warble made in code. It sits under the HUD.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 1.0;
uniform float t = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	float band = smoothstep(0.0, 0.02, fract(uv.y * 1.3 - t * 0.45)) * (1.0 - smoothstep(0.02, 0.05, fract(uv.y * 1.3 - t * 0.45)));
	uv.x += (band * 0.012 + sin(uv.y * 310.0 + t * 40.0) * 0.0007) * strength;
	float split = 0.0028 * strength;
	vec3 c = vec3(texture(screen_tex, uv + vec2(split, 0.0)).r, texture(screen_tex, uv).g, texture(screen_tex, uv - vec2(split, 0.0)).b);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 cool = mix(c, vec3(l) * vec3(0.78, 0.95, 1.1), 0.6 * strength);
	float scan = 1.0 - 0.07 * strength * (0.5 + 0.5 * sin(SCREEN_UV.y * 1100.0));
	COLOR = vec4(cool * scan + vec3(band * 0.08 * strength), 1.0);
}
"""

var _rect: ColorRect
var _mat: ShaderMaterial
var _label: Label
var _bar_back: ColorRect
var _bar: ColorRect
var _sound: AudioStreamPlayer
var _t := 0.0
var _on := false
var _prewarm := 3


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_label = UiKit.label("", 30, UiKit.MONO, 600, UiKit.TEAL)
	_label.position = Vector2(48.0, 40.0)
	add_child(_label)
	_bar_back = ColorRect.new()
	_bar_back.color = Color(1.0, 1.0, 1.0, 0.12)
	_bar_back.position = Vector2(50.0, 92.0)
	_bar_back.size = Vector2(320.0, 5.0)
	add_child(_bar_back)
	_bar = ColorRect.new()
	_bar.color = UiKit.TEAL
	_bar.size = Vector2(0.0, 5.0)
	_bar_back.add_child(_bar)
	_sound = AudioStreamPlayer.new()
	_sound.stream = _warble()
	_sound.volume_db = -14.0
	if AudioServer.get_bus_index(&"SFX") >= 0:
		_sound.bus = &"SFX"
	add_child(_sound)
	# Drawn for a few frames at start so the shader is compiled before the first rewind.
	_mat.set_shader_parameter(&"strength", 0.0)
	_label.visible = false
	_bar_back.visible = false


func start() -> void:
	_on = true
	_t = 0.0
	visible = true
	_rect.visible = true
	_label.visible = true
	_bar_back.visible = true
	_sound.pitch_scale = 0.8
	if DisplayServer.get_name() != "headless":
		_sound.play()


func stop() -> void:
	_on = false
	visible = false
	_sound.stop()


func show_depth(d: float, max_d: float) -> void:
	_label.text = tr("<< REWIND   -%.1f s") % d
	_bar.size = Vector2(_bar_back.size.x * clampf(d / maxf(max_d, 0.01), 0.0, 1.0), 5.0)
	_sound.pitch_scale = lerpf(0.8, 1.35, clampf(d / maxf(max_d, 0.01), 0.0, 1.0)) if d < max_d - 0.01 else 0.6


func _process(delta: float) -> void:
	if _prewarm > 0:
		_prewarm -= 1
		if _prewarm == 0 and not _on:
			visible = false
		return
	if not _on:
		return
	var real := delta / maxf(Engine.time_scale, 0.0001)
	_t += real
	_mat.set_shader_parameter(&"t", _t)
	_mat.set_shader_parameter(&"strength", clampf(_t / 0.25, 0.0, 1.0))
	_label.modulate.a = 0.75 + 0.25 * sin(_t * 9.0)


## A second of tape being wound back: a squealing tone that wobbles up and down, over hiss.
static func _warble() -> AudioStreamWAV:
	var rate := 22050
	var n := rate
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var noise := 0.0
	for i in n:
		var t := float(i) / rate
		var f := 520.0 + 260.0 * sin(TAU * 3.0 * t) + 140.0 * sin(TAU * 11.0 * t)
		phase = fmod(phase + f / rate, 1.0)
		var tone := (2.0 * phase - 1.0) * 0.22 + sin(TAU * phase * 2.0) * 0.12
		noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.35)
		var env := 0.75 + 0.25 * sin(TAU * 7.0 * t)
		var v := clampf((tone + noise * 0.1) * env, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav
