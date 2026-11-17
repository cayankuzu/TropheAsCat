class_name Chaos
extends Node
## Chaos stars (2026-11-17): the Owner's answer to Trophe, GTA's wanted level done the Owner's way.
##
## Heat comes from everything man-made she breaks (every break of a chain counts), more from a shattered
## person, an explosion, a toppled building or a wrecked unit of the Police. Once she has been quiet for a
## while the heat falls, but not while the Police can see her (`watched`): she has to get away. The heat gives one to five stars, drawn at the top right (they blink while they
## cool down), the Owner remarks on each new star, and the Police (game/world/traffic/police.gd) answers
## them. A rewind calms everything down; the stars are not saved.

signal stars_changed(stars: int)

const THRESHOLDS: Array[float] = [10.0, 35.0, 80.0, 150.0, 250.0]
const MAX_HEAT := 300.0
const CALM_AFTER := 10.0     ## seconds without new chaos before the heat starts to fall
const COOL_RATE := 2.0       ## heat lost per second once cooling, plus 3 % of the heat
const PERSON_HEAT := 6.0
const BLAST_HEAT := 2.5
const TOPPLE_HEAT := 30.0
const CALL_HEAT := 15.0              ## a witness got through to the police (People.called_police)
const UNIT_HEAT := 12.0
const LINES: PackedStringArray = [
	"One star. I am writing that down, Trophe.",
	"Two stars. I have called the nice people with the hats.",
	"Three stars. Road blocks. In my own city.",
	"Four stars. The fire brigade is on its way. For a cat.",
	"Five stars. SWAT. I did not want it to come to this.",
]
const CALM_LINE := "...And we are calm again. Good kitty."

var heat := 0.0
var stars := 0
var best_stars := 0
## Seconds since the last chaos.
var quiet := 0.0
## Set by the Police while one of its units or people is close to her: the heat does not fall.
var watched := false
var call_heat_mult := 1.0   ## the shop's LAWYER CAT halves it

var _last_chain := 0
var _voice: OwnerVoice = null
var _widget: StarsWidget
var _said := {}


## The row of stars at the top right of the screen.
class StarsWidget extends Control:
	var stars := 0
	var cooling := false
	var punch := 0.0
	var _t := 0.0

	func _process(delta: float) -> void:
		punch = maxf(punch - delta * 2.5, 0.0)
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var s := clampf(get_viewport_rect().size.y / 720.0, 0.75, 2.5)
		var r := 13.0 * s
		var gap := 34.0 * s
		var y := 66.0 * s
		var right := size.x - 26.0 * s
		for i in 5:
			var c := Vector2(right - (4 - i) * gap - r, y)
			var on := i < stars
			var k := 1.0 + (punch * 0.6 if on and i == stars - 1 else 0.0)
			var pts := _star(c, r * k, r * k * 0.46)
			var ring := pts.duplicate()
			ring.append(pts[0])
			if on:
				var a := 1.0
				if cooling:
					a = 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * 9.0))
				draw_colored_polygon(pts, Color(1.0, 0.82, 0.26, a))
				draw_polyline(ring, Color(0.3, 0.17, 0.02, a), 2.2 * s, true)
			else:
				draw_polyline(ring, Color(1.0, 1.0, 1.0, 0.22), 1.6 * s, true)

	static func _star(c: Vector2, outer: float, inner: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI * 0.5 + PI * 0.2 * i
			var rr := outer if i % 2 == 0 else inner
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		return pts


func setup(main: Node) -> void:
	_voice = main.get("owner_voice") as OwnerVoice
	Progress.chain_changed.connect(_on_chain)
	DamageRouter.blast.connect(_on_blast)
	Timeline.rewind_started.connect(reset)
	var people := main.get("people") as People
	if people != null:
		people.person_shattered.connect(_on_person)
		people.called_police.connect(func(_at: Vector3) -> void: add(CALL_HEAT * call_heat_mult))
	var sm := Game.structures as StructureManager
	if sm != null:
		sm.building_toppled.connect(_on_topple)
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_widget = StarsWidget.new()
	_widget.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_widget)


## More chaos: `amount` of heat.
func add(amount: float) -> void:
	heat = minf(heat + amount, MAX_HEAT)
	quiet = 0.0
	_update()


## All calm again (a rewind, a new Table).
func reset() -> void:
	heat = 0.0
	quiet = 0.0
	_last_chain = 0
	_update()


func cooling() -> bool:
	return heat > 0.0 and quiet > CALM_AFTER and not watched


func _process(delta: float) -> void:
	quiet += delta
	if cooling():
		heat = maxf(heat - (COOL_RATE + heat * 0.03) * delta, 0.0)
		_update()
	if _widget != null:
		_widget.cooling = cooling()


func _update() -> void:
	var s := 0
	for t in THRESHOLDS:
		if heat >= t:
			s += 1
	if s == stars:
		return
	var before := stars
	stars = s
	best_stars = maxi(best_stars, s)
	if _widget != null:
		_widget.stars = s
		if s > before:
			_widget.punch = 1.0
	if s > before and not _said.has(s):
		_said[s] = true
		_speak(LINES[s - 1], true)
		Audio.play_ui(&"owner_chime", -4.0)
	elif s == 0 and before > 0:
		_speak(CALM_LINE, false)
	stars_changed.emit(s)


func _speak(line: String, force: bool) -> void:
	if _voice != null and is_instance_valid(_voice):
		_voice.speak(line, force)


func _on_chain(count: int, _title: String) -> void:
	var gained := count - _last_chain if count > _last_chain else count
	_last_chain = count
	add(float(maxi(gained, 1)))


func _on_blast(_hit: DamageHit) -> void:
	add(BLAST_HEAT)


func _on_person(_at: Vector3) -> void:
	add(PERSON_HEAT)


func _on_topple(_bid: int, _storey: int) -> void:
	add(TOPPLE_HEAT)
