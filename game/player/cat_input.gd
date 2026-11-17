class_name CatInput
extends RefCounted
## One tick of cat controls. Filled from the InputMap for the player, or written directly by bots/tests
## (set CatPlayer.bot_input). The controller derives pressed/released edges itself.

var move := Vector2.ZERO   ## x = right, y = forward; length <= 1 (analog sticks may be shorter).
var jump := false
var sprint := false
var walk := false          ## Hold for the slow walk tier (Alt, or a light stick).
var crouch := false
var grab := false
var attack := false
var aim := false
var stand := false
var interact := false
var tool_slot := -1        ## One-shot: select slot 0..8.
var tool_cycle := 0        ## One-shot: +1 next / -1 previous.


func copy_from(o: CatInput) -> void:
	move = o.move
	jump = o.jump
	sprint = o.sprint
	walk = o.walk
	crouch = o.crouch
	grab = o.grab
	attack = o.attack
	aim = o.aim
	stand = o.stand
	interact = o.interact
	tool_slot = o.tool_slot
	tool_cycle = o.tool_cycle


func clear() -> void:
	copy_from(CatInput.new())


func read_devices() -> void:
	move = Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
	jump = Input.is_action_pressed(&"jump")
	sprint = Input.is_action_pressed(&"sprint")
	walk = InputMap.has_action(&"walk") and Input.is_action_pressed(&"walk")
	crouch = Input.is_action_pressed(&"crouch")
	grab = Input.is_action_pressed(&"grab")
	attack = Input.is_action_pressed(&"attack")
	aim = Input.is_action_pressed(&"aim")
	stand = Input.is_action_pressed(&"stand_up")
	interact = Input.is_action_pressed(&"interact")
