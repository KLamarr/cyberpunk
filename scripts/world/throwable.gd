@tool
class_name Throwable
extends RigidBody3D
## Oggetto fisico raccoglibile e lanciabile. Quando urta qualcosa abbastanza forte fa
## rumore (il modo classico per distrarre una guardia) e colpisce quello che tocca: una
## bottiglia lanciata rompe una lampada, una scatola può rompere una telecamera.
## Il comportamento viene dal suo MATERIALE (PropMaterial, in assets/prop_materials): peso,
## Forza necessaria, rumore, danni e cosa diventa quando si rompe:
##   cocci (bottiglia)   rumorosi per chiunque ci cammini sopra, guardie comprese;
##   pozza (tanica)      rumorosa, e conduce la corrente (vedi Stimuli, LiveCable);
##   nube (estintore)    blocca la vista di guardie, telecamere e torrette.
## Rotto, il nodo resta nella scena come «effetto» (i cocci, la pozza, la nube): così
## si salva da sé, come tutto il resto.

## can: lattina. bottle: bottiglia (si rompe in cocci). box: scatola da 4 kg.
## heavy: cassa SB-14 da 40 kg (Forza 2). jug: tanica d'acqua da 12 kg (si rompe in
## una pozza). extinguisher: estintore (colpito o lanciato fa una nube di fumo).
@export_enum("can", "bottle", "box", "heavy", "jug", "extinguisher") var kind := "can":
	set(v):
		kind = v
		_apply_kind()
		_editor_rebuild()
## Materiale: vuoto = quello del Kind (assets/prop_materials/<kind>.tres). Trascina qui un
## altro PropMaterial per un oggetto che si comporta diversamente (più pesante, fragile...).
@export var material: PropMaterial:
	set(v):
		material = v
		_apply_kind()

## Nomi in inglese, tradotti in get_frob_text().
# i18n
const NAMES := {
	"can": "Kaffa-Nova can", "bottle": "Bottle", "box": "Parts box", "heavy": "SB-14 crate",
	"jug": "Water jug", "extinguisher": "Fire extinguisher",
}
## Durata dell'allargarsi della pozza e del gonfiarsi della nube (s).
const SPREAD_TIME := 1.4
## Negli ultimi secondi la nube si dirada.
const SMOKE_FADE := 4.0

var mat: PropMaterial
var display: String = NAMES.can
var shape_kind := "can"
var size := Vector3(0.07, 0.13, 0.07)
var tex := ""
var col := Color(0.7, 0.1, 0.1)
var held := false
## Rotto: ora è cocci, una pozza o un estintore scarico (con la sua nube).
var broken := false
## Dove sono i cocci, la pozza o la nube.
var fx_pos := Vector3.ZERO
## Secondi dall'inizio dell'effetto (la pozza si allarga, la nube si dirada).
var fx_t := 0.0

var _field: Stimuli.Field
var _fx: Node3D
var _puddle_mat: StandardMaterial3D
var _smoke: CPUParticles3D
var _last_speed := 0.0
var _cooldown := 0.0
var _tick := 0.0
var _zap_cd := 0.0


func setup(pos: Vector3, k: String) -> Throwable:
	position = pos
	kind = k
	return self


## Il materiale in uso: quello scelto, o quello del Kind.
func get_mat() -> PropMaterial:
	if material != null:
		return material
	var p := "res://assets/prop_materials/%s.tres" % kind
	return load(p) if ResourceLoader.exists(p) else PropMaterial.new()


func _apply_kind() -> void:
	mat = get_mat()
	mass = mat.mass
	shape_kind = kind
	display = NAMES.get(kind, "Object")
	tex = ""
	match kind:
		"can":
			size = Vector3(0.07, 0.13, 0.07)
			col = [Color(0.75, 0.1, 0.12), Color(0.1, 0.5, 0.75), Color(0.85, 0.7, 0.1)][randi() % 3]
		"bottle":
			size = Vector3(0.08, 0.28, 0.08)
			col = Color(0.25, 0.55, 0.35)
		"box":
			size = Vector3(0.45, 0.32, 0.35)
			tex = "crate_light"
		"heavy":
			size = Vector3(0.8, 0.7, 0.8)
			tex = "crate"
		"jug":
			size = Vector3(0.28, 0.45, 0.28)
			col = Color(0.3, 0.52, 0.8)
		"extinguisher":
			size = Vector3(0.17, 0.5, 0.17)
			col = Color(0.72, 0.08, 0.06)


func _ready() -> void:
	_apply_kind()
	_build()
	if Engine.is_editor_hint():
		return
	add_to_group("throwables")
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	body_entered.connect(_on_body_entered)


func _editor_rebuild() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		for c in get_children():
			if c.owner == null:
				remove_child(c)
				c.queue_free()
		_build()


func _build() -> void:
	collision_layer = Layers.PROP
	collision_mask = Layers.WORLD | Layers.DOOR | Layers.GLASS | Layers.PROP | Layers.NPC | Layers.PLAYER | Layers.DEVICE
	var m: Material
	if tex != "":
		m = Util.mat(tex, {"fit": size})
	else:
		m = Util.color_mat(col)
	var cs := CollisionShape3D.new()
	if shape_kind in ["can", "bottle", "jug", "extinguisher"]:
		Util.cylinder(self, size.x * 0.5, size.y, Vector3.ZERO, m, Vector3.ZERO, 8 if shape_kind == "jug" else 6)
		var cyl := CylinderShape3D.new()
		cyl.radius = size.x * 0.5
		cyl.height = size.y
		cs.shape = cyl
		var dark := Util.color_mat(Color(0.1, 0.1, 0.11))
		if shape_kind == "jug":
			Util.cylinder(self, 0.045, 0.06, Vector3(0, size.y * 0.5 + 0.03, 0), Util.color_mat(Color(0.15, 0.3, 0.7)), Vector3.ZERO, 6)
		elif shape_kind == "extinguisher":
			Util.box(self, Vector3(0.05, 0.08, 0.05), Vector3(0, size.y * 0.5 + 0.04, 0), dark)
			Util.box(self, Vector3(0.14, 0.02, 0.03), Vector3(0.04, size.y * 0.5 + 0.08, 0), dark)
			Util.box(self, Vector3(0.025, 0.28, 0.025), Vector3(-0.1, 0.05, 0), dark, Vector3(0, 0, -8))
		elif shape_kind == "bottle":
			Util.cylinder(self, 0.018, 0.08, Vector3(0, size.y * 0.5 + 0.04, 0), m, Vector3.ZERO, 6)
	else:
		Util.box(self, size, Vector3.ZERO, m)
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
	add_child(cs)


func _exit_tree() -> void:
	Stimuli.remove_field(_field)
	_field = null


# --- fisica e urti -------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_last_speed = linear_velocity.length()
	_cooldown -= delta
	if broken:
		_update_fx(delta)


func _on_body_entered(body: Node) -> void:
	# urti lenti: contano solo se l'oggetto è pesante (una cassa da 40 kg che cade si sente)
	if held or (_last_speed < 2.2 and 0.5 * mass * _last_speed * _last_speed < 20.0):
		return
	if broken and mat.breaks_into != "smoke":
		return   # cocci e pozze non urtano più niente (l'estintore scarico sì)
	var speed := _last_speed
	if _cooldown <= 0.0:
		# un solo rumore per urto, anche se tocca più cose insieme
		_cooldown = 0.3
		var radius := clampf(3.0 + speed * 1.5, 4.0, 16.0) * mat.impact_noise
		if mass > 10.0:
			radius = maxf(radius, 7.0 * mat.impact_noise)   # un tonfo pesante si sente comunque
		Game.emit_noise(global_position, radius, "impact", self)
		Sfx.play_3d(mat.impact_sound, global_position, clampf(speed - 6.0, -10.0, 3.0))
	# l'urto colpisce tutto quello che tocca: energia cinetica × danno del materiale
	var dmg := 0.5 * mass * speed * speed * 0.4 * mat.impact_damage
	var dir := linear_velocity.normalized() if linear_velocity.length() > 0.1 else Vector3.DOWN
	if body != self:
		Stimuli.hit(body, dmg, global_position, dir, "impact")
	if mat.breaks() and mat.break_speed > 0.0 and speed >= mat.break_speed:
		shatter()


## Colpito da chiave inglese, proiettili o altri oggetti lanciati.
func take_damage(amount: float, _hit_pos: Vector3, _dir: Vector3, _kind: String) -> void:
	if broken or not mat.breaks():
		return
	if amount >= mat.break_damage:
		shatter()


## Si rompe: diventa cocci, una pozza o scarica la sua nube di fumo.
func shatter() -> void:
	if broken or not mat.breaks():
		return
	if held and Game.player != null:
		Game.player.drop_held_now()
	var space := get_world_3d().direct_space_state
	match mat.breaks_into:
		"shards":
			fx_pos = Stimuli.floor_below(space, global_position, [get_rid()])
			Sfx.play_3d("glass_break", global_position, 0.0)
			Game.emit_noise(global_position, 11.0 * mat.impact_noise, "glass", self)
		"water":
			fx_pos = Stimuli.floor_below(space, global_position, [get_rid()], true)
			Sfx.play_3d("splash", global_position, 2.0)
			Game.emit_noise(global_position, 9.0 * mat.impact_noise, "splash", self)
		"smoke":
			fx_pos = global_position
			Sfx.play_3d("hiss", global_position, 3.0)
			Game.emit_noise(global_position, 13.0, "hiss", self)
			# lo sfiato fa volare via l'estintore
			var kick := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 2.5 + Vector3.UP * 1.5
			apply_central_impulse(kick * mass)
			angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	_set_broken(0.0)


## Stato «rotto» (anche dal salvataggio, senza suoni né rumore).
func _set_broken(t: float) -> void:
	broken = true
	fx_t = t
	Util.set_highlight(self, false)
	if mat.breaks_into == "smoke" and t >= mat.effect_duration:
		return   # la nube si è già diradata
	if mat.breaks_into != "smoke":
		# cocci e pozza: l'oggetto sparisce, resta l'effetto (la fisica si cambia fuori
		# dalla risposta all'urto, vedi _disable_body)
		for c in get_children():
			if c is MeshInstance3D:
				c.visible = false
		_disable_body.call_deferred()
	_build_fx()


func _disable_body() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0
	for c in get_children():
		if c is CollisionShape3D:
			c.disabled = true


func _build_fx() -> void:
	if _fx != null:
		_fx.queue_free()
	_fx = Node3D.new()
	_fx.name = "Effetto"
	_fx.top_level = true
	add_child(_fx)
	_fx.global_transform = Transform3D(Basis(), fx_pos)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(name))
	match mat.breaks_into:
		"shards":
			var glass := Util.color_mat(col.lerp(Color.WHITE, 0.35), 0.5)
			for i in 16:
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf()) * mat.effect_radius * 0.85
				Util.box(_fx, Vector3(rng.randf_range(0.03, 0.08), 0.008, rng.randf_range(0.02, 0.06)),
					Vector3(cos(a) * r, 0.006, sin(a) * r), glass, Vector3(0, rng.randf() * 360.0, 0))
			_field = Stimuli.add_field(Stimuli.SHARDS, fx_pos, mat.effect_radius, 1.0, self)
		"water":
			_puddle_mat = StandardMaterial3D.new()
			_puddle_mat.albedo_color = Color(0.14, 0.22, 0.32, 0.5)
			_puddle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_puddle_mat.roughness = 0.05
			_puddle_mat.metallic_specular = 1.0
			_puddle_mat.emission_enabled = true
			_puddle_mat.emission = Color(0.3, 0.6, 1.0)
			_puddle_mat.emission_energy_multiplier = 0.0
			Util.cylinder(_fx, 1.0, 0.01, Vector3(0, 0.012, 0), _puddle_mat, Vector3.ZERO, 14)
			_field = Stimuli.add_field(Stimuli.WATER, fx_pos, _puddle_radius(), 1.0, self)
		"smoke":
			_smoke = CPUParticles3D.new()
			_smoke.amount = 56
			_smoke.lifetime = 2.6
			_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			_smoke.emission_sphere_radius = mat.effect_radius * 0.65
			_smoke.direction = Vector3.UP
			_smoke.spread = 180.0
			_smoke.initial_velocity_min = 0.1
			_smoke.initial_velocity_max = 0.45
			_smoke.gravity = Vector3(0, 0.08, 0)
			_smoke.scale_amount_min = 1.2
			_smoke.scale_amount_max = 2.2
			var grad := Gradient.new()
			grad.set_color(0, Color(0.8, 0.82, 0.84, 0.0))
			grad.set_color(1, Color(0.8, 0.82, 0.84, 0.0))
			grad.add_point(0.25, Color(0.8, 0.82, 0.84, 0.55))
			grad.add_point(0.7, Color(0.75, 0.77, 0.8, 0.45))
			_smoke.color_ramp = grad
			var q := QuadMesh.new()
			q.size = Vector2(1.1, 1.1)
			var sm := StandardMaterial3D.new()
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.vertex_color_use_as_albedo = true
			sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			sm.albedo_texture = _puff_texture()
			sm.roughness = 1.0
			q.material = sm
			_smoke.mesh = q
			_smoke.preprocess = minf(fx_t, 2.0)
			_smoke.emitting = fx_t < mat.effect_duration - SMOKE_FADE
			_fx.add_child(_smoke)
			_field = Stimuli.add_field(Stimuli.SMOKE, fx_pos, _smoke_radius(), _smoke_strength(), self)
	if Game.level != null:
		Util.set_layers_recursive(_fx, Game.level.zone_mask_at(fx_pos + Vector3.UP * 0.3))
	_apply_fx_size()


func _puddle_radius() -> float:
	return lerpf(0.3, mat.effect_radius, smoothstep(0.0, SPREAD_TIME, fx_t))


func _smoke_radius() -> float:
	return lerpf(mat.effect_radius * 0.4, mat.effect_radius, smoothstep(0.0, SPREAD_TIME, fx_t))


func _smoke_strength() -> float:
	var left := mat.effect_duration - fx_t
	return clampf(left / SMOKE_FADE, 0.0, 1.0)


func _apply_fx_size() -> void:
	if _fx == null or _field == null:
		return
	match mat.breaks_into:
		"water":
			_field.radius = _puddle_radius()
			var r := _field.radius
			(_fx.get_child(0) as Node3D).scale = Vector3(r, 1.0, r)
		"smoke":
			_field.radius = _smoke_radius()
			_field.strength = _smoke_strength()


func _update_fx(delta: float) -> void:
	fx_t += delta
	match mat.breaks_into:
		"water":
			if fx_t < SPREAD_TIME + 0.1:
				_apply_fx_size()
			_tick -= delta
			_zap_cd -= delta
			if _tick <= 0.0 and _field != null:
				_tick = 0.1
				var v := Stimuli.process_water(_field)
				_puddle_mat.emission_energy_multiplier = randf_range(0.1, 0.45) if v > 0 else 0.0
				if v > 0:
					var a := randf() * TAU
					var r := sqrt(randf()) * _field.radius
					Effects.sparks(fx_pos + Vector3(cos(a) * r, 0.03, sin(a) * r), Color(0.55, 0.8, 1.0), 5, 1.2)
					if _zap_cd <= 0.0:
						_zap_cd = 0.9
						Sfx.play_3d("spark", fx_pos, -4.0)
		"smoke":
			if _field == null:
				return
			_apply_fx_size()
			if _smoke != null and _smoke.emitting and fx_t >= mat.effect_duration - SMOKE_FADE:
				_smoke.emitting = false
			if fx_t >= mat.effect_duration:
				Stimuli.remove_field(_field)
				_field = null
				if _fx != null:
					_fx.queue_free()
					_fx = null
					_smoke = null


## Sbuffo morbido e tondo per le particelle del fumo (16×16, generato una volta).
static var _puff: Texture2D
static func _puff_texture() -> Texture2D:
	if _puff == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 16:
				var d := Vector2(x - 7.5, y - 7.5).length() / 7.5
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d * d, 0.0, 1.0)))
		_puff = ImageTexture.create_from_image(img)
	return _puff


# --- frob ------------------------------------------------------------------------------
func _name_text() -> String:
	if broken and mat.breaks_into == "smoke":
		return tr("Fire extinguisher (empty)")
	return tr(display)


func get_frob_text() -> String:
	if broken and mat.breaks_into != "smoke":
		return ""
	if Game.skill("forza") < mat.strength_required:
		return tr("%s — too heavy (Strength %d)") % [_name_text(), mat.strength_required]
	return tr("Take: %s") % _name_text()


func frob(player: Node) -> void:
	if broken and mat.breaks_into != "smoke":
		return
	if Game.skill("forza") < mat.strength_required:
		Game.notify(tr("Too heavy. You need Strength %d.") % mat.strength_required, Color(1, 0.7, 0.4))
		return
	player.pick_up(self)


# --- salvataggi ----------------------------------------------------------------------
func save_state() -> Dictionary:
	return {"xf": global_transform, "lv": linear_velocity, "av": angular_velocity, "broken": broken, "fx_pos": fx_pos, "fx_t": fx_t}


## Se era in mano al giocatore ci pensa il player (Player.load_state).
func load_state(d: Dictionary) -> void:
	global_transform = d.xf
	linear_velocity = d.lv   # un oggetto lanciato continua il volo (e fa rumore dove cade)
	angular_velocity = d.av
	if bool(d.broken) and not broken and mat.breaks():
		fx_pos = d.fx_pos
		_set_broken(float(d.fx_t))


func set_held(on: bool) -> void:
	held = on
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = on
	if on:
		collision_layer = 0
	else:
		collision_layer = Layers.PROP
