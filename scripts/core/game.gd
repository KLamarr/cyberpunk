extends Node
## Autoload "Game": stato globale della missione.
## Skill, inventario, obiettivi, registri letti, sistema del rumore, allarmi,
## statistiche. Gli altri script comunicano soprattutto tramite i segnali qui sotto.

signal message(text: String, color: Color)
signal subtitle(speaker: String, text: String, duration: float)
signal objectives_changed
signal inventory_changed
signal skills_changed
signal alarm_changed(active: bool)
signal lockdown_started
signal player_damaged(amount: float, from_pos: Vector3)
signal state_changed(new_state: int)
signal settings_changed
signal log_read(id: String)

enum State { MENU, PLAYING, PANEL, DEAD, COMPLETE }

# --- skill -------------------------------------------------------------------
const SKILLS := ["hacking", "armi", "forza", "furtivita"]
const SKILL_NAMES := {
	"hacking": "HACKING",
	"armi": "ARMI DA FUOCO",
	"forza": "FORZA",
	"furtivita": "FURTIVITÀ",
}
const SKILL_DESC := {
	"hacking": "Sblocca porte, terminali e torrette. Ogni dispositivo richiede un livello minimo; ogni livello in più alza le probabilità di successo per nodo.",
	"armi": "Pistola più precisa (-25% dispersione per livello), più danno e ricarica più rapida.",
	"forza": "+10 salute massima e più danno in mischia per livello. Livello 1: rimuovi le grate a mano, in silenzio. Lanci più lontano.",
	"furtivita": "-12% visibilità e -15% rumore dei passi per livello. Ti muovi più veloce da accovacciato.",
}
const SKILL_MAX := 4
const START_POINTS := 4
const START_CAP := 2
const MAG_SIZE := 8
const ALARM_DURATION := 45.0

const INPUT_MAP := {
	"move_forward": [["key", KEY_W]],
	"move_back": [["key", KEY_S]],
	"move_left": [["key", KEY_A]],
	"move_right": [["key", KEY_D]],
	"jump": [["key", KEY_SPACE]],
	"crouch": [["key", KEY_CTRL]],
	"crouch_toggle": [["key", KEY_C]],
	"sprint": [["key", KEY_SHIFT]],
	"lean_left": [["key", KEY_Q]],
	"lean_right": [["key", KEY_E]],
	"frob": [["key", KEY_F], ["mouse", MOUSE_BUTTON_RIGHT]],
	"attack": [["mouse", MOUSE_BUTTON_LEFT]],
	"reload": [["key", KEY_R]],
	"weapon_1": [["key", KEY_1]],
	"weapon_2": [["key", KEY_2]],
	"weapon_next": [["mouse", MOUSE_BUTTON_WHEEL_DOWN]],
	"weapon_prev": [["mouse", MOUSE_BUTTON_WHEEL_UP]],
	"medpatch": [["key", KEY_H]],
	"pda": [["key", KEY_TAB]],
	"pause": [["key", KEY_ESCAPE]],
	"toggle_pixel": [["key", KEY_F2]],
	"toggle_dither": [["key", KEY_F3]],
}

var state: int = State.MENU
var skills := {}
var start_alloc := {}
var modules := 0
var credits := 0
var ammo_mag := 6
var ammo_reserve := 10
var medpatches := 1
var keycards := {}          # id -> nome leggibile
var items := {}             # oggetti di missione (es. "core")
var logs_read: Array[String] = []
var objectives: Array = []  # [{id, text, optional, state}]  state: "active"|"done"|"failed"
var stats := {}
var alarm_time := 0.0
var security_disabled := false
var lockdown := false
var secrets_found: Array[String] = []

## Scena del livello da caricare (vedi scenes/main.tscn).
var level_path := "res://levels/seraph/seraph.tscn"
## true = salta il menu iniziale (livello avviato con F6 dall'editor).
var quick_start := false

var player: Node = null
var level: Node = null
var ui: Node = null
var hud: Node = null

var settings := {
	"pixel_scale": 2,
	"dither": true,
	"sensitivity": 0.12,
	"volume": 0.8,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_input_map()
	for s in SKILLS:
		start_alloc[s] = 0
	reset_state()


static func ensure_input_map() -> void:
	for action in INPUT_MAP:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for ev_def in INPUT_MAP[action]:
			var ev: InputEvent
			if ev_def[0] == "key":
				var k := InputEventKey.new()
				k.physical_keycode = ev_def[1]
				ev = k
			else:
				var m := InputEventMouseButton.new()
				m.button_index = ev_def[1]
				ev = m
			ev.device = -1  # tutti i dispositivi
			InputMap.action_add_event(action, ev)


## Scrive l'InputMap in project.godot, così i comandi compaiono (e si
## rimappano) in Progetto > Impostazioni > Mappa input. Uso:
##   godot --path . -- --write-input-map
func write_input_map_to_project() -> void:
	for action in INPUT_MAP:
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": InputMap.action_get_events(action)})
	ProjectSettings.save()
	print("InputMap salvata in project.godot")


func reset_state() -> void:
	skills = start_alloc.duplicate()
	modules = 0
	credits = 0
	ammo_mag = 6
	ammo_reserve = 10
	medpatches = 1
	keycards = {}
	items = {}
	logs_read = []
	secrets_found = []
	alarm_time = 0.0
	security_disabled = false
	lockdown = false
	player = null
	level = null
	stats = {
		"time": 0.0, "kills": 0, "kos": 0, "alarms": 0, "detections": 0,
		"pickpockets": 0, "hacks": 0, "shots": 0,
	}
	objectives = []   # li aggiunge lo script di missione del livello (setup_mission)


# --- stato / pausa ------------------------------------------------------------
func set_state(s: int) -> void:
	state = s
	match s:
		State.PLAYING:
			get_tree().paused = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		State.PANEL, State.MENU:
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		State.DEAD, State.COMPLETE:
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	state_changed.emit(s)


func is_playing() -> bool:
	return state == State.PLAYING


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	stats.time += delta
	if alarm_time > 0.0:
		alarm_time -= delta
		if alarm_time <= 0.0:
			alarm_time = 0.0
			Sfx.set_alarm(false)
			alarm_changed.emit(false)
			notify("Allarme rientrato.", Color(0.6, 0.9, 0.8))


# --- skill --------------------------------------------------------------------
func skill(s: String) -> int:
	return int(skills.get(s, 0))


func upgrade_cost(s: String) -> int:
	return skill(s) + 1


func try_upgrade(s: String) -> bool:
	if skill(s) >= SKILL_MAX:
		return false
	var cost := upgrade_cost(s)
	if modules < cost:
		return false
	modules -= cost
	skills[s] = skill(s) + 1
	skills_changed.emit()
	inventory_changed.emit()
	if player and player.has_method("on_skills_changed"):
		player.on_skills_changed()
	return true


# --- inventario ---------------------------------------------------------------
func give_keycard(id: String, display_name: String) -> void:
	keycards[id] = display_name
	inventory_changed.emit()


func has_keycard(id: String) -> bool:
	return keycards.has(id)


func add_modules(n: int) -> void:
	modules += n
	inventory_changed.emit()


func add_credits(n: int) -> void:
	credits += n
	inventory_changed.emit()


func add_ammo(n: int) -> void:
	ammo_reserve += n
	inventory_changed.emit()


func add_medpatch(n: int = 1) -> void:
	medpatches += n
	inventory_changed.emit()


func give_item(id: String) -> void:
	items[id] = true
	inventory_changed.emit()


func has_item(id: String) -> bool:
	return items.has(id)


func found_secret(id: String) -> void:
	if id in secrets_found:
		return
	secrets_found.append(id)
	notify("Hai trovato un segreto!", Color(1.0, 0.85, 0.3))


# --- registri -----------------------------------------------------------------
func read_log(id: String, open_reader := true) -> void:
	var first := not (id in logs_read)
	if first:
		logs_read.append(id)
		Sfx.play_ui("datapad")
		var title: String = Logs.ENTRIES.get(id, {}).get("title", id)
		notify("Registro aggiunto al PDA: " + title, Color(0.5, 0.9, 1.0))
		log_read.emit(id)
	if open_reader and ui:
		ui.show_log(id)


# --- obiettivi ----------------------------------------------------------------
func add_objective(id: String, text: String, optional := false) -> void:
	for o in objectives:
		if o.id == id:
			return
	objectives.append({"id": id, "text": text, "optional": optional, "state": "active"})
	objectives_changed.emit()


func _obj(id: String) -> Dictionary:
	for o in objectives:
		if o.id == id:
			return o
	return {}


func is_objective_active(id: String) -> bool:
	var o := _obj(id)
	return not o.is_empty() and o.state == "active"


func complete_objective(id: String, reward_modules := 0) -> void:
	var o := _obj(id)
	if o.is_empty() or o.state != "active":
		return
	o.state = "done"
	Sfx.play_ui("objective")
	var extra := ""
	if reward_modules > 0:
		modules += reward_modules
		extra = "  (+%d cyber-moduli)" % reward_modules
		inventory_changed.emit()
	notify("OBIETTIVO COMPLETATO: " + o.text + extra, Color(0.4, 1.0, 0.6))
	objectives_changed.emit()


func fail_objective(id: String) -> void:
	var o := _obj(id)
	if o.is_empty() or o.state != "active":
		return
	o.state = "failed"
	notify("OBIETTIVO FALLITO: " + o.text, Color(1.0, 0.35, 0.3))
	objectives_changed.emit()


# --- messaggi -----------------------------------------------------------------
func notify(text: String, color := Color(0.75, 0.95, 0.9)) -> void:
	message.emit(text, color)


func say(speaker: String, text: String, duration := 3.5) -> void:
	subtitle.emit(speaker, text, duration)


# --- rumore -------------------------------------------------------------------
## Ogni suono "udibile" dall'IA passa da qui. kind: step, impact, clang, glass,
## grate, gunshot, shout, body, alarm.  source: nodo che l'ha generato.
func emit_noise(pos: Vector3, radius: float, kind: String, source: Node = null, info := {}) -> void:
	if radius <= 0.05:
		return
	for n in get_tree().get_nodes_in_group("ai"):
		if n != source and n.has_method("hear"):
			n.hear(pos, radius, kind, source, info)
	if hud and hud.has_method("on_noise") and source == player:
		hud.on_noise(radius)


# --- allarmi / eventi ---------------------------------------------------------
func raise_alarm(pos: Vector3, source_name := "") -> void:
	if state != State.PLAYING:
		return
	var was_active := alarm_time > 0.0
	alarm_time = ALARM_DURATION
	if not was_active:
		stats.alarms += 1
		fail_objective("noalarm")
		Sfx.set_alarm(true)
		alarm_changed.emit(true)
		notify("ALLARME! " + source_name, Color(1.0, 0.3, 0.25))
		say("SISTEMA PA", "Allarme di sicurezza nel settore 14. Personale di vigilanza, convergere.", 4.0)
	for g in get_tree().get_nodes_in_group("guards"):
		if g.has_method("on_alarm"):
			g.on_alarm(pos)


func disable_security() -> void:
	security_disabled = true
	for c in get_tree().get_nodes_in_group("security_cameras"):
		c.set_disabled(true)
	notify("Telecamere disattivate.", Color(0.5, 1.0, 0.6))


func disable_turrets() -> void:
	for t in get_tree().get_nodes_in_group("turrets"):
		t.set_disabled(true)
	notify("Torrette disattivate.", Color(0.5, 1.0, 0.6))


func on_player_spotted() -> void:
	stats.detections += 1


func on_guard_down(guard: Node, killed: bool) -> void:
	if killed:
		stats.kills += 1
		fail_objective("nokill")
	else:
		stats.kos += 1


func start_lockdown() -> void:
	if lockdown:
		return
	lockdown = true
	lockdown_started.emit()
	if level and level.has_method("on_lockdown"):
		level.on_lockdown()


func complete_mission() -> void:
	# gli obiettivi opzionali ancora attivi (tranne Okafor) valgono come riusciti
	for id in ["nokill", "noalarm"]:
		if is_objective_active(id):
			_obj(id).state = "done"
	complete_objective("extract")
	set_state(State.COMPLETE)
	if ui:
		ui.show_complete()


func on_player_died() -> void:
	set_state(State.DEAD)
	if ui:
		ui.show_death()


func rating() -> String:
	if stats.kills == 0 and stats.alarms == 0 and stats.detections == 0 and stats.kos == 0:
		return "SPETTRO — nessuno sa che sei stato qui"
	if stats.kills == 0 and stats.alarms == 0 and stats.detections == 0:
		return "FANTASMA"
	if stats.kills == 0:
		return "PROFESSIONISTA NON LETALE"
	if stats.kills >= 3:
		return "MACELLAIO DI SERAPH"
	return "OPERATIVO"


func cycle_pixel_scale() -> void:
	settings.pixel_scale = settings.pixel_scale % 4 + 1
	settings_changed.emit()
	var names := ["1280x720 (nativa)", "640x360", "427x240", "320x180"]
	notify("Risoluzione interna: " + names[settings.pixel_scale - 1])


func toggle_dither() -> void:
	settings.dither = not settings.dither
	settings_changed.emit()
	notify("Dithering: " + ("attivo" if settings.dither else "disattivo"))


func restart() -> void:
	Sfx.set_alarm(false)
	reset_state()
	get_tree().paused = false
	state = State.MENU
	get_tree().reload_current_scene()
