class_name OwnerVoice
extends Node
## The Owner talks (docs/DESIGN.md section 1): the caretaker AI of the Table, polite, patient, slowly
## losing the battle. It greets Trophe, and it reacts to the big moments: the first wall, the first
## shattered mannequin, the domino run, a toppled building, a burning car, the ranks of a chain, the
## trees that will not break, a long quiet. Lines go to the HUD (MiniHud.say).
##
## Every moment speaks once per game, a rank once per rank, and the Owner waits at least COOLDOWN
## seconds between lines it chose itself, so it stays a voice and not a ticker.

const COOLDOWN := 12.0
const QUIET_SECONDS := 75.0

const GREETING := [
	"Good morning, Trophe.",
	"The Table is spotless. Every vase is exactly where it belongs.",
	"I have one rule today: nothing falls off the Table.",
]
const WELCOME_BACK := ["Welcome back, Trophe.", "I tidied up while you were away. Mostly."]
const MOMENTS := {
	&"dominoes_told": "Those dominoes took me three weeks. Please do not touch them.",
	&"first_wall": "That wall was not optional.",
	&"first_person": "We do not break the little people. We PET the little people.",
	&"dominoes_done": "Forty-four dominoes. Three weeks. Eleven seconds.",
	&"toppled": "Trophe. That was load-bearing.",
	&"car": "That car had a warranty. Had.",
	&"cat_proof": "Nice try. The trees are cat-proof. So are the pigeons. So am I.",
	&"pee": "Is that... on the pavement? Trophe. TROPHE.",
	&"slow_motion": "Time does not slow down for you, Trophe. ...Fine. It does.",
	&"meow": "Yes, yes. Hello to you too.",
	&"quiet": "Good kitty. Stay just like that. Forever, preferably.",
	&"rewind": "Ctrl+Z. Ctrl+Z. ...Trophe, that is MY shortcut.",
}
const RANKS := {
	"NAUGHTY": "That is quite enough, young lady.",
	"BAD KITTY": "Who taught you this? Not me.",
	"CAT-ASTROPHE": "I am logging this. All of it.",
	"TROPHE-POCALYPSE": "Please. I just dusted.",
	"TABLE FLIP": "...I need a minute.",
}

var spoken := {}            # moment or rank -> true once said
var lines_said := 0

var _main: Node
var _hud: MiniHud
var _wait := 0.0
var _quiet := 0.0
var _hooked_structures := 0


func setup(main: Node) -> void:
	_main = main
	_hud = main.get("hud") as MiniHud
	Progress.chain_changed.connect(_on_chain)
	Timeline.rewind_stopped.connect(_on_rewind_stopped)
	DamageRouter.protected_hit.connect(_on_protected_hit)
	var people := main.get("people") as People
	if people != null:
		people.person_shattered.connect(func(_at: Vector3) -> void: moment(&"first_person"))
	var dressing := main.get("dressing") as StreetDressing
	if dressing != null:
		for p in dressing.props:
			if is_instance_valid(p) and p.wreck:
				p.wrecked.connect(func(_p: BreakableProp) -> void: moment(&"car"))


## The opening lines: a greeting for a new Table, a welcome back for a saved one. The second greeting
## line comes as she lands; the domino warning when she can see them.
func intro(continued: bool) -> void:
	var lines: Array = WELCOME_BACK if continued else GREETING
	var at := 0.4
	for line: String in lines:
		_later(at, line)
		at += 3.2
	if not continued:
		spoken[&"dominoes_told"] = true
		_later(at + 1.5, MOMENTS[&"dominoes_told"])
	_wait = at + 6.0


## Says the line of a moment if it has not been said and the Owner is not busy.
func moment(key: StringName, force: bool = false) -> void:
	if spoken.has(key) or not MOMENTS.has(key):
		return
	if not force and (_wait > 0.0 or (_hud != null and _hud.is_speaking())):
		return
	spoken[key] = true
	_say(MOMENTS[key])


func _process(delta: float) -> void:
	_wait = maxf(_wait - delta, 0.0)
	_quiet += delta
	if _quiet > QUIET_SECONDS:
		_quiet = 0.0
		moment(&"quiet")
	var s: Object = Game.structures
	if s != null and is_instance_valid(s) and s.get_instance_id() != _hooked_structures:
		_hooked_structures = s.get_instance_id()
		var sm := s as StructureManager
		sm.element_destroyed.connect(func(_b: int, _e: int, _c: int) -> void:
			_quiet = 0.0
			moment(&"first_wall"))
		sm.building_toppled.connect(func(_b: int, _s: int) -> void: moment(&"toppled", true))
	var dominoes: DominoRun = (_main.get("dominoes") as DominoRun) if _main != null else null
	if dominoes != null and not spoken.has(&"dominoes_done") and dominoes.fallen >= dominoes.tiles.size() and dominoes.tiles.size() > 0:
		moment(&"dominoes_done", true)
	if not spoken.has(&"pee") and Game.player != null:
		var cat := Game.player as CatPlayer
		var pee: PeeTool = (cat.belt.slots[ToolKit.slot_of(&"pee")] as PeeTool) if cat != null else null
		if pee != null and pee.drops > 40:
			moment(&"pee")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"slow_motion"):
		moment(&"slow_motion")
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_M:
		moment(&"meow")


func _on_rewind_stopped() -> void:
	moment(&"rewind", true)


func _on_protected_hit(_hit: DamageHit, _target: Object) -> void:
	moment(&"cat_proof")


func _on_chain(_count: int, title: String) -> void:
	_quiet = 0.0
	if title == "" or spoken.has(title) or not RANKS.has(title):
		return
	spoken[title] = true
	_say(RANKS[title])


## A line from elsewhere (the chaos stars): said now when `force`, otherwise only when the Owner is not
## busy.
func speak(line: String, force: bool = false) -> void:
	if not force and (_wait > 0.0 or (_hud != null and _hud.is_speaking())):
		return
	_say(line)


func _say(line: String) -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	_hud.say(line)
	lines_said += 1
	_wait = COOLDOWN


func _later(seconds: float, line: String) -> void:
	get_tree().create_timer(seconds, false).timeout.connect(func() -> void:
		if is_instance_valid(_hud):
			_hud.say(line, 4.0)
			lines_said += 1)
