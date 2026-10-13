class_name DiskChart
extends Control
## The disk head's recent path (top = 40 ticks ago, bottom = now)
## and the waiting requests (red dots on the cylinder axis).

const LEFT := 12.0
const AXIS_Y := 26.0

func _ready() -> void:
	custom_minimum_size = Vector2(0, 250)

## Screen x position of a cylinder number.
func _x(cylinder: float) -> float:
	return LEFT + (size.x - 2 * LEFT) * cylinder / float(DiskManager.CYLINDERS - 1)

func _draw() -> void:
	var d := Kernel.disk
	var font: Font = UI.font_mono
	# swap area (page faults read from here)
	draw_rect(Rect2(_x(140), AXIS_Y - 4, _x(199) - _x(140), 8), UI.PANEL_LIGHT)
	draw_line(Vector2(LEFT, AXIS_Y), Vector2(size.x - LEFT, AXIS_Y), UI.MUTED, 2.0)
	for c in [0, 50, 100, 150, 199]:
		draw_string(font, Vector2(_x(c) - 20, AXIS_Y - 9), str(c), HORIZONTAL_ALIGNMENT_CENTER, 40, 11, UI.MUTED)
	# waiting requests
	for r in d.queue:
		draw_circle(Vector2(_x(r["cylinder"]), AXIS_Y), 5, UI.BAD)
	if d.active != null and d.active["pid"] > 0:
		draw_circle(Vector2(_x(d.active["cylinder"]), AXIS_Y), 7, UI.WARN)
	# where the head has been, then where it is now
	var history: Array = d.history
	var row_h: float = (size.y - AXIS_Y - 24.0) / float(DiskManager.HISTORY)
	var points := PackedVector2Array()
	for i in history.size():
		points.append(Vector2(_x(history[i]), AXIS_Y + 12 + i * row_h))
	var now_point := Vector2(_x(d.head), AXIS_Y + 12 + history.size() * row_h)
	points.append(now_point)
	if points.size() >= 2:
		draw_polyline(points, UI.ACCENT, 2.0, true)
	draw_circle(now_point, 6, UI.WARN)
	draw_string(font, now_point + Vector2(10, 4), "head %d" % d.head, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.TEXT)
