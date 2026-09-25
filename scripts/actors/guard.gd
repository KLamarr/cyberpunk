@tool
class_name Guard
extends CharacterBody3D
## Guardia di sicurezza con impianto CALMA.
## Percezione: vista (dipende da distanza, cono visivo e VISIBILITÀ del player,
## cioè dalla luce) e udito (eventi di rumore di Game.emit_noise, attenuati dai muri).
## Stati: PATROL → INVESTIGATE (sospetto) → COMBAT → SEARCH → PATROL, oppure DOWN.
## Un colpo di chiave alle spalle di una guardia non in allerta la mette KO.
## Aspetto e parametri (sensi, mira, velocità, comportamento, bottino, battute) vengono
## da una NPCDefinition, creata con il creatore di NPC dell'editor (vedi setup_def).

enum S { PATROL, INVESTIGATE, COMBAT, SEARCH, DOWN }

const GRAVITY := 18.0
const LOS_MASK := 1 | 8   # mondo + porte (il vetro non blocca la vista)

const BARK_SIGHT := ["Eh? C'è qualcuno?", "Chi va là?", "Ho visto qualcosa laggiù...", "Hm? Un'ombra..."]
const BARK_NOISE := ["Cos'era quel rumore?", "Hm? Vado a controllare.", "Sento qualcosa...", "Chi c'è?"]
const BARK_GIVEUP := ["Sarà stato il CALMA che mi fa sentire le cose.", "Niente. Torno al giro.", "Mi sto immaginando tutto.", "Topi. Sempre i topi."]
const BARK_COMBAT := ["Intruso!", "Eccoti! Fermo lì!", "Contatto! Livello 14!", "Ti ho visto!"]
const BARK_SEARCH := ["Dov'è finito?", "So che sei qui dentro.", "Esci fuori, non peggiorare le cose.", "Controllate gli angoli!"]
const BARK_SEARCH_END := ["L'ho perso. Resto all'erta.", "Maledizione, è sparito.", "Torno in posizione, ma occhi aperti."]
const BARK_BODY := ["Uomo a terra! Uomo a terra!", "Chi ti ha fatto questo?!", "C'è qualcuno qui dentro!"]
const BARK_ALARM := ["Allarme! Mi muovo!", "Ricevuto, controllo il settore."]
const BARK_HURT := ["Argh! Mi hanno colpito!", "Ah! Maledetto!"]
const BARK_IDLE := ["...lo senti anche tu, il ronzio?", "Altre sei ore di turno.", "Il server ronza più forte stanotte.", "Chissà se Okafor è ancora in laboratorio.", "Mi fa male la testa. Sempre dopo l'aggiornamento."]

## Chi è: aspetto, sensi, mira, velocità, bottino e battute. Trascina qui un personaggio
## di assets/npc/characters (si creano nella scheda NPC in alto). Vuoto = una guardia
## generica, con un aspetto generato dal nome (sempre lo stesso).
@export var definition: NPCDefinition:
	set(v):
		definition = v
		_editor_rebuild()
		update_configuration_warnings()
## Nome mostrato nei sottotitoli. Vuoto = quello della definizione.
@export var guard_name := ""
## Nodo PatrolRoute con i Waypoint da percorrere. Vuoto = resta di guardia
## nel punto in cui l'hai messa, guardando verso -Z locale.
@export var patrol_route: NodePath
## Inattiva e invisibile finché uno script non chiama activate() (es. rinforzi).
@export var dormant := false

## Usato solo se la guardia non ha una Definition (altrimenti vale quello del personaggio).
@export_group("Bottino (senza definizione)")
@export var loot_ammo := 0:
	set(v):
		loot_ammo = v
		update_configuration_warnings()
@export var loot_credits := 0:
	set(v):
		loot_credits = v
		update_configuration_warnings()
@export var loot_medpatch := 0:
	set(v):
		loot_medpatch = v
		update_configuration_warnings()
## Tessera che porta con sé (si ottiene perquisendola o borseggiandola).
@export var loot_keycard_id := "":
	set(v):
		loot_keycard_id = v
		update_configuration_warnings()
@export var loot_keycard_name := ""

var sight_range := 20.0
var walk_speed := 1.8
var run_speed := 4.0
var hearing := 1.0
var perception := 1.0
var reaction_time := 0.7
var accuracy := 0.8
var waypoints: Array[Vector3] = []
var waits: Array[float] = []
var post_pos := Vector3.ZERO
var post_yaw := 0.0
var loot := {}
var hp := 60.0
var state: int = S.PATROL
var awareness := 0.0
var alertness := 0.0
var last_known := Vector3.ZERO
var target_pos := Vector3.ZERO
var dead := false
var discovered := false
var carried := false
var can_see_player := false

var _agent: NavigationAgent3D
var _model: NPCBody
var _eye_h := 1.72
var _head_h := 1.55
var _icon: Label3D
var _shape_node: CollisionShape3D
var _wp := 0
var _wait := 0.0
var _look_timer := 0.0
var _look_base := 0.0
var _arrived := false
var _lost_timer := 0.0
var _search_timer := 0.0
var _shoot_cd := 0.0
var _reaction := 0.0
var _perceive_timer := 0.0
var _zone_timer := 0.0
var _bark_cd := 0.0
var _idle_bark := 20.0
var _phase := 0.0
var _speed_now := 0.0
var _nav_ready := false
var _last_nav_target := Vector3(INF, INF, INF)
var _stuck_timer := 0.0
var _last_pos := Vector3.ZERO
var _last_step_idx := 0
var _last_glow := Color(-1, -1, -1)


## Guardia da una definizione (.tres del creatore di NPC). Il bottino è quello della
## definizione, a meno di passarne uno diverso.
func setup_def(def: NPCDefinition, pos: Vector3, yaw_deg: float, route: Array = [], loot_override: Variant = null) -> Guard:
	_apply_definition(def)
	var lt: Dictionary = def.loot() if loot_override == null else loot_override
	return setup(def.display_name, pos, yaw_deg, route, lt)


## Versione senza definizione: aspetto generato a caso (ma sempre uguale) dal nome
## (vedi _generic_definition, applicata in _ready).
func setup(n: String, pos: Vector3, yaw_deg: float, route: Array = [], loot_table := {}) -> Guard:
	guard_name = n
	position = pos
	post_pos = pos
	post_yaw = deg_to_rad(yaw_deg)
	rotation.y = post_yaw
	for r in route:
		waypoints.append(r[0])
		waits.append(float(r[1]))
	loot = loot_table
	return self


func _apply_definition(def: NPCDefinition) -> void:
	definition = def
	if guard_name == "":
		guard_name = def.display_name
	# i limiti dell'Inspector valgono solo lì: un .tres scritto a mano o da codice può
	# contenere valori che bloccherebbero l'IA (velocità 0, reazione negativa...)
	hp = maxf(def.max_health, 1.0)
	sight_range = maxf(def.sight_range, 1.0)
	walk_speed = maxf(def.walk_speed, 0.3)
	run_speed = maxf(def.run_speed, walk_speed)
	hearing = maxf(def.hearing, 0.1)
	perception = maxf(def.perception, 0.05)
	reaction_time = maxf(def.reaction_time, 0.2)
	accuracy = clampf(def.accuracy, 0.0, 0.85)
	_eye_h = def.eye_height()
	_head_h = def.head_height()


func _ready() -> void:
	if Engine.is_editor_hint():
		_build_model()
		return
	# piazzata nell'editor: parametri dalla definizione (o da una generica, dal nome)
	var from_def := definition != null
	_apply_definition(definition if from_def else _generic_definition())
	post_pos = global_position
	post_yaw = global_rotation.y
	if loot.is_empty() and from_def:
		loot = definition.loot()
	elif loot.is_empty():
		if loot_ammo > 0:
			loot["ammo"] = loot_ammo
		if loot_credits > 0:
			loot["credits"] = loot_credits
		if loot_medpatch > 0:
			loot["medpatch"] = loot_medpatch
		if loot_keycard_id != "":
			loot["keycard"] = [loot_keycard_id, loot_keycard_name if loot_keycard_name != "" else loot_keycard_id]
	if waypoints.is_empty() and not patrol_route.is_empty():
		var route := get_node_or_null(patrol_route)
		if route != null:
			for wp in route.get_children():
				if wp is Node3D:
					waypoints.append((wp as Node3D).global_position)
					waits.append(float(wp.get("wait")) if wp.get("wait") != null else 2.0)
	add_to_group("ai")
	add_to_group("guards")
	collision_layer = Layers.NPC
	collision_mask = Layers.WORLD | Layers.DOOR | Layers.GLASS | Layers.PLAYER
	floor_snap_length = 0.3
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = clampf(definition.top_height() + 0.02, 1.5, 2.1)
	_shape_node = CollisionShape3D.new()
	_shape_node.shape = cap
	_shape_node.position.y = cap.height * 0.5
	add_child(_shape_node)
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.5
	_agent.target_desired_distance = 0.6
	_agent.radius = 0.4
	_agent.height = cap.height
	_agent.path_max_distance = 3.0
	add_child(_agent)
	_build_model()
	_icon = Label3D.new()
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.font_size = 72
	_icon.pixel_size = 0.004
	_icon.outline_size = 16
	_icon.position.y = 2.25
	_icon.visible = false
	_icon.no_depth_test = false
	_icon.set_meta("keep_layers", true)
	add_child(_icon)
	_last_pos = global_position
	_idle_bark = randf_range(15.0, 40.0)
	if dormant:
		_set_dormant(true)


func _set_dormant(on: bool) -> void:
	visible = not on
	process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	collision_layer = 0 if on else Layers.NPC
	if on:
		remove_from_group("ai")
		remove_from_group("guards")
	else:
		add_to_group("ai")
		add_to_group("guards")


## Risveglia una guardia "dormant" (rinforzi, eventi scriptati).
func activate() -> void:
	if not dormant:
		return
	dormant = false
	_set_dormant(false)


func _build_model() -> void:
	_model = NPCBody.new()
	_model.name = "Body"
	_model.definition = definition if definition != null else _generic_definition()
	add_child(_model)


## Guardia senza definizione: aspetto casuale ma stabile, dal nome (o dal nome del nodo).
func _generic_definition() -> NPCDefinition:
	var key := guard_name if guard_name != "" else String(name)
	return NPCLibrary.random_npc(NPCDefinition.Archetype.GUARDIA, hash(key))


## Nell'editor il modello segue la Definition scelta nell'Inspector.
func _editor_rebuild() -> void:
	if not (Engine.is_editor_hint() and is_inside_tree()):
		return
	if _model != null and is_instance_valid(_model):
		remove_child(_model)
		_model.queue_free()
	_build_model()


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if definition != null and (loot_ammo > 0 or loot_credits > 0 or loot_medpatch > 0 or loot_keycard_id != ""):
		w.append("Con una Definition il bottino è quello del personaggio: i valori in 'Bottino (senza definizione)' sono ignorati.")
	return w


func is_active() -> bool:
	return state != S.DOWN


# --- ciclo -------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if state == S.DOWN:
		if not carried:
			velocity.x = 0.0
			velocity.z = 0.0
			velocity.y -= GRAVITY * delta
			move_and_slide()
		return
	if not _nav_ready:
		_nav_ready = NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) > 0
	_bark_cd -= delta
	_speed_now = 0.0
	_perceive_timer -= delta
	if _perceive_timer <= 0.0:
		_perceive_timer = 0.1
		_perceive(0.1)
	match state:
		S.PATROL:
			_do_patrol(delta)
		S.INVESTIGATE:
			_do_investigate(delta)
		S.COMBAT:
			_do_combat(delta)
		S.SEARCH:
			_do_search(delta)
	_animate(delta)
	_update_icon()
	_zone_timer -= delta
	if _zone_timer <= 0.0 and Game.level:
		_zone_timer = 0.3
		Util.set_layers_recursive(_model, Game.level.zone_mask_at(global_position + Vector3.UP))
		_update_anim_lod()


# --- movimento -------------------------------------------------------------------
func _snap(p: Vector3) -> Vector3:
	if not _nav_ready:
		return p
	return NavigationServer3D.map_get_closest_point(_agent.get_navigation_map(), p)


func _face_dir(dir: Vector3, delta: float, speed := 7.0) -> void:
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var want := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(delta * speed, 0.0, 1.0))


func _halt(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, delta * 12.0)
	velocity.z = move_toward(velocity.z, 0.0, delta * 12.0)
	velocity.y -= GRAVITY * delta
	move_and_slide()


## Muove verso target lungo la navmesh. Ritorna true quando è arrivato.
func _nav_to(target: Vector3, speed: float, delta: float) -> bool:
	if not _nav_ready:
		_halt(delta)
		return false
	var flat := Vector2(global_position.x - target.x, global_position.z - target.z).length()
	if flat < 0.6:
		_halt(delta)
		return true
	if target.distance_to(_last_nav_target) > 0.35:
		_agent.target_position = target
		_last_nav_target = target
	if _agent.is_navigation_finished():
		_halt(delta)
		return true
	var next := _agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() > 0.001:
		dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y -= GRAVITY * delta
	_face_dir(dir, delta)
	move_and_slide()
	_speed_now = speed
	# rilevamento blocco
	if global_position.distance_to(_last_pos) < speed * delta * 0.2:
		_stuck_timer += delta
		if _stuck_timer > 2.0:
			_stuck_timer = 0.0
			return true
	else:
		_stuck_timer = 0.0
	_last_pos = global_position
	return false


# --- percezione ------------------------------------------------------------------
func _eye() -> Vector3:
	return global_position + Vector3.UP * _eye_h


func _perceive(dt: float) -> void:
	var p: Node = Game.player
	can_see_player = false
	if p != null and not p.dead:
		var eye := _eye()
		var target: Vector3 = p.get_aim_point()
		var to := target - eye
		var dist := to.length()
		if dist < sight_range:
			var fwd := -global_basis.z
			var flat := Vector3(to.x, 0.0, to.z)
			var ang := rad_to_deg(fwd.angle_to(flat)) if flat.length() > 0.01 else 0.0
			var fov := 0.0
			if ang < definition.fov_deg:
				fov = 1.0
			elif ang < 100.0 and dist < 7.0:
				fov = 0.4
			if dist < 1.3:
				fov = maxf(fov, 0.8)
			if fov > 0.0:
				var space := get_world_3d().direct_space_state
				var ex: Array[RID] = [get_rid()]
				var seen := Util.ray_clear(space, eye, target, LOS_MASK, ex)
				if not seen:
					seen = Util.ray_clear(space, eye, p.get_head_point(), LOS_MASK, ex)
				if seen:
					can_see_player = true
					var vis: float = p.visibility
					var df := 1.0 - dist / sight_range
					var rate := vis * fov * (0.3 + 3.2 * df * df) * perception
					match state:
						S.COMBAT, S.SEARCH:
							rate *= 2.2
						S.INVESTIGATE:
							rate *= 1.4
					rate *= 1.0 + 0.35 * alertness
					if dist < 2.5 and vis > 0.12:
						rate += 1.0
					awareness += rate * dt
					if awareness > 0.3 or state == S.COMBAT:
						last_known = p.global_position
	if not can_see_player and state == S.PATROL:
		awareness = maxf(awareness - 0.1 * dt, 0.0)
	awareness = minf(awareness, 1.3)
	if can_see_player:
		if awareness >= 1.0:
			_enter_combat()
		elif awareness >= 0.35 and state == S.PATROL:
			_investigate(last_known, true)
		elif awareness >= 0.35 and state == S.INVESTIGATE:
			target_pos = _snap(last_known)
			_arrived = false
	if (state == S.PATROL or state == S.INVESTIGATE) and definition.reacts_to_bodies:
		_check_bodies()


func _check_bodies() -> void:
	var eye := _eye()
	var fwd := -global_basis.z
	for g in get_tree().get_nodes_in_group("guards"):
		if g == self or g.state != S.DOWN or g.discovered or g.carried:
			continue
		var to: Vector3 = g.global_position + Vector3.UP * 0.3 - eye
		if to.length() > 12.0:
			continue
		var flat := Vector3(to.x, 0.0, to.z)
		if rad_to_deg(fwd.angle_to(flat)) > 60.0:
			continue
		if Util.ray_clear(get_world_3d().direct_space_state, eye, g.global_position + Vector3.UP * 0.3, LOS_MASK, [get_rid(), g.get_rid()]):
			g.discovered = true
			_bark(BARK_BODY, true)
			Game.emit_noise(global_position, 18.0, "shout", self, {"target": g.global_position})
			_enter_search(g.global_position)
			return


func hear(pos: Vector3, radius: float, kind: String, source: Node, info := {}) -> void:
	if state == S.DOWN or source == self:
		return
	var eye := _eye()
	var d := eye.distance_to(pos)
	if d > radius * maxf(hearing, 1.0):
		return
	var occluded := not Util.ray_clear(get_world_3d().direct_space_state, eye, pos + Vector3.UP * 0.3, LOS_MASK, [get_rid()])
	var eff := radius * (0.5 if occluded else 1.0) * hearing
	if d > eff:
		return
	var loud := 1.0 - d / eff
	match kind:
		"step", "door", "body":
			if state == S.COMBAT or not definition.investigates_noises:
				return
			awareness = minf(awareness + 0.12 + 0.45 * loud, 0.95)
			if state == S.SEARCH:
				_set_search_point(pos)
			elif awareness >= 0.35:
				_investigate(pos, false)
		"impact", "clang", "glass", "grate":
			if state == S.COMBAT or not definition.investigates_noises:
				return
			awareness = maxf(awareness, 0.45)
			if state == S.SEARCH:
				_set_search_point(pos)
			else:
				_investigate(pos, false)
		"gunshot":
			if state == S.COMBAT:
				return
			var tgt: Vector3 = info.get("target", pos)
			awareness = maxf(awareness, 0.9)
			_enter_search(tgt)
		"shout":
			if state == S.COMBAT:
				return
			_enter_search(info.get("target", pos))


# --- stati -------------------------------------------------------------------------
func _do_patrol(delta: float) -> void:
	_idle_bark -= delta
	if _idle_bark <= 0.0:
		_idle_bark = randf_range(30.0, 60.0)
		_bark(Array(definition.idle_barks) if not definition.idle_barks.is_empty() else BARK_IDLE)
	if waypoints.is_empty():
		if Vector2(global_position.x - post_pos.x, global_position.z - post_pos.z).length() > 0.6:
			_nav_to(post_pos, walk_speed, delta)
		else:
			_halt(delta)
			rotation.y = lerp_angle(rotation.y, post_yaw, clampf(delta * 3.0, 0.0, 1.0))
		return
	if _wait > 0.0:
		_wait -= delta
		_halt(delta)
		return
	if _nav_to(waypoints[_wp], walk_speed, delta):
		_wait = waits[_wp]
		_wp = (_wp + 1) % waypoints.size()


func _investigate(pos: Vector3, by_sight: bool) -> void:
	target_pos = _snap(pos)
	_arrived = false
	if state != S.INVESTIGATE:
		state = S.INVESTIGATE
		_reaction = 0.8
		_bark(BARK_SIGHT if by_sight else BARK_NOISE)


func _do_investigate(delta: float) -> void:
	if _reaction > 0.0:
		# si gira verso il punto sospetto prima di muoversi
		_reaction -= delta
		_face_dir(target_pos - global_position, delta, 4.0)
		_halt(delta)
		return
	if not _arrived:
		if _nav_to(target_pos, walk_speed * 1.2, delta):
			_arrived = true
			_look_timer = 5.0
			_look_base = rotation.y
	else:
		_halt(delta)
		_look_timer -= delta
		rotation.y = _look_base + sin((5.0 - _look_timer) * 1.3) * 1.1
		if _look_timer <= 0.0:
			awareness = minf(awareness, 0.15)
			state = S.PATROL
			_last_nav_target = Vector3(INF, INF, INF)
			_bark(BARK_GIVEUP)


func _enter_combat() -> void:
	if state == S.COMBAT:
		return
	Game.on_player_spotted()
	state = S.COMBAT
	awareness = 1.3
	alertness = 1.0
	_reaction = randf_range(maxf(reaction_time - 0.2, 0.15), reaction_time + 0.2)
	_lost_timer = 0.0
	_bark(BARK_COMBAT, true)
	if definition.calls_for_help:
		Sfx.play_3d("radio", global_position + Vector3.UP * 1.6, -2.0)
		Game.emit_noise(global_position, 22.0, "shout", self, {"target": last_known})


func _do_combat(delta: float) -> void:
	var p: Node = Game.player
	if p == null or p.dead:
		_enter_search(last_known)
		return
	if can_see_player:
		_lost_timer = 0.0
	else:
		_lost_timer += delta
	var to: Vector3 = p.global_position - global_position
	var dist := to.length()
	if can_see_player and dist < 22.0:
		_reaction -= delta
		_shoot_cd -= delta
		if dist > 9.0:
			_nav_to(p.global_position, run_speed * 0.6, delta)
		else:
			_halt(delta)
		_face_dir(to, delta, 10.0)
		if _reaction <= 0.0 and _shoot_cd <= 0.0:
			_shoot(p, dist)
			_shoot_cd = randf_range(0.8, 1.3)
	else:
		if _nav_to(last_known, run_speed, delta) or _lost_timer > 6.0:
			_enter_search(last_known)


func _shoot(p: Node, dist: float) -> void:
	var from := _model.muzzle_position()
	var aim: Vector3 = p.get_aim_point()
	var chance := accuracy - dist * 0.022
	var hs := Vector2(p.velocity.x, p.velocity.z).length()
	if hs > 4.0:
		chance -= 0.25
	elif hs > 0.5:
		chance -= 0.1
	chance -= (1.0 - float(p.visibility)) * 0.3
	if p.crouching:
		chance -= 0.05
	chance = clampf(chance, 0.12, 0.85)
	Sfx.play_3d("guard_gun", from, 0.0, 0.06, 50.0)
	Effects.flash_light(from, Color(1.0, 0.75, 0.4), 2.5, 5.0)
	Game.emit_noise(global_position, 25.0, "gunshot", self, {"target": p.global_position})
	var space := get_world_3d().direct_space_state
	if randf() < chance:
		Effects.tracer(from, aim)
		p.take_damage(randf_range(definition.damage_min, definition.damage_max), aim, (aim - from).normalized(), "bullet")
	else:
		var miss := aim + Vector3(randf_range(-1.2, 1.2), randf_range(-0.5, 1.0), randf_range(-1.2, 1.2))
		var dir := (miss - from).normalized()
		var hit := Util.ray(space, from, from + dir * 40.0, LOS_MASK | Layers.PROP | Layers.DEVICE, [get_rid()])
		var end: Vector3 = hit.get("position", from + dir * 40.0)
		Effects.tracer(from, end)
		if not hit.is_empty():
			Effects.sparks(end, Color(1, 0.9, 0.6), 6, 2.5)
			Sfx.play_3d("impact", end, -3.0)


func _enter_search(pos: Vector3) -> void:
	if state == S.DOWN:
		return
	var was := state
	state = S.SEARCH
	_search_timer = 25.0
	last_known = pos
	alertness = 1.0
	awareness = maxf(awareness, 0.6)
	_set_search_point(pos)
	if was != S.SEARCH and was != S.COMBAT:
		_bark(BARK_SEARCH)
	elif was == S.COMBAT:
		_bark(BARK_SEARCH)


func _set_search_point(pos: Vector3) -> void:
	target_pos = _snap(pos)
	_arrived = false


func _do_search(delta: float) -> void:
	_search_timer -= delta
	if not _arrived:
		if _nav_to(target_pos, run_speed * 0.75, delta):
			_arrived = true
			_look_timer = randf_range(1.5, 3.0)
			_look_base = rotation.y
	else:
		_halt(delta)
		_look_timer -= delta
		rotation.y = _look_base + sin(_look_timer * 2.0) * 0.9
		if _look_timer <= 0.0:
			var r := last_known + Vector3(randf_range(-7.0, 7.0), 0.0, randf_range(-7.0, 7.0))
			_set_search_point(r)
	if _search_timer <= 0.0:
		state = S.PATROL
		awareness = 0.25
		_last_nav_target = Vector3(INF, INF, INF)
		_bark(BARK_SEARCH_END)


func on_alarm(pos: Vector3) -> void:
	if state == S.DOWN or state == S.COMBAT or not definition.responds_to_alarms:
		return
	_bark(BARK_ALARM)
	_enter_search(pos)


func on_lockdown(pos: Vector3) -> void:
	if state == S.DOWN:
		return
	alertness = 1.0
	if state != S.COMBAT:
		_enter_search(pos)
		_search_timer = 35.0


# --- danni / KO --------------------------------------------------------------------
func can_knockout(attacker_pos: Vector3) -> bool:
	if state == S.DOWN or state == S.COMBAT:
		return false
	var to_att := attacker_pos - global_position
	to_att.y = 0.0
	var behind := (-global_basis.z).dot(to_att.normalized()) < 0.35
	if state == S.SEARCH:
		return behind
	return behind or awareness < 0.3


func knock_out() -> void:
	_go_down(false)


func take_damage(amount: float, hit_pos: Vector3, _dir: Vector3, kind: String) -> void:
	if state == S.DOWN:
		return
	if hit_pos.y - global_position.y > _head_h:
		amount *= 2.2
	hp -= amount
	Effects.sparks(hit_pos, Color(0.45, 0.02, 0.02), 10, 2.0)
	Sfx.play_3d("hit_flesh", hit_pos)
	if hp <= 0.0:
		_go_down(true)
		return
	_bark(BARK_HURT, true)
	if kind == "turret":
		_enter_search(global_position)
		return
	if Game.player:
		last_known = Game.player.global_position
	awareness = 1.3
	_enter_combat()


func _go_down(killed: bool) -> void:
	state = S.DOWN
	dead = killed
	Game.on_guard_down(self, killed)
	add_to_group("downed")
	collision_layer = Layers.INTERACT
	collision_mask = Layers.WORLD
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 0.3, 1.9)
	_shape_node.shape = bs
	_shape_node.position = Vector3(0, 0.15, 0.9)
	_icon.visible = false
	_model.set_glow(Color(0.05, 0.05, 0.06) if killed else _model.default_glow() * 0.35)
	_model.set_down(true)
	_model.lod_interval = 0.0
	var tw := create_tween()
	tw.tween_property(_model, "rotation:x", PI * 0.5, 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_model, "position:y", 0.14, 0.55)
	Sfx.play_3d("body_fall", global_position, 0.0)
	Game.emit_noise(global_position, 6.0, "body", self)


# --- frob: perquisire, borseggiare, trasportare ------------------------------------
func _pickpocketable() -> bool:
	if state == S.COMBAT or state == S.DOWN or Game.player == null:
		return false
	var to_p: Vector3 = Game.player.global_position - global_position
	to_p.y = 0.0
	return (-global_basis.z).dot(to_p.normalized()) < 0.2 and awareness < 0.6


func get_frob_text() -> String:
	if state == S.DOWN:
		if not loot.is_empty():
			return "Perquisisci " + guard_name + (" (morto)" if dead else " (svenuto)")
		return "Solleva il corpo di " + guard_name
	if not loot.is_empty() and _pickpocketable():
		return "Borseggia " + guard_name
	return ""


func frob(player: Node) -> void:
	if state == S.DOWN:
		if not loot.is_empty():
			_give_loot()
		else:
			player.carry_body(self)
		return
	if _pickpocketable() and not loot.is_empty():
		_give_loot()
		Game.stats.pickpockets += 1
		awareness += 0.25


func _give_loot() -> void:
	var got: Array[String] = []
	for k in loot:
		match k:
			"ammo":
				Game.add_ammo(int(loot.ammo))
				got.append("%d munizioni" % int(loot.ammo))
			"credits":
				Game.add_credits(int(loot.credits))
				got.append("%d crediti" % int(loot.credits))
			"medpatch":
				Game.add_medpatch(int(loot.medpatch))
				got.append("medipatch")
			"keycard":
				Game.give_keycard(loot.keycard[0], loot.keycard[1])
				got.append(loot.keycard[1])
	loot.clear()
	Sfx.play_ui("pickup")
	Game.notify("Trovato: " + ", ".join(got))


func set_carried(on: bool) -> void:
	carried = on
	visible = not on
	_shape_node.disabled = on
	collision_layer = 0 if on else Layers.INTERACT


func drop_at(pos: Vector3, yaw: float) -> void:
	global_position = pos + Vector3.UP * 0.05
	rotation.y = yaw + PI * 0.5
	velocity = Vector3.ZERO
	set_carried(false)
	Sfx.play_3d("body_fall", pos, -4.0)
	Game.emit_noise(pos, 3.5 * (1.0 - 0.12 * Game.skill("furtivita")), "body", Game.player)


# --- presentazione -------------------------------------------------------------------
func _bark(lines: Array, force := false) -> void:
	if _bark_cd > 0.0 and not force:
		return
	_bark_cd = 3.0
	if Game.player == null:
		return
	if global_position.distance_to(Game.player.global_position) > 20.0:
		return
	Game.say(guard_name, lines[randi() % lines.size()], 2.8)


func _update_icon() -> void:
	var txt := ""
	var c := Color.WHITE
	var visor := _model.default_glow()
	match state:
		S.COMBAT:
			txt = "!"
			c = Color(1.0, 0.2, 0.15)
			visor = Color(1.0, 0.15, 0.1)
		S.SEARCH:
			txt = "?"
			c = Color(1.0, 0.55, 0.1)
			visor = Color(1.0, 0.55, 0.1)
		S.INVESTIGATE:
			txt = "?"
			c = Color(1.0, 0.9, 0.2)
			visor = Color(1.0, 0.85, 0.2)
		_:
			if awareness > 0.12:
				txt = "?"
				c = Color(1.0, 1.0, 0.6, clampf(awareness * 2.5, 0.2, 1.0))
	_icon.visible = txt != ""
	_icon.text = txt
	_icon.modulate = c
	if visor != _last_glow:
		_last_glow = visor
		_model.set_glow(visor)


func _animate(delta: float) -> void:
	if _speed_now > 0.1:
		_phase += delta * (5.0 + _speed_now * 1.6)
		# passi udibili: fondamentali per giocare d'orecchio
		var idx := int(floor(_phase / PI))
		if idx != _last_step_idx:
			_last_step_idx = idx
			var surf := "concrete"
			if Game.level:
				surf = Game.level.surface_at(global_position)
			Sfx.play_3d("step_" + surf, global_position + Vector3.UP * 0.05, -4.0 if _speed_now > 3.0 else -8.0, 0.1, 22.0)
	else:
		_phase = lerpf(_phase, round(_phase / PI) * PI, clampf(delta * 5.0, 0.0, 1.0))
	# animazione dello scheletro, guidata dalla stessa fase dei passi
	_model.update_motion(delta, _speed_now, _phase, 1.0 if state == S.COMBAT else 0.0, run_speed)


## Le guardie lontane dalla camera aggiornano la posa meno spesso.
func _update_anim_lod() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := cam.global_position.distance_to(global_position)
	_model.lod_interval = 0.0 if d < 14.0 else (0.05 if d < 26.0 else 0.12)
