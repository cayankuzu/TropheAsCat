extends Node
## Headless check of the English / Turkish support (2026-11-17): every Turkish string keeps the placeholders of
## its English key in the same order, the "tr" locale translates through tr(), Lang.t() and a Label's own
## auto-translation, Lang.upper() knows the dotted capital I, and "en" switches back. Prints LANG_* lines.
## Run: Godot --headless --path <P> res://tests/test_lang.tscn

var _fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("LANG_FAIL ", what)


func _ready() -> void:
	var re := RegEx.new()
	re.compile("%(%|[-+ 0#]*[0-9]*(\\.[0-9]+)?[sdifxXcov])")
	var n := 0
	for k: String in LangTr.STRINGS:
		var v: String = LangTr.STRINGS[k]
		# A literal %% may move (Turkish puts the sign before the number); real placeholders may not.
		var a := re.search_all(k).map(func(m: RegExMatch) -> String: return m.get_string()).filter(func(s: String) -> bool: return s != "%%")
		var b := re.search_all(v).map(func(m: RegExMatch) -> String: return m.get_string()).filter(func(s: String) -> bool: return s != "%%")
		_check(a == b, "placeholders differ: '%s' %s vs %s" % [k.c_escape(), a, b])
		_check(not LangTr.STRINGS.has(v) or v == k, "a value is also a key: '%s'" % v)
		_check(v.strip_edges() != "", "empty value for '%s'" % k)
		n += 1
	Lang.setup("")
	print("LANG_OS os=%s default=%s" % [OS.get_locale(), TranslationServer.get_locale()])
	Lang.setup("tr")
	_check(Lang.code() == "tr", "locale is %s" % TranslationServer.get_locale())
	_check(tr("Back") == "Geri", "tr(Back) = %s" % tr("Back"))
	_check(Lang.t("Autosave") == "Otomatik kayıt", "Lang.t(Autosave) = %s" % Lang.t("Autosave"))
	_check(tr("JOB DONE   +%d catnip") % 50 == "İŞ TAMAM   +50 kedi otu", "format: %s" % (tr("JOB DONE   +%d catnip") % 50))
	_check(tr("JOB FAILED\n%s shrugs. The marker is back.") % "X" == "İŞ OLMADI\nX omuz silkiyor. İşaret yerine döndü.", "escaped key")
	_check(Lang.upper(tr("Downtown")) == "ŞEHİR MERKEZİ", "upper: %s" % Lang.upper(tr("Downtown")))
	var label := Label.new()
	label.text = "Settings"
	add_child(label)
	_check(label.atr(label.text) == "Ayarlar", "label auto-translation: %s" % label.atr(label.text))
	Lang.setup("en")
	_check(Lang.code() == "en", "back to en: %s" % TranslationServer.get_locale())
	_check(tr("Back") == "Back" and Lang.upper("Downtown") == "DOWNTOWN", "english again")
	print("LANG_RESULT ok=%s strings=%d fails=%d" % [_fails == 0, n, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
