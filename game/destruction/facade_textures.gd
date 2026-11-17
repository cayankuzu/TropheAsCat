class_name FacadeTextures
extends RefCounted
## Procedural looks of the building facades (2026-11-17): windows with frames, muntins, curtains, blinds
## or a warm light behind them; shop windows full of goods; panelled and glazed doors; striped awnings;
## balcony railings; the painted band of a parking deck; the parking sign; corrugated sheet, roller doors
## and brand fascias for the docks, the malls and the fuel stations.
##
## Each texture covers exactly one face of the element it is made for: the MaterialDB variant gives that
## face size as "uv", and the material maps it with object-space triplanar and a 0.5 offset, the same way
## every element and fracture piece is textured. So a window shatters into pieces of that window.
## Everything is drawn with Image.fill_rect, so the whole set costs a few milliseconds at load.

const PANE_TOP := Color(0.47, 0.57, 0.65)
const PANE_BOTTOM := Color(0.14, 0.18, 0.23)
const WARM_TOP := Color(1.0, 0.85, 0.6)
const WARM_BOTTOM := Color(0.94, 0.6, 0.3)

static var _cache: Dictionary = {}


## The render material of a variant whose data has "proc" (see MaterialDB.VARIANTS).
static func material(d: Dictionary) -> StandardMaterial3D:
	var maps := _maps(d)
	var uv: Vector3 = d.get("uv", Vector3.ONE)
	var mat := StandardMaterial3D.new()
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = false
	mat.uv1_triplanar_sharpness = 8.0
	mat.uv1_scale = Vector3(1.0 / uv.x, 1.0 / uv.y, 1.0 / uv.z)
	mat.uv1_offset = Vector3(0.5, 0.5, 0.5)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.albedo_texture = maps[0]
	mat.roughness_texture = maps[1]
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.roughness = 1.0
	mat.metallic_texture = maps[1]
	mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	mat.metallic = 1.0
	mat.metallic_specular = 0.6
	if maps[2] != null:
		mat.emission_enabled = true
		mat.emission = Color.BLACK   # added to the texture: the texture alone glows
		mat.emission_texture = maps[2]
		mat.emission_energy_multiplier = float(d.get("emit", 1.0))
	if d["proc"] == "railing":
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## [albedo, roughness (R) + metallic (G), emission or null] as textures, shared by every variant that
## draws the same thing.
static func _maps(d: Dictionary) -> Array:
	var key := "%s|%s|%s|%s" % [d["proc"], d.get("a", Color.WHITE), d.get("b", Color.WHITE), d.get("kind", "")]
	if _cache.has(key):
		return _cache[key]
	var imgs: Array = []
	match String(d["proc"]):
		"window":
			imgs = _window(d["a"], d["b"], String(d.get("kind", "plain")))
		"shop":
			imgs = _shop(d["a"], d["b"])
		"door_wood":
			imgs = _door_wood(d["a"])
		"door_glass":
			imgs = _door_glass(d["a"])
		"door_balcony":
			imgs = _door_balcony(d["a"])
		"awning":
			imgs = _awning(d["a"], d["b"])
		"railing":
			imgs = _railing(d["a"])
		"deck":
			imgs = _deck(d["a"])
		"corrugated":
			imgs = _corrugated(d["a"])
		"roller":
			imgs = _roller(d["a"])
		"fascia":
			imgs = _fascia(d["a"], d["b"])
		"tape":
			imgs = _tape()
		"clock":
			imgs = _clock()
		_:
			imgs = _parking()
	var out := []
	for img: Variant in imgs:
		if img == null:
			out.append(null)
			continue
		(img as Image).generate_mipmaps()
		out.append(ImageTexture.create_from_image(img))
	_cache[key] = out
	return out


static func _canvas(w: int, h: int, fill: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	return img


## Vertical gradient over a rectangle, one row at a time.
static func _gradient(img: Image, r: Rect2i, top: Color, bottom: Color) -> void:
	var rows := maxi(r.size.y - 1, 1)
	for y in r.size.y:
		img.fill_rect(Rect2i(r.position.x, r.position.y + y, r.size.x, 1), top.lerp(bottom, float(y) / rows))


## A diagonal band of reflected sky across a pane.
static func _streak(img: Image, r: Rect2i, width: int, strength: float) -> void:
	for y in r.size.y:
		var x0 := r.position.x + r.size.x - int(float(y) * 0.7) - width - int(r.size.x * 0.2)
		var x1 := x0 + width
		x0 = clampi(x0, r.position.x, r.end.x)
		x1 = clampi(x1, r.position.x, r.end.x)
		if x1 > x0:
			var row := Rect2i(x0, r.position.y + y, x1 - x0, 1)
			var c := img.get_pixel(x0, r.position.y + y)
			img.fill_rect(row, c.lerp(Color(0.85, 0.9, 0.95), strength))


## Curtain with folds over a rectangle.
static func _curtain(img: Image, r: Rect2i, c: Color) -> void:
	img.fill_rect(r, c)
	var x := r.position.x + 3
	while x < r.end.x:
		img.fill_rect(Rect2i(x, r.position.y, mini(4, r.end.x - x), r.size.y), c.darkened(0.14))
		x += 9


static func _window(frame: Color, curtain: Color, kind: String) -> Array:
	var s := 256
	var lit := kind == "lit"
	var alb := _canvas(s, s, frame)
	var rm := _canvas(s, s, Color(0.5, 0.0, 0.0))
	var em: Image = _canvas(s, s, Color.BLACK) if lit else null
	var fw := 22
	var bar := 10
	var mx := s >> 1
	var ty := fw + int((s - 2 * fw) * 0.34)    # transom: a short upper sash over a tall lower one
	var hb := bar >> 1
	# A darker line just inside the frame reads as the depth of the reveal.
	alb.fill_rect(Rect2i(fw - 4, fw - 4, s - 2 * fw + 8, s - 2 * fw + 8), frame.darkened(0.35))
	alb.fill_rect(Rect2i(mx - hb, fw, bar, s - 2 * fw), frame)
	alb.fill_rect(Rect2i(fw, ty - hb, s - 2 * fw, bar), frame)
	var panes: Array[Rect2i] = [
		Rect2i(fw, fw, mx - hb - fw, ty - hb - fw), Rect2i(mx + hb, fw, s - fw - mx - hb, ty - hb - fw),
		Rect2i(fw, ty + hb, mx - hb - fw, s - fw - ty - hb), Rect2i(mx + hb, ty + hb, s - fw - mx - hb, s - fw - ty - hb),
	]
	for p in panes:
		if lit:
			_gradient(alb, p, WARM_TOP, WARM_BOTTOM)
			_gradient(em, p, WARM_TOP, WARM_BOTTOM)
			rm.fill_rect(p, Color(0.35, 0.0, 0.0))
		else:
			_gradient(alb, p, PANE_TOP, PANE_BOTTOM)
			_streak(alb, p, 14, 0.35)
			rm.fill_rect(p, Color(0.05, 0.55, 0.0))
	match kind:
		"curtain", "lit":
			var c := curtain if kind == "curtain" else curtain.darkened(0.2)
			for i in 4:
				var p := panes[i]
				var cw := int(p.size.x * 0.4)
				var r := Rect2i(p.position.x, p.position.y, cw, p.size.y) if i % 2 == 0 else Rect2i(p.end.x - cw, p.position.y, cw, p.size.y)
				_curtain(alb, r, c)
				rm.fill_rect(r, Color(0.9, 0.0, 0.0))
				if lit:
					em.fill_rect(r, c * 0.3)
		"blind":
			for i in 4:
				var p := panes[i]
				var r := p if i < 2 else Rect2i(p.position.x, p.position.y, p.size.x, int(p.size.y * 0.28))
				alb.fill_rect(r, Color(0.9, 0.88, 0.82))
				var y := r.position.y + 4
				while y < r.end.y:
					alb.fill_rect(Rect2i(r.position.x, y, r.size.x, 1), Color(0.72, 0.7, 0.65))
					y += 6
				rm.fill_rect(r, Color(0.75, 0.0, 0.0))
	return [alb, rm, em]


static func _shop(frame: Color, accent: Color) -> Array:
	var w := 256
	var h := 358
	var alb := _canvas(w, h, frame)
	var rm := _canvas(w, h, Color(0.45, 0.2, 0.0))
	var em := _canvas(w, h, Color.BLACK)
	var fw := 14
	var pane := Rect2i(fw, fw, w - 2 * fw, h - 2 * fw)
	_gradient(alb, pane, Color(0.98, 0.91, 0.76), Color(0.84, 0.66, 0.46))
	_gradient(em, pane, Color(0.6, 0.5, 0.36), Color(0.42, 0.32, 0.2))
	rm.fill_rect(pane, Color(0.12, 0.3, 0.0))
	# The shop's colour across the top of the window, then shelves of goods.
	alb.fill_rect(Rect2i(fw, fw, w - 2 * fw, 30), accent)
	em.fill_rect(Rect2i(fw, fw, w - 2 * fw, 30), accent * 0.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(accent)
	for shelf_y: int in [150, 236, 322]:
		alb.fill_rect(Rect2i(fw, shelf_y, w - 2 * fw, 6), Color(0.36, 0.24, 0.15))
		em.fill_rect(Rect2i(fw, shelf_y, w - 2 * fw, 6), Color.BLACK)
		var x := fw + 6
		while x < w - fw - 24:
			var bw := rng.randi_range(12, 30)
			var bh := rng.randi_range(18, 52)
			var col := Color.from_hsv(rng.randf(), rng.randf_range(0.35, 0.75), rng.randf_range(0.55, 0.95))
			var box := Rect2i(x, shelf_y - bh, bw, bh)
			alb.fill_rect(box, col)
			em.fill_rect(box, col * 0.3)
			x += bw + rng.randi_range(4, 12)
	alb.fill_rect(Rect2i((w >> 1) - 4, fw, 8, h - 2 * fw), frame)
	em.fill_rect(Rect2i((w >> 1) - 4, fw, 8, h - 2 * fw), Color.BLACK)
	_streak(alb, Rect2i(fw, fw + 30, w - 2 * fw, 100), 18, 0.25)
	return [alb, rm, em]


static func _door_wood(paint: Color) -> Array:
	var w := 256
	var h := 410
	var alb := _canvas(w, h, paint.darkened(0.25))
	var rm := _canvas(w, h, Color(0.5, 0.0, 0.0))
	var fw := 14
	var mid := w >> 1
	for leaf: Rect2i in [Rect2i(fw, fw, mid - fw - 2, h - fw), Rect2i(mid + 2, fw, mid - fw - 2, h - fw)]:
		alb.fill_rect(leaf, paint)
		var g := Rect2i(leaf.position.x + 18, leaf.position.y + 20, leaf.size.x - 36, int(leaf.size.y * 0.22))
		alb.fill_rect(g.grow(3), paint.darkened(0.3))
		_gradient(alb, g, PANE_TOP, PANE_BOTTOM)
		rm.fill_rect(g, Color(0.05, 0.5, 0.0))
		var top := g.end.y + 22
		var ph := (leaf.end.y - top - 40) >> 1
		for k in 2:
			var p := Rect2i(leaf.position.x + 18, top + k * (ph + 16), leaf.size.x - 36, ph)
			alb.fill_rect(p, paint.darkened(0.22))
			alb.fill_rect(p.grow(-5), paint.lightened(0.06))
	alb.fill_rect(Rect2i(mid - 2, fw, 4, h - fw), paint.darkened(0.45))
	for kx: int in [mid - 16, mid + 8]:
		var knob := Rect2i(kx, int(h * 0.55), 8, 8)
		alb.fill_rect(knob, Color(0.82, 0.66, 0.3))
		rm.fill_rect(knob, Color(0.3, 0.9, 0.0))
	return [alb, rm, null]


static func _door_glass(frame: Color) -> Array:
	var w := 256
	var h := 410
	var alb := _canvas(w, h, frame)
	var rm := _canvas(w, h, Color(0.35, 0.8, 0.0))
	var fw := 14
	var mid := w >> 1
	for leaf: Rect2i in [Rect2i(fw + 6, fw + 6, mid - fw - 12, h - fw - 30), Rect2i(mid + 6, fw + 6, mid - fw - 12, h - fw - 30)]:
		_gradient(alb, leaf, PANE_TOP, PANE_BOTTOM)
		_streak(alb, leaf, 16, 0.3)
		rm.fill_rect(leaf, Color(0.05, 0.5, 0.0))
		var push := Rect2i(leaf.position.x + 10, int(h * 0.5), leaf.size.x - 20, 9)
		alb.fill_rect(push, frame.lightened(0.55))
		rm.fill_rect(push, Color(0.25, 0.9, 0.0))
	return [alb, rm, null]


static func _door_balcony(frame: Color) -> Array:
	var w := 256
	var h := 410
	var alb := _canvas(w, h, frame)
	var rm := _canvas(w, h, Color(0.5, 0.0, 0.0))
	var fw := 18
	var mid := w >> 1
	var kick := int(h * 0.2)
	for leaf: Rect2i in [Rect2i(fw, fw, mid - fw - 5, h - 2 * fw - kick), Rect2i(mid + 5, fw, mid - fw - 5, h - 2 * fw - kick)]:
		alb.fill_rect(leaf.grow(3), frame.darkened(0.3))
		_gradient(alb, leaf, PANE_TOP, PANE_BOTTOM)
		_streak(alb, leaf, 12, 0.3)
		rm.fill_rect(leaf, Color(0.05, 0.55, 0.0))
		for k in 2:
			var y := leaf.position.y + int(leaf.size.y * (k + 1) / 3.0)
			alb.fill_rect(Rect2i(leaf.position.x, y - 3, leaf.size.x, 6), frame)
			rm.fill_rect(Rect2i(leaf.position.x, y - 3, leaf.size.x, 6), Color(0.5, 0.0, 0.0))
		var panel := Rect2i(leaf.position.x + 6, leaf.end.y + 14, leaf.size.x - 12, kick - 24)
		alb.fill_rect(panel, frame.darkened(0.12))
	return [alb, rm, null]


## Stripes run down the slope (the u axis of the awning is along the wall).
static func _awning(a: Color, b: Color) -> Array:
	var s := 128
	var alb := _canvas(s, s, a)
	for i in 8:
		if i % 2 == 1:
			alb.fill_rect(Rect2i(i * 16, 0, 16, s), b)
	return [alb, _canvas(s, s, Color(0.85, 0.0, 0.0)), null]


## Wrought bars between a top and a bottom rail; the rest is cut away (alpha scissor). One metre square.
static func _railing(c: Color) -> Array:
	var s := 256
	var alb := _canvas(s, s, Color(c.r, c.g, c.b, 0.0))
	alb.fill_rect(Rect2i(0, 0, s, 16), c)
	alb.fill_rect(Rect2i(0, s - 18, s, 18), c)
	alb.fill_rect(Rect2i(0, 120, s, 6), c)
	var x := 13
	while x < s:
		alb.fill_rect(Rect2i(x, 16, 7, s - 34), c)
		x += 32
	return [alb, _canvas(s, s, Color(0.45, 0.6, 0.0)), null]


## Pale concrete with a painted band across the middle of the railing (one metre square, tiled along it).
static func _deck(band: Color) -> Array:
	var s := 256
	var base := Color(0.8, 0.79, 0.77)
	var alb := _canvas(s, s, base)
	var rng := RandomNumberGenerator.new()
	rng.seed = 911
	for i in 1800:
		var g := rng.randf_range(-0.07, 0.05)
		alb.fill_rect(Rect2i(rng.randi_range(0, s - 3), rng.randi_range(0, s - 3), rng.randi_range(1, 3), rng.randi_range(1, 3)),
			Color(base.r + g, base.g + g, base.b + g))
	alb.fill_rect(Rect2i(0, 100, s, 64), band)
	alb.fill_rect(Rect2i(0, 98, s, 2), band.darkened(0.4))
	alb.fill_rect(Rect2i(0, 164, s, 2), band.darkened(0.4))
	for i in 300:
		alb.fill_rect(Rect2i(rng.randi_range(0, s - 2), rng.randi_range(100, 162), 2, 2), band.darkened(rng.randf_range(0.03, 0.15)))
	return [alb, _canvas(s, s, Color(0.88, 0.0, 0.0)), null]


## Corrugated sheet: four ribs a metre, each with a lit crest and a shaded flank, and a little grime
## running down (one metre square, tiled; the ribs run along v).
static func _corrugated(c: Color) -> Array:
	var s := 256
	var alb := _canvas(s, s, c)
	for r in 4:
		var x0 := r * 64
		alb.fill_rect(Rect2i(x0, 0, 14, s), c.lightened(0.12))
		alb.fill_rect(Rect2i(x0 + 14, 0, 6, s), c.darkened(0.24))
		alb.fill_rect(Rect2i(x0 + 58, 0, 6, s), c.lightened(0.05))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 260:
		var x := rng.randi_range(0, s - 2)
		var y := rng.randi_range(0, s - 40)
		alb.fill_rect(Rect2i(x, y, rng.randi_range(1, 2), rng.randi_range(8, 38)), alb.get_pixel(x, y).darkened(rng.randf_range(0.03, 0.08)))
	return [alb, _canvas(s, s, Color(0.62, 0.3, 0.0)), null]


## A roller door: slats of 12.5 cm with a groove between them (one metre square, tiled; the slats run
## along u).
static func _roller(c: Color) -> Array:
	var s := 256
	var alb := _canvas(s, s, c)
	for i in 8:
		var y0 := i * 32
		alb.fill_rect(Rect2i(0, y0, s, 3), c.darkened(0.35))
		alb.fill_rect(Rect2i(0, y0 + 3, s, 4), c.lightened(0.08))
		alb.fill_rect(Rect2i(0, y0 + 26, s, 6), c.darkened(0.08))
	return [alb, _canvas(s, s, Color(0.6, 0.3, 0.0)), null]


## A brand fascia: the brand colour with a band of the second colour across it and dark edges (one face
## high, tiled along u).
static func _fascia(a: Color, b: Color) -> Array:
	var s := 128
	var alb := _canvas(s, s, a)
	alb.fill_rect(Rect2i(0, 0, s, 6), a.darkened(0.3))
	alb.fill_rect(Rect2i(0, s - 6, s, 6), a.darkened(0.3))
	alb.fill_rect(Rect2i(0, 54, s, 20), b)
	return [alb, _canvas(s, s, Color(0.4, 0.3, 0.0)), null]


## Letters of the tape, 5 x 7 pixels each (rows from the top, one bit a column).
const TAPE_FONT := {
	"D": [30, 17, 17, 17, 17, 17, 30], "O": [14, 17, 17, 17, 17, 17, 14], "N": [17, 25, 21, 19, 17, 17, 17],
	"T": [31, 4, 4, 4, 4, 4, 4], "U": [17, 17, 17, 17, 17, 17, 14], "C": [14, 17, 16, 16, 16, 17, 14],
	"H": [17, 17, 17, 31, 17, 17, 17],
}


## The Owner's tape round a ruin: DO NOT TOUCH in black on yellow between two black lines (2 m of tape).
static func _tape() -> Array:
	var w := 512
	var h := 64
	var yellow := Color(0.98, 0.82, 0.12)
	var black := Color(0.06, 0.06, 0.07)
	var alb := _canvas(w, h, yellow)
	alb.fill_rect(Rect2i(0, 0, w, 5), black)
	alb.fill_rect(Rect2i(0, h - 5, w, 5), black)
	var text := "DO NOT TOUCH"
	var px := 5
	var cell := 6 * px
	var x0 := (w - text.length() * cell) >> 1
	var y0 := (h - 7 * px) >> 1
	for i in text.length():
		var ch := text[i]
		if not TAPE_FONT.has(ch):
			continue
		var rows: Array = TAPE_FONT[ch]
		for r in 7:
			for c in 5:
				if int(rows[r]) & (1 << (4 - c)):
					alb.fill_rect(Rect2i(x0 + i * cell + c * px, y0 + r * px, px, px), black)
	return [alb, _canvas(w, h, Color(0.45, 0.0, 0.0)), null]


## A clock face: cream dial, twelve black marks, the hands at ten past ten; it glows a little at dusk.
static func _clock() -> Array:
	var s := 256
	var c := Vector2(s * 0.5, s * 0.5)
	var alb := _canvas(s, s, Color(0.12, 0.1, 0.08))
	var dial := Color(0.96, 0.93, 0.84)
	var ink := Color(0.08, 0.07, 0.06)
	for y in s:
		for x in s:
			if Vector2(x + 0.5, y + 0.5).distance_to(c) < s * 0.46:
				alb.set_pixel(x, y, dial)
	for k in 12:
		var a := TAU * k / 12.0
		var d := Vector2(sin(a), -cos(a))
		for t in range(int(s * 0.36), int(s * 0.43)):
			var p := c + d * t
			alb.fill_rect(Rect2i(int(p.x) - 3, int(p.y) - 3, 7 if k % 3 == 0 else 5, 7 if k % 3 == 0 else 5), ink)
	for hand: Array in [[TAU * 10.0 / 12.0 + TAU / 72.0, 0.24, 5], [TAU * 2.0 / 12.0, 0.36, 3]]:
		var d := Vector2(sin(float(hand[0])), -cos(float(hand[0])))
		for t in range(0, int(s * float(hand[1]))):
			var p := c + d * t
			alb.fill_rect(Rect2i(int(p.x) - int(hand[2]), int(p.y) - int(hand[2]), int(hand[2]) * 2 + 1, int(hand[2]) * 2 + 1), ink)
	alb.fill_rect(Rect2i(int(c.x) - 7, int(c.y) - 7, 15, 15), ink)
	var glow := alb.duplicate() as Image
	return [alb, _canvas(s, s, Color(0.5, 0.0, 0.0)), glow]


## The parking sign: a white P on blue, readable on the +Z face.
static func _parking() -> Array:
	var s := 256
	var blue := Color(0.07, 0.29, 0.67)
	var alb := _canvas(s, s, Color(0.95, 0.95, 0.95))
	alb.fill_rect(Rect2i(10, 10, s - 20, s - 20), blue)
	var white := Color(0.97, 0.97, 0.97)
	alb.fill_rect(Rect2i(78, 48, 38, 162), white)      # stem
	alb.fill_rect(Rect2i(78, 48, 96, 34), white)       # top of the bowl
	alb.fill_rect(Rect2i(148, 58, 36, 82), white)      # right of the bowl
	alb.fill_rect(Rect2i(78, 118, 96, 32), white)      # bottom of the bowl
	alb.fill_rect(Rect2i(160, 48, 14, 10), blue)       # rounded corners, roughly
	alb.fill_rect(Rect2i(174, 48, 10, 10), blue)
	alb.fill_rect(Rect2i(174, 140, 10, 10), blue)
	return [alb, _canvas(s, s, Color(0.35, 0.2, 0.0)), null]
