@tool
class_name SegmentShape
extends Resource
## Forma di un segmento del corpo: un "loft" di anelli low-poly lungo l'asse di un osso
## (vedi NPCBodyBuilder). Le curve di profilo danno il raggio in funzione della
## posizione lungo il segmento (0 = attacco, 1 = estremità) e si modificano con
## l'editor di curve dell'Inspector; tutto il resto sono numeri che il creatore di NPC
## espone come controlli. Le forme stanno in una libreria (assets/npc/segments) e sono
## condivise fra gli NPC: modificarne una cambia tutti quelli che la usano.

enum Category { TESTA, COLLO, TORACE, ADDOME, BACINO, BRACCIO, AVAMBRACCIO, MANO, COSCIA, STINCO, PIEDE, ACCESSORIO }
## Riga dell'atlante npc_atlas.png (dettaglio in scala di grigi, tinto dal colore).
enum Band { TESSUTO, ARMATURA, PELLE, VOLTO, GOMMA, METALLO, LUCE, CAPELLI }
## Colore della tavolozza dell'NPC. LUCE è emissivo e cambia con lo stato (visore, CALMA).
enum Slot { PELLE, UNIFORME, SECONDARIO, ARMATURA, STIVALI, CAPELLI, LUCE }

const BAND_COUNT := 8
const CURVE_MAX := 1.6

## Per quale parte del corpo è pensata: il creatore la propone solo lì.
@export var category: Category = Category.ACCESSORIO:
	set(v):
		category = v
		emit_changed()
## Archetipi (guardia, tecnico, ...) per cui il generatore casuale può sceglierla.
@export var tags: PackedStringArray = PackedStringArray():
	set(v):
		tags = v
		emit_changed()

@export_group("Profilo")
## Semilarghezza (asse X) lungo il segmento, moltiplicata per radius_x.
@export var width_curve: Curve:
	set(v):
		_swap_curve(width_curve, v)
		width_curve = v
		emit_changed()
## Semiprofondità (asse Z) lungo il segmento, moltiplicata per radius_z.
@export var depth_curve: Curve:
	set(v):
		_swap_curve(depth_curve, v)
		depth_curve = v
		emit_changed()
## Spostamento in avanti dell'anello, in frazioni di radius_z (pancia, mento, punta del piede).
@export var bulge_curve: Curve:
	set(v):
		_swap_curve(bulge_curve, v)
		bulge_curve = v
		emit_changed()
@export_range(0.005, 0.5, 0.001, "suffix:m") var radius_x := 0.08:
	set(v):
		radius_x = v
		emit_changed()
@export_range(0.005, 0.5, 0.001, "suffix:m") var radius_z := 0.08:
	set(v):
		radius_z = v
		emit_changed()
## Anelli lungo il segmento (più anelli = profilo più fedele alle curve).
@export_range(2, 16) var rings := 4:
	set(v):
		rings = clampi(v, 2, 16)
		emit_changed()
## Lati di ogni anello (6–8 per il look System Shock 2).
@export_range(3, 16) var sides := 6:
	set(v):
		sides = clampi(v, 3, 16)
		emit_changed()
## Quanto il segmento sporge oltre l'articolazione, in frazioni della lunghezza:
## le sovrapposizioni evitano le fessure quando l'arto si piega.
@export_range(0.0, 0.6, 0.01) var extend_start := 0.05:
	set(v):
		extend_start = v
		emit_changed()
@export_range(0.0, 0.6, 0.01) var extend_end := 0.05:
	set(v):
		extend_end = v
		emit_changed()
@export var cap_start := false:
	set(v):
		cap_start = v
		emit_changed()
@export var cap_end := false:
	set(v):
		cap_end = v
		emit_changed()
## Normali morbide (Gouraud, come i personaggi di SS2); spento = sfaccettato.
@export var smooth := true:
	set(v):
		smooth = v
		emit_changed()
## Sezione non ellittica: moltiplicatore del raggio per ogni lato
## (indice 0 = dietro, sides/2 = davanti). Vuoto = ellisse.
@export var section := PackedFloat32Array():
	set(v):
		section = v
		emit_changed()

@export_group("Materiale")
@export var band: Band = Band.TESSUTO:
	set(v):
		band = v
		emit_changed()
@export var color_slot: Slot = Slot.UNIFORME:
	set(v):
		color_slot = v
		emit_changed()
## Da questo punto (0..1) in poi il segmento usa band_b e color_slot_b (guanti, stivali).
@export_range(0.0, 1.0, 0.01) var split := 1.0:
	set(v):
		split = v
		emit_changed()
@export var band_b: Band = Band.GOMMA:
	set(v):
		band_b = v
		emit_changed()
@export var color_slot_b: Slot = Slot.STIVALI:
	set(v):
		color_slot_b = v
		emit_changed()

@export_group("Aggancio predefinito (accessori)")
## Dove va l'accessorio quando lo si aggiunge dal creatore (poi è modificabile nell'NPC).
## (l'elenco delle ossa viene da NPCRig.BONES, vedi _validate_property)
@export var attach_bone: String = "head"
@export var attach_offset := Vector3.ZERO
@export var attach_rotation := Vector3.ZERO
@export_range(0.005, 1.5, 0.005, "suffix:m") var attach_length := 0.1
@export var attach_mirror := false
## La punta di questa forma è la bocca di un'arma: la guardia spara da lì.
@export var is_weapon := false:
	set(v):
		is_weapon = v
		emit_changed()


func _validate_property(property: Dictionary) -> void:
	if property.name == "attach_bone":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(NPCRig.BONES)


func _swap_curve(old: Curve, new: Curve) -> void:
	if old != null and old.changed.is_connected(emit_changed):
		old.changed.disconnect(emit_changed)
	if new != null and not new.changed.is_connected(emit_changed):
		new.changed.connect(emit_changed)


# --- campionamento --------------------------------------------------------------------
## Raggi (x, z) in metri alla posizione t (0..1) lungo il segmento.
func radius_at(t: float) -> Vector2:
	return Vector2(_sample(width_curve, t, 1.0) * radius_x, _sample(depth_curve, t, 1.0) * radius_z)


func bulge_at(t: float) -> float:
	return _sample(bulge_curve, t, 0.0) * radius_z


## Moltiplicatore della sezione per il lato i di un anello a n lati
## (la sezione salvata viene ricampionata se ha un numero di lati diverso).
func section_at(i: int, n: int) -> float:
	var m := section.size()
	if m == 0:
		return 1.0
	if m == n:
		return section[i % m]
	var f := float(i) / float(n) * m
	var a := int(floor(f)) % m
	var b := (a + 1) % m
	return lerpf(section[a], section[b], f - floor(f))


static func _sample(c: Curve, t: float, fallback: float) -> float:
	if c == null or c.point_count == 0:
		return fallback
	return c.sample(clampf(t, 0.0, 1.0))


# --- costruzione da codice --------------------------------------------------------------
## Curva di profilo a tratti lineari: points = [Vector2(t, valore), ...].
static func make_curve(points: Array) -> Curve:
	var c := Curve.new()
	c.min_value = 0.0
	c.max_value = CURVE_MAX
	for p in points:
		c.add_point(p, 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return c


static func make_bulge_curve(points: Array) -> Curve:
	var c := Curve.new()
	c.min_value = -1.0
	c.max_value = 1.0
	for p in points:
		c.add_point(p, 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return c


## Sezione simmetrica a partire da metà profilo (da dietro a davanti, sides/2 + 1 valori).
static func symmetric_section(half: Array) -> PackedFloat32Array:
	var n := (half.size() - 1) * 2
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var j := i if i <= n / 2 else n - i
		out[i] = half[j]
	return out


## Crea una forma con i parametri più comuni; opts sovrascrive le proprietà.
static func create(cat: Category, rx: float, rz: float, width: Array, depth: Array = [], opts := {}) -> SegmentShape:
	var s := SegmentShape.new()
	s.category = cat
	s.radius_x = rx
	s.radius_z = rz
	s.width_curve = make_curve(width)
	s.depth_curve = make_curve(depth if not depth.is_empty() else width)
	for k in opts:
		if k == "bulge":
			s.bulge_curve = make_bulge_curve(opts[k])
		else:
			s.set(k, opts[k])
	return s
