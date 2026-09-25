@tool
class_name NPCLibrary
extends RefCounted
## Libreria delle forme (assets/npc/segments/*.tres), archetipi e generatore casuale.
## Le forme predefinite sono descritte qui in codice: tools/npc_seed.gd le salva come
## file .tres (da quel momento si modificano con il creatore e i file hanno la precedenza).

const SHAPES_DIR := "res://assets/npc/segments"
const CHARACTERS_DIR := "res://assets/npc/characters"
const ARCH_KEYS: Array[String] = ["guardia", "tecnico", "scienziato", "dirigente", "civile"]
const ARCH_LABELS: Array[String] = ["Guardia", "Tecnico", "Scienziato", "Dirigente", "Civile"]

const C := SegmentShape.Category
const B := SegmentShape.Band
const S := SegmentShape.Slot

static var _builtin := {}
static var _list_cache := {}
## Aumenta quando la libreria su disco cambia (il creatore ricarica i suoi elenchi).
static var version := 0

const SKIN_TONES: Array[Color] = [
	Color(0.93, 0.76, 0.64), Color(0.86, 0.66, 0.52), Color(0.76, 0.56, 0.42), Color(0.62, 0.45, 0.33),
	Color(0.48, 0.33, 0.24), Color(0.36, 0.24, 0.17), Color(0.27, 0.18, 0.13), Color(0.90, 0.72, 0.58),
]
const HAIR_COLORS: Array[Color] = [
	Color(0.06, 0.05, 0.05), Color(0.14, 0.09, 0.06), Color(0.30, 0.19, 0.10), Color(0.55, 0.42, 0.25),
	Color(0.45, 0.43, 0.42), Color(0.72, 0.70, 0.68), Color(0.40, 0.14, 0.07),
]
const SURNAMES: Array[String] = [
	"Ruiz", "Hale", "Kovač", "Mori", "Tanaka", "Novak", "Ibarra", "Lindqvist", "Mensah", "Petrov",
	"Castell", "Nakamura", "Brandt", "Silva", "Osei", "Varga", "Chen", "Adeyemi", "Duarte", "Keller",
	"Sato", "Moreau", "Rossi", "Byrne", "Haddad", "Kaur", "Weiss", "Quinn", "Lund", "Okoro",
]
const TITLES: Array[String] = ["Ag.", "Tec.", "Dr.", "Dir.", ""]


# --- forme predefinite --------------------------------------------------------------
static func builtin_shapes() -> Dictionary:
	if not _builtin.is_empty():
		return _builtin
	var d := {}
	var all := PackedStringArray()
	# teste: dal mento (0) alla sommità (1); il volto è davanti nell'atlante (banda VOLTO)
	var head_w := [Vector2(0, 0.55), Vector2(0.15, 0.8), Vector2(0.45, 1.0), Vector2(0.72, 0.97), Vector2(0.9, 0.72), Vector2(1, 0.3)]
	var head_d := [Vector2(0, 0.62), Vector2(0.15, 0.86), Vector2(0.45, 1.0), Vector2(0.75, 0.95), Vector2(0.92, 0.7), Vector2(1, 0.3)]
	var head_opts := {"rings": 6, "sides": 8, "band": B.VOLTO, "color_slot": S.PELLE, "cap_end": true,
		"extend_start": 0.05, "extend_end": 0.0, "split": 1.0,
		"bulge": [Vector2(0, 0.18), Vector2(0.35, 0.1), Vector2(0.7, 0.02), Vector2(1, 0.0)]}
	d["testa"] = SegmentShape.create(C.TESTA, 0.085, 0.1, head_w, head_d, head_opts)
	var sq := head_opts.duplicate()
	sq["section"] = SegmentShape.symmetric_section([1.0, 1.08, 1.0, 1.1, 0.96])
	d["testa_squadrata"] = SegmentShape.create(C.TESTA, 0.09, 0.098,
		[Vector2(0, 0.75), Vector2(0.2, 0.92), Vector2(0.5, 1.0), Vector2(0.8, 0.95), Vector2(0.94, 0.72), Vector2(1, 0.35)], head_d, sq)
	d["testa_stretta"] = SegmentShape.create(C.TESTA, 0.076, 0.1,
		[Vector2(0, 0.45), Vector2(0.2, 0.75), Vector2(0.5, 1.0), Vector2(0.78, 1.0), Vector2(0.93, 0.75), Vector2(1, 0.3)], head_d, head_opts)
	d["collo"] = SegmentShape.create(C.COLLO, 0.056, 0.06, [Vector2(0, 1.12), Vector2(1, 0.95)], [],
		{"rings": 2, "sides": 6, "band": B.PELLE, "color_slot": S.PELLE, "extend_start": 0.25, "extend_end": 0.35})
	# torsi: dalla vita (0) alla base del collo (1)
	var chest_w := [Vector2(0, 0.8), Vector2(0.4, 0.94), Vector2(0.72, 1.0), Vector2(0.9, 0.93), Vector2(1, 0.58)]
	var chest_d := [Vector2(0, 0.86), Vector2(0.45, 1.0), Vector2(0.8, 0.93), Vector2(1, 0.64)]
	var chest_opts := {"rings": 5, "sides": 8, "band": B.TESSUTO, "color_slot": S.UNIFORME, "cap_end": true,
		"extend_start": 0.1, "extend_end": 0.0, "section": SegmentShape.symmetric_section([0.96, 1.07, 1.0, 1.07, 1.0]),
		"bulge": [Vector2(0, 0.0), Vector2(0.5, 0.07), Vector2(1, -0.06)]}
	d["torace"] = SegmentShape.create(C.TORACE, 0.185, 0.118, chest_w, chest_d, chest_opts)
	var ar := chest_opts.duplicate()
	ar["band"] = B.ARMATURA
	ar["color_slot"] = S.ARMATURA
	ar["smooth"] = false
	d["torace_armatura"] = SegmentShape.create(C.TORACE, 0.198, 0.132,
		[Vector2(0, 0.86), Vector2(0.4, 0.97), Vector2(0.72, 1.0), Vector2(0.9, 0.95), Vector2(1, 0.6)], chest_d, ar)
	d["torace_massiccio"] = SegmentShape.create(C.TORACE, 0.21, 0.135,
		[Vector2(0, 0.85), Vector2(0.4, 0.97), Vector2(0.7, 1.0), Vector2(0.88, 0.95), Vector2(1, 0.6)], chest_d, chest_opts)
	var coat := chest_opts.duplicate()
	coat["split"] = 1.0
	d["torace_camice"] = SegmentShape.create(C.TORACE, 0.19, 0.122, chest_w, chest_d, coat)
	d["addome"] = SegmentShape.create(C.ADDOME, 0.158, 0.108, [Vector2(0, 1.0), Vector2(0.5, 0.93), Vector2(1, 0.95)], [],
		{"rings": 3, "sides": 8, "band": B.TESSUTO, "color_slot": S.UNIFORME, "extend_start": 0.12, "extend_end": 0.12,
		"section": SegmentShape.symmetric_section([0.96, 1.05, 1.0, 1.05, 1.0]),
		"bulge": [Vector2(0, 0.04), Vector2(0.5, 0.08), Vector2(1, 0.04)]})
	d["addome_pancia"] = SegmentShape.create(C.ADDOME, 0.17, 0.12, [Vector2(0, 1.0), Vector2(0.45, 1.05), Vector2(1, 0.95)], [],
		{"rings": 4, "sides": 8, "band": B.TESSUTO, "color_slot": S.UNIFORME, "extend_start": 0.12, "extend_end": 0.12,
		"bulge": [Vector2(0, 0.1), Vector2(0.45, 0.3), Vector2(1, 0.08)]})
	d["bacino"] = SegmentShape.create(C.BACINO, 0.162, 0.108, [Vector2(0, 1.0), Vector2(0.6, 0.98), Vector2(1, 0.8)], [],
		{"rings": 3, "sides": 8, "band": B.TESSUTO, "color_slot": S.SECONDARIO, "cap_end": true,
		"extend_start": 0.15, "extend_end": 0.0, "section": SegmentShape.symmetric_section([0.98, 1.05, 1.0, 1.04, 1.0])})
	# braccia: dalla spalla verso il basso
	var arm_opts := {"rings": 4, "sides": 6, "band": B.TESSUTO, "color_slot": S.UNIFORME, "cap_start": true,
		"extend_start": 0.18, "extend_end": 0.1}
	d["braccio"] = SegmentShape.create(C.BRACCIO, 0.05, 0.054, [Vector2(0, 1.0), Vector2(0.3, 1.02), Vector2(1, 0.8)], [], arm_opts)
	d["braccio_muscoloso"] = SegmentShape.create(C.BRACCIO, 0.06, 0.064, [Vector2(0, 1.0), Vector2(0.35, 1.08), Vector2(1, 0.78)], [], arm_opts)
	var fa_opts := {"rings": 4, "sides": 6, "band": B.TESSUTO, "color_slot": S.UNIFORME, "extend_start": 0.1, "extend_end": 0.04}
	var fa_w := [Vector2(0, 1.0), Vector2(0.3, 1.02), Vector2(1, 0.72)]
	d["avambraccio"] = SegmentShape.create(C.AVAMBRACCIO, 0.041, 0.044, fa_w, [], fa_opts)
	var gl := fa_opts.duplicate()
	gl.merge({"split": 0.78, "band_b": B.GOMMA, "color_slot_b": S.STIVALI}, true)
	d["avambraccio_guanto"] = SegmentShape.create(C.AVAMBRACCIO, 0.042, 0.045,
		[Vector2(0, 1.0), Vector2(0.3, 1.02), Vector2(0.75, 0.8), Vector2(0.8, 0.95), Vector2(1, 0.86)], [], gl)
	var bare := fa_opts.duplicate()
	bare.merge({"split": 0.45, "band_b": B.PELLE, "color_slot_b": S.PELLE}, true)
	d["avambraccio_nudo"] = SegmentShape.create(C.AVAMBRACCIO, 0.04, 0.043,
		[Vector2(0, 1.04), Vector2(0.42, 1.05), Vector2(0.47, 0.9), Vector2(1, 0.68)], [], bare)
	# mani a manopola: larghe lungo Z (il palmo guarda la coscia)
	var hand_opts := {"rings": 3, "sides": 6, "band": B.PELLE, "color_slot": S.PELLE, "cap_end": true, "extend_start": 0.12, "extend_end": 0.0}
	var hand_w := [Vector2(0, 0.95), Vector2(0.45, 1.0), Vector2(1, 0.6)]
	var hand_d := [Vector2(0, 0.8), Vector2(0.45, 1.0), Vector2(1, 0.6)]
	d["mano"] = SegmentShape.create(C.MANO, 0.022, 0.042, hand_w, hand_d, hand_opts)
	var gh := hand_opts.duplicate()
	gh.merge({"band": B.GOMMA, "color_slot": S.STIVALI}, true)
	d["mano_guanto"] = SegmentShape.create(C.MANO, 0.025, 0.045, hand_w, hand_d, gh)
	# gambe
	var leg_opts := {"rings": 4, "sides": 7, "band": B.TESSUTO, "color_slot": S.SECONDARIO, "cap_start": true,
		"extend_start": 0.12, "extend_end": 0.08}
	d["coscia"] = SegmentShape.create(C.COSCIA, 0.08, 0.086, [Vector2(0, 1.0), Vector2(0.45, 0.94), Vector2(1, 0.7)], [], leg_opts)
	d["coscia_robusta"] = SegmentShape.create(C.COSCIA, 0.09, 0.096, [Vector2(0, 1.0), Vector2(0.45, 0.96), Vector2(1, 0.7)], [], leg_opts)
	var shin_opts := {"rings": 4, "sides": 7, "band": B.TESSUTO, "color_slot": S.SECONDARIO,
		"extend_start": 0.08, "extend_end": 0.12, "bulge": [Vector2(0, 0.0), Vector2(0.3, -0.15), Vector2(1, 0.0)]}
	var shin_w := [Vector2(0, 0.95), Vector2(0.3, 1.0), Vector2(1, 0.68)]
	d["stinco"] = SegmentShape.create(C.STINCO, 0.058, 0.064, shin_w, [], shin_opts)
	var boot := shin_opts.duplicate()
	boot.merge({"split": 0.55, "band_b": B.GOMMA, "color_slot_b": S.STIVALI}, true)
	d["stinco_stivale"] = SegmentShape.create(C.STINCO, 0.059, 0.065,
		[Vector2(0, 0.95), Vector2(0.3, 1.0), Vector2(0.52, 0.85), Vector2(0.58, 0.98), Vector2(1, 0.85)], [], boot)
	# piedi: dal tallone alla punta; "davanti" per il piede è il collo del piede (in alto)
	var foot_opts := {"rings": 4, "sides": 6, "band": B.GOMMA, "color_slot": S.STIVALI, "cap_start": true, "cap_end": true,
		"extend_start": 0.08, "extend_end": 0.0, "smooth": false,
		"bulge": [Vector2(0, 0.0), Vector2(0.35, 0.3), Vector2(0.75, 0.0), Vector2(1, -0.2)]}
	d["piede"] = SegmentShape.create(C.PIEDE, 0.042, 0.04,
		[Vector2(0, 0.8), Vector2(0.35, 0.9), Vector2(0.75, 1.0), Vector2(1, 0.75)],
		[Vector2(0, 0.85), Vector2(0.35, 1.0), Vector2(0.75, 0.7), Vector2(1, 0.45)], foot_opts)
	d["piede_stivale"] = SegmentShape.create(C.PIEDE, 0.05, 0.048,
		[Vector2(0, 0.85), Vector2(0.35, 0.92), Vector2(0.75, 1.0), Vector2(1, 0.85)],
		[Vector2(0, 0.9), Vector2(0.35, 1.0), Vector2(0.75, 0.75), Vector2(1, 0.5)], foot_opts)

	# --- accessori ---
	d["casco"] = _acc(SegmentShape.create(C.ACCESSORIO, 0.102, 0.12,
		[Vector2(0, 0.86), Vector2(0.25, 1.0), Vector2(0.62, 1.0), Vector2(0.86, 0.84), Vector2(1, 0.35)],
		[Vector2(0, 0.9), Vector2(0.25, 1.0), Vector2(0.62, 1.0), Vector2(0.86, 0.84), Vector2(1, 0.35)],
		{"rings": 5, "sides": 8, "band": B.ARMATURA, "color_slot": S.ARMATURA, "cap_end": true, "cap_start": true,
		"extend_start": 0.0, "extend_end": 0.0, "section": SegmentShape.symmetric_section([1.0, 1.04, 1.0, 1.04, 0.98])}),
		&"head", Vector3(0, -0.012, 0.004), Vector3.ZERO, 0.24, false)
	d["visore"] = _acc(SegmentShape.create(C.ACCESSORIO, 0.106, 0.124, [Vector2(0, 1.0), Vector2(1, 1.0)], [],
		{"rings": 2, "sides": 8, "band": B.LUCE, "color_slot": S.LUCE, "smooth": false, "extend_start": 0.0, "extend_end": 0.0,
		"section": SegmentShape.symmetric_section([0.8, 0.84, 1.0, 1.03, 1.03])}),
		&"head", Vector3(0, 0.112, -0.002), Vector3.ZERO, 0.036, false)
	d["impianto_calma"] = _acc(SegmentShape.create(C.ACCESSORIO, 0.02, 0.013, [Vector2(0, 1.0), Vector2(1, 0.85)], [],
		{"rings": 2, "sides": 4, "band": B.LUCE, "color_slot": S.LUCE, "cap_end": true, "smooth": false,
		"extend_start": 0.0, "extend_end": 0.0}),
		&"head", Vector3(0, 0.07, 0.095), Vector3(90, 0, 0), 0.032, false)
	d["spallaccio"] = _acc(SegmentShape.create(C.ACCESSORIO, 0.074, 0.08, [Vector2(0, 0.7), Vector2(0.3, 1.0), Vector2(1, 0.92)], [],
		{"rings": 3, "sides": 6, "band": B.ARMATURA, "color_slot": S.ARMATURA, "cap_start": true, "smooth": false,
		"extend_start": 0.0, "extend_end": 0.0}),
		&"upperarm_l", Vector3(-0.012, 0.05, 0.0), Vector3(180, 0, 0), 0.12, true)
	d["cintura"] = _acc(SegmentShape.create(C.ACCESSORIO, 0.17, 0.116, [Vector2(0, 1.0), Vector2(1, 1.0)], [],
		{"rings": 2, "sides": 8, "band": B.GOMMA, "color_slot": S.STIVALI, "smooth": false, "extend_start": 0.0, "extend_end": 0.0,
		"section": SegmentShape.symmetric_section([0.98, 1.05, 1.0, 1.04, 1.0])}),
		&"hips", Vector3(0, 0.0, 0.0), Vector3.ZERO, 0.055, false)
	d["pistola"] = _acc(SegmentShape.create(C.ACCESSORIO, 0.02, 0.05, [Vector2(0, 1.0), Vector2(0.4, 0.95), Vector2(1, 0.8)],
		[Vector2(0, 1.0), Vector2(0.38, 1.0), Vector2(0.42, 0.62), Vector2(1, 0.58)],
		{"rings": 3, "sides": 4, "band": B.METALLO, "color_slot": S.SECONDARIO, "cap_start": true, "cap_end": true,
		"smooth": false, "extend_start": 0.0, "extend_end": 0.0, "is_weapon": true}),
		&"hand_r", Vector3(0, -0.08, -0.012), Vector3(180, 0, 0), 0.17, false)
	var hair_opts := {"rings": 4, "sides": 8, "band": B.CAPELLI, "color_slot": S.CAPELLI, "cap_end": true,
		"extend_start": 0.0, "extend_end": 0.0}
	d["capelli"] = _acc(SegmentShape.create(C.ACCESSORIO, 0.092, 0.108,
		[Vector2(0, 1.0), Vector2(0.45, 0.98), Vector2(0.8, 0.8), Vector2(1, 0.35)],
		[Vector2(0, 1.0), Vector2(0.45, 0.97), Vector2(0.8, 0.8), Vector2(1, 0.35)], hair_opts),
		&"head", Vector3(0, 0.125, 0.018), Vector3(28, 0, 0), 0.105, false)
	d["capelli_lunghi"] = _acc(SegmentShape.create(C.ACCESSORIO, 0.096, 0.112,
		[Vector2(0, 0.95), Vector2(0.5, 1.0), Vector2(0.82, 0.82), Vector2(1, 0.35)],
		[Vector2(0, 0.95), Vector2(0.5, 1.0), Vector2(0.82, 0.8), Vector2(1, 0.35)], hair_opts),
		&"head", Vector3(0, 0.07, 0.035), Vector3(38, 0, 0), 0.16, false)
	d["berretto"] = _acc(SegmentShape.create(C.ACCESSORIO, 0.095, 0.112,
		[Vector2(0, 1.0), Vector2(0.5, 0.97), Vector2(1, 0.4)], [],
		{"rings": 3, "sides": 8, "band": B.TESSUTO, "color_slot": S.UNIFORME, "cap_end": true, "smooth": true,
		"extend_start": 0.0, "extend_end": 0.0}),
		&"head", Vector3(0, 0.15, 0.008), Vector3(12, 0, 0), 0.085, false)
	d["visiera_berretto"] = _acc(SegmentShape.create(C.ACCESSORIO, 0.07, 0.008, [Vector2(0, 1.0), Vector2(1, 0.8)], [],
		{"rings": 2, "sides": 4, "band": B.TESSUTO, "color_slot": S.UNIFORME, "cap_end": true, "smooth": false,
		"extend_start": 0.0, "extend_end": 0.0}),
		&"head", Vector3(0, 0.155, -0.085), Vector3(-80, 0, 0), 0.07, false)
	d["falda_camice"] = _acc(SegmentShape.create(C.ACCESSORIO, 0.172, 0.122, [Vector2(0, 1.0), Vector2(0.5, 1.12), Vector2(1, 1.3)], [],
		{"rings": 3, "sides": 8, "band": B.TESSUTO, "color_slot": S.UNIFORME, "extend_start": 0.0, "extend_end": 0.0,
		"section": SegmentShape.symmetric_section([0.98, 1.04, 1.0, 1.04, 1.0])}),
		&"hips", Vector3(0, 0.06, 0.0), Vector3(180, 0, 0), 0.38, false)
	d["colletto"] = _acc(SegmentShape.create(C.ACCESSORIO, 0.078, 0.082, [Vector2(0, 1.0), Vector2(1, 0.86)], [],
		{"rings": 2, "sides": 8, "band": B.ARMATURA, "color_slot": S.UNIFORME, "smooth": false,
		"extend_start": 0.0, "extend_end": 0.0, "bulge": [Vector2(0, 0.05), Vector2(1, 0.0)]}),
		&"neck", Vector3(0, -0.02, 0.0), Vector3.ZERO, 0.07, false)
	d["cuffia"] = _acc(SegmentShape.create(C.ACCESSORIO, 0.028, 0.03, [Vector2(0, 1.0), Vector2(1, 0.9)], [],
		{"rings": 2, "sides": 6, "band": B.GOMMA, "color_slot": S.STIVALI, "cap_end": true, "smooth": false,
		"extend_start": 0.0, "extend_end": 0.0}),
		&"head", Vector3(-0.078, 0.11, 0.0), Vector3(0, 0, 90), 0.03, true)
	# etichette per il generatore casuale
	for k in d:
		var s: SegmentShape = d[k]
		s.resource_name = k
	for k in ["torace_armatura", "spallaccio", "casco", "visore", "colletto", "pistola", "mano_guanto", "avambraccio_guanto"]:
		(d[k] as SegmentShape).tags = PackedStringArray(["guardia"])
	(d["torace_camice"] as SegmentShape).tags = PackedStringArray(["scienziato"])
	(d["falda_camice"] as SegmentShape).tags = PackedStringArray(["scienziato"])
	(d["berretto"] as SegmentShape).tags = PackedStringArray(["tecnico"])
	(d["avambraccio_nudo"] as SegmentShape).tags = PackedStringArray(["tecnico", "civile"])
	for k in ["stinco_stivale", "piede_stivale"]:
		(d[k] as SegmentShape).tags = PackedStringArray(["guardia", "tecnico"])
	_builtin = d
	return d


static func _acc(s: SegmentShape, bone: String, off: Vector3, rot: Vector3, len: float, mirror: bool) -> SegmentShape:
	s.attach_bone = bone
	s.attach_offset = off
	s.attach_rotation = rot
	s.attach_length = len
	s.attach_mirror = mirror
	return s


# --- accesso alla libreria su disco ---------------------------------------------------
static func shape_path(shape_name: String) -> String:
	return SHAPES_DIR.path_join(shape_name + ".tres")


## Forma per nome: il file della libreria se esiste, altrimenti quella predefinita.
static func shape(shape_name: String) -> SegmentShape:
	var p := shape_path(shape_name)
	if ResourceLoader.exists(p):
		return load(p)
	return builtin_shapes().get(shape_name)


static func shape_name_of(s: SegmentShape) -> String:
	if s == null:
		return ""
	if NPCDefinition.is_library_shape(s):
		return s.resource_path.get_file().get_basename()
	return s.resource_name


## Da chiamare quando si aggiungono o tolgono file dalla libreria.
static func invalidate() -> void:
	_list_cache.clear()
	_users_cache.clear()
	version += 1


static var _users_cache := {}


## Nomi dei personaggi (file in CHARACTERS_DIR) che usano la forma di libreria `path`.
static func shape_users(path: String) -> PackedStringArray:
	if _users_cache.has(path):
		return _users_cache[path]
	var out := PackedStringArray()
	var dir := DirAccess.open(CHARACTERS_DIR)
	if dir != null:
		for f in dir.get_files():
			var fn := f.trim_suffix(".remap")
			if not fn.ends_with(".tres"):
				continue
			for dep in ResourceLoader.get_dependencies(CHARACTERS_DIR.path_join(fn)):
				if dep.ends_with(path) or dep.contains(path + "::") or dep.split("::")[-1] == path:
					out.append(fn.get_basename())
					break
	_users_cache[path] = out
	return out


# --- copia e ripristino ---------------------------------------------------------------
## Copia tutte le proprietà salvate (quelle che finiscono nel .tres) da una risorsa a
## un'altra dello stesso tipo, comprese quelle al valore predefinito.
static func copy_storage(from: Resource, to: Resource) -> void:
	for p in from.get_property_list():
		var pn: String = p.name
		if not (p.usage & PROPERTY_USAGE_STORAGE) or pn == "script" or pn.begins_with("resource_"):
			continue
		var v: Variant = from.get(pn)
		var cur: Variant = to.get(pn)
		# una sottorisorsa incorporata (le curve di una forma) si aggiorna dentro, così
		# l'oggetto e il suo id nel .tres restano gli stessi (niente rumore in git)
		if v is Resource and cur is Resource and v != cur and _embedded(v) and _embedded(cur) \
				and (v as Resource).get_class() == (cur as Resource).get_class() \
				and (v as Resource).get_script() == (cur as Resource).get_script():
			copy_storage(v, cur)
			(cur as Resource).emit_changed()
		else:
			to.set(pn, v)


static func _embedded(r: Resource) -> bool:
	return r.resource_path == "" or r.resource_path.contains("::")


## Riporta una risorsa (definizione o forma) com'è su disco, anche nelle proprietà al
## valore predefinito: ResourceLoader.CACHE_MODE_REPLACE non le tocca perché nel .tres
## non sono scritte. Gli oggetti in memoria restano gli stessi, quindi chi li usa (le
## guardie di un livello aperto, gli altri NPC) vede subito la versione su disco.
static func restore_from_disk(res: Resource) -> bool:
	if res == null:
		return false
	var path := res.resource_path
	if path == "" or path.contains("::") or not ResourceLoader.exists(path):
		return false
	var fresh := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if fresh == null or fresh.get_script() != res.get_script():
		return false
	copy_storage(fresh, res)
	return true


## Tutte le forme della libreria su disco, ordinate per nome: [[nome, forma], ...].
## L'elenco è in cache (vedi invalidate).
static func list_shapes(category := -1) -> Array:
	if _list_cache.has(category):
		return _list_cache[category]
	var out := []
	var names := PackedStringArray()
	var dir := DirAccess.open(SHAPES_DIR)
	if dir != null:
		for f in dir.get_files():
			var fn := f.trim_suffix(".remap")
			if fn.ends_with(".tres"):
				names.append(fn.get_basename())
	if names.is_empty():
		names = PackedStringArray(builtin_shapes().keys())
	names.sort()
	for n in names:
		var s := shape(n)
		if s != null and (category < 0 or s.category == category):
			out.append([n, s])
	_list_cache[category] = out
	return out


## Crea un accessorio dalla forma usando il suo aggancio predefinito.
static func attachment_from(shape_name: String, s: SegmentShape = null) -> NPCAttachment:
	if s == null:
		s = shape(shape_name)
	var lbl := shape_name.replace("_", " ").capitalize().replace("Calma", "CALMA")
	return NPCAttachment.create(lbl, s, s.attach_bone, s.attach_offset, s.attach_rotation, s.attach_length, s.attach_mirror)


# --- archetipi --------------------------------------------------------------------------
const PRESET_PARTS := {
	"guardia": {"testa": "testa", "collo": "collo", "torace": "torace_armatura", "addome": "addome", "bacino": "bacino",
		"braccio": "braccio", "avambraccio": "avambraccio_guanto", "mano": "mano_guanto", "coscia": "coscia",
		"stinco": "stinco_stivale", "piede": "piede_stivale"},
	"tecnico": {"testa": "testa", "collo": "collo", "torace": "torace", "addome": "addome", "bacino": "bacino",
		"braccio": "braccio", "avambraccio": "avambraccio_nudo", "mano": "mano", "coscia": "coscia",
		"stinco": "stinco_stivale", "piede": "piede_stivale"},
	"scienziato": {"testa": "testa_stretta", "collo": "collo", "torace": "torace_camice", "addome": "addome", "bacino": "bacino",
		"braccio": "braccio", "avambraccio": "avambraccio", "mano": "mano", "coscia": "coscia",
		"stinco": "stinco", "piede": "piede"},
	"dirigente": {"testa": "testa_squadrata", "collo": "collo", "torace": "torace", "addome": "addome", "bacino": "bacino",
		"braccio": "braccio", "avambraccio": "avambraccio", "mano": "mano", "coscia": "coscia",
		"stinco": "stinco", "piede": "piede"},
	"civile": {"testa": "testa", "collo": "collo", "torace": "torace", "addome": "addome", "bacino": "bacino",
		"braccio": "braccio", "avambraccio": "avambraccio_nudo", "mano": "mano", "coscia": "coscia",
		"stinco": "stinco", "piede": "piede"},
}
## Accessori: [forma, probabilità] (ordine = ordine di disegno).
const PRESET_ACC := {
	"guardia": [["casco", 1.0], ["visore", 1.0], ["impianto_calma", 1.0], ["colletto", 1.0], ["spallaccio", 0.6], ["cintura", 0.9], ["pistola", 1.0]],
	"tecnico": [["berretto", 0.5], ["visiera_berretto", 0.5], ["impianto_calma", 0.6], ["cintura", 0.9], ["cuffia", 0.3]],
	"scienziato": [["capelli", 0.9], ["falda_camice", 1.0], ["impianto_calma", 0.3]],
	"dirigente": [["capelli", 0.95]],
	"civile": [["capelli", 0.85], ["impianto_calma", 0.2]],
}
## Tavolozze curate per archetipo: [uniforme, secondario, armatura, stivali/guanti, luce].
## La prima è quella del preset; il generatore ne sceglie una e varia solo la luminosità,
## così le guardie restano riconoscibili come Seraph e i civili non diventano arcobaleni.
const PRESET_COLORS := {
	"guardia": [
		[Color(0.17, 0.19, 0.24), Color(0.10, 0.11, 0.13), Color(0.28, 0.30, 0.35), Color(0.07, 0.07, 0.08), Color(0.3, 0.9, 1.0)],
		[Color(0.15, 0.17, 0.21), Color(0.09, 0.10, 0.12), Color(0.24, 0.26, 0.30), Color(0.06, 0.06, 0.07), Color(0.3, 0.9, 1.0)],
	],
	"tecnico": [
		[Color(0.60, 0.40, 0.13), Color(0.52, 0.35, 0.12), Color(0.35, 0.35, 0.33), Color(0.12, 0.10, 0.08), Color(1.0, 0.7, 0.25)],
		[Color(0.62, 0.30, 0.10), Color(0.55, 0.27, 0.09), Color(0.35, 0.35, 0.33), Color(0.12, 0.10, 0.08), Color(1.0, 0.7, 0.25)],
		[Color(0.28, 0.33, 0.38), Color(0.24, 0.28, 0.33), Color(0.55, 0.45, 0.15), Color(0.10, 0.09, 0.08), Color(1.0, 0.7, 0.25)],
	],
	"scienziato": [
		[Color(0.82, 0.84, 0.85), Color(0.16, 0.17, 0.20), Color(0.50, 0.55, 0.60), Color(0.10, 0.08, 0.07), Color(0.4, 1.0, 0.6)],
		[Color(0.74, 0.80, 0.84), Color(0.22, 0.20, 0.18), Color(0.50, 0.55, 0.60), Color(0.12, 0.09, 0.07), Color(0.4, 1.0, 0.6)],
		[Color(0.86, 0.85, 0.80), Color(0.14, 0.16, 0.22), Color(0.50, 0.55, 0.60), Color(0.08, 0.07, 0.07), Color(0.4, 1.0, 0.6)],
	],
	"dirigente": [
		[Color(0.13, 0.13, 0.15), Color(0.12, 0.12, 0.14), Color(0.60, 0.12, 0.10), Color(0.06, 0.05, 0.05), Color(0.9, 0.9, 1.0)],
		[Color(0.11, 0.14, 0.22), Color(0.10, 0.13, 0.20), Color(0.55, 0.50, 0.40), Color(0.07, 0.05, 0.04), Color(0.9, 0.9, 1.0)],
		[Color(0.26, 0.21, 0.16), Color(0.23, 0.19, 0.15), Color(0.20, 0.30, 0.45), Color(0.10, 0.07, 0.05), Color(0.9, 0.9, 1.0)],
	],
	"civile": [
		[Color(0.30, 0.33, 0.28), Color(0.20, 0.22, 0.30), Color(0.40, 0.40, 0.40), Color(0.15, 0.12, 0.10), Color(0.3, 0.9, 1.0)],
		[Color(0.45, 0.20, 0.18), Color(0.18, 0.18, 0.20), Color(0.40, 0.40, 0.40), Color(0.10, 0.09, 0.09), Color(0.3, 0.9, 1.0)],
		[Color(0.52, 0.50, 0.44), Color(0.25, 0.23, 0.20), Color(0.40, 0.40, 0.40), Color(0.20, 0.14, 0.10), Color(0.3, 0.9, 1.0)],
		[Color(0.20, 0.30, 0.38), Color(0.14, 0.14, 0.16), Color(0.40, 0.40, 0.40), Color(0.12, 0.10, 0.10), Color(0.3, 0.9, 1.0)],
	],
}


## Definizione di base per un archetipo (senza variazioni casuali).
static func preset(arch: int) -> NPCDefinition:
	var key := ARCH_KEYS[clampi(arch, 0, ARCH_KEYS.size() - 1)]
	var d := NPCDefinition.new()
	d.archetype = arch
	d.display_name = ARCH_LABELS[arch]
	var parts: Dictionary[String, NPCPart] = {}
	var pp: Dictionary = PRESET_PARTS[key]
	for p in pp:
		parts[p] = NPCPart.new(shape(pp[p]))
	d.parts = parts
	var acc: Array[NPCAttachment] = []
	for a in PRESET_ACC[key]:
		acc.append(attachment_from(a[0]))
	d.attachments = acc
	var pc: Array = PRESET_COLORS[key][0]
	d.palette = PackedColorArray([SKIN_TONES[2], pc[0], pc[1], pc[2], pc[3], HAIR_COLORS[1], pc[4]])
	d.faction = "seraph_sicurezza" if key == "guardia" else "seraph_personale"
	if key != "guardia":
		d.max_health = 35.0
		d.ammo = 0
		d.accuracy = 0.4
		d.calls_for_help = true
	return d


# --- generatore casuale -----------------------------------------------------------------
## Nuovo NPC casuale dell'archetipo (stesso seme = stesso NPC).
static func random_npc(arch: int, rseed: int) -> NPCDefinition:
	var d := preset(arch)
	randomize_appearance(d, rseed, true)
	return d


## Rimescola l'aspetto (proporzioni, forme, accessori, colori); i dati di gameplay restano.
static func randomize_appearance(d: NPCDefinition, rseed: int, rename := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rseed
	var key := ARCH_KEYS[d.archetype]
	var guard := key == "guardia"
	d.random_seed = rseed
	d.height = snappedf(rng.randfn(1.78 if guard else 1.74, 0.06), 0.01)
	d.height = clampf(d.height, 1.55, 2.0)
	d.mass = snappedf(clampf(rng.randfn(1.05 if guard else 1.0, 0.08), 0.8, 1.35), 0.01)
	d.shoulders = snappedf(clampf(rng.randfn(1.04 if guard else 0.98, 0.06), 0.85, 1.25), 0.01)
	d.hips = snappedf(clampf(rng.randfn(1.0, 0.05), 0.85, 1.2), 0.01)
	d.arm_length = snappedf(clampf(rng.randfn(1.0, 0.03), 0.9, 1.1), 0.01)
	d.leg_length = snappedf(clampf(rng.randfn(1.0, 0.03), 0.9, 1.1), 0.01)
	d.head_size = snappedf(clampf(rng.randfn(1.0, 0.04), 0.9, 1.12), 0.01)
	d.neck_length = snappedf(clampf(rng.randfn(1.0, 0.1), 0.75, 1.3), 0.01)
	d.posture = snappedf(clampf(rng.randfn(-0.1 if guard else 0.1, 0.25), -0.8, 0.8), 0.01)
	# forme: preferisce le varianti dell'archetipo, altrimenti quelle generiche
	var base: Dictionary = PRESET_PARTS[key]
	var parts: Dictionary[String, NPCPart] = {}
	for p in NPCDefinition.PART_NAMES:
		var cands := []
		var preferred: String = base.get(p, p)
		var pref_tags := shape(preferred).tags if shape(preferred) != null else PackedStringArray()
		for e in list_shapes(_category_of(p)):
			var s: SegmentShape = e[1]
			# se la forma dell'archetipo ha dei tag (uniforme, stivali...) si pesca fra quelle
			# marcate per l'archetipo; altrimenti fra quelle generiche (senza tag)
			if (pref_tags.is_empty() and s.tags.is_empty()) or (not pref_tags.is_empty() and key in s.tags):
				cands.append(e)
		var pick: SegmentShape = shape(preferred)
		if cands.size() > 1 and rng.randf() < 0.45:
			pick = cands[rng.randi() % cands.size()][1]
		var part := NPCPart.new(pick)
		part.thickness = snappedf(clampf(rng.randfn(1.0, 0.04), 0.85, 1.2), 0.01)
		parts[p] = part
	d.parts = parts
	# accessori
	var acc: Array[NPCAttachment] = []
	var has_helmet := false
	for a in PRESET_ACC[key]:
		var nm: String = a[0]
		if nm == "visore" and not has_helmet:
			continue
		if nm == "visiera_berretto" and not _has_shape(acc, "berretto"):
			continue
		if rng.randf() <= float(a[1]):
			acc.append(attachment_from(nm))
			has_helmet = has_helmet or nm == "casco"
	if not has_helmet and not _has_shape(acc, "berretto") and not _has_shape(acc, "capelli") and rng.randf() < 0.85:
		acc.push_front(attachment_from("capelli_lunghi" if rng.randf() < 0.25 else "capelli"))
	d.attachments = acc
	# colori
	var pal := d.palette.duplicate()
	pal[S.PELLE] = SKIN_TONES[rng.randi() % SKIN_TONES.size()]
	pal[S.CAPELLI] = HAIR_COLORS[rng.randi() % HAIR_COLORS.size()]
	var variants: Array = PRESET_COLORS[key]
	var pc: Array = variants[rng.randi() % variants.size()]
	for i in 4:
		var c: Color = pc[i]
		var k := clampf(rng.randfn(1.0, 0.035 if guard else 0.07), 0.8, 1.2)
		pal[i + 1] = Color(clampf(c.r * k, 0, 1), clampf(c.g * k, 0, 1), clampf(c.b * k, 0, 1))
	pal[S.LUCE] = pc[4]
	d.palette = pal
	if rename:
		var title := TITLES[d.archetype]
		d.display_name = (title + " " if title != "" else "") + SURNAMES[rng.randi() % SURNAMES.size()]


static func _category_of(part: String) -> int:
	return NPCDefinition.PART_NAMES.find(part)


static func _has_shape(acc: Array, shape_name: String) -> bool:
	for a in acc:
		if shape_name_of(a.shape) == shape_name:
			return true
	return false
