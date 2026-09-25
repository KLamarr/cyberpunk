class_name Level
extends Node3D
## Base di ogni livello. La scena di un livello contiene:
##   Geometria (LevelGeometry)  -> brush d'aria nelle Zone, compilati all'avvio
##   Arredo, Luci, Porte, Dispositivi, Oggetti, Guardie, Trigger (nodi liberi)
##   un PlayerStart
## All'avvio: compila la geometria, cuoce la navmesh, assegna a ogni oggetto il
## layer della sua zona (così è illuminato solo dalle luci di quella stanza),
## avvisa le entità (on_level_ready) e crea il player.
##
## Per la logica di missione (obiettivi, eventi) estendi questo script: vedi
## levels/seraph/seraph.gd.

## Gruppo usato come sorgente della navmesh (geometria, arredo, dispositivi).
const NAV_GROUP := "nav_source"

var builder: LevelBuilder
var nav: NavigationRegion3D
var player: Player
var _redirecting := false


func _ready() -> void:
	# Avviato da solo con F6: passa dalla scena principale (HUD, menu, SubViewport)
	if get_tree().current_scene == self:
		_redirecting = true
		Game.level_path = scene_file_path
		Game.quick_start = true
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return
	Game.level = self
	var geo := _find_geometry(self)
	if geo == null:
		push_error("Level: manca il nodo LevelGeometry")
		return
	builder = LevelBuilder.new()
	nav = NavigationRegion3D.new()
	nav.name = "Navigazione"
	add_child(nav)
	var body := builder.compile(geo, nav)
	if body:
		body.add_to_group(NAV_GROUP)
	for n in get_children():
		if n != nav and n is Node3D and not (n is LevelGeometry):
			n.add_to_group(NAV_GROUP)
	_assign_zone_layers(self)
	_bake_nav()
	get_tree().call_group("level_aware", "on_level_ready", self)
	_spawn_player()
	setup_mission()


func _find_geometry(n: Node) -> LevelGeometry:
	for c in n.get_children():
		if c is LevelGeometry:
			return c
	return null


# --- interfaccia usata dagli altri script ----------------------------------------------
func zone_mask_at(p: Vector3) -> int:
	return builder.zone_mask_at(p) if builder else 1


func surface_at(p: Vector3) -> String:
	return builder.surface_at(p) if builder else "concrete"


func find_marker(marker_name: String) -> Node3D:
	return find_child(marker_name, true, false) as Node3D


## Aggiunge a partita iniziata un oggetto creato da codice (es. guardie di rinforzo),
## nella cartella indicata se esiste, con il render layer della sua zona.
func spawn(n: Node3D, folder := "") -> Node3D:
	var parent: Node = get_node_or_null(folder) if folder != "" else null
	(parent if parent != null else self).add_child(n)
	if n is VisualInstance3D and not n.has_meta("keep_layers"):
		(n as VisualInstance3D).layers = zone_mask_at(n.global_position)
	_assign_zone_layers(n)
	return n


## Ogni oggetto visibile prende come render layer la zona in cui si trova.
func _assign_zone_layers(n: Node) -> void:
	for c in n.get_children():
		if c is Guard or c is Player or c.name == "GeometriaCompilata":
			continue
		if c is VisualInstance3D and not (c is Light3D) and not c.has_meta("keep_layers"):
			(c as VisualInstance3D).layers = zone_mask_at((c as Node3D).global_position)
		_assign_zone_layers(c)


func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.cell_size = 0.2
	nm.cell_height = 0.2
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.4
	nm.agent_max_slope = 40.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Layers.WORLD
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = NAV_GROUP
	nav.navigation_mesh = nm
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, 0.2)
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map, 0.2)
	nav.bake_navigation_mesh(false)


func _spawn_player() -> void:
	var start: Node3D = null
	for n in find_children("*", "Marker3D", true, false):
		if n is PlayerStart:
			start = n
			break
	player = Player.new()
	player.name = "Player"
	if start != null:
		player.position = start.global_position + Vector3.UP * 0.05
		player.rotation.y = start.global_rotation.y
	else:
		push_warning("Level: nessun PlayerStart, il player parte dall'origine")
	add_child(player)


# --- logica di missione: da sovrascrivere ----------------------------------------------
## Obiettivi e stato iniziale della missione (chiamato dopo la costruzione).
func setup_mission() -> void:
	pass


## Chiamato quando il giocatore inizia la partita (dopo il menu).
func start_intro() -> void:
	Sfx.start_ambient()


## Chiamato da Game.start_lockdown().
func on_lockdown() -> void:
	pass
