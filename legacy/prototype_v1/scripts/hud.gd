extends Control

@onready var mode_1_btn = $BottomBar/HBoxContainer/Mode1
@onready var mode_2_btn = $BottomBar/HBoxContainer/Mode2
@onready var mode_3_btn = $BottomBar/HBoxContainer/Mode3
@onready var mode_4_btn = $BottomBar/HBoxContainer/Mode4
@onready var alert_label = $AlertLabel
@onready var reticle = $CenterContainer/Reticle
@onready var rewind_overlay = $RewindOverlay

var alert_timer: float = 0.0

func _ready() -> void:
	add_to_group("hud")
	update_mode_ui(1)
	alert_label.modulate.a = 0.0
	if rewind_overlay:
		rewind_overlay.visible = false

func _process(delta: float) -> void:
	if alert_timer > 0.0:
		alert_timer -= delta
		alert_label.modulate.a = clamp(alert_timer / 0.5, 0.0, 1.0)
	
	# Show rewind effect if R is held
	if Input.is_action_pressed("rewind"):
		if rewind_overlay:
			rewind_overlay.visible = true
			rewind_overlay.modulate.a = 0.4 + sin(Time.get_ticks_msec() * 0.015) * 0.25
	else:
		if rewind_overlay:
			rewind_overlay.visible = false

func update_mode_ui(mode: int) -> void:
	var buttons = [mode_1_btn, mode_2_btn, mode_3_btn, mode_4_btn]
	for i in range(buttons.size()):
		var btn = buttons[i]
		if not btn:
			continue
		if (i + 1) == mode:
			btn.modulate = Color(1.0, 0.9, 0.2) # Active highlighted yellow/gold
			btn.text = "★ " + btn.text.replace("★ ", "")
		else:
			btn.modulate = Color(0.65, 0.65, 0.7, 0.7)
			btn.text = btn.text.replace("★ ", "")

func show_alert(text: String, color: Color) -> void:
	alert_label.text = text
	alert_label.modulate = color
	alert_label.modulate.a = 1.0
	alert_timer = 2.0
