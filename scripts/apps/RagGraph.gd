class_name RagGraph
extends Control
## Resource-allocation graph of the LIVE system.
## Circles = processes that hold or wait for a device. Squares = devices.
## Blue arrow device -> process = holds it. Yellow arrow process -> device =
## waits for it.
## Red = part of a deadlock.

func _ready() -> void:
	custom_minimum_size = Vector2(0, 240)

func _draw() -> void:
	var res := Kernel.resources
	var font: Font = UI.font_bold
	var involved := []
	for p in Kernel.processes:
		if res.holds_anything(p.pid) or (p.state == PCB.WAITING and p.waiting_for != ""):
			involved.append(p)
	var devices: Array = ResourceManager.TOTAL.keys()
	var dev_pos := {}
	for i in devices.size():
		dev_pos[devices[i]] = Vector2(size.x * (i + 1) / (devices.size() + 1), 190)
	var proc_pos := {}
	for i in involved.size():
		proc_pos[involved[i].pid] = Vector2(size.x * (i + 1) / (involved.size() + 1), 50)
	# Blue arrows: device -> the process holding it
	for dev in devices:
		for pid in res.holders(dev):
			if proc_pos.has(pid):
				var red: bool = Kernel.deadlocked.has(pid) and _deadlocked_wants(dev)
				_arrow(dev_pos[dev], proc_pos[pid], UI.BAD if red else UI.ACCENT, 0.0)
	# Yellow arrows: waiting process -> the device it wants
	for p in involved:
		if p.state == PCB.WAITING and p.waiting_for != "":
			var stuck: bool = Kernel.deadlocked.has(p.pid)
			_arrow(proc_pos[p.pid], dev_pos[p.waiting_for], UI.BAD if stuck else UI.WARN, 8.0)
	# Device squares
	for dev in devices:
		var dpos: Vector2 = dev_pos[dev]
		var rect := Rect2(dpos - Vector2(46, 24), Vector2(92, 48))
		draw_rect(rect, UI.PANEL_LIGHT)
		draw_rect(rect, UI.MUTED, false, 2.0)
		draw_string(font, dpos + Vector2(-46, -2), dev, HORIZONTAL_ALIGNMENT_CENTER, 92, 13, UI.TEXT)
		draw_string(font, dpos + Vector2(-46, 16), "%d of %d free" % [res.available[dev], ResourceManager.TOTAL[dev]], HORIZONTAL_ALIGNMENT_CENTER, 92, 11, UI.MUTED)
	# Process circles
	for p in involved:
		var ppos: Vector2 = proc_pos[p.pid]
		draw_circle(ppos, 26, UI.pid_color(p.pid))
		if Kernel.deadlocked.has(p.pid):
			draw_arc(ppos, 31, 0, TAU, 32, UI.BAD, 3.0)
		draw_string(font, ppos + Vector2(-26, 6), "P%d" % p.pid, HORIZONTAL_ALIGNMENT_CENTER, 52, 15, UI.BG)
	if involved.is_empty():
		draw_string(UI.font_regular, Vector2(10, 110), "No process is using a device. Try: run print_job scan_job, then Play.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.MUTED)

## True if some deadlocked process is waiting for this device.
func _deadlocked_wants(dev: String) -> bool:
	for p in Kernel.processes:
		if Kernel.deadlocked.has(p.pid) and p.state == PCB.WAITING and p.waiting_for == dev:
			return true
	return false

## A line with an arrowhead. `offset` shifts it sideways so two arrows
## between
## the same pair of nodes do not sit on top of each other.
func _arrow(from: Vector2, to: Vector2, color: Color, offset: float) -> void:
	var dir := (to - from).normalized()
	var side := Vector2(-dir.y, dir.x)
	var start := from + dir * 30 + side * offset
	var tip := to - dir * 30 + side * offset
	draw_line(start, tip, color, 3.0)
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * 12 + side * 6, tip - dir * 12 - side * 6]), color)
