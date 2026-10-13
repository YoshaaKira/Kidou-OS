extends PanelContainer
## Terminal: type a command, the Shell runs it against the kernel, the answer
## is printed.
## Up / Down arrows bring back earlier commands.

var shell := Shell.new()
var _output: RichTextLabel
var _prompt: Label
var _input: LineEdit
var _history: Array = []
var _history_index := 0

func _ready() -> void:
	add_theme_stylebox_override("panel", UI.box(Color("#0a0d14"), 12, UI.PANEL_LIGHT))
	var column := UI.vbox(6)
	add_child(column)
	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.scroll_following = true
	_output.selection_enabled = true
	_output.add_theme_font_override("normal_font", UI.font_mono)
	_output.add_theme_font_size_override("normal_font_size", 13)
	_output.add_theme_color_override("default_color", UI.TEXT)
	column.add_child(_output)
	var row := UI.hbox(8)
	_prompt = UI.mono("", 14, UI.GOOD)
	row.add_child(_prompt)
	_input = UI.line_edit("", _on_submit)
	_input.add_theme_font_override("font", UI.font_mono)
	_input.placeholder_text = "type a command, e.g. help"
	_input.gui_input.connect(_on_key)
	if "keep_editing_on_text_submit" in _input:
		_input.set("keep_editing_on_text_submit", true)
	row.add_child(_input)
	column.add_child(row)
	Kernel.log_added.connect(_on_kernel_log)
	_print("Kidou OS terminal. Type help to see every command.", UI.ACCENT)
	_update_prompt()

func _on_submit(text: String) -> void:
	_input.clear()
	_print(_prompt.text + " " + text, UI.GOOD)
	var command := text.strip_edges()
	if command != "":
		_history.append(command)
		_history_index = _history.size()
	if command == "clear":
		_output.clear()
	elif command != "":
		var result := shell.execute(command)
		if result != "":
			_print(result, UI.TEXT)
	_update_prompt()
	_input.call_deferred("grab_focus")

## Up / Down arrow = previous / next command.
func _on_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or _history.is_empty():
		return
	if key.keycode == KEY_UP:
		_history_index = maxi(0, _history_index - 1)
	elif key.keycode == KEY_DOWN:
		_history_index = mini(_history.size(), _history_index + 1)
	else:
		return
	_input.text = _history[_history_index] if _history_index < _history.size() else ""
	_input.caret_column = _input.text.length()
	_input.accept_event()

## Kernel messages (process created, finished, deadlock ...) appear in grey.
func _on_kernel_log(line: String, quiet: bool) -> void:
	if not quiet:
		_print(line, UI.MUTED)

func _print(text: String, color: Color) -> void:
	_output.push_color(color)
	_output.add_text(text + "\n")
	_output.pop()

func _update_prompt() -> void:
	_prompt.text = "user@kidou:%s$" % shell.cwd
