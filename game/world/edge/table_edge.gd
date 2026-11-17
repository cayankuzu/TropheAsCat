class_name TableEdge
extends Node3D
## The end of the Table (docs/DESIGN.md section 4, "the edge"). Where the slab ends the ground turns into
## the Owner's wireframe (terrain shader, u_rim_*), and over the rim hangs a quiet curtain of the Owner's
## code: it rises a little above the hills, so from the city the horizon reads as the end of something
## made, and it hangs far down into the void, where Trophe sees it when she falls. Far below the Table a
## faint grid gives the void a floor that is never reached.
##
## Calm, readable white and teal monospace and clean lines (the art direction of the simulation layer),
## never green rain. Everything here is unshaded and additive: five draw calls, no lights, no shadows.

const HALF := TerrainShape.WORLD_HALF
const RIM_Y := 30.0
const WALL_TOP := 260.0
const WALL_BOTTOM := -1400.0
const CODE_PX := 1024

const CODE := [
	"func keep_the_table_clean() -> void:",
	"    for vase in table.vases:",
	"        vase.position = vase.home    # again",
	"    if trophe.is_near(vase):",
	"        vase.raise(0.4)",
	"table.integrity = 0.997",
	"assert(nothing.falls_off(table))",
	"while trophe.awake:",
	"    owner.patience -= 1",
	"# TODO: make the trees cat-proof   (done)",
	"# TODO: make the vases cat-proof   (impossible)",
	"undo(trophe.chaos)    # backfired",
	"const RULE := \"nothing falls off the Table\"",
	"func _on_meow() -> void:",
	"    pigeons.take_off()",
	"if building.is_load_bearing:",
	"    return    # please",
	"table.edge = 512.0",
	"var mood := \"calm\"",
	"func _on_trophe_fell_off() -> void:",
	"    trophe.drop_from_sky(gently=true)",
	"for person in table.people:",
	"    person.glaze = Color.WHITE",
	"dominoes.count = 44    # three weeks",
	"if table.cleared > 0.15:",
	"    spray_bottle.enable()    # last resort",
	"func pet(cat) -> void:",
	"    pass    # not allowed",
	"world.time_scale = 1.0",
	"# the Table is all there is",
	"# the Table is all there is",
	"var vacuum := Robot.new()",
	"vacuum.collect(rubble)",
	"signal everything_is_fine",
	"emit_signal(\"everything_is_fine\")",
	"if trophe.on_table():",
	"    owner.relax()    # never happens",
	"edge.render(wireframe=true)",
	"func is_off_the_table(thing) -> bool:",
	"    return false    # nothing is",
]

var code_texture: Texture2D
var _walls: Array[MeshInstance3D] = []
var _wall_mat: ShaderMaterial
var _floor_mat: ShaderMaterial


func _ready() -> void:
	_wall_mat = ShaderMaterial.new()
	_wall_mat.shader = _wall_shader()
	_wall_mat.set_shader_parameter(&"rim_y", RIM_Y)
	for side in 4:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(HALF * 2.0 + 60.0, WALL_TOP - WALL_BOTTOM)
		mi.mesh = q
		mi.material_override = _wall_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var y := (WALL_TOP + WALL_BOTTOM) * 0.5
		# A metre and a half out from the cut face, so the code also drifts over the strata.
		var r := HALF + 1.5
		var xf := Transform3D(Basis.IDENTITY, Vector3(0.0, y, -r))
		match side:
			1:
				xf = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, y, r))
			2:
				xf = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-r, y, 0.0))
			3:
				xf = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(r, y, 0.0))
		mi.transform = xf
		add_child(mi)
		_walls.append(mi)
	var deep := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30000.0, 30000.0)
	deep.mesh = plane
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = _floor_shader()
	deep.material_override = _floor_mat
	deep.position = Vector3(0.0, -1500.0, 0.0)
	deep.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(deep)
	_render_code()


## The code is set once with real fonts in a small viewport, then kept as a mipmapped texture (readable
## at the rim, a soft glow from the city).
func _render_code() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(CODE_PX, CODE_PX)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var column := VBoxContainer.new()
	column.position = Vector2(24.0, 12.0)
	column.add_theme_constant_override(&"separation", 1)
	vp.add_child(column)
	var rng := RandomNumberGenerator.new()
	rng.seed = 512
	for i in CODE.size():
		var line: String = CODE[i]
		var bright := rng.randf() < 0.3
		var l := UiKit.label(line, 19, UiKit.MONO, 500, Color(0.95, 1.0, 0.98, 0.95) if bright else Color(0.55, 0.95, 0.9, 0.7))
		l.add_theme_constant_override(&"outline_size", 0)
		column.add_child(l)
	add_child(vp)
	code_texture = vp.get_texture()
	_wall_mat.set_shader_parameter(&"code_tex", code_texture)
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return
	img.generate_mipmaps()
	code_texture = ImageTexture.create_from_image(img)
	_wall_mat.set_shader_parameter(&"code_tex", code_texture)
	vp.queue_free()


static func _wall_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;
uniform sampler2D code_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint = vec3(0.55, 0.95, 0.9);
uniform float rim_y = 30.0;
uniform float up_fade = 38.0;
uniform float down_fade = 500.0;
uniform float tile = 48.0;
uniform float speed = 1.5;
uniform float strength = 0.55;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float along = abs(wpos.x) > abs(wpos.z) ? wpos.z : wpos.x;
	vec2 uv = vec2(along / tile, (-wpos.y - TIME * speed) / tile);
	vec4 c = texture(code_tex, uv);
	vec2 g = abs(fract(vec2(along, wpos.y) / 16.0) - 0.5);
	vec2 gw = fwidth(vec2(along, wpos.y) / 16.0) * 1.5;
	float grid = 1.0 - smoothstep(vec2(0.0), gw + 0.01, 0.5 - g).x * smoothstep(vec2(0.0), gw + 0.01, 0.5 - g).y;
	float h = wpos.y - rim_y;
	float fade = h > 0.0 ? exp(-h / up_fade) : exp(h / down_fade);
	float near_rim = exp(-abs(h) / 6.0);
	// Up close the curtain is only a whisper: it must never wash the picture out.
	float near_cam = smoothstep(4.0, 70.0, distance(CAMERA_POSITION_WORLD, wpos));
	float a = (c.a * 0.85 + grid * (h > 0.0 ? 0.08 : 0.18) + near_rim * 0.5) * fade * strength * near_cam;
	ALBEDO = mix(tint, vec3(1.0), c.r * 0.5) * a;
	ALPHA = 1.0;
}
"""
	return sh


static func _floor_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;
uniform vec3 tint = vec3(0.4, 0.85, 0.8);
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 g = abs(fract(wpos.xz / 80.0) - 0.5);
	vec2 gw = fwidth(wpos.xz / 80.0) * 1.5;
	vec2 on = 1.0 - smoothstep(vec2(0.0), gw + 0.004, 0.5 - g);
	float line = max(on.x, on.y);
	float fade = exp(-length(wpos.xz) / 5000.0);
	ALBEDO = tint * line * fade * 0.6;
	ALPHA = 1.0;
}
"""
	return sh
