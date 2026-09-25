extends CanvasLayer
## HUD: gemma di visibilità, rumore, salute, arma/munizioni, mirino e prompt di
## interazione, messaggi, sottotitoli, allarme, lampo di danno.

class LightGem extends Control:
	var vis := 0.0
	var noise := 0.0

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := Vector2(w * 0.5, h * 0.5)
		var pts := PackedVector2Array([Vector2(0, h * 0.5), Vector2(w * 0.25, 0), Vector2(w * 0.75, 0), Vector2(w, h * 0.5), Vector2(w * 0.75, h), Vector2(w * 0.25, h)])
		var dark := Color(0.04, 0.05, 0.05)
		var lit := Color(1.0, 0.97, 0.75)
		var fill := dark.lerp(lit, clampf(vis, 0.0, 1.0))
		draw_colored_polygon(pts, fill)
		# sfaccettature
		var facet := Color(0, 0, 0, 0.25)
		draw_line(Vector2(w * 0.25, 0), c, facet, 1.0)
		draw_line(Vector2(w * 0.75, 0), c, facet, 1.0)
		draw_line(Vector2(w * 0.25, h), c, facet, 1.0)
		draw_line(Vector2(w * 0.75, h), c, facet, 1.0)
		draw_line(Vector2(0, h * 0.5), Vector2(w, h * 0.5), facet, 1.0)
		var hl := PackedVector2Array([Vector2(w * 0.25, 2), Vector2(w * 0.5, 2), Vector2(w * 0.38, h * 0.3)])
		draw_colored_polygon(hl, Color(1, 1, 1, 0.12 + 0.3 * vis))
		pts.append(pts[0])
		draw_polyline(pts, UITheme.BORDER.darkened(0.2), 2.0)
		# indicatore di rumore: archi ai lati
		if noise > 0.02:
			var a := clampf(noise, 0.0, 1.0)
			var col := Color(1.0, 0.75, 0.3, a)
			for i in 3:
				var r := h * 0.55 + i * 7.0
				if a > i * 0.3:
					draw_arc(c, r + w * 0.3, deg_to_rad(160), deg_to_rad(200), 6, col, 2.0)
					draw_arc(c, r + w * 0.3, deg_to_rad(-20), deg_to_rad(20), 6, col, 2.0)


class Bar extends Control:
	var value := 1.0
	var col := Color(0.4, 1.0, 0.6)
	var segments := 20

	func _draw() -> void:
		var sw := (size.x - (segments - 1) * 2.0) / segments
		for i in segments:
			var on := float(i) / segments < value - 0.001
			var c := col if on else Color(col.r, col.g, col.b, 0.12)
			draw_rect(Rect2(i * (sw + 2.0), 0, sw, size.y), c)


class Crosshair extends Control:
	var active := false

	func _draw() -> void:
		var c := size * 0.5
		var col := UITheme.ACCENT if active else Color(0.8, 0.95, 0.9, 0.6)
		if active:
			draw_arc(c, 7.0, 0, TAU, 12, col, 1.5)
		draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), col)


var root: Control
var gem: LightGem
var health_bar: Bar
var health_label: Label
var weapon_label: Label
var ammo_label: Label
var items_label: Label
var prompt: Label
var crosshair: Crosshair
var msg_box: VBoxContainer
var sub_speaker: Label
var sub_text: Label
var sub_panel: PanelContainer
var alarm_label: Label
var flash: ColorRect
var _sub_timer := 0.0
var _noise := 0.0
var _flash_a := 0.0
var _heart_t := 0.0
var _blink := 0.0


func _ready() -> void:
	layer = 1
	Game.hud = self
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # i testi passano già da tr()
	add_child(root)

	flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(0.8, 0.05, 0.02, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)

	crosshair = Crosshair.new()
	_place(crosshair, Control.PRESET_CENTER, Rect2(-12, -12, 24, 24))
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)

	prompt = UITheme.label("", 18, UITheme.ACCENT)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(prompt, Control.PRESET_CENTER, Rect2(-350, 26, 700, 30))
	prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt.add_theme_constant_override("outline_size", 6)
	root.add_child(prompt)

	# gemma in basso al centro
	gem = LightGem.new()
	_place(gem, Control.PRESET_CENTER_BOTTOM, Rect2(-36, -58, 72, 34))
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(gem)

	# salute in basso a sinistra
	var hp_box := VBoxContainer.new()
	_place(hp_box, Control.PRESET_BOTTOM_LEFT, Rect2(24, -92, 330, 76))
	hp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hp_box)
	health_label = UITheme.label("", 15, UITheme.TEXT)
	hp_box.add_child(health_label)
	health_bar = Bar.new()
	health_bar.custom_minimum_size = Vector2(240, 12)
	hp_box.add_child(health_bar)
	items_label = UITheme.label("", 14, UITheme.DIM)
	hp_box.add_child(items_label)

	# arma in basso a destra
	var w_box := VBoxContainer.new()
	_place(w_box, Control.PRESET_BOTTOM_RIGHT, Rect2(-284, -92, 260, 76))
	w_box.alignment = BoxContainer.ALIGNMENT_END
	w_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(w_box)
	weapon_label = UITheme.label("", 15, UITheme.TEXT)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	w_box.add_child(weapon_label)
	ammo_label = UITheme.label("", 26, UITheme.ACCENT)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	w_box.add_child(ammo_label)

	# messaggi in alto a sinistra
	msg_box = VBoxContainer.new()
	msg_box.position = Vector2(20, 18)
	msg_box.size = Vector2(700, 200)
	msg_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(msg_box)

	# allarme in alto al centro
	alarm_label = UITheme.label("", 22, UITheme.DANGER)
	alarm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alarm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(alarm_label, Control.PRESET_TOP_RIGHT, Rect2(-560, 16, 540, 30))
	root.add_child(alarm_label)

	# sottotitoli
	sub_panel = PanelContainer.new()
	sub_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0, 0, 0, 0.6), Color(0, 0, 0, 0), 0, 8))
	_place(sub_panel, Control.PRESET_CENTER_BOTTOM, Rect2(-420, -168, 840, 70))
	sub_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sub_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_panel.visible = false
	root.add_child(sub_panel)
	var sv := VBoxContainer.new()
	sub_panel.add_child(sv)
	sub_speaker = UITheme.label("", 14, UITheme.ACCENT)
	sub_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(sub_speaker)
	sub_text = UITheme.label("", 18, Color.WHITE, true)
	sub_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_text.custom_minimum_size.x = 800
	sv.add_child(sub_text)

	Game.message.connect(_on_message)
	Game.subtitle.connect(_on_subtitle)
	Game.player_damaged.connect(_on_damage)


func _place(c: Control, preset: int, r: Rect2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x
	c.offset_bottom = r.position.y + r.size.y


func on_noise(radius: float) -> void:
	_noise = maxf(_noise, clampf(radius / 14.0, 0.0, 1.0))


func _on_message(text: String, color: Color) -> void:
	var l := UITheme.label(text, 16, color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	msg_box.add_child(l)
	while msg_box.get_child_count() > 6:
		msg_box.get_child(0).queue_free()
		msg_box.remove_child(msg_box.get_child(0))
	var tw := l.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(l.queue_free)


func _on_subtitle(speaker: String, text: String, duration: float) -> void:
	sub_speaker.text = speaker
	sub_text.text = text
	sub_panel.visible = true
	_sub_timer = duration
	if speaker == tr("VESPER") or speaker == tr("PA SYSTEM"):   # voci via radio
		Sfx.play_ui("radio", -8.0)


func _on_damage(amount: float, _from: Vector3) -> void:
	_flash_a = clampf(_flash_a + amount / 40.0, 0.0, 0.55)


func _process(delta: float) -> void:
	var p: Node = Game.player
	root.visible = Game.state == Game.State.PLAYING or Game.state == Game.State.PANEL
	if _sub_timer > 0.0:
		_sub_timer -= delta
		if _sub_timer <= 0.0:
			sub_panel.visible = false
	_flash_a = maxf(_flash_a - delta * 0.8, 0.0)
	flash.color.a = _flash_a
	_noise = maxf(_noise - delta * 0.7, 0.0)
	if p == null or not is_instance_valid(p):
		return
	gem.vis = p.visibility
	gem.noise = _noise
	gem.queue_redraw()
	var hp_frac: float = p.health / p.max_health
	health_bar.value = hp_frac
	health_bar.col = UITheme.GOOD if hp_frac > 0.5 else (UITheme.ACCENT if hp_frac > 0.25 else UITheme.DANGER)
	health_bar.queue_redraw()
	health_label.text = tr("HEALTH %d / %d") % [int(ceil(p.health)), int(p.max_health)]
	items_label.text = tr("MEDIPATCH x%d [H]   MODULES %d   CREDITS %d") % [Game.medpatches, Game.modules, Game.credits]
	if p.weapon == 0:
		weapon_label.text = tr("WRENCH")
		ammo_label.text = "—"
	else:
		weapon_label.text = tr("9mm PISTOL") + ("  " + tr("(reloading...)") if p.reloading > 0.0 else "")
		ammo_label.text = "%d / %d" % [Game.ammo_mag, Game.ammo_reserve]
	var pr: String = p.get_frob_prompt()
	prompt.text = pr
	crosshair.active = pr != ""
	crosshair.queue_redraw()
	_blink += delta
	if Game.alarm_time > 0.0:
		alarm_label.text = tr("ALARM  %ds") % int(ceil(Game.alarm_time))
		alarm_label.modulate.a = 0.6 + 0.4 * absf(sin(_blink * 5.0))
	elif Game.lockdown:
		alarm_label.text = tr("LOCKDOWN — GET BACK TO THE ELEVATOR")
		alarm_label.modulate.a = 0.5 + 0.3 * absf(sin(_blink * 2.0))
	else:
		alarm_label.text = ""
	# battito cardiaco a bassa salute
	if hp_frac < 0.3 and not p.dead:
		_heart_t -= delta
		if _heart_t <= 0.0:
			_heart_t = 0.9
			Sfx.play_ui("heartbeat", -6.0)
