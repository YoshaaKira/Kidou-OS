extends Control
## Main: the Kidou OS desktop.
## Left: program launcher + system apps. Top: clock bar. Middle: the open
## app. Bottom: terminal.

const OS_NAME := "KIDOU OS"
const AUTHOR := "Aakash Sehgal | 24BIT0091" # <- put your name and register number here
const APPS := [
	{"name": "Task Manager", "icon": "tasks", "script": "res://scripts/apps/TaskManagerView.gd"},
	{"name": "Memory", "icon": "memory", "script": "res://scripts/apps/MemoryView.gd"},
	{"name": "Storage", "icon": "storage", "script": "res://scripts/apps/StorageView.gd"},
	{"name": "Resources & Sync", "icon": "resources", "script": "res://scripts/apps/ResourcesView.gd"},
	{"name": "Settings", "icon": "settings", "script": "res://scripts/apps/SettingsView.gd"},
]
const SPEEDS := [0.5, 1.0, 2.0, 4.0]

var _content: VBoxContainer
var _title: Label
var _cpu_label: Label
var _time_label: Label
var _play_button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UI.build_theme()
	var background := ColorRect.new()
	background.color = UI.BG
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var root := UI.hbox(0)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(_build_sidebar())
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	root.add_child(margin)
	var main := UI.vbox(10)
	margin.add_child(main)
	main.add_child(_build_top_bar())
	# The open app goes in a scroll area so tall apps still fit.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	_content = UI.vbox(0)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	# The terminal is always open at the bottom.
	var terminal: Control = load("res://scripts/apps/TerminalView.gd").new()
	terminal.custom_minimum_size.y = 240
	main.add_child(terminal)
	Kernel.ticked.connect(_on_tick)
	Kernel.changed.connect(_update_status)
	Kernel.state_changed.connect(_on_state_changed)
	open_app(0)
	_update_status()
	# The boot screen sits on top of everything and removes itself.
	add_child(load("res://scripts/core/BootScreen.gd").new())

func _build_sidebar() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(UI.PANEL, 0))
	panel.custom_minimum_size.x = 240
	var list := UI.vbox(8)
	panel.add_child(list)
	list.add_child(UI.label(OS_NAME, 28, UI.ACCENT, true))
	list.add_child(UI.label("simulated operating system", 12, UI.MUTED))
	list.add_child(HSeparator.new())
	list.add_child(UI.label("LAUNCH A PROGRAM", 12, UI.MUTED, true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for program_name in Programs.names():
		var program_button := UI.button(program_name, _launch.bind(program_name))
		program_button.add_theme_font_size_override("font_size", 13)
		program_button.tooltip_text = Programs.info(program_name)["about"]
		program_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(program_button)
	list.add_child(grid)
	list.add_child(HSeparator.new())
	list.add_child(UI.label("SYSTEM APPS", 12, UI.MUTED, true))
	for i in APPS.size():
		var app: Dictionary = APPS[i]
		var app_button := UI.button(" " + app["name"], open_app.bind(i))
		app_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		app_button.custom_minimum_size.y = 40
		var icon_path: String = "res://assets/icons/%s.png" % app["icon"]
		if ResourceLoader.exists(icon_path):
			app_button.icon = load(icon_path)
			app_button.add_theme_constant_override("icon_max_width", 22)
		list.add_child(app_button)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_child(filler)
	list.add_child(UI.label(AUTHOR, 12, UI.MUTED))
	return panel

func _build_top_bar() -> Control:
	var bar := UI.hbox(10)
	_title = UI.label("", 22, UI.TEXT, true)
	bar.add_child(_title)
	bar.add_child(UI.spacer())
	_cpu_label = UI.mono("CPU: idle", 15, UI.GOOD)
	bar.add_child(_cpu_label)
	_time_label = UI.mono("t = 0", 15, UI.ACCENT)
	bar.add_child(_time_label)
	_play_button = UI.button("Play", Kernel.toggle)
	_play_button.custom_minimum_size.x = 80
	bar.add_child(_play_button)
	bar.add_child(UI.button("Step", Kernel.step))
	var speed := UI.option(["0.5x", "1x", "2x", "4x"], _on_speed)
	speed.select(1)
	bar.add_child(speed)
	return bar

## Opens system app number `index`. The kernel keeps running underneath.
func open_app(index: int) -> void:
	UI.clear(_content)
	var app: Dictionary = APPS[index]
	_title.text = app["name"]
	if not ResourceLoader.exists(app["script"]):
		_content.add_child(UI.label("This app is not built yet. Use the terminal below.", 16, UI.MUTED))
		return
	var view: Control = load(app["script"]).new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(view)

func _launch(program_name: String) -> void:
	Kernel.spawn(program_name)

func _on_speed(index: int) -> void:
	Kernel.set_speed(SPEEDS[index])

func _on_tick(_time: int) -> void:
	_update_status()

## Top bar: the clock and which process used the CPU on the last tick.
func _update_status() -> void:
	_time_label.text = "t = %d" % Kernel.time
	var last_pid := 0
	if not Kernel.cpu_history.is_empty():
		last_pid = Kernel.cpu_history.back()
	if last_pid == 0:
		_cpu_label.text = "CPU: idle"
	else:
		var p := Kernel.find(last_pid)
		_cpu_label.text = "CPU: P%d %s" % [last_pid, p.name if p != null else "(ended)"]

func _on_state_changed() -> void:
	_play_button.text = "Pause" if Kernel.running else "Play"
