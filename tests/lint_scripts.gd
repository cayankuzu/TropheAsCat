extends Node
## Static check for GDScript warnings, which Godot only shows in the editor (a runtime log never prints
## them). Re-parses every script under res://game and res://tests with all default-on warnings raised to
## errors. The warning levels can only be changed before startup, so this scene writes res://override.cfg,
## runs itself again in a child process, deletes the file and reports:
##   Godot --headless --path <P> res://tests/lint_scripts.tscn
## Exit code 0 when no script outside IGNORED has a warning.

const ROOTS := ["res://game", "res://tests"]
## Owned by the lead (game.gd:86 assigns an int to MouseButton); reported, not failed.
const IGNORED := ["res://game/core/game.gd"]
const WARNINGS := [
	"assert_always_false", "assert_always_true", "confusable_capture_reassignment", "confusable_identifier",
	"confusable_local_declaration", "confusable_local_usage", "confusable_temporary_modification",
	"deprecated_keyword", "empty_file", "enum_variable_without_default", "incompatible_ternary",
	"int_as_enum_without_cast", "int_as_enum_without_match", "integer_division", "missing_tool",
	"narrowing_conversion", "redundant_await", "redundant_static_unload", "shadowed_global_identifier",
	"shadowed_variable", "shadowed_variable_base_class", "standalone_expression", "standalone_ternary",
	"static_called_on_instance", "unassigned_variable", "unassigned_variable_op_assign", "unreachable_code",
	"unreachable_pattern", "unsafe_void_return", "unused_local_constant", "unused_parameter",
	"unused_private_class_variable", "unused_signal", "unused_variable",
]
const OVERRIDE := "res://override.cfg"


func _ready() -> void:
	if int(ProjectSettings.get_setting("debug/gdscript/warnings/unused_variable", 1)) == 2:
		_lint()
	else:
		_relaunch()


func _relaunch() -> void:
	var cfg := ProjectSettings.globalize_path(OVERRIDE)
	if FileAccess.file_exists(cfg):
		print("LINT refusing to overwrite an existing override.cfg")
		get_tree().quit(2)
		return
	var f := FileAccess.open(cfg, FileAccess.WRITE)
	f.store_line("[debug]\n")
	for w: String in WARNINGS:
		f.store_line("gdscript/warnings/%s=2" % w)
	f.close()
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(),
			["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/lint_scripts.tscn"], out, true)
	DirAccess.remove_absolute(cfg)
	var seen := {}
	for s: String in out:
		var lines := s.split("\n")
		for i in lines.size():
			lines[i] = lines[i].strip_edges()
		for i in lines.size():
			if lines[i].contains("Warning treated as error") and i + 1 < lines.size():
				var msg := "LINT warning %s: %s" % [lines[i + 1].get_slice("(", 1).trim_suffix(")"),
						lines[i].get_slice("Parse Error: ", 1).trim_suffix(" (Warning treated as error.)")]
				if not seen.has(msg):
					seen[msg] = true
					print(msg)
			elif lines[i].begins_with("LINT"):
				print(lines[i])
	get_tree().quit(code)


func _lint() -> void:
	var paths: PackedStringArray = []
	for r: String in ROOTS:
		_collect(r, paths)
	var bad: PackedStringArray = []
	for p in paths:
		if p == get_script().resource_path:
			continue   # re-loading the running script with CACHE_MODE_IGNORE breaks the VM
		var s := ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
		if (s == null or not s.can_instantiate()) and not IGNORED.has(p):
			bad.append(p)
	print("LINT scripts=%d failing=%d %s" % [paths.size(), bad.size(), str(bad)])
	get_tree().quit(1 if bad.size() > 0 else 0)


func _collect(dir_path: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.get_extension() == "gd":
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_collect(dir_path.path_join(sub), out)
