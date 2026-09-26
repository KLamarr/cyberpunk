extends Level
## Missione "Protocollo Seraph": obiettivi, battute di Vesper e lockdown.
## Tutto il resto (geometria, luci, guardie, oggetti) è nella scena seraph.tscn.
## Testi in inglese: gli obiettivi si traducono quando vengono mostrati, le battute
## passano da tr(). L'italiano è in locale/it.po.

## Registri da leggere per l'obiettivo opzionale su Okafor.
const OKAFOR_LOGS := ["okafor1", "okafor2", "intruso"]


func setup_mission() -> void:
	Game.add_objective("core", "Retrieve the SERAPH-7 data core from the Lab C server.")
	Game.add_objective("okafor", "Find out what happened to Dr. Okafor.", true)
	Game.add_objective("nokill", "Don't kill anyone.", true)
	Game.add_objective("noalarm", "Don't trigger any alarms.", true)
	Game.log_read.connect(_on_log_read)


func _on_log_read(_id: String) -> void:
	if not Game.is_objective_active("okafor"):
		return
	for l in OKAFOR_LOGS:
		if not (l in Game.logs_read):
			return
	Game.complete_objective("okafor", 1)


func start_intro() -> void:
	Game.read_log("vesper", false)
	Sfx.start_ambient()
	Game.say(tr("VESPER"), tr("You're in. Level 14, Seraph labs. The briefing's on your PDA [Tab]."), 4.5)
	get_tree().create_timer(5.0, false).timeout.connect(_intro_2)


func _intro_2() -> void:
	Game.say(tr("VESPER"), tr("The core is in Lab C, north of the lobby. How you get there is your business."), 4.5)


## Dopo il furto del nucleo: luci d'emergenza, guardie in allerta, rinforzi.
func on_lockdown() -> void:
	for l in get_tree().get_nodes_in_group("game_lights"):
		if l is LightFixture:
			if l.emergency:
				l.set_on(true)
			else:
				l.set_dim(0.5)
	Sfx.set_alarm(true)
	Game.say(tr("PA SYSTEM"), tr("Breach in Lab C. SERAPH protocol active. Security: seal the exits."), 5.0)
	var marker := find_marker("PuntoLockdown")
	var search_pos := marker.global_position if marker else Vector3.ZERO
	for g in get_tree().get_nodes_in_group("guards"):
		g.on_lockdown(search_pos)
	# i rinforzi sono guardie "dormant" già piazzate nella scena
	for g in find_children("*", "CharacterBody3D", true, false):
		if g is Guard and g.dormant:
			g.activate()
			g.alertness = 1.0
	get_tree().create_timer(7.0, false).timeout.connect(_lockdown_followup)


func _lockdown_followup() -> void:
	if Game.alarm_time <= 0.0:
		Sfx.set_alarm(false)
	Game.say(tr("VESPER"), tr("They know the core's gone. They're sending someone up the main elevator — get back here, fast."), 5.0)
