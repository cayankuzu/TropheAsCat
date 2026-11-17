extends Node3D

@onready var player = $Player
@onready var magma_plane = $MagmaSea

func _ready() -> void:
	print("Cat As Rophe: Simulation Active!")

func _physics_process(delta: float) -> void:
	# Keep magma animated (pulsing light)
	if magma_plane:
		var light = magma_plane.get_node_or_null("OmniLight3D")
		if light:
			light.light_energy = 3.5 + sin(Time.get_ticks_msec() * 0.005) * 1.0
