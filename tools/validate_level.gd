extends Node
## VALIDATORE DI LIVELLO: controlla gli errori tipici di chi costruisce una mappa
## nell'editor, senza dover giocare. Avvio:
##   godot --headless --path . -- --validate                     (livello di default)
##   godot --headless --path . -- --validate --level=res://levels/mio/mio.tscn
## Stampa ERRORE (il livello è rotto: esce con codice 1) e AVVISO (probabile svista).
## Gira da solo anche quando provi un livello con F6: i messaggi finiscono nel
## pannello Output e in Debugger > Errori, e il gioco continua.
##
## Controlla: geometria (Solido, zone, brush), PlayerStart, oggetti fuori mappa o
## nei muri, NodePath (torretta, interruttori, percorsi), registri dei datapad,
## porte chiuse che non si possono aprire, guardie che non raggiungono le tappe,
## testi del livello senza traduzione italiana (in italiano resterebbero in inglese).

var errors := 0
var warnings := 0
var lvl: Level
## false = modalità F6: segnala e basta, senza chiudere il gioco.
var quit_when_done := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	lvl = Game.level
	print("=== Validazione livello: %s ===" % Game.level_path)
	if lvl == null or lvl.builder == null:
		_err("", "il livello non si è caricato (manca il nodo LevelGeometry o lo script Level?)")
		_finish()
		return
	_check_geometry()
	_check_positions()
	_check_links()
	_check_doors()
	_check_translations()
	# fisica e navmesh sono pronte solo dopo i primi frame
	var map: RID = lvl.get_world_3d().navigation_map
	for i in 120:
		await get_tree().physics_frame
		if i >= 10 and NavigationServer3D.map_get_iteration_id(map) > 1:
			break
	_check_player_start()
	_check_guards()
	_finish()


func _err(where: String, what: String) -> void:
	errors += 1
	var msg := (("[%s] " % where) if where != "" else "") + what
	print("ERRORE  ", msg)
	if not quit_when_done:
		push_error("Livello: " + msg)


func _warn(where: String, what: String) -> void:
	warnings += 1
	var msg := (("[%s] " % where) if where != "" else "") + what
	print("AVVISO  ", msg)
	if not quit_when_done:
		push_warning("Livello: " + msg)


func _path(n: Node) -> String:
	return String(lvl.get_path_to(n))


func _all(cls_check: Callable) -> Array:
	var out: Array = []
	for n in lvl.find_children("*", "", true, false):
		if cls_check.call(n):
			out.append(n)
	return out


func _finish() -> void:
	print("RISULTATO: %d errori, %d avvisi" % [errors, warnings])
	if quit_when_done:
		get_tree().quit(1 if errors > 0 else 0)
	else:
		queue_free()


# --- geometria -------------------------------------------------------------------
func _check_geometry() -> void:
	var b := lvl.builder
	if not b.solid_aabb.has_volume():
		_err("Geometria", "il primo figlio deve essere il blocco 'Solido' (CSGBox3D) che contiene tutto")
	var used := {}
	for z in b.zones:
		var bits := 0
		for i in 20:
			if int(z.layer) & (1 << i):
				bits += 1
		if bits != 1:
			_err(z.path, "la zona deve avere esattamente un layer spuntato (ne ha %d)" % bits)
		elif used.has(z.layer):
			_err(z.path, "stesso layer della zona %s: ogni zona deve avere il suo" % used[z.layer])
		else:
			used[z.layer] = z.path
	var air := 0
	for br in b.brushes:
		if br.surface == null:
			_err(br.path, "brush senza SurfaceSet (sarà invisibile)")
		if br.air:
			air += 1
			if b.solid_aabb.has_volume() and not b.solid_aabb.grow(0.01).encloses(br.aabb):
				_err(br.path, "esce dal blocco Solido: lì la stanza non ha muri")
		elif int(br.zones) == 0:
			_err(br.path, "brush solido senza zona: spunta la sua zona in 'Extra Zones' (ora è invisibile)")
	if air == 0:
		_err("Geometria", "nessun brush d'aria: aggiungi una Zona con dentro almeno un Brush")
	print("        geometria: %d zone, %d brush (%d d'aria)" % [b.zones.size(), b.brushes.size(), air])


func _check_player_start() -> void:
	var starts := _all(func(n): return n is PlayerStart)
	if starts.is_empty():
		_err("", "manca il PlayerStart (scenes/entities/player_start.tscn)")
		return
	if starts.size() > 1:
		_warn("", "%d PlayerStart: viene usato solo il primo (%s)" % [starts.size(), _path(starts[0])])
	var s: Node3D = starts[0]
	var p := s.global_position
	if lvl.builder.air_brush_at(p + Vector3.UP * 0.9).is_empty():
		_err(_path(s), "il PlayerStart non è dentro una stanza (è nel muro o fuori mappa)")
		return
	var space := lvl.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 1.5, Layers.WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		_err(_path(s), "sotto il PlayerStart non c'è pavimento")
	elif p.y - (hit.position as Vector3).y > 0.3:
		_warn(_path(s), "il PlayerStart è %.1f m sopra il pavimento" % (p.y - (hit.position as Vector3).y))


# --- oggetti fuori mappa ---------------------------------------------------------
func _is_entity(n: Node) -> bool:
	return n is Pickup or n is Datapad or n is Throwable or n is SlidingDoor or n is LightFixture \
		or n is Guard or n is SecurityCamera or n is Turret or n is TurretPanel or n is LightSwitch \
		or n is VentGrate or n is ElevatorPanel or n is SecurityTerminal or n is UpgradeStation \
		or n is ServerCore or n is PropBox or n is PropCylinder or n is PropQuad or n is TriggerZone \
		or n is Waypoint


func _check_positions() -> void:
	var count := 0
	for n in _all(_is_entity):
		count += 1
		var p: Vector3 = (n as Node3D).global_position
		# gli oggetti appoggiati a terra hanno l'origine sul pavimento: controlla poco sopra
		if lvl.builder.air_brush_at(p + Vector3.UP * 0.05, 0.35).is_empty():
			_warn(_path(n), "è fuori dalle stanze (dentro un muro o fuori mappa?) a %s" % _v(p))
	print("        entità controllate: %d" % count)


func _v(p: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]


# --- collegamenti ----------------------------------------------------------------
func _check_links() -> void:
	for tp in _all(func(n): return n is TurretPanel):
		var t: Node = tp.get_node_or_null(tp.turret_path)
		if not (t is Turret):
			_err(_path(tp), "'Turret Path' non punta a una Torretta")
	for ls in _all(func(n): return n is LightSwitch):
		if ls.targets.is_empty():
			_warn(_path(ls), "interruttore senza luci collegate ('Targets')")
		for np in ls.targets:
			if not (ls.get_node_or_null(np) is LightFixture):
				_err(_path(ls), "'Targets' contiene %s che non è una luce" % np)
	for g in _all(func(n): return n is Guard):
		if g.patrol_route.is_empty():
			continue
		var r: Node = g.get_node_or_null(g.patrol_route)
		if not (r is PatrolRoute):
			_err(_path(g), "'Patrol Route' non punta a un PatrolRoute")
		elif r.get_children().filter(func(c): return c is Waypoint).size() < 2:
			_warn(_path(r), "percorso con meno di 2 tappe: la guardia resta ferma")
	for d in _all(func(n): return n is Datapad):
		if d.log_id == "":
			_err(_path(d), "datapad senza 'Log Id'")
		elif not Logs.ENTRIES.has(d.log_id):
			_err(_path(d), "registro '%s' inesistente: aggiungilo in scripts/data/logs.gd" % d.log_id)
	for pk in _all(func(n): return n is Pickup):
		if pk.kind == "keycard" and pk.item_id == "":
			_err(_path(pk), "tessera senza 'Item Id' (serve alle porte per riconoscerla)")


# --- porte chiuse: si possono aprire? ----------------------------------------------
func _check_doors() -> void:
	var cards := {}
	for pk in _all(func(n): return n is Pickup):
		if pk.kind == "keycard":
			cards[pk.item_id] = "raccolta in " + _path(pk)
	for g in _all(func(n): return n is Guard):
		# bottino già risolto dalla guardia (dalla sua definizione o dai campi "Bottino")
		if g.loot.has("keycard"):
			cards[String(g.loot.keycard[0])] = "addosso a " + String(g.guard_name)
	var texts := ""
	for d in _all(func(n): return n is Datapad):
		if Logs.ENTRIES.has(d.log_id):
			texts += String(Logs.ENTRIES[d.log_id].text) + "\n\u0001"   # separatore fra i registri
	for d in _all(func(n): return n is SlidingDoor):
		if not d.locked:
			continue
		var ways: Array[String] = []
		if d.keycard_id != "":
			if cards.has(d.keycard_id):
				ways.append("tessera '%s' (%s)" % [d.keycard_id, cards[d.keycard_id]])
			else:
				_warn(_path(d), "chiede la tessera '%s' ma nel livello non c'è (né a terra né addosso a una guardia)" % d.keycard_id)
		if d.code != "":
			if d.code in texts:
				ways.append("codice %s (scritto in un datapad)" % d.code)
				for lang in _other_languages():
					if not (d.code in _translate_all(texts, lang)):
						_warn(_path(d), "il codice %s non compare nella traduzione (%s) dei datapad: controlla locale/%s.po" % [d.code, lang, lang])
			else:
				_warn(_path(d), "il codice %s non compare in nessun datapad del livello" % d.code)
		if d.hack_level > 0:
			ways.append("hacking %d" % d.hack_level)
		if ways.is_empty():
			_warn(_path(d), "porta chiusa che non si può aprire (ok solo se la apre lo script di missione)")


# --- testi e traduzioni ------------------------------------------------------------
## Lingue del gioco oltre all'inglese (la lingua in cui si scrivono i testi).
func _other_languages() -> Array:
	return Game.LANGUAGES.keys().filter(func(l): return l != "en")


## Traduce riga per riga i testi dei datapad (per cercarci i codici).
func _translate_all(texts: String, lang: String) -> String:
	var t := TranslationServer.get_translation_object(lang)
	var out := ""
	for s in texts.split("\n\u0001", false):
		var m := String(t.get_message(s)) if t != null else ""
		out += (m if m != "" else s) + "\n"
	return out


func _check_translations() -> void:
	var texts := {}   # [testo, contesto] -> nodo in cui compare
	var add := func(s: String, n: Node, ctx := ""):
		if s.strip_edges() != "" and not texts.has([s, ctx]):
			texts[[s, ctx]] = n
	var add_name := func(s: String, n: Node):
		var sp := s.find(" ")
		if sp > 1 and s[sp - 1] == ".":
			add.call(s.substr(0, sp), n, "title")
		else:
			add.call(s, n)
	for n in _all(func(x): return x is TriggerZone):
		add_name.call(n.speaker, n)
		add.call(n.text, n)
	for n in _all(func(x): return x is SlidingDoor):
		add.call(n.lock_title, n)
		add.call(n.keycard_name, n)
	for n in _all(func(x): return x is Pickup):
		add.call(n.display, n)
	for n in _all(func(x): return x is Label3D):
		add.call(n.text, n)
	for n in _all(func(x): return x is PropQuad or x is PropBox):
		if n.caption != "-":
			add.call(n.caption, n)   # didascalia scritta sull'oggetto (quelle delle texture sono nel codice)
	for g in _all(func(x): return x is Guard):
		add_name.call(g.guard_name, g)
		add.call(g.loot_keycard_name, g)
		if g.definition != null:
			add.call(g.definition.keycard_name, g)
			for b in g.definition.idle_barks:
				add.call(b, g)
	for d in _all(func(x): return x is Datapad):
		var e: Dictionary = Logs.ENTRIES.get(d.log_id, {})
		for k in ["title", "author", "text"]:
			add.call(String(e.get(k, "")), d)
	for o in Game.objectives:
		add.call(String(o.text), lvl)
	for lang in _other_languages():
		var t := TranslationServer.get_translation_object(lang)
		var missing := 0
		for key in texts:
			if t == null or String(t.get_message(key[0], key[1])) == "":
				missing += 1
				if missing <= 12:
					_warn(_path(texts[key]), "manca la traduzione (%s) di «%s»" % [lang, _short(key[0])])
		if missing > 0:
			_warn("Traduzioni", "%d testi senza traduzione (%s): in quella lingua restano in inglese. Aggiorna locale/%s.po con tools/aggiorna_traduzioni.gd (File → Run) e traducili: vedi la guida, «Testi e traduzioni»" % [missing, lang, lang])
	print("        testi del livello: %d" % texts.size())


func _short(s: String) -> String:
	s = s.replace("\n", " ")
	return s if s.length() <= 50 else s.substr(0, 47) + "..."


# --- guardie e navmesh -----------------------------------------------------------
func _reachable(a: Vector3, b: Vector3) -> bool:
	var map: RID = lvl.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	return path.size() > 1 and path[path.size() - 1].distance_to(b) < 0.8


func _check_guards() -> void:
	var map: RID = lvl.get_world_3d().navigation_map
	for g in _all(func(n): return n is Guard):
		var start: Vector3 = g.post_pos
		var closest := NavigationServer3D.map_get_closest_point(map, start)
		if Vector2(closest.x - start.x, closest.z - start.z).length() > 0.6:
			_err(_path(g), "la guardia a %s non è sulla navmesh (troppo vicina a un muro o a un mobile?)" % _v(start))
			continue
		for i in g.waypoints.size():
			var wp: Vector3 = g.waypoints[i]
			if not _reachable(start, wp):
				_err(_path(g), "non può raggiungere la tappa %d %s del suo percorso" % [i + 1, _v(wp)])
