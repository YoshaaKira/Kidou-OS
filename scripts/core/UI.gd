extends Node
## UI (autoload): colours, fonts and helpers so every screen looks the same.
## Use it anywhere as UI.something, e.g. UI.ACCENT or UI.label("Hello").

# ---------- Colours ----------
const BG := Color("#0f1420")
const PANEL := Color("#182033")
const PANEL_LIGHT := Color("#25304a")
const ACCENT := Color("#4fc3f7")
const TEXT := Color("#e6ebf5")
const MUTED := Color("#8a96b0")
const GOOD := Color("#66bb6a")
const BAD := Color("#ef5350")
const WARN := Color("#ffca28")

## One colour per process so P1, P2, P3 ... are easy to tell apart.
const PALETTE := [
	Color("#4fc3f7"), Color("#ffb74d"), Color("#81c784"),
	Color("#f06292"), Color("#ba68c8"), Color("#4db6ac"),
	Color("#e57373"), Color("#aed581"),
]

# ---------- Fonts ----------
var font_regular: Font
var font_bold: Font
var font_mono: Font

func _init() -> void:
	font_regular = _load_font("res://assets/fonts/Inter-Regular.ttf")
	font_bold = _load_font("res://assets/fonts/Inter-Bold.ttf")
	font_mono = _load_font("res://assets/fonts/JetBrainsMonoRegular.ttf")

## Uses Godot's built-in font if a file is missing, so the game never crashes.
func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path)
	return ThemeDB.fallback_font

## Colour for a process ID: P1, P2, P3 ...
func pid_color(pid: int) -> Color:
	return PALETTE[maxi(pid - 1, 0) % PALETTE.size()]

# ---------- Theme ----------
## Builds one Theme. Main applies it, and every node inside Main inherits it.
func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_regular
	t.default_font_size = 15

	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 12))

	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, box(PANEL_LIGHT, 8))
		t.set_stylebox("hover", type, box(PANEL_LIGHT.lightened(0.15), 8))
		t.set_stylebox("pressed", type, box(ACCENT.darkened(0.4), 8))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)

	t.set_stylebox("normal", "LineEdit", box(BG, 8, PANEL_LIGHT))
	t.set_stylebox("focus", "LineEdit", box(BG, 8, ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_color", "CheckButton", TEXT)

	t.set_constant("h_separation", "GridContainer", 16)
	t.set_constant("v_separation", "GridContainer", 6)

	return t

## A flat rounded rectangle style, optionally with a border.
func box(color: Color, radius: int = 10, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8

	if border.a > 0:
		s.set_border_width_all(2)
		s.border_color = border

	return s

# ---------- Node helpers ----------
func label(text: String, size: int = 15, color: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)

	if bold:
		l.add_theme_font_override("font", font_bold)

	return l

## Monospace label: used for numbers, tables and the terminal.
func mono(text: String, size: int = 14, color: Color = TEXT) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", font_mono)
	return l

## A label that wraps onto several lines.
func paragraph(text: String, color: Color = TEXT, size: int = 14) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	return b

## A rounded panel with a vertical list inside.
func card(title: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	var v := vbox(8)
	p.add_child(v)

	if title != "":
		v.add_child(label(title, 16, ACCENT, true))

	return p

func content(card_node: PanelContainer) -> VBoxContainer:
	return card_node.get_child(0) as VBoxContainer

func hbox(separation: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h

func vbox(separation: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v

## Empty stretchy space that pushes the next items to the right.
func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

## Drop-down list. The callback receives the chosen index.
func option(items: Array, callback: Callable = Callable()) -> OptionButton:
	var o := OptionButton.new()

	for item in items:
		o.add_item(str(item))

	if callback.is_valid():
		o.item_selected.connect(callback)

	return o

## Number box with up/down arrows.
func spin(min_value: int, max_value: int, value: int, callback: Callable = Callable()) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_value
	s.max_value = max_value
	s.value = value

	if callback.is_valid():
		s.value_changed.connect(callback)

	return s

## On/off switch. The callback receives true or false.
func toggle(text: String, on: bool, callback: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(callback)
	return c

## Text box. The callback runs when the user presses Enter.
func line_edit(text: String, callback: Callable = Callable()) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if callback.is_valid():
		e.text_submitted.connect(callback)

	return e

## Removes every child of a node (used to redraw tables).
func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
