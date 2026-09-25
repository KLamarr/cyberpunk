class_name UITheme
extends RefCounted
## Tema dell'interfaccia: pannelli verde-acqua su fondo scuro, font monospazio,
## nello spirito delle interfacce di System Shock 2.

const BG := Color(0.02, 0.06, 0.07, 0.94)
const BG2 := Color(0.04, 0.11, 0.12, 0.95)
const BORDER := Color(0.18, 0.84, 0.76)
const TEXT := Color(0.72, 0.95, 0.9)
const DIM := Color(0.42, 0.62, 0.6)
const ACCENT := Color(1.0, 0.8, 0.33)
const DANGER := Color(1.0, 0.32, 0.26)
const GOOD := Color(0.45, 1.0, 0.6)

static var _theme: Theme
static var _font: Font


static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "Liberation Mono", "Menlo", "Courier New", "monospace"])
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_NORMAL
		_font = f
	return _font


static func box(bg: Color, border: Color, bw := 2, margin := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_content_margin_all(margin)
	s.corner_detail = 1
	return s


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 17
	t.set_stylebox("panel", "Panel", box(BG, BORDER))
	t.set_stylebox("panel", "PanelContainer", box(BG, BORDER, 2, 14))
	t.set_stylebox("normal", "Button", box(BG2, BORDER.darkened(0.35), 1, 8))
	t.set_stylebox("hover", "Button", box(Color(0.08, 0.22, 0.22), BORDER, 1, 8))
	t.set_stylebox("pressed", "Button", box(Color(0.14, 0.34, 0.32), ACCENT, 1, 8))
	t.set_stylebox("disabled", "Button", box(Color(0.03, 0.05, 0.05, 0.9), Color(0.2, 0.28, 0.28), 1, 8))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), ACCENT, 1, 8))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color(0.3, 0.4, 0.4))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("normal", "LineEdit", box(Color(0, 0.03, 0.02), BORDER, 1, 6))
	t.set_color("font_color", "LineEdit", GOOD)
	t.set_stylebox("panel", "TabContainer", box(BG, BORDER, 2, 12))
	t.set_stylebox("tab_selected", "TabContainer", box(Color(0.08, 0.24, 0.24), BORDER, 1, 8))
	t.set_stylebox("tab_unselected", "TabContainer", box(BG2, BORDER.darkened(0.5), 1, 8))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(0.06, 0.18, 0.18), BORDER, 1, 8))
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	t.set_color("font_unselected_color", "TabContainer", DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_stylebox("panel", "ItemList", box(Color(0, 0.03, 0.03), BORDER.darkened(0.4), 1, 6))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", ACCENT)
	t.set_stylebox("selected", "ItemList", box(Color(0.08, 0.24, 0.24), BORDER, 1, 4))
	t.set_stylebox("selected_focus", "ItemList", box(Color(0.08, 0.24, 0.24), ACCENT, 1, 4))
	t.set_stylebox("background", "HSlider", box(Color(0.05, 0.12, 0.12), BORDER.darkened(0.4), 1, 3))
	t.set_stylebox("slider", "HSlider", box(Color(0.05, 0.15, 0.15), BORDER.darkened(0.4), 1, 3))
	t.set_stylebox("grabber_area", "HSlider", box(BORDER.darkened(0.3), BORDER, 1, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(BORDER, ACCENT, 1, 3))
	_theme = t
	return t


static func label(text: String, size := 17, color := TEXT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, cb: Callable, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	b.pressed.connect(func(): Sfx.play_ui("ui_click", -6.0))
	b.pressed.connect(cb)
	return b


static func pips(level: int, total: int) -> String:
	var s := ""
	for i in total:
		s += "■" if i < level else "□"
	return s
