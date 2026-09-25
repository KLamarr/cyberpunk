class_name LightFixture
extends StaticBody3D
## Luce di gioco: OmniLight3D + plafoniera colpibile.
## Tutte le LightFixture stanno nel gruppo "game_lights": il player somma i loro
## contributi (con raycast di occlusione) per calcolare quanto è visibile.
## Sparare o colpire la plafoniera la rompe: meno luce, ma rumore di vetri.

## le energie visive sono più alte di quelle "di gioco": questo le riporta in scala
const VIS_SCALE := 0.6

var light: OmniLight3D
var base_energy := 1.0
var light_range := 6.0
var color := Color.WHITE
var flicker := 0.0        # 0 = stabile; 0..1 = frequenza dello sfarfallio
var zones := 1
var style := "panel"      # panel | lamp | none
var shadows := false
var emergency := false    # luce rossa che si accende solo in lockdown
var is_on := true
var broken := false
var dim := 1.0

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _flick := 1.0
var _flick_t := 0.0
var _t := 0.0


func setup(pos: Vector3, col: Color, energy: float, rng: float, zone_mask: int, opts := {}) -> LightFixture:
	position = pos
	color = col
	base_energy = energy
	light_range = rng
	zones = zone_mask
	flicker = opts.get("flicker", 0.0)
	style = opts.get("style", "panel")
	shadows = opts.get("shadows", false)
	emergency = opts.get("emergency", false)
	is_on = not emergency
	return self


func _ready() -> void:
	add_to_group("game_lights")
	collision_layer = Game.L_DEVICE
	collision_mask = 0
	light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = base_energy if is_on else 0.0
	light.omni_range = light_range
	light.omni_attenuation = 0.75
	light.light_cull_mask = zones
	light.shadow_enabled = shadows
	light.light_specular = 0.3
	light.position = Vector3(0, -0.2 if style == "panel" else 0.0, 0)
	light.visible = is_on
	add_child(light)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	match style:
		"panel":
			_mat.albedo_texture = Util.tex("light_panel")
			_mesh = Util.box(self, Vector3(1.0, 0.06, 0.5), Vector3.ZERO, _mat)
			Util.add_box_collider(self, Vector3(1.0, 0.1, 0.5))
		"lamp":
			_mesh = Util.box(self, Vector3(0.18, 0.12, 0.18), Vector3.ZERO, _mat)
			Util.add_box_collider(self, Vector3(0.2, 0.15, 0.2))
		_:
			pass
	_mesh_set_on(is_on)


func _mesh_set_on(on: bool) -> void:
	if _mat == null:
		return
	var c: Color = color.lerp(Color.WHITE, 0.5) if on else Color(0.12, 0.12, 0.13)
	_mat.albedo_color = c


func _process(delta: float) -> void:
	if not is_on or broken:
		return
	_t += delta
	if emergency:
		# lampeggio rotante
		light.light_energy = base_energy * (0.35 + 0.65 * absf(sin(_t * 2.6)))
		return
	if flicker > 0.0:
		_flick_t -= delta
		if _flick_t <= 0.0:
			if randf() < flicker * 0.5:
				_flick = randf_range(0.0, 0.5)
				_flick_t = randf_range(0.04, 0.15)
			else:
				_flick = 1.0
				_flick_t = randf_range(0.1, 1.2) / max(flicker, 0.05)
		light.light_energy = base_energy * _flick * dim
		_mesh_set_on(_flick > 0.5)
	else:
		light.light_energy = base_energy * dim


## Contributo di luce nel punto p (per la visibilità del player).
func light_contribution(p: Vector3) -> float:
	if not is_on or broken or light.light_energy <= 0.01:
		return 0.0
	var lp := light.global_position
	var d := p.distance_to(lp)
	if d >= light_range:
		return 0.0
	var w := 1.0 - pow(d / light_range, 4.0)
	w *= w
	var c := light.light_energy * VIS_SCALE * w / maxf(d, 1.0)
	if c < 0.01:
		return 0.0
	var space := get_world_3d().direct_space_state
	if not Util.ray_clear(space, lp, p, Game.L_WORLD | Game.L_DOOR, [get_rid()]):
		return 0.0
	return c


func set_on(on: bool) -> void:
	if broken and on:
		return
	is_on = on
	light.visible = on
	light.light_energy = base_energy * dim if on else 0.0
	_mesh_set_on(on)


func set_dim(f: float) -> void:
	dim = f


func take_damage(_amount: float, hit_pos: Vector3, _dir: Vector3, _kind: String) -> void:
	if broken or style == "none":
		return
	broken = true
	set_on(false)
	Sfx.play_3d("glass_break", global_position, 2.0)
	Game.emit_noise(global_position, 12.0, "glass", Game.player)
	Effects.sparks(global_position if hit_pos == Vector3.ZERO else hit_pos, Color(1, 0.9, 0.6))
