extends Node
## CONVERTITORE UNA TANTUM: dalla vecchia mappa scritta in codice alla scena
## levels/seraph/seraph.tscn (+ i SurfaceSet in assets/surfaces).
## Uso:  godot --headless --path . -- --convert-seraph --force
## ATTENZIONE: sovrascrive seraph.tscn e i SurfaceSet, cancellando le modifiche
## fatte nell'editor (per questo serve --force). Tenuto nel repo come esempio di
## come generare livelli da script.

const Z_START := 1
const Z_SERV := 2
const Z_BREAK := 4
const Z_LOBBY := 8
const Z_OFFICE := 16
const Z_STORE := 32
const Z_LABC := 64
const Z_LAB := 128
const Z_VENT := 256
const ZONE_NAMES := {1: "Partenza", 2: "Servizio", 4: "Relax", 8: "Hall", 16: "Sicurezza", 32: "Magazzino", 64: "CorridoioLab", 128: "Laboratorio", 256: "Condotti"}
const SET_FILES := {
	"start": "partenza", "elev": "ascensore", "frame": "cornice", "frame_hz": "cornice_pericolo",
	"service": "servizio", "lobby": "hall", "office": "sicurezza", "break": "relax",
	"store": "magazzino", "labc": "corridoio_lab", "lab": "laboratorio", "vent": "condotto",
	"pillar": "pilastro",
}
const OUT := "res://levels/seraph/seraph.tscn"

var root: Node3D
var geo: LevelGeometry
var solids: CSGCombiner3D
var zone_nodes := {}
var groups := {}
var surfaces := {}
var counters := {}
var lab_lights: Array = []
var turret: Node


func _ready() -> void:
	if FileAccess.file_exists(OUT) and not ("--force" in OS.get_cmdline_user_args()):
		push_error("%s esiste già: rigenerarla cancella le modifiche fatte nell'editor. Aggiungi --force se sei sicuro." % OUT)
		get_tree().quit(1)
		return
	convert_level()
	get_tree().quit()


func _count(key: String) -> int:
	counters[key] = int(counters.get(key, 0)) + 1
	return counters[key]


func _own(n: Node, parent: Node) -> Node:
	parent.add_child(n)
	n.owner = root
	return n


func _group(group_name: String) -> Node3D:
	if not groups.has(group_name):
		var g := Node3D.new()
		g.name = group_name
		_own(g, root)
		groups[group_name] = g
	return groups[group_name]


func convert_level() -> void:
	root = Node3D.new()
	root.name = "Seraph"
	root.set_script(load("res://levels/seraph/seraph.gd"))
	_environment()
	geo = LevelGeometry.new()
	geo.name = "Geometria"
	_own(geo, root)
	var solid := CSGBox3D.new()
	solid.name = "Solido"
	solid.size = Vector3(48, 9, 56)
	solid.position = Vector3(0, 3.5, -6)
	var inv := StandardMaterial3D.new()
	inv.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inv.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	inv.albedo_color = Color(0, 0, 0, 0)
	ResourceSaver.save(inv, "res://assets/materials/solido_invisibile.tres")
	solid.material = load("res://assets/materials/solido_invisibile.tres")
	solid.set_meta("_edit_lock_", true)
	_own(solid, geo)
	_define_sets()
	_carve()
	solids = CSGCombiner3D.new()
	solids.name = "Solidi"
	_own(solids, geo)
	_solids()
	for g in ["Arredo", "Luci", "Porte", "Dispositivi", "Oggetti", "Guardie", "Trigger"]:
		_group(g)
	var routes := Node3D.new()
	routes.name = "Percorsi"
	_own(routes, _group("Guardie"))
	groups["Percorsi"] = routes
	_props()
	_lights()
	_doors()
	_devices()
	_items()
	_guards()
	_triggers()
	var start := PlayerStart.new()
	start.name = "PartenzaPlayer"
	start.position = Vector3(19.4, 0, 15.2)
	start.rotation_degrees.y = 90
	_own(start, root)
	var lock := Marker3D.new()
	lock.name = "PuntoLockdown"
	lock.position = Vector3(0, 0, -9)
	_own(lock, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack fallito: %d" % err)
		return
	DirAccess.make_dir_recursive_absolute("res://levels/seraph")
	err = ResourceSaver.save(ps, OUT)
	print("Scena salvata: ", OUT, " (", err, ") nodi: ", root.get_child_count())
	root.free()


func _environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "Ambiente"
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
	_own(we, root)


# --- brush -------------------------------------------------------------------------
func define_set(set_name: String, wall: String, floor_tex: String, ceil: String, sound := "concrete", scales := Vector3(0.5, 0.5, 0.5), tint := Color.WHITE) -> void:
	var s := SurfaceSet.new()
	s.wall_texture = Util.tex(wall)
	s.floor_texture = Util.tex(floor_tex)
	s.ceiling_texture = Util.tex(ceil)
	s.wall_scale = scales.x
	s.floor_scale = scales.y
	s.ceiling_scale = scales.z
	s.tint = tint
	s.footsteps = sound
	var path := "res://assets/surfaces/%s.tres" % SET_FILES[set_name]
	DirAccess.make_dir_recursive_absolute("res://assets/surfaces")
	ResourceSaver.save(s, path)
	surfaces[set_name] = load(path)


func _zone(bit: int) -> Zone:
	if not zone_nodes.has(bit):
		var z := Zone.new()
		z.name = "Zona" + ZONE_NAMES[bit]
		z.layer = bit
		z.operation = CSGShape3D.OPERATION_SUBTRACTION
		_own(z, geo)
		zone_nodes[bit] = z
	return zone_nodes[bit]


func _brush(a: Vector3, b: Vector3, set_name: String) -> Brush:
	var br := Brush.new()
	var mn := Vector3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))
	var mx := Vector3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))
	br.size = _snap(mx - mn)
	br.position = _snap((mn + mx) * 0.5)
	br.surface = surfaces[set_name]
	return br


## arrotonda al millimetro calcolando in double (niente 1.5000001 nell'Inspector)
func _snap(v: Vector3) -> Vector3:
	return Vector3(snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001))


func carve(a: Vector3, b: Vector3, set_name: String, zones: int) -> void:
	var bit := zones & -zones
	var br := _brush(a, b, set_name)
	br.extra_zones = zones & ~bit
	var z := _zone(bit)
	br.name = SET_FILES[set_name].to_pascal_case() + str(z.get_child_count() + 1)
	_own(br, z)


var _pending_solids: Array = []


func add_solid(a: Vector3, b: Vector3, set_name: String, zones: int, rot_deg := Vector3.ZERO) -> void:
	_pending_solids.append([a, b, set_name, zones, rot_deg])


func _solids() -> void:
	for d in _pending_solids:
		var br := _brush(d[0], d[1], d[2])
		br.rotation_degrees = d[4]
		br.extra_zones = d[3]
		br.name = SET_FILES[d[2]].to_pascal_case() + str(solids.get_child_count() + 1)
		_own(br, solids)


func _define_sets() -> void:
	var b = self
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
	var b = self
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


# --- arredo: dai vecchi materiali alle proprietà dei prop -------------------------------
func _box_fields(inst: PropBox, m: Material) -> void:
	var sm := m as StandardMaterial3D
	inst.texture = sm.albedo_texture
	inst.tint = Color(sm.albedo_color.r, sm.albedo_color.g, sm.albedo_color.b, 1.0)
	if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
		inst.opacity = sm.albedo_color.a
	if sm.albedo_texture != null:
		if sm.uv1_world_triplanar:
			inst.uv_mode = 1
			inst.density = sm.uv1_scale.x
		else:
			inst.uv_mode = 0
	if sm.emission_enabled:
		inst.emission = sm.emission_energy_multiplier
		if sm.emission_texture != null and sm.emission_texture != sm.albedo_texture:
			inst.emission_texture = sm.emission_texture


func prop(size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO, collide := true) -> PropBox:
	var inst: PropBox = load("res://scenes/props/prop_box.tscn").instantiate()
	inst.name = "Arredo%d" % _count("arredo")
	inst.size = size
	inst.position = pos
	inst.rotation_degrees = rot
	_box_fields(inst, m)
	if not collide:
		inst.collision = 2
	_own(inst, _group("Arredo"))
	return inst


func deco(tex_name: String, size: Vector2, pos: Vector3, yaw := 0.0, emission := 0.0, alpha := false) -> void:
	var q: PropQuad = load("res://scenes/props/prop_quad.tscn").instantiate()
	q.name = "Pannello_" + tex_name + str(_count("q_" + tex_name))
	q.size = size
	q.texture = Util.tex(tex_name)
	q.emission = emission
	q.alpha_cut = alpha
	q.position = pos
	q.rotation_degrees.y = yaw
	_own(q, _group("Arredo"))


func cyl(radius: float, length: float, pos: Vector3, tex_name: String, opacity := 1.0, sides := 6, basis := Basis(), tint := Color.WHITE) -> void:
	var c: PropCylinder = load("res://scenes/props/prop_cylinder.tscn").instantiate()
	c.name = ("Tubo" if tex_name == "pipe" else "Cilindro") + str(_count("cyl"))
	c.radius = radius
	c.length = length
	c.sides = sides
	c.texture = Util.tex(tex_name) if tex_name != "" else null
	c.tint = tint
	c.opacity = opacity
	c.transform = Transform3D(basis, pos)
	_own(c, _group("Arredo"))


func pipe(from: Vector3, to: Vector3, r := 0.08) -> void:
	var dir := (to - from).normalized()
	var q := Quaternion(Vector3.UP, dir) if absf(dir.dot(Vector3.UP)) < 0.999 else Quaternion.IDENTITY
	cyl(r, from.distance_to(to), (from + to) * 0.5, "pipe", 1.0, 6, Basis(q))


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
		prop(Vector3(0.55, 0.36, 0.05), Vector3(x, 1.4, 4.75), Util.mat("screen_blue", {"fit": Vector3(0.55, 0.36, 0.05), "emission": 1.2}), Vector3(0, 180, 0), false)
	for p in [Vector3(-9.3, 0.25, -3.0), Vector3(9.3, 0.25, 4.0)]:
		prop(Vector3(0.9, 0.5, 2.4), p, desk)
	for p in [Vector3(-9.2, 0.5, 3.6), Vector3(8.9, 0.5, 6.9), Vector3(-9.2, 0.5, -5.2), Vector3(9.2, 0.5, -5.2)]:
		prop(Vector3(1.0, 1.0, 1.0), p, Util.mat("wall_concrete", {"fit": Vector3(1, 1, 1)}))
		prop(Vector3(0.8, 0.7, 0.8), p + Vector3(0, 0.85, 0), plant, Vector3(0, 30, 0), false)
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
	var glass := prop(Vector3(0.04, 1.2, 2.0), Vector3(-10.5, 1.6, -1.8), Util.mat("glass_blue", {"transparent": 0.25, "fit": Vector3(0.04, 1.2, 2.0)}))
	glass.name = "VetroFinestra"
	glass.collision = 1

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
	prop(Vector3(0.7, 0.45, 0.05), Vector3(5.0, 1.2, -29.55), Util.mat("screen_green", {"fit": Vector3(0.7, 0.45, 0.05), "emission": 1.3}), Vector3.ZERO, false)
	# capsula criogenica con il corpo di Okafor
	prop(Vector3(1.2, 0.3, 1.2), Vector3(-6.8, 0.15, -28.7), dark)
	prop(Vector3(1.2, 0.2, 1.2), Vector3(-6.8, 4.1, -28.7), dark)
	cyl(0.5, 3.6, Vector3(-6.8, 2.1, -28.7), "glass_blue", 0.35, 8)
	prop(Vector3(0.36, 1.7, 0.24), Vector3(-6.8, 1.3, -28.7), Util.color_mat(Color(0.5, 0.6, 0.62)), Vector3.ZERO, false)
	prop(Vector3(0.2, 0.24, 0.22), Vector3(-6.8, 2.3, -28.7), Util.color_mat(Color(0.5, 0.6, 0.62)), Vector3.ZERO, false)
	deco("screen_amber", Vector2(0.5, 0.35), Vector3(-6.8, 0.7, -28.08), 0, 1.2)
	pipe(Vector3(-7.9, 4.2, -18.3), Vector3(7.9, 4.2, -18.3), 0.1)
	pipe(Vector3(-7.8, 4.25, -29.8), Vector3(7.8, 4.25, -29.8), 0.14)


# --- entità: stessa chiamata di prima, ma diventano istanze di scena ---------------------
const SCENES := {
	"LightFixture": ["res://scenes/entities/light.tscn", "Luci"],
	"SlidingDoor": ["res://scenes/entities/door.tscn", "Porte"],
	"ElevatorPanel": ["res://scenes/entities/elevator_panel.tscn", "Dispositivi"],
	"SecurityTerminal": ["res://scenes/entities/security_terminal.tscn", "Dispositivi"],
	"UpgradeStation": ["res://scenes/entities/upgrade_station.tscn", "Dispositivi"],
	"ServerCore": ["res://scenes/entities/server_core.tscn", "Dispositivi"],
	"SecurityCamera": ["res://scenes/entities/security_camera.tscn", "Dispositivi"],
	"Turret": ["res://scenes/entities/turret.tscn", "Dispositivi"],
	"TurretPanel": ["res://scenes/entities/turret_panel.tscn", "Dispositivi"],
	"LightSwitch": ["res://scenes/entities/light_switch.tscn", "Dispositivi"],
	"VentGrate": ["res://scenes/entities/vent_grate.tscn", "Dispositivi"],
	"Datapad": ["res://scenes/entities/datapad.tscn", "Oggetti"],
	"Pickup": ["res://scenes/entities/pickup.tscn", "Oggetti"],
	"Throwable": ["res://scenes/entities/throwable.tscn", "Oggetti"],
	"Guard": ["res://scenes/entities/guard.tscn", "Guardie"],
}


func _class_of(n: Object) -> String:
	var s: Script = n.get_script()
	return s.get_global_name() if s else ""


func _entity_name(src: Object, cls: String) -> String:
	match cls:
		"LightFixture":
			return ("LuceEmergenza%d" % _count("le")) if src.emergency else ("Luce%d" % _count("l"))
		"SlidingDoor":
			if src.lock_title != "":
				return "Porta" + src.lock_title.to_pascal_case()
			return "Porta%d" % _count("p")
		"Datapad":
			return "Datapad_" + src.log_id
		"Pickup":
			return "%s%d" % [src.kind.capitalize(), _count("pk_" + src.kind)]
		"Throwable":
			return "%s%d" % [src.kind.capitalize(), _count("th_" + src.kind)]
		"Guard":
			return String(src.guard_name).split(" ")[-1]
		"SecurityCamera":
			return "Telecamera%d" % _count("cam")
		"VentGrate":
			return "Grata%d" % _count("grate")
		"Turret":
			return "Torretta"
		"TurretPanel":
			return "PannelloTorretta"
		"LightSwitch":
			return "InterruttoreLab"
		"ElevatorPanel":
			return "PulsantieraAscensore"
		"SecurityTerminal":
			return "TerminaleSicurezza"
		"UpgradeStation":
			return "StazionePotenziamento"
		"ServerCore":
			return "ServerNucleo"
	return cls + str(_count(cls))


func _add(src: Node3D) -> Node3D:
	var cls := _class_of(src)
	var info: Array = SCENES[cls]
	var inst: Node3D = load(info[0]).instantiate()
	for p in src.get_property_list():
		if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) and (p.usage & PROPERTY_USAGE_STORAGE):
			inst.set(p.name, src.get(p.name))
	inst.transform = src.transform
	inst.name = _entity_name(src, cls)
	_own(inst, _group(info[1]))
	match cls:
		"TurretPanel":
			inst.turret_path = NodePath("../" + String(src.turret.name))
		"LightSwitch":
			var t: Array[NodePath] = []
			for l in src.lights:
				t.append(NodePath("../../Luci/" + String(l.name)))
			inst.targets = t
		"Guard":
			_guard_extras(src, inst)
	src.free()
	return inst


func _guard_extras(src: Guard, g: Guard) -> void:
	g.guard_name = ""   # il nome viene dalla definizione
	_guard_route(src, g)
	if src.definition != null:
		return   # bottino, nome e parametri stanno nel personaggio (.tres)
	g.guard_name = src.guard_name
	var loot: Dictionary = src.loot
	g.loot_ammo = loot.get("ammo", 0)
	g.loot_credits = loot.get("credits", 0)
	g.loot_medpatch = loot.get("medpatch", 0)
	if loot.has("keycard"):
		g.loot_keycard_id = loot.keycard[0]
		g.loot_keycard_name = loot.keycard[1]


func _guard_route(src: Guard, g: Guard) -> void:
	if src.waypoints.is_empty():
		return
	var route: PatrolRoute = load("res://scenes/entities/patrol_route.tscn").instantiate()
	route.name = "Percorso" + String(g.name)
	_own(route, groups["Percorsi"])
	for i in src.waypoints.size():
		var wp: Waypoint = load("res://scenes/entities/waypoint.tscn").instantiate()
		wp.name = "Tappa%d" % (i + 1)
		wp.position = src.waypoints[i]
		wp.wait = src.waits[i]
		_own(wp, route)
	g.patrol_route = NodePath("../Percorsi/" + String(route.name))


func light(pos: Vector3, col: Color, energy: float, rng: float, zones: int, opts := {}) -> Node3D:
	return _add(LightFixture.new().setup(pos, col, energy, rng, zones, opts))


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


func _doors() -> void:
	_add(SlidingDoor.new().setup(Vector3(11.5, 0, 15.0), 90, 1.6, 2.5))
	_add(SlidingDoor.new().setup(Vector3(6.0, 0, 8.5), 0, 1.6, 2.5))
	_add(SlidingDoor.new().setup(Vector3(10.5, 0, -1.0), 90, 1.6, 2.5))
	_add(SlidingDoor.new().setup(Vector3(-10.5, 0, 6.4), 90, 1.6, 2.5))
	_add(SlidingDoor.new().setup(Vector3(-10.5, 0, 1.8), 90, 1.6, 2.5, {
		"title": "Sala Sicurezza", "keycard": "sicurezza", "keycard_name": "Tessera Sicurezza",
		"code": "0451", "hack": 1, "difficulty": 1,
	}))
	_add(SlidingDoor.new().setup(Vector3(0, 0, -17.5), 0, 2.0, 2.6, {
		"title": "Laboratorio C", "keycard": "lab", "keycard_name": "Tessera Laboratorio C",
		"hack": 2, "difficulty": 2, "alarm_on_fail": true, "bypass_zone": Z_LAB,
	}))


func _devices() -> void:
	_add(ElevatorPanel.new().setup(Vector3(19.9, 1.3, 14.04), 0))
	_add(SecurityTerminal.new().setup(Vector3(-17.3, 0.82, 0.0), 90))
	_add(UpgradeStation.new().setup(Vector3(15.5, 0, 1.72), 180))
	_add(ServerCore.new().setup(Vector3(0, 0, -27.8), 0))
	_add(SecurityCamera.new().setup(Vector3(9.3, 4.6, -5.3), 135, 40, Z_LOBBY))
	_add(SecurityCamera.new().setup(Vector3(-7.4, 3.9, -18.5), -45, 35, Z_LAB))
	turret = _add(Turret.new().setup(Vector3(0, 3.0, -16.7), 180, Z_LABC))
	_add(TurretPanel.new().setup(Vector3(1.97, 1.3, -14.0), -90, turret))
	_add(LightSwitch.new().setup(Vector3(-1.6, 1.3, -18.03), 180, lab_lights))
	_add(VentGrate.new().setup(Vector3(16.05, 1.55, -5.99), 0, Vector2(1.1, 1.1), 0))
	_add(VentGrate.new().setup(Vector3(7.99, 1.55, -21.45), -90, Vector2(1.1, 1.1), Z_VENT))


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
## Chi sono (aspetto, sensi, bottino, battute) sta nelle definizioni fatte col creatore di
## NPC (assets/npc/characters); qui si decide solo dove stanno e che giro fanno.
func _npc(id: String) -> NPCDefinition:
	return load(NPCLibrary.CHARACTERS_DIR.path_join(id + ".tres"))


func _guards() -> void:
	_add(Guard.new().setup_def(_npc("ruiz"), Vector3(-7, 0, -3.5), 0, [
		[Vector3(-7, 0, -3.5), 2.5], [Vector3(0, 0, -9), 3.0], [Vector3(7, 0, -3.5), 3.0],
		[Vector3(7.5, 0, 5.8), 2.0], [Vector3(-7.5, 0, 5.8), 3.0],
	]))
	_add(Guard.new().setup_def(_npc("hale"), Vector3(-16.3, 0, 0.6), 90))
	_add(Guard.new().setup_def(_npc("kovac"), Vector3(-2.8, 0, -19.5), 180, [
		[Vector3(-2.8, 0, -19.5), 3.0], [Vector3(-2.8, 0, -26.2), 2.0], [Vector3(2.8, 0, -26.2), 4.0],
		[Vector3(2.8, 0, -19.5), 2.0],
	]))
	# rinforzo del lockdown: inattivo finché la missione non lo sveglia
	var mori := _add(Guard.new().setup_def(_npc("mori"), Vector3(6.0, 0, 12.5), 180, [
		[Vector3(6, 0, 10.5), 1.0], [Vector3(6, 0, 4), 2.0], [Vector3(-3, 0, 2), 2.0],
		[Vector3(6, 0, 4), 1.0], [Vector3(6, 0, 11), 2.0], [Vector3(9.5, 0, 15), 2.5],
	]))
	mori.dormant = true


func _trig(center: Vector3, size: Vector3, who: String, what: String, secs: float, trig_name: String) -> void:
	var t: TriggerZone = load("res://scenes/entities/trigger_zone.tscn").instantiate()
	t.name = trig_name
	t.position = center
	t.size = size
	t.speaker = who
	t.text = what
	t.duration = secs
	_own(t, _group("Trigger"))


func _triggers() -> void:
	_trig(Vector3(0, 2, 1), Vector3(19, 4, 13), "VESPER", "La hall. Telecamera sull'angolo nord-est e una guardia di ronda. Resta nell'ombra.", 4.5, "TriggerHall")
	_trig(Vector3(0, 2, -24), Vector3(15, 4, 11), "VESPER", "Sei nel laboratorio. Il nucleo è nel server centrale, quello che ronza.", 4.0, "TriggerLaboratorio")
	_trig(Vector3(16.05, 1.5, -9), Vector3(1.1, 1.0, 3), "", "Condotto di ventilazione: resta accovacciato.", 4.0, "TriggerCondotto")
