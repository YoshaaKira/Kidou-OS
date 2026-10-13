class_name DiskManager
extends RefCounted
## The disk: 200 cylinders, one read/write head, a queue of requests.
## Every tick the head moves up to SPEED cylinders toward the request chosen
## by the disk-scheduling algorithm. When it arrives, that request is finished.

const CYLINDERS := 200
const SPEED := 25
const HISTORY := 40
const ALGORITHMS := ["FCFS", "SSTF", "SCAN", "C-SCAN", "LOOK"]

var algorithm := 0
var head := 50
var direction := 1 # +1 = moving toward higher cylinders, -1 = lower
var queue: Array = [] # waiting requests: {"pid", "cylinder", "kind", "frame"}
var active = null # the request the head is travelling to right now
var total_movement := 0
var served := 0
var history: Array = [] # recent head positions (for the chart)

func add(pid: int, cylinder: int, kind: String, frame: int = -1) -> void:
	queue.append({
		"pid": pid,
		"cylinder": clampi(cylinder, 0, CYLINDERS - 1),
		"kind": kind,
		"frame": frame
	})

## Removes every request of a process that was killed.
func cancel(pid: int) -> void:
	queue = queue.filter(func(r): return r["pid"] != pid)
	if active != null and active["pid"] == pid:
		active = null

## Moves the head one step. Returns the request that finished this tick, or null.
func tick():
	history.append(head)
	if history.size() > HISTORY:
		history.pop_front()

	if active == null:
		active = _choose()
	if active == null:
		return null

	var target: int = active["cylinder"]
	var move: int = clampi(target - head, -SPEED, SPEED)
	head += move
	total_movement += absi(move)

	if move != 0 and algorithm != 3:
		direction = signi(move)

	if head != target:
		return null

	var done: Dictionary = active
	active = null

	if done["kind"] == "edge": # SCAN reached the end of the disk: turn around
		direction = -direction
		return null

	if done["kind"] == "wrap": # C-SCAN reached the end: jump back to cylinder 0
		head = 0
		total_movement += CYLINDERS - 1
		return null

	served += 1
	return done

## Picks the next request according to the algorithm.
func _choose():
	if queue.is_empty():
		return null

	var pick = null

	match algorithm:
		0: # FCFS: oldest request first
			pick = queue[0]

		1: # SSTF: closest request first
			pick = _closest(queue)

		2, 4: # SCAN and LOOK: keep moving the same way, then turn around
			pick = _closest(_ahead())
			if pick == null:
				var edge := CYLINDERS - 1 if direction > 0 else 0
				if algorithm == 2 and head != edge:
					return {
						"pid": -1,
						"cylinder": edge,
						"kind": "edge",
						"frame": -1
					}
				direction = -direction
				pick = _closest(_ahead())

		3: # C-SCAN: only serve while moving up, then jump back to 0
			direction = 1
			pick = _closest(_ahead())
			if pick == null:
				if head != CYLINDERS - 1:
					return {
						"pid": -1,
						"cylinder": CYLINDERS - 1,
						"kind": "wrap",
						"frame": -1
					}
				head = 0
				total_movement += CYLINDERS - 1
				pick = _closest(_ahead())

	if pick != null:
		queue.erase(pick)

	return pick

## Requests in front of the head in the current direction.
func _ahead() -> Array:
	return queue.filter(func(r): return r["cylinder"] >= head if direction > 0 else r["cylinder"] <= head)

func _closest(list: Array):
	var best = null
	for r in list:
		if best == null or absi(r["cylinder"] - head) < absi(best["cylinder"] - head):
			best = r
	return best

func direction_text() -> String:
	return "up" if direction > 0 else "down"

## The queue as text, e.g. "[now] P3 c42 page | P5 c12 file"
func queue_text() -> String:
	var parts := PackedStringArray()
	if active != null and active["pid"] > 0:
		parts.append("[now] P%d c%d %s" % [active["pid"], active["cylinder"], active["kind"]])
	for r in queue:
		parts.append("P%d c%d %s" % [r["pid"], r["cylinder"], r["kind"]])
	return "empty" if parts.is_empty() else " | ".join(parts)
