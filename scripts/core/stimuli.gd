class_name Stimuli
extends RefCounted
## STIMOLI E RECETTORI, come l'Act/React del Dark Engine: le cose del mondo emettono
## stimoli e chi ha il «recettore» giusto reagisce. Così i sistemi si parlano senza
## conoscersi: la bottiglia non sa che esistono le guardie, sa solo che rompendosi fa
## rumore e lascia dei cocci; le guardie non sanno che esistono le bottiglie, sanno solo
## sentire i rumori e camminare sulle superfici.
##
## EVENTI (istantanei)            recettore (chi reagisce)
##   rumore   Game.emit_noise()    guardie: hear()
##   colpo    Stimuli.hit()        chi ha take_damage(): luci, telecamere, torrette,
##                                 grate, oggetti fisici (bottiglie, estintori...)
##   scossa   Stimuli.shock()      guardie e giocatore: on_shock()
##
## CAMPI (durano nel tempo: chi percepisce li interroga)
##   SHARDS   cocci di vetro: passi rumorosi, anche accovacciati   (surface_at)
##   WATER    pozza d'acqua: passi rumorosi; conduce la corrente   (surface_at, process_water)
##   CURRENT  corrente scoperta (scintille, cavi): elettrifica l'acqua che tocca
##   SMOKE    nube: blocca la vista di guardie, telecamere e torrette (smoke_between)
##
## Stessa regola per tutti: anche le guardie fanno rumore sui cocci, prendono la scossa
## nell'acqua elettrificata e non vedono attraverso il fumo.
##
## Ogni campo appartiene al nodo che l'ha creato (la bottiglia rotta possiede i suoi
## cocci, il cavo la sua corrente): è quel nodo a salvarlo nel suo save_state e a
## toglierlo quando esce dalla scena. I campi non si salvano da soli.

const SHARDS := &"shards"
const WATER := &"water"
const CURRENT := &"current"
const SMOKE := &"smoke"

## Tensione della corrente (Field.strength dei campi CURRENT).
const LOW_VOLTAGE := 1    # fa svenire (KO): non conta come uccisione
const HIGH_VOLTAGE := 2   # mortale

## Fumo oltre questa opacità: la vista è bloccata del tutto.
const SMOKE_BLOCKS := 0.85


## Un campo: un disco sul pavimento (cocci, acqua, corrente) o una sfera (fumo).
class Field extends RefCounted:
	var kind: StringName
	## Per i campi a terra è il punto sul pavimento; per il fumo il centro della nube.
	var center := Vector3.ZERO
	var radius := 1.0
	## Fumo: opacità 0..1. Corrente: LOW_VOLTAGE o HIGH_VOLTAGE. Altri: 1.
	var strength := 1.0
	## Il nodo che l'ha creato e lo salva.
	var source: Node


static var _fields: Array[Field] = []
## Ultima scossa data a ogni attore (instance id -> secondi di gioco), per non darne
## una a ogni fotogramma.
static var _last_shock := {}


# --- campi --------------------------------------------------------------------------
static func add_field(kind: StringName, center: Vector3, radius: float, strength: float, source: Node) -> Field:
	var f := Field.new()
	f.kind = kind
	f.center = center
	f.radius = radius
	f.strength = strength
	f.source = source
	_fields.append(f)
	return f


static func remove_field(f: Field) -> void:
	if f != null:
		_fields.erase(f)


## Toglie tutti i campi (a ogni livello caricato: i nodi che li possedevano non ci sono più).
static func clear() -> void:
	_fields.clear()
	_last_shock.clear()


static func fields(kind: StringName) -> Array[Field]:
	var out: Array[Field] = []
	for f in _fields:
		if f.kind == kind and is_instance_valid(f.source):
			out.append(f)
	return out


## Il punto p (i piedi di qualcuno) è dentro il disco a terra del campo?
static func on_floor_field(f: Field, p: Vector3) -> bool:
	var d := Vector2(p.x - f.center.x, p.z - f.center.z).length()
	return d <= f.radius and absf(p.y - f.center.y) < 0.5


## Il primo campo di quel tipo sotto i piedi in p (null se non c'è).
static func floor_field_at(kind: StringName, p: Vector3) -> Field:
	for f in fields(kind):
		if on_floor_field(f, p):
			return f
	return null


## Superficie speciale sotto i piedi: "glass" (cocci), "water" (pozza) o "" (quella del
## pavimento, vedi Level.surface_at).
static func surface_at(p: Vector3) -> String:
	if floor_field_at(SHARDS, p) != null:
		return "glass"
	if floor_field_at(WATER, p) != null:
		return "water"
	return ""


## Quanto fumo c'è sulla linea da a a b: 0 = niente, 1 = muro di fumo.
static func smoke_between(a: Vector3, b: Vector3) -> float:
	var total := 0.0
	for f in fields(SMOKE):
		if f.strength <= 0.01:
			continue
		var chord := _chord(a, b, f.center, f.radius)
		if chord <= 0.0:
			continue
		# dentro la nube (o attraverso tutto il suo spessore) = opacità piena
		var inside := a.distance_to(f.center) < f.radius or b.distance_to(f.center) < f.radius
		var k := 1.0 if inside else clampf(chord / f.radius, 0.0, 1.0)
		total += f.strength * k
	return clampf(total, 0.0, 1.0)


## Lunghezza del tratto del segmento a-b dentro la sfera (centro c, raggio r).
static func _chord(a: Vector3, b: Vector3, c: Vector3, r: float) -> float:
	var d := b - a
	var len2 := d.length_squared()
	if len2 < 0.0001:
		return 0.0
	var t := clampf((c - a).dot(d) / len2, 0.0, 1.0)
	var closest := a + d * t
	var dist := closest.distance_to(c)
	if dist >= r:
		return 0.0
	var half := sqrt(r * r - dist * dist)
	var seg := sqrt(len2)
	var t0 := clampf(t * seg - half, 0.0, seg)
	var t1 := clampf(t * seg + half, 0.0, seg)
	return t1 - t0


## Tensione dell'acqua di una pozza: la più alta fra le correnti che la toccano (0 = niente).
static func voltage_of(water: Field) -> int:
	var v := 0
	for c in fields(CURRENT):
		var d := Vector2(c.center.x - water.center.x, c.center.z - water.center.z).length()
		if d <= water.radius + c.radius and absf(c.center.y - water.center.y) < 0.8:
			v = maxi(v, int(c.strength))
	return v


## Da chiamare ogni ~0,1 s da chi possiede una pozza: se è elettrificata dà la scossa a
## chi ci sta dentro (guardie comprese). Ritorna la tensione (0 = acqua innocua).
static func process_water(water: Field) -> int:
	var v := voltage_of(water)
	if v <= 0:
		return 0
	for a in actors():
		if a.is_on_floor() and on_floor_field(water, a.global_position):
			shock(a, v, a.global_position)
	return v


## Chi può prendere la scossa: il giocatore e le guardie in piedi.
static func actors() -> Array[Node]:
	var out: Array[Node] = []
	if Game.player != null and is_instance_valid(Game.player) and not Game.player.dead:
		out.append(Game.player)
	for g in Game.get_tree().get_nodes_in_group("guards"):
		if g.is_active():
			out.append(g)
	return out


# --- eventi -------------------------------------------------------------------------
## Colpo su un oggetto del mondo (il collider o un suo genitore con take_damage).
## Gli attori (giocatore e guardie) sono esclusi se exclude_actors: un oggetto lanciato
## li distrae col rumore, non li ferisce. Ritorna il nodo colpito (o null).
static func hit(collider: Node, amount: float, pos: Vector3, dir: Vector3, kind: String, exclude_actors := true) -> Node:
	if collider == null or amount < 1.0:
		return null
	var t := Util.find_method_owner(collider, "take_damage")
	if t == null:
		return null
	if exclude_actors and (t is Player or t is Guard):
		return null
	t.take_damage(amount, pos, dir, kind)
	return t


## Scossa elettrica: il bersaglio reagisce con on_shock(tensione, punto). Al massimo
## una scossa ogni 0,8 s per bersaglio.
static func shock(target: Node, voltage: int, pos: Vector3) -> void:
	if target == null or not target.has_method("on_shock"):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var id := target.get_instance_id()
	if now - float(_last_shock.get(id, -10.0)) < 0.8:
		return
	_last_shock[id] = now
	target.on_shock(voltage, pos)
	Effects.sparks(pos + Vector3.UP * 0.4, Color(0.55, 0.8, 1.0), 16, 3.0)
	Sfx.play_3d("zap", pos + Vector3.UP * 0.5, 2.0)
	Game.emit_noise(pos, 9.0, "zap", target)


# --- servizio -----------------------------------------------------------------------
## La superficie fissa sotto p: pavimento o mobili (gli oggetti che si spostano no, se
## no i cocci resterebbero a mezz'aria quando la cassa sotto si sposta). Con
## through_props l'acqua scende oltre i mobili (tavoli, distributore) fino al pavimento
## della stanza.
static func floor_below(space: PhysicsDirectSpaceState3D, p: Vector3, exclude: Array[RID] = [], through_props := false) -> Vector3:
	var ex: Array[RID] = exclude.duplicate()
	var from := p + Vector3.UP * 0.1
	for i in 6:
		var hit := Util.ray(space, from, from + Vector3.DOWN * 8.0, Layers.WORLD, ex)
		if hit.is_empty():
			return p
		var c: Object = hit.collider
		var is_room := c is Node and (c as Node).name == "GeometriaCompilata"
		if through_props and not is_room and c is CollisionObject3D:
			ex.append((c as CollisionObject3D).get_rid())
			continue
		return hit.position
	return p
