@tool
extends EditorPlugin
## Registers the export plugins of the game (2026-11-17): WebTextures shrinks every texture for the browser
## demo, so the download stays small and fits a browser's memory.

var _web_textures: EditorExportPlugin


func _enter_tree() -> void:
	_web_textures = preload("res://addons/trophe_export/web_textures.gd").new()
	add_export_plugin(_web_textures)


func _exit_tree() -> void:
	remove_export_plugin(_web_textures)
	_web_textures = null
