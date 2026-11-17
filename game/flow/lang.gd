class_name Lang
extends RefCounted
## Languages (2026-11-17): English (the text in the code) and Turkish (LangTr.STRINGS). The game starts in
## the language of the system (Turkish on a Turkish Windows) unless the player picked one in Settings.
## Static text of controls is translated by Godot on its own (auto translate); text put together in code
## goes through tr() / Lang.t() where it is shown (MiniHud.say, People, Jobs, GameHud, Opening, Driving).

const LANGUAGES: Array[String] = ["en", "tr"]
const NAMES: Array[String] = ["English", "Türkçe"]

static var _added := false


## Registers the Turkish strings once and switches to `choice` ("" = the system's language).
static func setup(choice: String) -> void:
	if not _added:
		_added = true
		var table := Translation.new()
		table.locale = "tr"
		for k: String in LangTr.STRINGS:
			table.add_message(k, LangTr.STRINGS[k])
		TranslationServer.add_translation(table)
	var lang := choice if LANGUAGES.has(choice) else ("tr" if OS.get_locale_language() == "tr" else "en")
	TranslationServer.set_locale(lang)


static func code() -> String:
	return TranslationServer.get_locale().left(2)


## Upper case that knows the Turkish dotted capital I (i -> İ, ı -> I).
static func upper(s: String) -> String:
	return (s.replace("i", "İ") if code() == "tr" else s).to_upper()


static func t(s: String) -> String:
	return TranslationServer.translate(s)
