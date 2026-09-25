extends Node3D
## LIVELLO: Arcologia Nysa, livello 14 — ala laboratori della Seraph Biotek.
##
## Pianta (x verso est, z verso sud; misure in metri):
##
##          ┌──────────── LABORATORIO C ────────────┐ z -30..-18
##          │  server   [NUCLEO]   server      ═════╪═══ condotto ═══╗
##          └──────────────┬[porta]┬────────────────┘                ║
##                         │ corr. │ torretta                        ║  (segreto)
##   ┌─────────┐   ┌───────┴───────┴──────────┐   ┌───────────┐ ═════╝
##   │SICUREZZA│═══│          HALL            │═══│SALA RELAX │ grata
##   └─────────┘   │  (telecamera NE)         │   └───────────┘
##   ┌─────────┐═══│                          │
##   │MAGAZZINO│   └───────────[porta]────────┘
##   └─────────┘               │ corridoio di servizio ═ [START/ascensore]
##
## Tutta la geometria è scavata con brush sottrattivi (vedi LevelBuilder).

const Z_START := 1
const Z_SERV := 2
const Z_BREAK := 4
const Z_LOBBY := 8
const Z_OFFICE := 16
const Z_STORE := 32
const Z_LABC := 64
const Z_LAB := 128
const Z_VENT := 256

var builder: LevelBuilder
var nav: NavigationRegion3D
var props_root: Node3D
var entities: Node3D
var normal_lights: Array = []
var emergency_lights: Array = []
var lab_lights: Array = []
var turret: Turret
var player: Player
var spawn_pos := Vector3(19.4, 0.05, 15.2)
var spawn_yaw := 90.0


func _ready() -> void:
	Game.level = self
	_environment()
	builder = LevelBuilder.new(self, Vector3(-24, -1, -34), Vector3(24, 8, 22))
	_define_sets()
	_carve()
	nav = NavigationRegion3D.new()
	nav.name = "Navigation"
	add_child(nav)
	builder.compile(nav)
	props_root = Node3D.new()
	props_root.name = "Props"
	nav.add_child(props_root)
	entities = Node3D.new()
	entities.name = "Entities"
	add_child(entities)
	_props()
	_bake_nav()
	_lights()
	_doors()
	_devices()
	_items()
	_guards()
	_triggers()
	_spawn_player()


# --- interfaccia usata dagli altri script ----------------------------------------------
func zone_mask_at(p: Vector3) -> int:
	return builder.zone_mask_at(p)


func surface_at(p: Vector3) -> String:
	return builder.surface_at(p)


# --- ambiente -----------------------------------------------------------------------
func _environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.01)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.62)
	env.ambient_light_energy = 0.32
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.03, 0.045)
	env.fog_density = 0.035
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.1
	we.environment = env
	add_child(we)


func _define_sets() -> void:
	var b := builder
	b.define_set("start", "wall_concrete", "floor_grate", "ceiling_dark", "grate")
	b.define_set("elev", "wall_panel", "floor_grate", "ceiling_panel", "metal", Vector3(0.5, 0.5, 0.5), Color(1.0, 0.9, 0.75))
	b.define_set("frame", "wall_panel", "floor_grate", "wall_panel", "metal", Vector3(0.5, 0.5, 0.5), Color(0.7, 0.72, 0.75))
	b.define_set("frame_hz", "hazard", "floor_grate", "hazard", "metal", Vector3(1.0, 0.5, 1.0))
	b.define_set("service", "wall_concrete", "floor_grate", "ceiling_dark", "grate")
	b.define_set("lobby", "wall_panel", "floor_tiles", "ceiling_panel", "concrete")
	b.define_set("office", "wall_panel", "floor_carpet", "ceiling_panel", "carpet", Vector3(0.5, 0.5, 0.5), Color(0.95, 0.95, 1.0))
	b.define_set("break", "wall_tile", "floor_tiles", "ceiling_panel", "concrete")
	b.define_set("store", "wall_concrete", "floor_grate", "ceiling_dark", "grate", Vector3(0.5, 0.5, 0.5), Color(0.9, 0.85, 0.8))
	b.define_set("labc", "wall_tech", "floor_grate", "ceiling_dark", "grate")
	b.define_set("lab", "wall_tech", "floor_lab", "ceiling_panel", "concrete")
	b.define_set("vent", "rust_metal", "rust_metal", "rust_metal", "metal", Vector3(1.0, 1.0, 1.0))
	b.define_set("pillar", "wall_concrete", "floor_tiles", "ceiling_panel", "concrete", Vector3(0.5, 0.5, 0.5), Color(0.85, 0.85, 0.9))


func _carve() -> void:
	var b := builder
	# ascensore e stanza di partenza
	b.carve(Vector3(12, 0, 12), Vector3(18, 3.5, 18), "start", Z_START)
	b.carve(Vector3(18, 0, 14), Vector3(20.6, 3.0, 16.4), "elev", Z_START)
	b.carve(Vector3(11, 0, 14.2), Vector3(12, 2.5, 15.8), "frame", Z_START | Z_SERV)
	# corridoio di servizio
	b.carve(Vector3(5, 0, 14), Vector3(11, 3.0, 16), "service", Z_SERV)
	b.carve(Vector3(5, 0, 9), Vector3(7, 3.0, 14), "service", Z_SERV)
	b.carve(Vector3(5.2, 0, 8), Vector3(6.8, 2.5, 9), "frame", Z_SERV | Z_LOBBY)
	# hall
	b.carve(Vector3(-10, 0, -6), Vector3(10, 6, 8), "lobby", Z_LOBBY)
	for p in [Vector2(-5, -1), Vector2(5, -1), Vector2(-5, 4.6), Vector2(5, 4.6)]:
		b.add_solid(Vector3(p.x - 0.5, 0, p.y - 0.5), Vector3(p.x + 0.5, 6, p.y + 0.5), "pillar", Z_LOBBY)
	# fascia decorativa a metà altezza della hall
	b.add_solid(Vector3(-10, 3.6, -6), Vector3(10, 3.9, -5.7), "frame", Z_LOBBY)
	b.add_solid(Vector3(-10, 3.6, 7.7), Vector3(10, 3.9, 8), "frame", Z_LOBBY)
	# sala sicurezza (+ finestra sulla hall)
	b.carve(Vector3(-11, 0, 1), Vector3(-10, 2.5, 2.6), "frame", Z_LOBBY | Z_OFFICE)
	b.carve(Vector3(-18, 0, -4), Vector3(-11, 3.5, 4), "office", Z_OFFICE)
	b.carve(Vector3(-11, 1.0, -2.8), Vector3(-10, 2.2, -0.8), "frame", Z_LOBBY | Z_OFFICE)
	# magazzino
	b.carve(Vector3(-11, 0, 5.6), Vector3(-10, 2.5, 7.2), "frame", Z_LOBBY | Z_STORE)
	b.carve(Vector3(-18, 0, 5), Vector3(-11, 3.5, 13), "store", Z_STORE)
	# sala relax
	b.carve(Vector3(10, 0, -1.8), Vector3(11, 2.5, -0.2), "frame", Z_LOBBY | Z_BREAK)
	b.carve(Vector3(11, 0, -6), Vector3(19, 3.2, 2), "break", Z_BREAK)
	# corridoio del laboratorio (arco aperto sulla hall) e laboratorio
	b.carve(Vector3(-2, 0, -17), Vector3(2, 3.5, -6), "labc", Z_LABC)
	b.carve(Vector3(-1, 0, -18), Vector3(1, 2.6, -17), "frame_hz", Z_LABC | Z_LAB)
	b.carve(Vector3(-8, 0, -30), Vector3(8, 4.5, -18), "lab", Z_LAB)
	# condotti di ventilazione (quota 1.0-2.1: ci si entra con il mantle, accovacciati)
	b.carve(Vector3(15.5, 1.0, -22), Vector3(16.6, 2.1, -6), "vent", Z_VENT)
	b.carve(Vector3(8, 1.0, -22), Vector3(16.6, 2.1, -20.9), "vent", Z_VENT)
	b.carve(Vector3(16.6, 1.0, -14), Vector3(20, 2.1, -12.9), "vent", Z_VENT)


func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.cell_size = 0.2
	nm.cell_height = 0.2
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.4
	nm.agent_max_slope = 40.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Game.L_WORLD
	nm.filter_baking_aabb = AABB(Vector3(-23, -0.5, -33), Vector3(46, 7.0, 54))
	nav.navigation_mesh = nm
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, 0.2)
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map, 0.2)
	nav.bake_navigation_mesh(false)


# --- helper ---------------------------------------------------------------------------
func light(pos: Vector3, col: Color, energy: float, rng: float, zones: int, opts := {}) -> LightFixture:
	var l := LightFixture.new().setup(pos, col, energy, rng, zones, opts)
	entities.add_child(l)
	Util.set_layers_recursive(l, zones)
	if l.emergency:
		emergency_lights.append(l)
	else:
		normal_lights.append(l)
	return l


func prop(size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> StaticBody3D:
	var sb := Util.static_box(props_root, size, pos, m, Game.L_WORLD, rot)
	Util.set_layers_recursive(sb, zone_mask_at(pos + Vector3(0, size.y * 0.5 + 0.2, 0)))
	return sb


func deco(tex_name: String, size: Vector2, pos: Vector3, yaw := 0.0, emission := 0.0, alpha := false) -> MeshInstance3D:
	var opts := {"mesh_uv": true}
	if emission > 0.0:
		opts["emission"] = emission
	if alpha:
		opts["alpha"] = true
	var q := Util.quad(entities, size, pos, Util.mat(tex_name, opts), Vector3(0, yaw, 0))
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.layers = zone_mask_at(pos)
	return q


func _add(n: Node3D) -> Node3D:
	entities.add_child(n)
	Util.set_layers_recursive(n, zone_mask_at(n.global_position + Vector3.UP * 0.3))
	return n


func pipe(from: Vector3, to: Vector3, r := 0.08) -> void:
	var mid := (from + to) * 0.5
	var length := from.distance_to(to)
	var mi := Util.cylinder(props_root, r, length, mid, Util.mat("pipe", {"fit": Vector3(r * 2, length, r * 2)}), Vector3.ZERO, 6)
	var dir := (to - from).normalized()
	if absf(dir.y) < 0.99:
		mi.look_at_from_position(mid, to, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	mi.layers = zone_mask_at(mid)


# --- arredo ------------------------------------------------------------------------
func _props() -> void:
	var crate := Util.mat("crate", {"fit": Vector3(0.9, 0.9, 0.9)})
	var crate_s := Util.mat("crate", {"fit": Vector3(0.8, 0.8, 0.8)})
	var desk := Util.mat("desk", {"density": 1.0})
	var panel := Util.mat("wall_panel", {"density": 1.0})
	var dark := Util.color_mat(Color(0.1, 0.1, 0.11))
	var plant := Util.color_mat(Color(0.12, 0.3, 0.14))

	# --- partenza / ascensore
	prop(Vector3(0.9, 0.9, 0.9), Vector3(12.6, 0.45, 12.6), crate)
	prop(Vector3(0.9, 0.9, 0.9), Vector3(13.6, 0.45, 12.6), crate)
	prop(Vector3(0.9, 0.9, 0.9), Vector3(12.6, 1.35, 12.7), crate, Vector3(0, 12, 0))
	pipe(Vector3(17.6, 0, 12.4), Vector3(17.6, 3.5, 12.4), 0.12)
	pipe(Vector3(12.3, 3.1, 12.3), Vector3(17.7, 3.1, 12.3), 0.08)
	deco("sign_lift", Vector2(1.6, 0.4), Vector3(17.97, 3.25, 15.2), -90, 1.2)
	deco("graffiti", Vector2(1.8, 0.9), Vector3(15.2, 1.5, 12.02), 0, 0.0, true)
	deco("elevator_door", Vector2(1.9, 2.7), Vector3(20.58, 1.35, 15.2), -90)

	# --- corridoio di servizio
	pipe(Vector3(5.1, 2.7, 14.3), Vector3(11, 2.7, 14.3), 0.1)
	pipe(Vector3(5.1, 2.8, 15.75), Vector3(11, 2.8, 15.75), 0.06)
	pipe(Vector3(5.3, 2.7, 9.1), Vector3(5.3, 2.7, 14.3), 0.1)
	prop(Vector3(0.8, 0.8, 0.8), Vector3(5.5, 0.4, 15.5), crate_s, Vector3(0, 20, 0))
	deco("graffiti", Vector2(1.6, 0.8), Vector3(8.2, 1.5, 15.98), 180, 0.0, true)
	deco("poster", Vector2(0.5, 1.0), Vector3(6.98, 1.6, 11.5), -90)

	# --- hall
	prop(Vector3(4.2, 1.1, 0.9), Vector3(0, 0.55, 4.6), panel)
	prop(Vector3(4.4, 0.06, 1.1), Vector3(0, 1.13, 4.6), desk)
	for x in [-1.0, 1.0]:
		var mon := Util.box(props_root, Vector3(0.55, 0.36, 0.05), Vector3(x, 1.4, 4.75), Util.mat("screen_blue", {"fit": Vector3(0.55, 0.36, 0.05), "emission": 1.2}), Vector3(0, 180, 0))
		mon.layers = Z_LOBBY
	for p in [Vector3(-9.3, 0.25, -3.0), Vector3(9.3, 0.25, 4.0)]:
		prop(Vector3(0.9, 0.5, 2.4), p, desk)
	for p in [Vector3(-9.2, 0.5, 3.6), Vector3(8.9, 0.5, 6.9), Vector3(-9.2, 0.5, -5.2), Vector3(9.2, 0.5, -5.2)]:
		prop(Vector3(1.0, 1.0, 1.0), p, Util.mat("wall_concrete", {"fit": Vector3(1, 1, 1)}))
		var leaves := Util.box(props_root, Vector3(0.8, 0.7, 0.8), p + Vector3(0, 0.85, 0), plant, Vector3(0, 30, 0))
		leaves.layers = Z_LOBBY
	deco("sign_seraph", Vector2(5.0, 0.62), Vector3(0, 4.5, -5.68), 0, 1.4)
	deco("poster", Vector2(0.9, 1.8), Vector3(-9.97, 2.0, -3.2), 90)
	deco("poster", Vector2(0.9, 1.8), Vector3(9.97, 2.0, 2.2), -90)
	deco("sign_sec", Vector2(1.2, 0.3), Vector3(-9.97, 2.85, 1.8), 90, 1.0)
	deco("sign_store", Vector2(1.2, 0.3), Vector3(-9.97, 2.85, 6.4), 90, 1.0)
	deco("sign_relax", Vector2(1.2, 0.3), Vector3(9.97, 2.85, -1.0), -90, 1.0)
	deco("sign_lab", Vector2(1.6, 0.2), Vector3(-1.97, 2.4, -9.5), 90, 1.2)

	# --- sala sicurezza
	prop(Vector3(1.1, 0.8, 2.6), Vector3(-17.2, 0.4, 0.0), desk)
	prop(Vector3(0.5, 1.0, 0.5), Vector3(-15.8, 0.5, -1.2), dark)
	for z in [-1.2, 0.0, 1.2]:
		deco("screen_blue" if z != 0.0 else "screen_green", Vector2(1.0, 0.62), Vector3(-17.97, 2.2, z), 90, 1.3)
	prop(Vector3(0.6, 2.0, 0.9), Vector3(-11.35, 1.0, -3.4), Util.mat("locker", {"fit": Vector3(0.6, 2.0, 0.9)}))
	prop(Vector3(1.0, 0.9, 0.6), Vector3(-12.6, 0.45, -3.6), desk)
	var glass := Util.static_box(entities, Vector3(0.04, 1.2, 2.0), Vector3(-10.5, 1.6, -1.8), Util.mat("glass_blue", {"transparent": 0.25, "fit": Vector3(0.04, 1.2, 2.0)}), Game.L_GLASS)
	glass.get_child(0).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Util.set_layers_recursive(glass, Z_LOBBY | Z_OFFICE)

	# --- magazzino
	prop(Vector3(0.8, 1.2, 5.0), Vector3(-17.5, 0.6, 9.0), desk)
	prop(Vector3(1.0, 1.0, 1.0), Vector3(-13.0, 0.5, 11.8), crate)
	prop(Vector3(1.0, 1.0, 1.0), Vector3(-14.1, 0.5, 11.8), crate)
	prop(Vector3(1.0, 1.0, 1.0), Vector3(-13.5, 1.5, 11.85), crate, Vector3(0, 8, 0))
	prop(Vector3(1.0, 1.0, 1.0), Vector3(-16.9, 0.5, 12.3), crate, Vector3(0, -15, 0))
	prop(Vector3(0.8, 0.9, 1.4), Vector3(-12.0, 0.45, 9.5), desk)
	pipe(Vector3(-17.9, 3.0, 5.2), Vector3(-17.9, 3.0, 12.8), 0.12)

	# --- sala relax
	prop(Vector3(1.4, 0.8, 0.9), Vector3(14.5, 0.4, -1.5), desk)
	prop(Vector3(0.9, 0.45, 2.2), Vector3(12.0, 0.23, -3.5), Util.color_mat(Color(0.35, 0.1, 0.1)))
	prop(Vector3(0.25, 0.9, 2.2), Vector3(11.6, 0.65, -3.5), Util.color_mat(Color(0.3, 0.08, 0.08)))
	prop(Vector3(0.8, 2.0, 0.9), Vector3(18.5, 1.0, 0.8), Util.color_mat(Color(0.25, 0.06, 0.2)))
	deco("vending", Vector2(0.8, 1.6), Vector3(18.08, 1.0, 0.8), -90, 0.7)
	prop(Vector3(3.0, 0.9, 0.7), Vector3(13.0, 0.45, -5.6), desk)
	prop(Vector3(0.5, 2.0, 0.9), Vector3(11.3, 1.0, 1.4), Util.mat("locker", {"fit": Vector3(0.5, 2.0, 0.9)}))
	deco("poster", Vector2(0.8, 1.6), Vector3(11.02, 1.8, -4.3), 90)

	# --- corridoio laboratorio
	pipe(Vector3(-1.7, 3.2, -6.2), Vector3(-1.7, 3.2, -16.9), 0.09)
	pipe(Vector3(1.75, 3.25, -6.2), Vector3(1.75, 3.25, -16.9), 0.06)

	# --- laboratorio
	var srv := Util.mat("server", {"fit": Vector3(0.8, 2.2, 1.2), "emission": 0.9, "emission_tex": "server_emit"})
	for z in [-20.5, -21.8, -23.1, -24.4, -25.7]:
		prop(Vector3(0.8, 2.2, 1.2), Vector3(-6.2, 1.1, z), srv)
		prop(Vector3(0.8, 2.2, 1.2), Vector3(6.2, 1.1, z), srv)
	prop(Vector3(1.6, 0.9, 0.8), Vector3(-4.5, 0.45, -29.3), desk)
	prop(Vector3(1.6, 0.9, 0.8), Vector3(5.0, 0.45, -29.3), desk)
	var bench_scr := Util.box(props_root, Vector3(0.7, 0.45, 0.05), Vector3(5.0, 1.2, -29.55), Util.mat("screen_green", {"fit": Vector3(0.7, 0.45, 0.05), "emission": 1.3}))
	bench_scr.layers = Z_LAB
	# capsula criogenica con il corpo di Okafor
	prop(Vector3(1.2, 0.3, 1.2), Vector3(-6.8, 0.15, -28.7), dark)
	prop(Vector3(1.2, 0.2, 1.2), Vector3(-6.8, 4.1, -28.7), dark)
	var pod := Util.cylinder(props_root, 0.5, 3.6, Vector3(-6.8, 2.1, -28.7), Util.mat("glass_blue", {"transparent": 0.35, "fit": Vector3(1, 3.6, 1)}), Vector3.ZERO, 8)
	pod.layers = Z_LAB
	pod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := Util.box(props_root, Vector3(0.36, 1.7, 0.24), Vector3(-6.8, 1.3, -28.7), Util.color_mat(Color(0.5, 0.6, 0.62)))
	body.layers = Z_LAB
	Util.box(props_root, Vector3(0.2, 0.24, 0.22), Vector3(-6.8, 2.3, -28.7), Util.color_mat(Color(0.5, 0.6, 0.62))).layers = Z_LAB
	deco("screen_amber", Vector2(0.5, 0.35), Vector3(-6.8, 0.7, -28.08), 0, 1.2)
	pipe(Vector3(-7.9, 4.2, -18.3), Vector3(7.9, 4.2, -18.3), 0.1)
	pipe(Vector3(-7.8, 4.25, -29.8), Vector3(7.8, 4.25, -29.8), 0.14)


# --- luci ---------------------------------------------------------------------------
func _lights() -> void:
	var cold := Color(0.75, 0.85, 1.0)
	var warm := Color(1.0, 0.8, 0.55)
	var teal := Color(0.55, 1.0, 0.95)
	var red := Color(1.0, 0.12, 0.08)
	light(Vector3(15, 3.45, 15), cold, 2.21, 7.5, Z_START, {"flicker": 0.08})
	light(Vector3(19.3, 2.95, 15.2), warm, 1.53, 3.8, Z_START)
	light(Vector3(8.5, 2.95, 15), Color(1.0, 0.9, 0.6), 1.7, 5.5, Z_SERV, {"flicker": 0.6})
	light(Vector3(6, 2.95, 11), cold, 1.36, 5.0, Z_SERV)
	light(Vector3(0, 5.95, 1.5), cold, 2.89, 10.0, Z_LOBBY, {"shadows": true})
	light(Vector3(-6, 5.95, -3), cold, 2.21, 8.0, Z_LOBBY, {"shadows": true})
	light(Vector3(6, 5.95, -3), cold, 1.7, 7.5, Z_LOBBY, {"flicker": 0.5})
	light(Vector3(0, 1.45, 4.35), warm, 1.19, 3.5, Z_LOBBY, {"style": "lamp"})
	light(Vector3(0, 4.3, -5.3), Color(0.35, 0.95, 1.0), 1.2, 5.0, Z_LOBBY, {"style": "none"})
	light(Vector3(-14.5, 3.45, 0), cold, 1.7, 7.5, Z_OFFICE)
	light(Vector3(-17.0, 1.2, 1.1), warm, 1.02, 3.0, Z_OFFICE, {"style": "lamp"})
	light(Vector3(15, 3.15, -2), cold, 1.87, 7.5, Z_BREAK)
	light(Vector3(17.6, 1.3, 0.8), Color(1.0, 0.3, 0.8), 1.0, 3.0, Z_BREAK, {"style": "none"})
	light(Vector3(-14.5, 3.45, 9), Color(0.9, 0.85, 0.7), 0.95, 5.0, Z_STORE, {"flicker": 0.2})
	light(Vector3(0, 3.45, -9), cold, 2.04, 5.5, Z_LABC)
	light(Vector3(0, 3.45, -14.2), cold, 2.04, 5.5, Z_LABC)
	lab_lights.append(light(Vector3(-4, 4.45, -23.5), teal, 2.04, 8.0, Z_LAB, {"shadows": true}))
	lab_lights.append(light(Vector3(4, 4.45, -23.5), teal, 2.04, 8.0, Z_LAB, {"shadows": true}))
	lab_lights.append(light(Vector3(0, 4.45, -27.2), Color(0.9, 0.95, 1.0), 1.7, 6.0, Z_LAB))
	light(Vector3(-6.8, 0.8, -27.9), Color(1.0, 0.7, 0.3), 0.7, 2.5, Z_LAB, {"style": "none"})
	light(Vector3(16.05, 1.95, -21.45), Color(1.0, 0.55, 0.2), 0.6, 3.0, Z_VENT, {"style": "none", "flicker": 0.3})
	light(Vector3(19.4, 1.95, -13.45), Color(0.4, 1.0, 0.9), 0.5, 2.5, Z_VENT, {"style": "none"})
	# luci d'emergenza (lockdown)
	light(Vector3(0, 5.9, -5.3), red, 1.6, 12.0, Z_LOBBY | Z_LABC, {"style": "lamp", "emergency": true})
	light(Vector3(0, 5.9, 7.5), red, 1.4, 11.0, Z_LOBBY, {"style": "lamp", "emergency": true})
	light(Vector3(6, 2.9, 13), red, 1.2, 6.0, Z_SERV, {"style": "lamp", "emergency": true})
	light(Vector3(15, 3.4, 12.4), red, 1.0, 6.0, Z_START, {"style": "lamp", "emergency": true})
	light(Vector3(0, 3.4, -11.5), red, 1.0, 6.0, Z_LABC, {"style": "lamp", "emergency": true})
	light(Vector3(0, 4.4, -19), red, 1.2, 8.0, Z_LAB, {"style": "lamp", "emergency": true})


# --- porte ----------------------------------------------------------------------------
func _doors() -> void:
	_add(SlidingDoor.new().setup(Vector3(11.5, 0, 15.0), 90, 1.6, 2.5))
	_add(SlidingDoor.new().setup(Vector3(6.0, 0, 8.5), 0, 1.6, 2.5))
	_add(SlidingDoor.new().setup(Vector3(10.5, 0, -1.0), 90, 1.6, 2.5))
	_add(SlidingDoor.new().setup(Vector3(-10.5, 0, 6.4), 90, 1.6, 2.5))
	_add(SlidingDoor.new().setup(Vector3(-10.5, 0, 1.8), 90, 1.6, 2.5, {
		"title": "Sala Sicurezza", "keycard": "sicurezza", "keycard_name": "Tessera Sicurezza",
		"code": "0451", "hack": 1, "difficulty": 1,
	}))
	var lab_door := SlidingDoor.new().setup(Vector3(0, 0, -17.5), 0, 2.0, 2.6, {
		"title": "Laboratorio C", "keycard": "lab", "keycard_name": "Tessera Laboratorio C",
		"hack": 2, "difficulty": 2, "alarm_on_fail": true, "bypass_zone": Z_LAB,
	})
	lab_door.tex = "door"
	_add(lab_door)


# --- dispositivi -------------------------------------------------------------------
func _devices() -> void:
	_add(ElevatorPanel.new().setup(Vector3(19.9, 1.3, 14.04), 0))
	_add(SecurityTerminal.new().setup(Vector3(-17.3, 0.82, 0.0), 90))
	_add(UpgradeStation.new().setup(Vector3(15.5, 0, 1.72), 180))
	_add(ServerCore.new().setup(Vector3(0, 0, -27.8), 0))
	_add(SecurityCamera.new().setup(Vector3(9.3, 4.6, -5.3), 135, 40, Z_LOBBY))
	_add(SecurityCamera.new().setup(Vector3(-7.4, 3.9, -18.5), -45, 35, Z_LAB))
	turret = _add(Turret.new().setup(Vector3(0, 3.0, -16.7), 180, Z_LABC)) as Turret
	_add(TurretPanel.new().setup(Vector3(1.97, 1.3, -14.0), -90, turret))
	_add(LightSwitch.new().setup(Vector3(-1.6, 1.3, -18.03), 180, lab_lights))
	_add(VentGrate.new().setup(Vector3(16.05, 1.55, -5.99), 0, Vector2(1.1, 1.1), 0))
	_add(VentGrate.new().setup(Vector3(7.99, 1.55, -21.45), -90, Vector2(1.1, 1.1), Z_VENT))


# --- oggetti --------------------------------------------------------------------------
func _items() -> void:
	# registri
	_add(Datapad.new().setup(Vector3(14.6, 0.81, -1.2), "turni", 20))
	_add(Datapad.new().setup(Vector3(18.95, 1.5, -3.5), "okafor1", -90, true))
	_add(Datapad.new().setup(Vector3(-12.0, 0.91, 9.2), "manutenzione", -30))
	_add(Datapad.new().setup(Vector3(-12.0, 0.91, 9.9), "magazzino", 15))
	_add(Datapad.new().setup(Vector3(-16.9, 0.81, 0.9), "sicurezza", 80))
	_add(Datapad.new().setup(Vector3(-4.4, 0.91, -29.1), "okafor2", 10))
	_add(Datapad.new().setup(Vector3(19.1, 1.02, -13.2), "intruso", -60))
	# pickup
	_add(Pickup.new().setup(Vector3(5.5, 0.81, 15.5), "medpatch"))
	_add(Pickup.new().setup(Vector3(12.5, 0.91, -5.6), "medpatch"))
	_add(Pickup.new().setup(Vector3(13.6, 0.91, -5.5), "module"))
	_add(Pickup.new().setup(Vector3(-17.4, 1.21, 10.4), "ammo", 8))
	_add(Pickup.new().setup(Vector3(-17.4, 1.21, 7.6), "medpatch"))
	_add(Pickup.new().setup(Vector3(-13.5, 0.02, 12.65), "module", 1, "", "", "magazzino"))
	_add(Pickup.new().setup(Vector3(19.5, 1.02, -13.6), "module", 1, "", "", "condotto"))
	_add(Pickup.new().setup(Vector3(-12.6, 0.91, -3.6), "keycard", 1, "lab", "Tessera Laboratorio C"))
	_add(Pickup.new().setup(Vector3(5.4, 0.91, -29.1), "medpatch"))
	_add(Pickup.new().setup(Vector3(1.8, 1.17, 4.4), "credits", 40))
	_add(Pickup.new().setup(Vector3(-17.3, 1.21, 8.8), "ammo", 6))
	# oggetti da lanciare
	for p in [Vector3(13.8, 0.1, 16.5), Vector3(14.2, 0.87, -1.4), Vector3(14.8, 0.87, -1.75), Vector3(-1.6, 1.23, 4.4), Vector3(9.2, 0.6, 14.8)]:
		_add(Throwable.new().setup(p, "can"))
	for p in [Vector3(-17.5, 1.35, 8.2), Vector3(12.3, 1.05, -5.7)]:
		_add(Throwable.new().setup(p, "bottle"))
	for p in [Vector3(-12.3, 0.2, 7.0), Vector3(-15.2, 0.2, 6.3), Vector3(7.4, 0.2, 15.3)]:
		_add(Throwable.new().setup(p, "box"))


# --- guardie ----------------------------------------------------------------------
func _guards() -> void:
	_add(Guard.new().setup("Ag. Ruiz", Vector3(-7, 0, -3.5), 0, [
		[Vector3(-7, 0, -3.5), 2.5], [Vector3(0, 0, -9), 3.0], [Vector3(7, 0, -3.5), 3.0],
		[Vector3(7.5, 0, 5.8), 2.0], [Vector3(-7.5, 0, 5.8), 3.0],
	], {"keycard": ["sicurezza", "Tessera Sicurezza"], "ammo": 6, "credits": 30}))
	_add(Guard.new().setup("Op. Hale", Vector3(-16.3, 0, 0.6), 90, [], {"ammo": 4, "credits": 20, "medpatch": 1}))
	_add(Guard.new().setup("Ag. Kovač", Vector3(-2.8, 0, -19.5), 180, [
		[Vector3(-2.8, 0, -19.5), 3.0], [Vector3(-2.8, 0, -26.2), 2.0], [Vector3(2.8, 0, -26.2), 4.0],
		[Vector3(2.8, 0, -19.5), 2.0],
	], {"ammo": 6, "credits": 15}))


func _spawn_reinforcement() -> void:
	var g := Guard.new().setup("Ag. Mori", Vector3(6.0, 0, 12.5), 180, [
		[Vector3(6, 0, 10.5), 1.0], [Vector3(6, 0, 4), 2.0], [Vector3(-3, 0, 2), 2.0],
		[Vector3(6, 0, 4), 1.0], [Vector3(6, 0, 11), 2.0], [Vector3(9.5, 0, 15), 2.5],
	], {"ammo": 8, "credits": 10})
	_add(g)
	g.alertness = 1.0


# --- script di missione ---------------------------------------------------------------
func _triggers() -> void:
	_add(TriggerZone.new().setup(Vector3(0, 2, 1), Vector3(19, 4, 13), _say_lobby))
	_add(TriggerZone.new().setup(Vector3(0, 2, -24), Vector3(15, 4, 11), _say_lab))
	_add(TriggerZone.new().setup(Vector3(16.05, 1.5, -9), Vector3(1.1, 1.0, 3), _say_vent))


func _say_lobby() -> void:
	Game.say("VESPER", "La hall. Telecamera sull'angolo nord-est e una guardia di ronda. Resta nell'ombra.", 4.5)


func _say_lab() -> void:
	Game.say("VESPER", "Sei nel laboratorio. Il nucleo è nel server centrale, quello che ronza.", 4.0)


func _say_vent() -> void:
	Game.notify("Condotto di ventilazione: resta accovacciato.")


func start_intro() -> void:
	Game.read_log("vesper", false)
	Sfx.start_ambient()
	Game.say("VESPER", "Sei dentro. Livello 14, laboratori Seraph. Il briefing è nel tuo PDA [Tab].", 4.5)
	get_tree().create_timer(5.0, false).timeout.connect(_intro_2)


func _intro_2() -> void:
	Game.say("VESPER", "Il nucleo è nel Laboratorio C, a nord della hall. Come ci arrivi è affar tuo.", 4.5)


func on_lockdown() -> void:
	for l in normal_lights:
		l.set_dim(0.5)
	for l in emergency_lights:
		l.set_on(true)
	Sfx.set_alarm(true)
	Game.say("SISTEMA PA", "Violazione nel Laboratorio C. Protocollo SERAPH attivo. Vigilanza: bloccare le uscite.", 5.0)
	for g in get_tree().get_nodes_in_group("guards"):
		g.on_lockdown(Vector3(0, 0, -9))
	_spawn_reinforcement()
	get_tree().create_timer(7.0, false).timeout.connect(_lockdown_followup)


func _lockdown_followup() -> void:
	if Game.alarm_time <= 0.0:
		Sfx.set_alarm(false)
	Game.say("VESPER", "Si sono accorti del nucleo. Hanno mandato qualcuno dall'ascensore principale: torna indietro, e veloce.", 5.0)


func _spawn_player() -> void:
	player = Player.new()
	player.position = spawn_pos
	player.rotation.y = deg_to_rad(spawn_yaw)
	add_child(player)
