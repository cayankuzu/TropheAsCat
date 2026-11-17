class_name GameHud
extends CanvasLayer
## The game's own HUD layer (2026-11-17), next to MiniHud (Owner lines, TABLE CLEARED, chain, tools) and the
## chaos stars: a round radar at the bottom left that turns with the camera (the city drawn once from the
## layout: roads, blocks by district, buildings, parks; blips for the police, the cleanup robots, the giants
## and the jobs), and the name of a district in big letters with a line under it when Trophe walks into it.

const RADIUS_PX := 118.0
const RANGE_M := 140.0          ## metres from the centre to the rim of the radar
const MAP_SIZE := 1024
const DISTRICT_LINES := {
	CityLayout.District.DOWNTOWN: "where the glass is load-bearing",
	CityLayout.District.OLD_QUARTER: "bricks older than your grandmother",
	CityLayout.District.WORKS: "parking for people who hate parking",
	CityLayout.District.PARK: "CAT-PROOF. Mostly.",
	CityLayout.District.STRIP: "everything half price, including the buildings",
	CityLayout.District.YARDS: "containers full of other containers",
	CityLayout.District.SUBURBS: "white fences, dark secrets",
}
## The phones of the city film her chaos (People FILM witnesses): every milestone of views gets a flash and
## a line from the Owner.
const VIEW_MILESTONES: Array[float] = [10000.0, 100000.0, 1000000.0, 10000000.0, 100000000.0]
const VIEW_LINES: PackedStringArray = [
	"Someone filmed that. Of course someone filmed that.",
	"One hundred thousand people watched you break my things.",
	"A million views. You are trending, Trophe. I hate it.",
	"Ten million. My mother saw it.",
	"You are the internet now. I am logging off.",
]
const DISTRICT_TINT := {
	CityLayout.District.DOWNTOWN: Color(0.36, 0.42, 0.52), CityLayout.District.OLD_QUARTER: Color(0.55, 0.36, 0.3),
	CityLayout.District.WORKS: Color(0.5, 0.46, 0.34), CityLayout.District.PARK: Color(0.24, 0.42, 0.24),
	CityLayout.District.STRIP: Color(0.27, 0.5, 0.52), CityLayout.District.YARDS: Color(0.52, 0.44, 0.28),
	CityLayout.District.SUBURBS: Color(0.56, 0.52, 0.42),
}

var _main: Node
var _radar: Radar
var _disc: TextureRect          # the map, through the radar shader (round, turned, zoomed)
var _banner: Label
var _tagline: Label
var _banner_t := 0.0
var _district := -1
var _views: Label
var _views_shown := -1
var _views_ready := false
var _milestone := 0


class Radar extends Control:
	var hud: GameHud
	var map: ImageTexture
	var mat: ShaderMaterial
	var blink := 0.0

	func _process(delta: float) -> void:
		blink += delta
		queue_redraw()

	func _draw() -> void:
		var r := GameHud.RADIUS_PX * hud.scale_ui()
		var c := Vector2(r + 26.0 * hud.scale_ui(), size.y - r - 26.0 * hud.scale_ui())
		var cat := Game.player
		var cam := get_viewport().get_camera_3d()
		if cat == null or not is_instance_valid(cat) or cam == null:
			return
		var f3 := -cam.global_basis.z
		var fwd := Vector2(f3.x, f3.z).normalized() if Vector2(f3.x, f3.z).length_squared() > 0.0001 else Vector2(0.0, -1.0)
		var p := cat.global_position
		mat.set_shader_parameter(&"center_uv", Vector2((p.x + MAP_SIZE * 0.5) / MAP_SIZE, (p.z + MAP_SIZE * 0.5) / MAP_SIZE))
		mat.set_shader_parameter(&"fwd", fwd)
		mat.set_shader_parameter(&"zoom", RANGE_M / MAP_SIZE)
		hud._disc.position = c - Vector2(r, r)
		hud._disc.size = Vector2(r, r) * 2.0
		# Blips.
		for b: Array in hud.blips():
			var rel := Vector2(b[0].x - p.x, b[0].z - p.z)
			var right := Vector2(-fwd.y, fwd.x)
			var q := Vector2(rel.dot(right), -rel.dot(fwd)) / RANGE_M
			if q.length() > 1.0:
				if not bool(b[3]):
					continue
				q = q.normalized() * 0.97   # important ones stay on the rim
			draw_circle(c + q * r, float(b[2]) * hud.scale_ui(), b[1])
		# Trophe: an arrow the way she goes (straight up while she stands).
		var vel: Vector3 = cat.get(&"velocity") if cat.get(&"velocity") != null else Vector3.ZERO
		var fv := Vector2(vel.x, vel.z).normalized() if Vector2(vel.x, vel.z).length_squared() > 0.25 else fwd
		var a := atan2(fv.dot(Vector2(-fwd.y, fwd.x)), fv.dot(fwd))
		var s := 9.0 * hud.scale_ui()
		var pts := PackedVector2Array([Vector2(0.0, -1.3), Vector2(0.8, 0.9), Vector2(0.0, 0.45), Vector2(-0.8, 0.9)])
		for i in pts.size():
			pts[i] = c + pts[i].rotated(a) * s
		draw_colored_polygon(pts, Color(1.0, 0.86, 0.3))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.1, 0.06, 0.0), 1.5, true)
		draw_arc(c, r + 3.0, 0.0, TAU, 64, Color(0.95, 0.9, 0.78, 0.85), 2.5 * hud.scale_ui(), true)
		# North on the rim.
		var north := Vector2(-Vector2(0.0, -1.0).dot(Vector2(-fwd.y, fwd.x)), Vector2(0.0, -1.0).dot(fwd) * -1.0)
		draw_circle(c + Vector2(north.x, north.y).normalized() * (r + 3.0), 7.0 * hud.scale_ui(), Color(0.95, 0.35, 0.3))


func setup(main: Node) -> void:
	_main = main
	layer = 5
	_radar = Radar.new()
	_radar.hud = self
	_radar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar.map = ImageTexture.create_from_image(_draw_map(main.get("city") as CityLayout))
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform sampler2D map_tex : filter_linear;
uniform vec2 center_uv;
uniform vec2 fwd;
uniform float zoom;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	vec2 right = vec2(-fwd.y, fwd.x);
	vec2 off = right * p.x - fwd * p.y;
	vec4 col = texture(map_tex, center_uv + off * zoom);
	col.rgb *= mix(1.0, 0.7, smoothstep(0.75, 1.0, r));
	COLOR = vec4(col.rgb, 0.93);
}
"""
	_radar.mat = ShaderMaterial.new()
	_radar.mat.shader = shader
	_radar.mat.set_shader_parameter(&"map_tex", _radar.map)
	_disc = TextureRect.new()
	_disc.texture = _radar.map
	_disc.stretch_mode = TextureRect.STRETCH_SCALE
	_disc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_disc.material = _radar.mat
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_disc)
	add_child(_radar)
	_banner = _label(64, 0.0)
	_tagline = _label(26, 70.0)
	_views = _label(22, 0.0)
	_views.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_views.offset_left = -360.0
	_views.offset_right = -24.0
	_views.offset_top = 104.0
	_views.offset_bottom = 136.0
	_views.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_views.add_theme_color_override(&"font_color", Color(0.62, 0.9, 1.0))


func scale_ui() -> float:
	var vp := get_viewport()
	return clampf(vp.get_visible_rect().size.y / 720.0, 0.75, 2.5) if vp != null else 1.0


func _label(size: int, y: float) -> Label:
	var l := Label.new()
	l.add_theme_font_override(&"font", UiKit.font(UiKit.FREDOKA, 600))
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.85))
	l.add_theme_color_override(&"font_outline_color", Color(0.04, 0.06, 0.1, 0.9))
	l.add_theme_constant_override(&"outline_size", 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	l.offset_left = -600.0
	l.offset_right = 600.0
	l.offset_top = 178.0 + y     # under the TABLE CLEARED ring and the Owner's line
	l.offset_bottom = 258.0 + y
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0
	add_child(l)
	return l


func _process(delta: float) -> void:
	var cat := Game.player
	if cat == null or not is_instance_valid(cat):
		return
	var d := CityLayout.district_at(cat.global_position)
	if d != _district:
		_district = d
		if d != CityLayout.District.NONE:
			_banner.text = Lang.upper(tr(CityLayout.DISTRICT_NAMES[d]))
			_tagline.text = tr(String(DISTRICT_LINES.get(d, "")))
			_banner_t = 4.0
	if _banner_t > 0.0:
		_banner_t -= delta
		var a := clampf(_banner_t / 0.8, 0.0, 1.0) * clampf((4.0 - _banner_t) / 0.4, 0.0, 1.0)
		_banner.modulate.a = a
		_tagline.modulate.a = a
	_update_views()


func _update_views() -> void:
	var people := _main.get("people") as People if _main != null else null
	if people == null or _views == null:
		return
	if not _views_ready:
		_views_ready = true   # milestones already passed in a loaded game are not announced again
		while _milestone < VIEW_MILESTONES.size() and people.views >= VIEW_MILESTONES[_milestone]:
			_milestone += 1
	var v := int(people.views)
	if v != _views_shown:
		_views_shown = v
		_views.text = tr("%s VIEWS") % short_number(v)
		_views.modulate.a = 1.0 if v > 0 else 0.0
	while _milestone < VIEW_MILESTONES.size() and people.views >= VIEW_MILESTONES[_milestone]:
		var hud := _main.get("hud") as MiniHud
		if hud != null:
			hud.flash(tr("GOING VIRAL  -  %s views") % short_number(int(VIEW_MILESTONES[_milestone])), 3.0)
		var voice := _main.get("owner_voice") as OwnerVoice
		if voice != null:
			voice.speak(VIEW_LINES[_milestone], true)
		_milestone += 1


## 950, 12.4K, 3.1M.
static func short_number(v: int) -> String:
	if v >= 1000000:
		return "%.1fM" % (v / 1000000.0)
	if v >= 1000:
		return "%.1fK" % (v / 1000.0)
	return str(v)


## [world position, colour, size in px, stays on the rim when out of range]
func blips() -> Array:
	var out := []
	var on := fmod(_radar.blink * 3.0, 1.0) < 0.5
	var police: Police = _main.get("police")
	if police != null:
		for u in police.units:
			if not u.car.gone:
				out.append([u.car.pos, Color(1.0, 0.2, 0.15) if on else Color(0.25, 0.45, 1.0), 5.0, true])
	var robots: CleanupRobots = _main.get("robots")
	if robots != null:
		for r in robots.robots:
			if is_instance_valid(r.prop):
				out.append([r.prop.global_position, Color(0.45, 1.0, 0.9), 3.5, false])
	var sp: SetPieces = _main.get("set_pieces")
	if sp != null:
		for g in sp.giants:
			if not g.broken:
				out.append([g.global_position, Color(1.0, 0.95, 0.8), 5.5, false])
	var jobs: Object = _main.get("jobs")
	if jobs != null and jobs.has_method(&"radar_blips"):
		out.append_array(jobs.call(&"radar_blips"))
	return out


## The city from above, 1 px a metre: the Table, the blocks by district, the buildings, the roads.
static func _draw_map(city: CityLayout) -> Image:
	var img := Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8)
	var half := MAP_SIZE >> 1
	img.fill(Color(0.02, 0.03, 0.05, 1.0))
	img.fill_rect(Rect2i(half - 484, half - 484, 968, 968), Color(0.2, 0.3, 0.2))   # the hills, up to the rim
	if city == null:
		return img
	var reach := int(CityLayout.half_extent())
	img.fill_rect(Rect2i(half - reach, half - reach, reach * 2, reach * 2), Color(0.25, 0.34, 0.24))
	for b in CityLayout.block_order():
		var c := CityLayout.block_centre(b)
		var tint: Color = DISTRICT_TINT.get(CityLayout.district_at(c), Color(0.3, 0.3, 0.3))
		img.fill_rect(Rect2i(half + int(c.x) - 52, half + int(c.z) - 52, 104, 104), tint.lerp(Color(0.3, 0.32, 0.3), 0.35))
	for r in city.car_parks:
		img.fill_rect(Rect2i(half + int(r.position.x), half + int(r.position.y), int(r.size.x), int(r.size.y)), Color(0.22, 0.23, 0.25))
	var sm := Game.structures as StructureManager
	if sm != null:
		for lot in city.lots:
			var fp := sm.building_footprint(int(lot["bid"]))
			var tint: Color = DISTRICT_TINT.get(int(lot["district"]), Color(0.5, 0.5, 0.5))
			img.fill_rect(Rect2i(half + int(fp.position.x), half + int(fp.position.y), maxi(int(fp.size.x), 1), maxi(int(fp.size.y), 1)), tint.lightened(0.25))
	for line in CityLayout.road_lines():
		var l := int(line)
		img.fill_rect(Rect2i(half + l - 12, half - reach, 24, reach * 2), Color(0.62, 0.6, 0.56))   # sidewalks
		img.fill_rect(Rect2i(half - reach, half + l - 12, reach * 2, 24), Color(0.62, 0.6, 0.56))
	for line in CityLayout.road_lines():
		var l := int(line)
		img.fill_rect(Rect2i(half + l - 8, half - reach, 16, reach * 2), Color(0.16, 0.17, 0.19))
		img.fill_rect(Rect2i(half - reach, half + l - 8, reach * 2, 16), Color(0.16, 0.17, 0.19))
	return img
