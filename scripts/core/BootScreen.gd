extends ColorRect
## Fake boot sequence shown when Kidou OS starts. Click to skip.

const LINES := [
	"KIDOU BIOS v1.0    memory check .......... 12 frames OK",
	"Loading kernel image .................... [ OK ]",
	"Starting process scheduler .............. [ OK ]",
	"Starting memory manager (demand paging) . [ OK ]",
	"Spinning up disk (200 cylinders) ........ [ OK ]",
	"Mounting file system on / ............... [ OK ]",
	"Registering devices: PRINTER SCANNER TAPE [ OK ]",
	"Creating semaphores and mutexes ......... [ OK ]",
	"Starting deadlock detector .............. [ OK ]",
	"",
	"Welcome to KIDOU OS. Type  help  in the terminal.",
]

var _skip := false
var _closing := false

func _ready() -> void:
	color = Color.BLACK
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_top", 60)
	add_child(margin)
	var console := UI.mono("", 18, UI.GOOD)
	margin.add_child(console)
	_type_lines(console)

## Prints one line every 0.25 s, like a real boot log.
func _type_lines(console: Label) -> void:
	for line in LINES:
		console.text += line + "\n"
		if not _skip:
			await get_tree().create_timer(0.25).timeout
	if not _skip:
		await get_tree().create_timer(0.8).timeout
	_close()

func _close() -> void:
	if _closing:
		return
	_closing = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_skip = true
