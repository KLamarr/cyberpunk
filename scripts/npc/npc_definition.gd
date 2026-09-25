@tool
class_name NPCDefinition
extends Resource
## Definizione completa di un NPC: aspetto (proporzioni, forme, accessori, colori) e dati
## di gameplay (sensi, combattimento, comportamento, inventario, battute).
## Si crea e modifica con il creatore di NPC (scheda "NPC" dell'editor) e si salva come .tres;
## la guardia la legge in setup_def(). Tutto quello che serve a disegnarla è qui dentro:
## lo scheletro e la mesh vengono generati al caricamento (NPCBodyBuilder).

enum Archetype { GUARDIA, TECNICO, SCIENZIATO, DIRIGENTE, CIVILE }

const PART_NAMES: Array[String] = ["testa", "collo", "torace", "addome", "bacino", "braccio", "avambraccio", "mano", "coscia", "stinco", "piede"]
const SLOT_NAMES: Array[String] = ["Pelle", "Uniforme", "Secondario", "Armatura", "Stivali e guanti", "Capelli", "Luce (visore, CALMA)"]

## Aumenta a ogni modifica, anche delle forme e delle curve: invalida la cache delle mesh.
var revision := 0

@export_group("Identità")
@export var display_name := "Guardia":
	set(v):
		display_name = v
		_touch()
@export var archetype: Archetype = Archetype.GUARDIA:
	set(v):
		archetype = v
		_touch()
@export var faction := "seraph_sicurezza":
	set(v):
		faction = v
		_touch()
## Seme del generatore casuale che ha prodotto l'aspetto (0 = fatto a mano).
@export var random_seed := 0:
	set(v):
		random_seed = v
		_touch()

@export_group("Proporzioni")
## Altezza alla sommità della testa (casco escluso).
@export_range(1.4, 2.2, 0.01, "suffix:m") var height := 1.8:
	set(v):
		height = v
		_touch()
## Corporatura: moltiplica lo spessore di tutti i segmenti.
@export_range(0.7, 1.5, 0.01) var mass := 1.0:
	set(v):
		mass = v
		_touch()
@export_range(0.75, 1.35, 0.01) var shoulders := 1.0:
	set(v):
		shoulders = v
		_touch()
@export_range(0.75, 1.35, 0.01) var hips := 1.0:
	set(v):
		hips = v
		_touch()
@export_range(0.8, 1.2, 0.01) var arm_length := 1.0:
	set(v):
		arm_length = v
		_touch()
@export_range(0.8, 1.2, 0.01) var leg_length := 1.0:
	set(v):
		leg_length = v
		_touch()
@export_range(0.8, 1.3, 0.01) var head_size := 1.0:
	set(v):
		head_size = v
		_touch()
@export_range(0.6, 1.5, 0.01) var neck_length := 1.0:
	set(v):
		neck_length = v
		_touch()
## Postura: -1 impettito, 0 normale, 1 curvo.
@export_range(-1.0, 1.0, 0.01) var posture := 0.0:
	set(v):
		posture = v
		_touch()

@export_group("Colori")
## Tavolozza, un colore per ogni SegmentShape.Slot (vedi SLOT_NAMES).
@export var palette := PackedColorArray([
	Color(0.62, 0.45, 0.36), Color(0.19, 0.21, 0.26), Color(0.11, 0.12, 0.14),
	Color(0.30, 0.32, 0.37), Color(0.08, 0.08, 0.09), Color(0.12, 0.09, 0.07), Color(0.3, 0.9, 1.0)]):
	set(v):
		palette = v
		_touch()

@export_group("Forme")
@export var parts: Dictionary[String, NPCPart] = {}:
	set(v):
		for k in parts:
			_unwire(parts[k])
		parts = v
		for k in parts:
			_wire(parts[k])
		_touch()
@export var attachments: Array[NPCAttachment] = []:
	set(v):
		for a in attachments:
			_unwire(a)
		attachments = v
		for a in attachments:
			_wire(a)
		_touch()

@export_group("Sensi e combattimento")
@export_range(10.0, 300.0, 1.0) var max_health := 60.0:
	set(v):
		max_health = v
		_touch()
## Portata della vista.
@export_range(5.0, 40.0, 0.5, "suffix:m") var sight_range := 20.0:
	set(v):
		sight_range = v
		_touch()
## Semiampiezza del cono visivo pieno (oltre, fino a 100°, vede solo da vicino).
@export_range(20.0, 90.0, 1.0, "suffix:°") var fov_deg := 55.0:
	set(v):
		fov_deg = v
		_touch()
## Velocità con cui si accorge del giocatore che vede (1 = standard).
@export_range(0.2, 3.0, 0.05) var perception := 1.0:
	set(v):
		perception = v
		_touch()
## Moltiplicatore del raggio dei rumori che sente.
@export_range(0.2, 3.0, 0.05) var hearing := 1.0:
	set(v):
		hearing = v
		_touch()
## Probabilità base di colpire (scende con distanza, movimento e buio).
@export_range(0.1, 1.0, 0.01) var accuracy := 0.8:
	set(v):
		accuracy = v
		_touch()
@export_range(0.0, 100.0, 0.5) var damage_min := 8.0:
	set(v):
		damage_min = v
		_touch()
@export_range(0.0, 100.0, 0.5) var damage_max := 13.0:
	set(v):
		damage_max = v
		_touch()
## Tempo medio fra il momento in cui ti vede e il primo sparo.
@export_range(0.1, 3.0, 0.05, "suffix:s") var reaction_time := 0.7:
	set(v):
		reaction_time = v
		_touch()
@export_range(0.5, 4.0, 0.05, "suffix:m/s") var walk_speed := 1.8:
	set(v):
		walk_speed = v
		_touch()
@export_range(1.0, 8.0, 0.05, "suffix:m/s") var run_speed := 4.0:
	set(v):
		run_speed = v
		_touch()

@export_group("Comportamento")
@export var investigates_noises := true:
	set(v):
		investigates_noises = v
		_touch()
@export var reacts_to_bodies := true:
	set(v):
		reacts_to_bodies = v
		_touch()
@export var responds_to_alarms := true:
	set(v):
		responds_to_alarms = v
		_touch()
## In combattimento grida e richiama le altre guardie.
@export var calls_for_help := true:
	set(v):
		calls_for_help = v
		_touch()

@export_group("Inventario")
@export_range(0, 99) var ammo := 6:
	set(v):
		ammo = v
		_touch()
@export_range(0, 999) var credits := 20:
	set(v):
		credits = v
		_touch()
@export_range(0, 9) var medpatch := 0:
	set(v):
		medpatch = v
		_touch()
## Tessera (id usato da porte e terminali, es. "sicurezza") e nome mostrato al giocatore.
@export var keycard_id := "":
	set(v):
		keycard_id = v
		_touch()
@export var keycard_name := "":
	set(v):
		keycard_name = v
		_touch()

@export_group("Voce")
## Battute di ronda, una per riga (vuoto = quelle standard della guardia).
@export var idle_barks := PackedStringArray():
	set(v):
		idle_barks = v
		_touch()


func _touch() -> void:
	revision += 1
	emit_changed()


func _on_sub_changed() -> void:
	_touch()


func _wire(r: Resource) -> void:
	if r != null and not r.changed.is_connected(_on_sub_changed):
		r.changed.connect(_on_sub_changed)


func _unwire(r: Resource) -> void:
	if r != null and r.changed.is_connected(_on_sub_changed):
		r.changed.disconnect(_on_sub_changed)


# --- modifica da codice (il creatore passa da qui) ------------------------------------
func set_part(key: String, part: NPCPart) -> void:
	if parts.has(key):
		_unwire(parts[key])
	if part == null:
		parts.erase(key)
	else:
		parts[key] = part
		_wire(part)
	_touch()


func get_part(key: String) -> NPCPart:
	return parts.get(key)


func add_attachment(a: NPCAttachment) -> void:
	attachments.append(a)
	_wire(a)
	_touch()


func remove_attachment(a: NPCAttachment) -> void:
	_unwire(a)
	attachments.erase(a)
	_touch()


func color(slot: int) -> Color:
	if slot >= 0 and slot < palette.size():
		return palette[slot]
	return Color.MAGENTA


func set_color(slot: int, c: Color) -> void:
	var p := palette.duplicate()
	while p.size() <= slot:
		p.append(Color.GRAY)
	p[slot] = c
	palette = p


## Copia indipendente: le parti e gli accessori vengono duplicati, le forme della
## libreria (file .tres esterni) restano condivise, quelle "uniche" vengono copiate.
func clone() -> NPCDefinition:
	var d: NPCDefinition = duplicate(false)
	var np: Dictionary[String, NPCPart] = {}
	for k in parts:
		var p: NPCPart = parts[k].duplicate(false)
		p.shape = _dup_if_local(parts[k].shape)
		p.shape_b = _dup_if_local(parts[k].shape_b)
		np[k] = p
	d.parts = np
	var na: Array[NPCAttachment] = []
	for a in attachments:
		var c: NPCAttachment = a.duplicate(false)
		c.shape = _dup_if_local(a.shape)
		na.append(c)
	d.attachments = na
	return d


static func _dup_if_local(s: SegmentShape) -> SegmentShape:
	if s == null or is_library_shape(s):
		return s
	return s.duplicate(true)


## Una forma è "di libreria" se è salvata in un suo file .tres (non incorporata).
static func is_library_shape(s: Resource) -> bool:
	return s != null and s.resource_path != "" and not s.resource_path.contains("::")


# --- dati per il gameplay ---------------------------------------------------------------
## Bottino nel formato usato da Guard._give_loot().
func loot() -> Dictionary:
	var l := {}
	if keycard_id != "":
		l["keycard"] = [keycard_id, keycard_name if keycard_name != "" else "Tessera " + keycard_id.capitalize()]
	if ammo > 0:
		l["ammo"] = ammo
	if credits > 0:
		l["credits"] = credits
	if medpatch > 0:
		l["medpatch"] = medpatch
	return l


func eye_height() -> float:
	return NPCRig.layout(self).eye_height


## Sopra questa quota (dai piedi) un colpo è alla testa.
func head_height() -> float:
	return NPCRig.layout(self).neck_top


func top_height() -> float:
	return NPCRig.layout(self).top
