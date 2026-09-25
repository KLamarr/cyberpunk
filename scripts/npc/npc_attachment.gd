@tool
class_name NPCAttachment
extends Resource
## Accessorio agganciato rigidamente a un osso: casco, visore, impianto CALMA,
## spallacci, cintura, pistola... È un segmento come gli altri (stessa SegmentShape),
## solo che posizione, direzione e lunghezza le decide l'accessorio e non lo scheletro.

@export var label := "Accessorio":
	set(v):
		label = v
		emit_changed()
@export var enabled := true:
	set(v):
		enabled = v
		emit_changed()
@export var shape: SegmentShape:
	set(v):
		if shape != null and shape.changed.is_connected(emit_changed):
			shape.changed.disconnect(emit_changed)
		shape = v
		if v != null and not v.changed.is_connected(emit_changed):
			v.changed.connect(emit_changed)
		emit_changed()
## Osso a cui è agganciato (vedi NPCRig.BONES). Con mirror, un osso "_l"/"_r" vale per i
## due lati; su un osso centrale (testa, torace...) si aggiunge la copia speculare
## rispetto al centro del corpo (per esempio le due cuffie).
@export var bone: String = "head":
	set(v):
		bone = v
		emit_changed()
@export var mirror := false:
	set(v):
		mirror = v
		emit_changed()
## Posizione dell'attacco rispetto all'origine dell'osso, in metri per un corpo di 1,80 m.
@export var offset := Vector3.ZERO:
	set(v):
		offset = v
		emit_changed()
## Direzione del segmento: (0, 0, 0) = verso l'alto; X = 90 lo punta all'indietro.
@export var rotation_deg := Vector3.ZERO:
	set(v):
		rotation_deg = v
		emit_changed()
@export_range(0.005, 1.5, 0.005, "suffix:m") var length := 0.1:
	set(v):
		length = v
		emit_changed()


## Nel creatore di NPC le forme di libreria sono bloccate finché non si attiva
## «Modifica la libreria»: nell'Inspector la forma resta visibile ma non modificabile.
static var library_locked := true


func _validate_property(property: Dictionary) -> void:
	if property.name == "bone":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(NPCRig.BONES)
	if property.name == "shape" and library_locked and NPCDefinition.is_library_shape(shape):
		property.usage |= PROPERTY_USAGE_READ_ONLY


static func create(lbl: String, s: SegmentShape, b: String, off: Vector3, rot: Vector3, len: float, mir := false) -> NPCAttachment:
	var a := NPCAttachment.new()
	a.label = lbl
	a.shape = s
	a.bone = b
	a.offset = off
	a.rotation_deg = rot
	a.length = len
	a.mirror = mir
	return a
