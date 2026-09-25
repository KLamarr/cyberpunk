@tool
extends Control
## Editor della sezione di un segmento: l'anello visto lungo l'osso, con il davanti in
## alto. Trascina un vertice per allontanarlo o avvicinarlo all'asse; con la simmetria
## attiva il vertice speculare segue. Il contorno tratteggiato è l'ellisse di partenza.
## Durante il trascinamento emette section_edited (anteprima dal vivo); al rilascio
## section_committed (una sola voce di annulla).

signal section_edited(section: PackedFloat32Array)
signal section_committed(old_section: PackedFloat32Array, section: PackedFloat32Array)

var symmetric := true
## false = solo da guardare (forma di libreria protetta).
var editable := true:
	set(v):
		editable = v
		_hover = -1
		_drag = -1
		queue_redraw()
var _shape: SegmentShape
var _vals := PackedFloat32Array()
var _start := PackedFloat32Array()
var _drag := -1
var _hover := -1


func _init() -> void:
	custom_minimum_size = Vector2(200, 190)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Sezione del segmento vista lungo l'osso (davanti in alto).\nTrascina i vertici; doppio clic per riportarne uno sull'ellisse."


func set_shape(s: SegmentShape) -> void:
	_shape = s
	_reload()


func _reload() -> void:
	_vals = PackedFloat32Array()
	if _shape != null:
		var n := _shape.sides
		_vals.resize(n)
		for i in n:
			_vals[i] = _shape.section_at(i, n)
	queue_redraw()


func refresh() -> void:
	if _drag < 0:
		_reload()


func _geom() -> Array:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.34
	var ax := 1.0
	var az := 1.0
	if _shape != null:
		var m := maxf(_shape.radius_x, _shape.radius_z)
		ax = _shape.radius_x / m
		az = _shape.radius_z / m
	return [c, r, ax, az]


func _point(i: int, v: float) -> Vector2:
	var g := _geom()
	var n := _vals.size()
	var th := TAU * float(i) / float(n)
	var c: Vector2 = g[0]
	var r: float = g[1]
	# indice 0 = dietro (in basso), n/2 = davanti (in alto)
	return c + Vector2(sin(th) * float(g[2]), cos(th) * float(g[3])) * r * v


func _draw() -> void:
	var bg := get_theme_color("dark_color_2", "Editor") if has_theme_color("dark_color_2", "Editor") else Color(0.1, 0.1, 0.12)
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	var font := get_theme_default_font()
	var fs := get_theme_default_font_size()
	var dim := Color(1, 1, 1, 0.35)
	if _shape == null or _vals.is_empty():
		draw_string(font, Vector2(8, size.y * 0.5), "Nessuna forma selezionata", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)
		return
	var g := _geom()
	var n := _vals.size()
	draw_line(Vector2(g[0].x, 6), Vector2(g[0].x, size.y - 6), Color(1, 1, 1, 0.08))
	draw_line(Vector2(6, g[0].y), Vector2(size.x - 6, g[0].y), Color(1, 1, 1, 0.08))
	draw_string(font, Vector2(g[0].x - 26, 14), "davanti", HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, dim)
	draw_string(font, Vector2(g[0].x - 20, size.y - 6), "dietro", HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, dim)
	var ell := PackedVector2Array()
	for k in 49:
		var th := TAU * k / 48.0
		ell.append(g[0] + Vector2(sin(th) * g[2], cos(th) * g[3]) * g[1])
	for k in range(0, 48, 2):
		draw_line(ell[k], ell[k + 1], Color(1, 1, 1, 0.25))
	var poly := PackedVector2Array()
	for i in n:
		poly.append(_point(i, _vals[i]))
	poly.append(poly[0])
	var accent := get_theme_color("accent_color", "Editor") if has_theme_color("accent_color", "Editor") else Color(0.4, 0.7, 1.0)
	draw_colored_polygon(poly.slice(0, n), Color(accent, 0.12))
	draw_polyline(poly, accent, 2.0)
	for i in n:
		var p := poly[i]
		var col := Color.WHITE if i == _hover or i == _drag else accent
		draw_circle(p, 5.0 if i == _hover or i == _drag else 4.0, col)
	if _hover >= 0:
		draw_string(font, Vector2(6, size.y - 6), "×%.2f" % _vals[_hover], HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, Color(1, 1, 1, 0.7))
	if not editable:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
		draw_string(font, Vector2(8, 18), "forma condivisa: bloccata", HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, Color(1, 0.8, 0.4, 0.9))


func _nearest(pos: Vector2) -> int:
	var best := -1
	var bd := 12.0
	for i in _vals.size():
		var d := pos.distance_to(_point(i, _vals[i]))
		if d < bd:
			bd = d
			best = i
	return best


func _gui_input(event: InputEvent) -> void:
	if _shape == null or not editable:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.double_click:
			var i := _nearest(mb.position)
			if i >= 0:
				var old := _vals.duplicate()
				_set_val(i, 1.0)
				section_committed.emit(old, _vals.duplicate())
			accept_event()
			return
		if mb.pressed:
			_drag = _nearest(mb.position)
			_start = _vals.duplicate()
		elif _drag >= 0:
			_drag = -1
			if _start != _vals:
				section_committed.emit(_start, _vals.duplicate())
		accept_event()
		queue_redraw()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag >= 0:
			var center: Vector2 = _geom()[0]
			var base: Vector2 = _point(_drag, 1.0) - center
			var along: float = (mm.position - center).dot(base.normalized())
			_set_val(_drag, clampf(along / maxf(base.length(), 1.0), 0.2, 1.8))
			section_edited.emit(_vals.duplicate())
			accept_event()
		else:
			var h := _nearest(mm.position)
			if h != _hover:
				_hover = h
				queue_redraw()


func _set_val(i: int, v: float) -> void:
	var n := _vals.size()
	_vals[i] = snappedf(v, 0.01)
	if symmetric:
		_vals[(n - i) % n] = _vals[i]
	queue_redraw()
