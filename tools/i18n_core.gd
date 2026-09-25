extends RefCounted
## TRADUZIONI: raccoglie i testi del gioco (scritti in inglese) e tiene aggiornati
## i file delle traduzioni, locale/<lingua>.po (oggi solo locale/it.po).
## Si usa dall'editor con tools/aggiorna_traduzioni.gd (File → Run) oppure da riga
## di comando con tools/i18n.gd (lo usa anche la CI). Cosa fa:
##   update: aggiunge ai .po le frasi nuove (da tradurre) e mette in fondo, come
##       obsolete («#~»), quelle che non esistono più. Se una frase inglese è solo
##       cambiata un po', ripropone la vecchia traduzione segnata «fuzzy» (da
##       ricontrollare: finché resta fuzzy il gioco mostra l'inglese).
##   check: controlla i .po: frasi mancanti o da tradurre, segnaposto (%d, %s) e tag
##       [b]...[/b] diversi dall'inglese, numeri spariti (i codici dei tastierini!),
##       immagini per lingua (insegne, <nome>_it.png) senza l'originale inglese.
##       In modalità strict anche una frase non tradotta è un errore (lo usa la CI).
##
## Dove cerca i testi (vedi docs/GUIDA_EDITOR.md, «Testi e traduzioni»):
##   - negli script di scripts/ e levels/: tr("...") e tr("...", "contesto"), il
##     testo degli obiettivi in add_objective("id", "..."), e tutti i testi delle
##     costanti precedute dalla riga «# i18n» (le chiavi dei dizionari no);
##   - nelle scene e nelle risorse (.tscn, .tres) di levels/, scenes/ e assets/:
##     le proprietà in TEXT_PROPS e, per i nomi dei personaggi (NAME_PROPS), il
##     titolo («Ofc.» di «Ofc. Rossi», con contesto "title").
## Gli strumenti di sviluppo (tools/, addons/) restano in italiano e non si traducono.

const SCRIPT_DIRS := ["res://scripts", "res://levels"]
const SCENE_DIRS := ["res://levels", "res://scenes", "res://assets"]
const TEXT_PROPS := ["text", "display", "lock_title", "keycard_name", "loot_keycard_name", "idle_barks"]
const NAME_PROPS := ["guard_name", "display_name", "speaker"]
const LOCALE_DIR := "res://locale"
## Chiamate che mostrano testo al giocatore: una stringa scritta lì senza tr() è una svista.
const LINT_CALLS := ["label", "button", "notify", "say", "add_item", "set_tab_title", "_window", "_rich"]
const LINT_PROPS := ["text", "placeholder_text", "tooltip_text"]

var entries := {}        # chiave (contesto + \u0004 + msgid) -> {msgid, ctx, refs, cformat}
var errors := 0
var warnings := 0
var _re_spec := RegEx.create_from_string("%[-+0]?[0-9]*(?:\\.[0-9]+)?[sdifxXcvo%]")
var _re_tag := RegEx.create_from_string("\\[/?[a-z_]+(?:=[^\\]]*)?\\]")
var _re_num := RegEx.create_from_string("[0-9]{3,}")
var _re_letters := RegEx.create_from_string("[A-Za-zÀ-ÿ]")
var _re_bbcode_or_spec := RegEx.create_from_string("\\[[^\\]]*\\]|%[-+0]?[0-9]*(?:\\.[0-9]+)?[sdifxXcvo%]")


## Raccoglie i testi del gioco (va chiamata prima di update() e check()).
func scan() -> void:
	entries.clear()
	for d in SCRIPT_DIRS:
		for f in _files(d, ["gd"]):
			_scan_script(f)
	for d in SCENE_DIRS:
		for f in _files(d, ["tscn", "tres"]):
			_scan_resource(f)
	print("Testi del gioco trovati: %d" % entries.size())


## Aggiorna i .po di tutte le lingue del progetto; restituisce il numero di errori.
func update(drop_obsolete := false) -> int:
	errors = 0
	for l in _languages():
		_update(l, drop_obsolete)
	return errors


## Controlla i .po; restituisce il numero di errori.
func check(strict := false) -> int:
	errors = 0
	warnings = 0
	for l in _languages():
		_check(l, strict)
	_check_images()
	print("RISULTATO TRADUZIONI: %d errori, %d avvisi" % [errors, warnings])
	return errors


## Crea locale/<lang>.po vuoto (poi va elencato nelle impostazioni del progetto).
func new_language(lang: String) -> void:
	if not FileAccess.file_exists(_po_path(lang)):
		if _write_po(lang, {}, [], []):
			print("Creato %s: aggiungilo in Progetto > Impostazioni > Localizzazione > Traduzioni e in Game.LANGUAGES" % _po_path(lang))


## Lingue delle traduzioni elencate nelle impostazioni del progetto.
func _languages() -> Array[String]:
	var out: Array[String] = []
	for p in ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray()):
		if String(p).get_extension() == "po":
			out.append(String(p).get_file().get_basename())
	return out


func _po_path(lang: String) -> String:
	return LOCALE_DIR.path_join(lang + ".po")


func _files(dir: String, exts: Array) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for sub in da.get_directories():
		if not sub.begins_with(".") and sub != "addons":
			out.append_array(_files(dir.path_join(sub), exts))
	for f in da.get_files():
		if f.get_extension() in exts:
			out.append(dir.path_join(f))
	return out


func _add(msgid: String, ctx: String, ref: String, cformat := false) -> void:
	if msgid.strip_edges() == "":
		return
	var key := ctx + "\u0004" + msgid
	if not entries.has(key):
		entries[key] = {"msgid": msgid, "ctx": ctx, "refs": [], "cformat": false}
	var e: Dictionary = entries[key]
	if not (ref in e.refs):
		e.refs.append(ref)
	e.cformat = e.cformat or cformat


# --- script GDScript -------------------------------------------------------------------
## Divide il sorgente in token: id, str, num, nl, comment, e punteggiatura.
func _tokenize(src: String) -> Array:
	var toks: Array = []
	var i := 0
	var line := 1
	var n := src.length()
	while i < n:
		var c := src[i]
		if c == "\n":
			toks.append({"t": "nl", "line": line})
			line += 1
			i += 1
		elif c == " " or c == "\t" or c == "\r":
			i += 1
		elif c == "\\" and i + 1 < n and src[i + 1] == "\n":
			i += 2    # continuazione di riga
			line += 1
		elif c == "#":
			var e := src.find("\n", i)
			if e < 0:
				e = n
			toks.append({"t": "comment", "v": src.substr(i, e - i), "line": line})
			i = e
		elif c == "\"" or c == "'" or ((c == "&" or c == "^" or c == "r") and i + 1 < n and (src[i + 1] == "\"" or src[i + 1] == "'")):
			var raw := c == "r"
			if c != "\"" and c != "'":
				i += 1
			var q := src[i]
			var triple := src.substr(i, 3) == q + q + q
			var start_line := line
			i += 3 if triple else 1
			var s := ""
			while i < n:
				var ch := src[i]
				if triple and src.substr(i, 3) == q + q + q:
					i += 3
					break
				if not triple and ch == q:
					i += 1
					break
				if ch == "\n":
					line += 1
				if ch == "\\" and i + 1 < n:
					var nx := src[i + 1]
					if raw:
						s += ch + nx
					else:
						match nx:
							"n": s += "\n"
							"t": s += "\t"
							"r": s += "\r"
							"\\": s += "\\"
							"\"": s += "\""
							"'": s += "'"
							"\n":
								line += 1
							"u":
								s += char(src.substr(i + 2, 4).hex_to_int())
								i += 4
							"U":
								s += char(src.substr(i + 2, 6).hex_to_int())
								i += 6
							"a": s += char(7)
							"b": s += char(8)
							"f": s += char(12)
							"v": s += char(11)
							_: s += nx
					i += 2
					continue
				s += ch
				i += 1
			toks.append({"t": "str", "v": s, "line": start_line})
		elif c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z"):
			var j := i
			while j < n and (src[j] == "_" or (src[j] >= "a" and src[j] <= "z") or (src[j] >= "A" and src[j] <= "Z") or (src[j] >= "0" and src[j] <= "9")):
				j += 1
			toks.append({"t": "id", "v": src.substr(i, j - i), "line": line})
			i = j
		elif c >= "0" and c <= "9":
			var j := i
			while j < n and (src[j] == "." or src[j] == "_" or (src[j] >= "0" and src[j] <= "9") or (src[j] >= "a" and src[j] <= "z") or (src[j] >= "A" and src[j] <= "Z")):
				j += 1
			toks.append({"t": "num", "line": line})
			i = j
		else:
			toks.append({"t": c, "line": line})
			i += 1
	return toks


## Indice del prossimo token significativo da k in poi (salta a capo e commenti).
func _skip(toks: Array, k: int) -> int:
	while k < toks.size() and (toks[k].t == "nl" or toks[k].t == "comment"):
		k += 1
	return k


func _tok(toks: Array, k: int) -> String:
	return toks[k].t if k < toks.size() else ""


## Il testo contiene segnaposto (%s, %d...) oltre a %%?
func _has_spec(s: String) -> bool:
	return _re_spec.search_all(s).any(func(m): return m.get_string() != "%%")


func _scan_script(path: String) -> void:
	var rel := path.trim_prefix("res://")
	var toks := _tokenize(FileAccess.get_file_as_string(path))
	var re_marker := RegEx.create_from_string("^#\\s*i18n(?:\\s+ctx=(\\S+))?\\s*$")
	var k := 0
	var n := toks.size()
	while k < n:
		var t: Dictionary = toks[k]
		var where := "%s:%d" % [rel, t.line]
		var prev: String = toks[k - 1].get("v", toks[k - 1].t) if k > 0 else ""
		# tr("testo") / tr("testo", "contesto") / atr(...) / TranslationServer.translate(...)
		if t.t == "id" and (t.v == "tr" or t.v == "atr" or (t.v == "translate" and k >= 2 and toks[k - 2].get("v", "") == "TranslationServer")) \
				and prev != "func" and _tok(toks, k + 1) == "(":
			var a := _skip(toks, k + 2)
			if _tok(toks, a) == "str":
				var msgid: String = toks[a].v
				var ctx := ""
				var j := _skip(toks, a + 1)
				if _tok(toks, j) == ",":
					var c := _skip(toks, j + 1)
					if _tok(toks, c) == "str":
						ctx = toks[c].v
						j = _skip(toks, c + 1)
				if _tok(toks, j) == ")":
					_add(msgid, ctx, where, _tok(toks, j + 1) == "%" or _has_spec(msgid))
				else:
					_warn("%s: tr() deve contenere una sola stringa (più il contesto): con + o %% dentro la traduzione non verrebbe trovata. Scrivi tr(\"... %%s\") %% valore" % where)
				k = j
				continue
		if t.t == "id" and (t.v == "tr_n" or t.v == "atr_n") and _tok(toks, k + 1) == "(":
			_warn("%s: tr_n() (plurali) non è gestito da questo strumento" % where)
		# add_objective(id, "testo dell'obiettivo")
		if t.t == "id" and t.v == "add_objective" and prev != "func" and _tok(toks, k + 1) == "(":
			var c := _skip(toks, _skip(toks, k + 2) + 1)
			if _tok(toks, c) == ",":
				var s := _skip(toks, c + 1)
				if _tok(toks, s) == "str":
					var e := _skip(toks, s + 1)
					if _tok(toks, e) == ")" or _tok(toks, e) == ",":
						_add(toks[s].v, "", "%s:%d" % [rel, toks[s].line], _has_spec(toks[s].v))
					else:
						_warn("%s: il testo di add_objective() deve essere una sola stringa, senza + o %%" % where)
		# testo per il giocatore scritto senza tr(): label("..."), button("..."), notify("..."), x.text = "..."
		var lint := ""
		if t.t == "id" and t.v in LINT_CALLS and prev != "func" and _tok(toks, k + 1) == "(":
			lint = _lint_literal(toks, _skip(toks, k + 2))
		elif t.t == "id" and t.v in LINT_PROPS and prev == "." and _tok(toks, k + 1) == "=":
			lint = _lint_literal(toks, _skip(toks, k + 2))
		if lint != "":
			_warn("%s: testo per il giocatore senza tr(): %s" % [where, _short(lint)])
		# costante marcata con «# i18n» (su una riga a sé): tutti i testi tranne le chiavi
		if t.t == "comment" and (k == 0 or toks[k - 1].t == "nl"):
			var m := re_marker.search(String(t.v).strip_edges())
			if m != null:
				k = _scan_marked(toks, k + 1, m.get_string(1), rel)
				continue
		k += 1


## Se al token k c'è una stringa con parole (tolti tag e segnaposto), la restituisce.
func _lint_literal(toks: Array, k: int) -> String:
	if _tok(toks, k) != "str":
		return ""
	var s: String = toks[k].v
	return s if _re_letters.search(_re_bbcode_or_spec.sub(s, "", true)) != null else ""


func _scan_marked(toks: Array, k: int, ctx: String, rel: String) -> int:
	var n := toks.size()
	while k < n and (toks[k].t == "nl" or toks[k].t == "comment"):
		k += 1
	if k >= n or toks[k].t != "id" or not (toks[k].v in ["const", "var", "static"]):
		_warn("%s:%d: «# i18n» deve stare subito sopra una costante" % [rel, toks[max(k - 1, 0)].line])
		return k
	var depth := 0
	var started := false
	while k < n:
		var t: Dictionary = toks[k]
		match t.t:
			"(", "[", "{":
				depth += 1
			")", "]", "}":
				depth -= 1
			"=":
				started = true
			"nl":
				if depth == 0 and started:
					return k
			"str":
				var next: String = toks[k + 1].t if k + 1 < n else ""
				if next != ":":
					_add(t.v, ctx, "%s:%d" % [rel, t.line])
		k += 1
	return k


# --- scene e risorse -----------------------------------------------------------------------
func _scan_resource(path: String) -> void:
	var rel := path.trim_prefix("res://")
	var src := FileAccess.get_file_as_string(path)
	var re := RegEx.create_from_string("(?m)^([a-z_]+) = ")
	for m in re.search_all(src):
		var prop := m.get_string(1)
		if not (prop in TEXT_PROPS or prop in NAME_PROPS):
			continue
		var line := src.count("\n", 0, m.get_start()) + 1
		var i := m.get_end()
		var values: Array[String] = []
		if i < src.length() and src[i] == "\"":
			values.append(_tscn_string(src, i))
		elif src.substr(i, 18) == "PackedStringArray(" or src.substr(i, 15) == "Array[String]([":
			# elenco di stringhe: "a", "b", ... fino alla parentesi chiusa
			i = src.find("(", i) + 1
			while i < src.length():
				var c := src[i]
				if c == "\"":
					values.append(_tscn_string(src, i))
					i = _tscn_end
				elif c == ")":
					break
				else:
					i += 1
		for v in values:
			if prop in NAME_PROPS:
				var sp := v.find(" ")
				if sp > 1 and v[sp - 1] == ".":
					_add(v.substr(0, sp), "title", "%s:%d" % [rel, line])
				else:
					_add(v, "", "%s:%d" % [rel, line])
			else:
				_add(v, "", "%s:%d" % [rel, line])


var _tscn_end := 0


## Stringa di un file .tscn/.tres che inizia alla posizione i (sulle virgolette).
func _tscn_string(src: String, i: int) -> String:
	var s := ""
	i += 1
	while i < src.length():
		var c := src[i]
		if c == "\"":
			break
		if c == "\\" and i + 1 < src.length():
			var nx := src[i + 1]
			match nx:
				"n": s += "\n"
				"t": s += "\t"
				_: s += nx
			i += 2
			continue
		s += c
		i += 1
	_tscn_end = i + 1
	return s


# --- file .po ----------------------------------------------------------------------------
## Legge un .po: {"header": String, "items": [{ctx, msgid, msgstr, flags, comments, prev, obsolete}]}.
func _read_po(path: String) -> Dictionary:
	var out := {"header": "", "header_comments": [], "items": [], "error": ""}
	if not FileAccess.file_exists(path):
		return out
	var cur := {}
	var field := ""
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for ln in lines.size():
		var l := String(lines[ln]).strip_edges()
		var obsolete := false
		if l.begins_with("#~"):
			obsolete = true
			l = l.substr(2).strip_edges()
			if l.begins_with("|"):
				continue
		if l == "":
			cur = _po_flush(out, cur)
			field = ""
			continue
		if l.begins_with("#"):
			if cur.has("msgid"):
				cur = _po_flush(out, cur)
			if l.begins_with("#,"):
				cur["flags"] = Array(l.substr(2).split(",", false)).map(func(f): return String(f).strip_edges())
			elif l.begins_with("#| msgid "):
				cur["prev"] = _unquote(l.substr(9))
			elif l.begins_with("#| \"") and cur.has("prev"):
				cur["prev"] += _unquote(l.substr(3))   # frase precedente su più righe
			elif l.begins_with("#:") or l.begins_with("#|"):
				pass
			else:
				if not cur.has("comments"):
					cur["comments"] = []
				cur.comments.append(lines[ln])
			continue
		if obsolete:
			cur["obsolete"] = true
		var sp := l.find(" ")
		var kw := l.substr(0, sp) if sp > 0 else l
		if kw in ["msgctxt", "msgid", "msgstr"]:
			if kw != "msgstr" and cur.has("msgid"):
				cur = _po_flush(out, cur)
				if obsolete:
					cur["obsolete"] = true
			field = kw
			cur[{"msgctxt": "ctx", "msgid": "msgid", "msgstr": "msgstr"}[kw]] = _unquote(l.substr(sp + 1))
		elif kw == "msgid_plural" or kw.begins_with("msgstr["):
			out.error = "%s:%d: plurali non gestiti" % [path, ln + 1]
		elif l.begins_with("\"") and field != "":
			var key: String = {"msgctxt": "ctx", "msgid": "msgid", "msgstr": "msgstr"}[field]
			cur[key] = cur.get(key, "") + _unquote(l)
		else:
			out.error = "%s:%d: riga non valida: %s" % [path, ln + 1, l]
	_po_flush(out, cur)
	for it in out.items:
		for k in ["ctx", "msgstr"]:
			if not it.has(k):
				it[k] = ""
		for k in ["flags", "comments"]:
			if not it.has(k):
				it[k] = []
	return out


## Chiude la voce in lettura: l'intestazione (msgid vuoto) o una frase.
func _po_flush(out: Dictionary, cur: Dictionary) -> Dictionary:
	if cur.has("msgid"):
		if cur.msgid == "" and cur.get("ctx", "") == "":
			out.header = cur.get("msgstr", "")
			out.header_comments = cur.get("comments", [])
		else:
			out.items.append(cur)
	return {}


func _unquote(s: String) -> String:
	s = s.strip_edges()
	if s.length() < 2 or not s.begins_with("\"") or not s.ends_with("\""):
		return s
	s = s.substr(1, s.length() - 2)
	var out := ""
	var i := 0
	while i < s.length():
		var c := s[i]
		if c == "\\" and i + 1 < s.length():
			var nx := s[i + 1]
			match nx:
				"n": out += "\n"
				"t": out += "\t"
				"r": out += "\r"
				_: out += nx
			i += 2
			continue
		out += c
		i += 1
	return out


func _quote(s: String) -> String:
	return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\t", "\\t").replace("\r", "\\r").replace("\n", "\\n") + "\""


func _po_field(prefix: String, kw: String, s: String) -> String:
	if not ("\n" in s.trim_suffix("\n")):
		return "%s%s %s\n" % [prefix, kw, _quote(s)]
	var out := "%s%s \"\"\n" % [prefix, kw]
	var parts := s.split("\n")
	for p in parts.size():
		var seg: String = parts[p] + ("\n" if p < parts.size() - 1 else "")
		if seg != "":
			out += prefix + _quote(seg) + "\n"
	return out


func _default_header(lang: String) -> String:
	return "Project-Id-Version: Seraph Protocol\nLanguage: %s\nMIME-Version: 1.0\nContent-Type: text/plain; charset=UTF-8\nContent-Transfer-Encoding: 8bit\nPlural-Forms: nplurals=2; plural=(n != 1);\n" % lang


func _write_po(lang: String, po: Dictionary, items: Array, obsolete: Array) -> bool:
	var t := ""
	var head_comments: Array = po.get("header_comments", [])
	if head_comments.is_empty():
		head_comments = [
			"# Traduzione (%s) dei testi del gioco. Le frasi inglesi (msgid) vengono dal codice e" % lang,
			"# dalle scene: le aggiunge tools/aggiorna_traduzioni.gd, qui si scrive solo msgstr.",
		]
	for c in head_comments:
		t += String(c) + "\n"
	var header: String = po.get("header", "")
	t += "msgid \"\"\n" + _po_field("", "msgstr", header if header != "" else _default_header(lang))
	for it in items:
		t += "\n"
		for c in it.get("comments", []):
			t += String(c) + "\n"
		for r in it.get("refs", []):
			t += "#: %s\n" % r
		if not it.flags.is_empty():
			t += "#, %s\n" % ", ".join(it.flags)
		if it.get("prev", "") != "" and "fuzzy" in it.flags:
			t += "#| msgid %s\n" % _quote(it.prev)
		if it.ctx != "":
			t += _po_field("", "msgctxt", it.ctx)
		t += _po_field("", "msgid", it.msgid)
		t += _po_field("", "msgstr", it.msgstr)
	for it in obsolete:
		t += "\n"
		for c in it.get("comments", []):
			t += String(c) + "\n"
		if not it.flags.is_empty():
			t += "#, %s\n" % ", ".join(it.flags)
		if it.ctx != "":
			t += _po_field("#~ ", "msgctxt", it.ctx)
		t += _po_field("#~ ", "msgid", it.msgid)
		t += _po_field("#~ ", "msgstr", it.msgstr)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOCALE_DIR))
	var f := FileAccess.open(_po_path(lang), FileAccess.WRITE)
	if f == null:
		_err("impossibile scrivere %s (%s)" % [_po_path(lang), error_string(FileAccess.get_open_error())])
		return false
	f.store_string(t)
	f.close()
	return true


# --- aggiornamento -----------------------------------------------------------------------
func _update(lang: String, drop_obsolete: bool) -> void:
	var path := _po_path(lang)
	var po := _read_po(path)
	if po.error != "":
		_err(po.error)
		return
	var old := {}
	for it in po.items:
		old[it.ctx + "\u0004" + it.msgid] = it
	var items: Array = []
	var added := 0
	var fuzzy := 0
	var used := {}
	for key in entries:
		var e: Dictionary = entries[key]
		var it := {"ctx": e.ctx, "msgid": e.msgid, "msgstr": "", "flags": [], "comments": [], "refs": e.refs}
		if old.has(key):
			var o: Dictionary = old[key]
			it.msgstr = o.msgstr
			it.flags = o.flags.filter(func(f): return f != "c-format")
			it.comments = o.comments
			if o.has("prev"):
				it.prev = o.prev
			used[key] = true
		else:
			added += 1
		if e.cformat:
			it.flags.append("c-format")
		items.append(it)
	# frasi sparite: diventano obsolete; se una frase nuova le somiglia, ne riprende
	# la traduzione come «fuzzy» (il gioco la ignora finché non la ricontrolli)
	var gone: Array = []
	for key in old:
		if not used.has(key) and old[key].msgstr != "":
			gone.append(old[key])
	for it in items:
		if it.msgstr != "" or gone.is_empty():
			continue
		var best: Dictionary = {}
		var best_sim := 0.7
		for o in gone:
			if o.ctx != it.ctx:
				continue
			var sim: float = String(o.msgid).similarity(it.msgid)
			if sim > best_sim:
				best_sim = sim
				best = o
		if not best.is_empty():
			it.msgstr = best.msgstr
			it.flags.append("fuzzy")
			it.prev = best.msgid
			fuzzy += 1
	var obsolete: Array = []
	if not drop_obsolete:
		for key in old:
			if not used.has(key):
				obsolete.append(old[key])
	if not _write_po(lang, po, items, obsolete):
		return
	var todo := items.filter(func(it): return it.msgstr == "" or "fuzzy" in it.flags).size()
	print("%s: %d frasi, %d nuove (%d con una traduzione da ricontrollare), %d obsolete; da tradurre: %d" % [
		path, items.size(), added, fuzzy, obsolete.size(), todo])


# --- controllo -----------------------------------------------------------------------------
func _check(lang: String, strict: bool) -> void:
	var path := _po_path(lang)
	if not FileAccess.file_exists(path):
		_err("%s non esiste: crealo con --update" % path)
		return
	var po := _read_po(path)
	if po.error != "":
		_err(po.error)
		return
	if not (("Language: " + lang) in String(po.header)):
		_err("%s: manca «Language: %s» nell'intestazione (Godot non saprebbe di che lingua è)" % [path, lang])
	var have := {}
	var obsolete := 0
	for it in po.items:
		if it.get("obsolete", false):
			obsolete += 1
			continue
		var key: String = it.ctx + "\u0004" + it.msgid
		if have.has(key):
			_err("%s: frase ripetuta: %s" % [path, _short(it.msgid)])
		have[key] = it
	var missing := 0
	var untranslated := 0
	var fuzzy := 0
	for key in entries:
		var e: Dictionary = entries[key]
		var where := "%s (%s)" % [_short(e.msgid), e.refs[0]]
		if not have.has(key):
			missing += 1
			_problem(strict, "%s: manca %s — aggiorna il file (tools/aggiorna_traduzioni.gd)" % [path, where])
			continue
		var it: Dictionary = have[key]
		if "fuzzy" in it.flags:
			fuzzy += 1
			_problem(strict, "%s: traduzione da ricontrollare (fuzzy): %s" % [path, where])
			continue
		if it.msgstr == "":
			untranslated += 1
			_problem(strict, "%s: da tradurre: %s" % [path, where])
			continue
		var a := _specs(e.msgid)
		var b := _specs(it.msgstr)
		if a != b:
			_err("%s: segnaposto diversi dall'inglese %s -> %s: %s" % [path, a, b, where])
		if _tags(e.msgid) != _tags(it.msgstr):
			_err("%s: tag diversi dall'inglese %s -> %s: %s" % [path, _tags(e.msgid), _tags(it.msgstr), where])
		for m in _re_num.search_all(e.msgid):
			if not m.get_string() in it.msgstr:
				_err("%s: il numero %s non c'è nella traduzione: %s" % [path, m.get_string(), where])
		if (e.msgid.begins_with(" ") != it.msgstr.begins_with(" ")) or (e.msgid.ends_with(" ") != it.msgstr.ends_with(" ")) \
				or (e.msgid.ends_with("\n") != it.msgstr.ends_with("\n")):
			_warn("%s: spazi o a capo iniziali/finali diversi dall'inglese: %s" % [path, where])
	var unused := 0
	for key in have:
		if not entries.has(key):
			unused += 1
	if unused > 0:
		_problem(strict, "%s: %d frasi non esistono più nel gioco — aggiorna il file (tools/aggiorna_traduzioni.gd)" % [path, unused])
	print("%s: %d frasi del gioco, %d tradotte, %d da tradurre, %d fuzzy, %d mancanti, %d obsolete" % [
		path, entries.size(), entries.size() - missing - untranslated - fuzzy, untranslated, fuzzy, missing, obsolete])


## Immagini con scritte (insegne, poster): la variante <nome>_<lingua>.png si usa
## al posto di <nome>.png (Util.localized), che quindi deve esistere.
func _check_images() -> void:
	var count := 0
	for lang in _languages():
		for f in _files("res://assets", ["png", "jpg", "webp", "svg"]):
			var base := f.get_basename()
			if base.ends_with("_" + lang):
				count += 1
				var orig := base.trim_suffix("_" + lang) + "." + f.get_extension()
				if not FileAccess.file_exists(orig):
					_err("%s è la versione (%s) di %s, che non esiste: non verrà mai usata" % [f, lang, orig])
	print("Immagini con una versione per lingua (insegne, poster): %d" % count)


func _specs(s: String) -> Array:
	return _re_spec.search_all(s).map(func(m): return m.get_string())


func _tags(s: String) -> Array:
	var t := _re_tag.search_all(s).map(func(m): return m.get_string())
	t.sort()
	return t


func _short(s: String) -> String:
	s = s.replace("\n", " ")
	return "«%s»" % (s if s.length() <= 60 else s.substr(0, 57) + "...")


func _problem(strict: bool, msg: String) -> void:
	if strict:
		_err(msg)
	else:
		_warn(msg)


func _err(msg: String) -> void:
	errors += 1
	print("ERRORE  ", msg)


func _warn(msg: String) -> void:
	warnings += 1
	print("AVVISO  ", msg)
