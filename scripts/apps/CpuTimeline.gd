class_name CpuTimeline
extends Control
## A strip showing which process used the CPU on each of the last 60 ticks.
## Each block = one tick, coloured by process, with its PID. Empty = CPU
## idle.

func _ready() -> void:
	custom_minimum_size = Vector2(0, 56)

func _draw() -> void:
	var history: Array = Kernel.cpu_history
	var cell: float = (size.x - 4.0) / Kernel.HISTORY
	var font: Font = UI.font_mono
	draw_rect(Rect2(0, 0, size.x, 34), UI.PANEL_LIGHT)
	for i in history.size():
		var pid: int = history[i]
		if pid == 0:
			continue
		var rect := Rect2(2 + i * cell, 2, cell - 1, 30)
		draw_rect(rect, UI.pid_color(pid))
		if cell >= 12:
			draw_string(font, rect.position + Vector2(0, 20), str(pid), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 11, UI.BG)
	var first_tick: int = maxi(1, Kernel.time - history.size() + 1)
	draw_string(font, Vector2(0, 50), "t=%d" % first_tick, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.MUTED)
	draw_string(font, Vector2(size.x - 120, 50), "now t=%d" % Kernel.time, HORIZONTAL_ALIGNMENT_RIGHT, 120, 12, UI.MUTED)
