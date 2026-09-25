@tool
class_name NPCRig
extends RefCounted
## Scheletro comune a tutti gli NPC: 17 ossa le cui posizioni derivano dalle proporzioni
## della NPCDefinition. Le ossa hanno rotazione di riposo nulla (assi allineati al modello):
## ruotare un osso attorno a X porta avanti braccia e gambe (angolo positivo), quindi la
## stessa animazione vale per qualunque NPC, alto, basso, massiccio o esile.
## Il personaggio guarda verso -Z; la sua destra è +X.

const BONES: Array[String] = [
	"hips", "spine", "chest", "neck", "head",
	"upperarm_l", "forearm_l", "hand_l", "upperarm_r", "forearm_r", "hand_r",
	"thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r",
]
const PARENTS: Array[String] = [
	"", "hips", "spine", "chest", "neck",
	"chest", "upperarm_l", "forearm_l", "chest", "upperarm_r", "forearm_r",
	"hips", "thigh_l", "shin_l", "hips", "thigh_r", "shin_r",
]
## Etichette italiane per il creatore.
const BONE_LABELS := {
	"hips": "Bacino", "spine": "Addome", "chest": "Torace", "neck": "Collo", "head": "Testa",
	"upperarm_l": "Braccio sx", "forearm_l": "Avambraccio sx", "hand_l": "Mano sx",
	"upperarm_r": "Braccio dx", "forearm_r": "Avambraccio dx", "hand_r": "Mano dx",
	"thigh_l": "Coscia sx", "shin_l": "Stinco sx", "foot_l": "Piede sx",
	"thigh_r": "Coscia dx", "shin_r": "Stinco dx", "foot_r": "Piede dx",
}
## Parte del corpo → osso (i nomi senza lato valgono per sinistra e destra).
const PART_BONE := {
	"testa": "head", "collo": "neck", "torace": "chest", "addome": "spine", "bacino": "hips",
	"braccio": "upperarm", "avambraccio": "forearm", "mano": "hand",
	"coscia": "thigh", "stinco": "shin", "piede": "foot",
}


class Segment:
	var part: String       ## "testa", "braccio", ...
	var bone: String       ## osso effettivo ("upperarm_l")
	var from: Vector3      ## inizio del segmento (articolazione), spazio modello, pose di riposo
	var to: Vector3        ## fine del segmento
	var radial := Vector2.ONE  ## scala dei raggi (x, z) data da corporatura e proporzioni
	var left := false


class Layout:
	var scale := 1.0
	var pos := {}          ## osso → posizione globale di riposo
	var segments: Array[Segment] = []
	var radial := {}       ## osso → scala radiale (x, z) del segmento, anche per gli accessori
	var lengthscale := {}  ## osso → scala delle lunghezze (per gli accessori)
	var eye_height := 1.72
	var neck_top := 1.55
	var top := 1.8

	func bone_index(n: String) -> int:
		return BONES.find(n)


static var _cache := {}


## Layout dello scheletro per la definizione (in cache finché la definizione non cambia).
static func layout(def: NPCDefinition) -> Layout:
	var key := def.get_instance_id()
	var c: Array = _cache.get(key, [])
	if not c.is_empty() and c[0] == def.revision:
		return c[1]
	var l := compute(def)
	# le definizioni liberate (livello riavviato, NPC chiusi) escono subito dalla cache
	for k in _cache.keys():
		if not is_instance_id_valid(k):
			_cache.erase(k)
	_cache[key] = [def.revision, l]
	return l


static func compute(def: NPCDefinition) -> Layout:
	var lf := def.leg_length
	var af := def.arm_length
	var hs := def.head_size
	var nk := def.neck_length
	# quote "grezze" per un corpo di riferimento, poi tutto viene scalato sull'altezza
	var ankle := 0.08
	var knee := ankle + 0.44 * lf
	var hipj := knee + 0.42 * lf
	var pelvis := hipj + 0.04
	var chest := pelvis + 0.22
	var neck := chest + 0.27
	var head := neck + 0.095 * nk
	var head_len := 0.22 * hs
	var raw_top := head + head_len
	var s := def.height / raw_top
	var sw := 0.205 * def.shoulders
	var hw := 0.095 * def.hips
	var ua := 0.29 * af
	var fa := 0.26 * af
	var hand_len := 0.17 * af

	var l := Layout.new()
	l.scale = s
	var p := {}
	p["hips"] = Vector3(0, pelvis, 0)
	p["spine"] = Vector3(0, pelvis + 0.03, 0)
	p["chest"] = Vector3(0, chest, 0)
	p["neck"] = Vector3(0, neck, 0.01)
	p["head"] = Vector3(0, head, 0.0)
	for side in [-1.0, 1.0]:
		var sfx := "_l" if side < 0.0 else "_r"
		var sh := Vector3(sw * side, neck - 0.035, 0.0)
		p["upperarm" + sfx] = sh
		p["forearm" + sfx] = sh + Vector3(0.012 * side, -ua, 0.0)
		p["hand" + sfx] = sh + Vector3(0.02 * side, -ua - fa, -0.01)
		p["thigh" + sfx] = Vector3(hw * side, hipj, 0.0)
		p["shin" + sfx] = Vector3(hw * side * 0.95, knee, 0.0)
		p["foot" + sfx] = Vector3(hw * side * 0.9, ankle, 0.01)
	for k in p:
		l.pos[k] = p[k] * s

	var seg_def := [
		# parte, osso, da, a, scala radiale (x, z)
		["bacino", "hips", p.hips + Vector3(0, 0.01, 0), Vector3(0, hipj - 0.07, 0), Vector2(def.hips, 1.0)],
		["addome", "spine", p.spine, p.chest, Vector2((def.hips + def.shoulders) * 0.5, 1.0)],
		["torace", "chest", p.chest, p.neck, Vector2(def.shoulders, 1.0)],
		["collo", "neck", p.neck, p.head, Vector2.ONE],
		["testa", "head", p.head, p.head + Vector3(0, head_len, 0), Vector2(hs, hs)],
	]
	for side in [-1.0, 1.0]:
		var sfx := "_l" if side < 0.0 else "_r"
		seg_def.append(["braccio", "upperarm" + sfx, p["upperarm" + sfx], p["forearm" + sfx], Vector2.ONE])
		seg_def.append(["avambraccio", "forearm" + sfx, p["forearm" + sfx], p["hand" + sfx], Vector2.ONE])
		seg_def.append(["mano", "hand" + sfx, p["hand" + sfx], p["hand" + sfx] + Vector3(0.005 * side, -hand_len, -0.01), Vector2.ONE])
		seg_def.append(["coscia", "thigh" + sfx, p["thigh" + sfx], p["shin" + sfx], Vector2.ONE])
		seg_def.append(["stinco", "shin" + sfx, p["shin" + sfx], p["foot" + sfx], Vector2.ONE])
		var fx: float = p["foot" + sfx].x
		seg_def.append(["piede", "foot" + sfx, Vector3(fx, 0.048, 0.035), Vector3(fx, 0.045, -0.17), Vector2.ONE])
	for sd in seg_def:
		var sg := Segment.new()
		sg.part = sd[0]
		sg.bone = sd[1]
		sg.from = sd[2] * s
		sg.to = sd[3] * s
		var part: NPCPart = def.get_part(sg.part)
		var thick := part.thickness if part != null else 1.0
		var head_part: bool = sg.part == "testa"
		sg.radial = sd[4] * (s * thick * (1.0 if head_part else def.mass))
		sg.left = sg.bone.ends_with("_l")
		l.segments.append(sg)
		l.radial[sg.bone] = sg.radial
		l.lengthscale[sg.bone] = s * (hs if head_part else 1.0)
	l.eye_height = (head + head_len * 0.58) * s
	l.neck_top = (head - 0.02) * s
	l.top = raw_top * s
	return l


static func mirror_bone(b: String) -> String:
	if b.ends_with("_l"):
		return b.substr(0, b.length() - 2) + "_r"
	if b.ends_with("_r"):
		return b.substr(0, b.length() - 2) + "_l"
	return b
