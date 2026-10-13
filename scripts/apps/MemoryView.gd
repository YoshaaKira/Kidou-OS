extends VBoxContainer
## Memory app: the 12 physical frames and every process's page table.

var _summary: Label
var _frames: GridContainer
var _tables: Label

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var frames_card := UI.card("Physical memory: 12 frames (colour = owner, yellow border = loading from disk)")
	_summary = UI.paragraph("", UI.TEXT, 14)
	UI.content(frames_card).add_child(_summary)
	_frames = GridContainer.new()
	_frames.columns = 6
	_frames.add_theme_constant_override("h_separation", 8)
	_frames.add_theme_constant_override("v_separation", 8)
	UI.content(frames_card).add_child(_frames)
	add_child(frames_card)
	var tables_card := UI.card("Page tables (page:frame, -- = not in memory)")
	_tables = UI.mono("", 13)
	UI.content(tables_card).add_child(_tables)
	add_child(tables_card)
	Kernel.ticked.connect(_on_tick)
	Kernel.changed.connect(_refresh, CONNECT_DEFERRED)
	_refresh()

func _on_tick(_time: int) -> void:
	_refresh()

func _refresh() -> void:
	var m := Kernel.memory
	var accesses := m.page_faults + m.hits
	var ratio := 100.0 * m.hits / accesses if accesses > 0 else 0.0
	_summary.text = "Replacement: %s Frames used: %d / %d Page faults: %d Hits: %d Hit ratio: %.0f%%" % [
		MemoryManager.ALGORITHMS[m.algorithm], m.used_frames(),
		MemoryManager.FRAME_COUNT, m.page_faults, m.hits, ratio
	]
	UI.clear(_frames)
	for f in MemoryManager.FRAME_COUNT:
		var fr = m.frames[f]
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(148, 62)
		var text := "Frame %d\nfree" % f
		var fill: Color = UI.PANEL_LIGHT
		var border := Color(0, 0, 0, 0)
		if fr != null:
			text = "Frame %d\nP%d page %d" % [f, fr["pid"], fr["page"]]
			fill = UI.pid_color(fr["pid"])
			if fr["loading"]:
				text += " (loading)"
				border = UI.WARN
		slot.add_theme_stylebox_override("panel", UI.box(fill, 10, border))
		slot.add_child(UI.label(text, 13, UI.MUTED if fr == null else UI.BG, true))
		_frames.add_child(slot)
	var lines := PackedStringArray()
	for p in Kernel.processes:
		lines.append("P%-3d %-10s %s faults: %d" % [p.pid, p.name, m.page_table_text(p), p.page_faults])
	if lines.is_empty():
		lines.append("No processes. Try: run memhog memhog (16 pages, but only 12 frames)")
	_tables.text = "\n".join(lines)
