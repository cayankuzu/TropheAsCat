extends StaticBody3D

@onready var shield_mesh = $ShieldMesh
@onready var audio = $AudioStreamPlayer3D

var shield_tween: Tween
var snd_shield = preload("res://assets/audio/sfx_nature_shield.wav")

func _ready() -> void:
	add_to_group("nature")
	if shield_mesh:
		shield_mesh.visible = false

func defend(hit_pos: Vector3) -> void:
	if not shield_mesh and has_node("ShieldMesh"):
		shield_mesh = $ShieldMesh
	if not shield_mesh:
		return
	
	shield_mesh.visible = true
	shield_mesh.scale = Vector3(0.5, 0.5, 0.5)
	
	if audio:
		audio.stream = snd_shield
		audio.pitch_scale = randf_range(0.95, 1.1)
		audio.play()
	
	if shield_tween and shield_tween.is_valid():
		shield_tween.kill()
	
	shield_tween = create_tween()
	shield_tween.tween_property(shield_mesh, "scale", Vector3(1.15, 1.15, 1.15), 0.15)
	shield_tween.tween_property(shield_mesh, "scale", Vector3(1.0, 1.0, 1.0), 0.1)
	shield_tween.tween_interval(0.3)
	shield_tween.tween_property(shield_mesh, "scale", Vector3(0.1, 0.1, 0.1), 0.2)
	shield_tween.tween_callback(func():
		shield_mesh.visible = false
	)
	
	if is_inside_tree():
		var t = get_tree()
		if t:
			var hud = t.get_first_node_in_group("hud")
			if hud and hud.has_method("show_alert"):
				hud.show_alert("[ NATURE IS PROTECTED ]", Color.LIME_GREEN)
