class_name UiKit
extends RefCounted
## The look of every menu and screen (docs/DESIGN.md section 2, UI): soft, rounded, friendly, with the
## Owner's calm teal monospace as the accent. Fonts, colours and the button style live here so the
## loading screen, the title and the pause menu stay one family.

const NUNITO := "res://assets/fonts/Nunito.ttf"
const FREDOKA := "res://assets/fonts/Fredoka.ttf"
const MONO := "res://assets/fonts/JetBrainsMono.ttf"

const NAVY := Color(0.055, 0.075, 0.11)
const NAVY_LIGHT := Color(0.1, 0.14, 0.2)
const CREAM := Color(1.0, 0.95, 0.84)
const TEAL := Color(0.55, 0.95, 0.9)
const DIM := Color(1.0, 1.0, 1.0, 0.55)

static var _fonts: Dictionary = {}


## A font with its variable weight set (cached).
static func font(path: String, weight: int = 700) -> Font:
	var key := "%s|%d" % [path, weight]
	if _fonts.has(key):
		return _fonts[key]
	var out: Font = null
	if ResourceLoader.exists(path):
		var base := load(path) as Font
		if base != null:
			var v := FontVariation.new()
			v.base_font = base
			v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
			if path == FREDOKA:
				# Fredoka has no Turkish ş / ğ / İ, and a browser has no system font to fall back on.
				var fallback: Array[Font] = [font(NUNITO, weight)]
				v.fallbacks = fallback
			out = v
	_fonts[key] = out
	return out


static func label(text: String, size: int, path: String = NUNITO, weight: int = 700, color: Color = CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := font(path, weight)
	if f != null:
		l.add_theme_font_override(&"font", f)
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_constant_override(&"outline_size", maxi(2, int(size * 0.1)))
	l.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.45))
	return l


static func box(bg: Color, radius: int = 16, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(14.0)
	s.content_margin_left = 26.0
	s.content_margin_right = 26.0
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	return s


## A menu button: dark glass, teal edge when hovered or focused (keyboard and mouse look the same).
static func button(text: String, size: int = 28) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_ALL
	var f := font(NUNITO, 700)
	if f != null:
		b.add_theme_font_override(&"font", f)
	b.add_theme_font_size_override(&"font_size", size)
	b.add_theme_color_override(&"font_color", CREAM)
	b.add_theme_color_override(&"font_hover_color", Color.WHITE)
	b.add_theme_color_override(&"font_focus_color", Color.WHITE)
	b.add_theme_color_override(&"font_pressed_color", TEAL)
	b.add_theme_color_override(&"font_disabled_color", Color(1, 1, 1, 0.3))
	var normal := box(Color(0.04, 0.06, 0.09, 0.62))
	var hot := box(Color(0.08, 0.2, 0.22, 0.85), 16, TEAL, 2)
	b.add_theme_stylebox_override(&"normal", normal)
	b.add_theme_stylebox_override(&"hover", hot)
	b.add_theme_stylebox_override(&"focus", hot)
	b.add_theme_stylebox_override(&"pressed", box(Color(0.1, 0.3, 0.3, 0.9), 16, TEAL, 2))
	b.add_theme_stylebox_override(&"disabled", box(Color(0.04, 0.06, 0.09, 0.35)))
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	b.focus_entered.connect(func() -> void: Audio.play_ui(&"ui_click", -14.0))
	return b


## Text in the Owner's voice: teal monospace with a prompt.
static func owner_label(text: String, size: int = 20) -> Label:
	return label(("> " + Lang.t(text)) if text != "" else "", size, MONO, 500, TEAL)
