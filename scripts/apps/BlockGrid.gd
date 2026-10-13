class_name BlockGrid
extends Control
## The 64 disk blocks as an 8 x 8 grid.
## Grey = superblock, yellow = index block, blue = data block, dark = free.

const COLUMNS := 8
const CELL := 34.0

func _ready() -> void:
	custom_minimum_size = Vector2(COLUMNS * CELL, 8 * CELL)

func _draw() -> void:
	var fs := Kernel.fs
	var font: Font = UI.font_mono
	for b in FileSystem.BLOCKS:
		var column: int = b % COLUMNS
		var row: int = floori(b / float(COLUMNS))
		var rect := Rect2(column * CELL, row * CELL, CELL - 3, CELL - 3)
		var owner_text: String = fs.owner[b]
		var fill: Color = UI.PANEL_LIGHT
		if owner_text == "superblock":
			fill = UI.MUTED
		elif owner_text.begins_with("index:"):
			fill = UI.WARN
		elif owner_text.begins_with("data:"):
			fill = UI.ACCENT
		draw_rect(rect, fill)
		draw_string(font, rect.position + Vector2(0, 21), str(b), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 11, UI.BG if owner_text != "" else UI.MUTED)
