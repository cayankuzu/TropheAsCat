class_name Settings
extends RefCounted
## Player settings, kept in user://settings.cfg: mouse sensitivity, volumes, the graphics preset, full
## screen and the sandbox switch (every tool from the start). Changed from the title and the pause menu
## (SettingsPanel), applied at once and saved on every change.

const PATH := "user://settings.cfg"
## CatCamera.mouse_sensitivity at a multiplier of 1.
const BASE_SENSITIVITY := 0.0024

static var mouse := 1.0          ## multiplier of the mouse sensitivity, 0.25 .. 2.5
static var master := 0.9         ## linear volumes, 0 .. 1
static var music := 0.7
static var effects := 1.0
static var quality := 0 if OS.has_feature("web") else 2          ## WorldLook.Quality (Low in the browser)
static var fullscreen := false
static var sandbox := false
static var language := ""     ## "en", "tr", or "" for the system's language
static var _loaded := false


static func load_settings() -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	mouse = clampf(float(cfg.get_value("input", "mouse", mouse)), 0.25, 2.5)
	master = clampf(float(cfg.get_value("audio", "master", master)), 0.0, 1.0)
	music = clampf(float(cfg.get_value("audio", "music", music)), 0.0, 1.0)
	effects = clampf(float(cfg.get_value("audio", "effects", effects)), 0.0, 1.0)
	quality = clampi(int(cfg.get_value("video", "quality", quality)), 0, 2)
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	sandbox = bool(cfg.get_value("game", "sandbox", sandbox))
	language = String(cfg.get_value("game", "language", language))


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse", mouse)
	cfg.set_value("audio", "master", master)
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "effects", effects)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("game", "sandbox", sandbox)
	cfg.set_value("game", "language", language)
	cfg.save(PATH)


## What can be applied before there is a world: sound, the window, the sandbox switch.
static func load_and_apply() -> void:
	load_settings()
	Lang.setup(language)
	apply_audio()
	apply_window()
	Progress.sandbox_all_tools = sandbox or OS.get_cmdline_user_args().has("--sandbox")


static func apply_audio() -> void:
	_volume(&"Master", master)
	_volume(&"Music", music)
	for bus: StringName in [&"SFX", &"Ambience", &"UI"]:
		_volume(bus, effects)


static func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


## The graphics preset of a built world (main.look).
static func apply_world(look: WorldLook) -> void:
	if _loaded and look != null and look.get_quality() != quality:
		look.set_quality(quality)


static func apply_cat(cat: CatPlayer) -> void:
	if cat != null and cat.camera != null:
		cat.camera.mouse_sensitivity = BASE_SENSITIVITY * mouse


static func _volume(bus: StringName, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(i, linear <= 0.001)
