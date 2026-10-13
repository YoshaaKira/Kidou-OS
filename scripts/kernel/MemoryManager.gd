class_name MemoryManager
extends RefCounted
## Physical memory: 12 frames shared by all processes (demand paging).
## A page is loaded only when a process first uses it. When memory is full,
## a victim page is chosen by FIFO or LRU (global replacement).

const FRAME_COUNT := 12
const ALGORITHMS := ["FIFO", "LRU"]

var algorithm := 0
var frames: Array = []   # null = free, or {"pid", "page", "loaded_at", "last_used", "loading"}
var page_faults := 0
var hits := 0

func _init() -> void:
	frames.resize(FRAME_COUNT)
	frames.fill(null)

## Which frame holds this page of this process (-1 = not in memory).
func frame_of(pid: int, page: int) -> int:
	for f in FRAME_COUNT:
		var fr = frames[f]
		if fr != null and fr["pid"] == pid and fr["page"] == page:
			return f
	return -1

## One memory access.
## Returns {"result": "hit" | "fault" | "full", "frame": number, "victim": text}
## "fault": a frame was reserved and the kernel must load the page from disk.
## "full": every frame is busy loading; try again later.
func access(p: PCB, page: int, now: int) -> Dictionary:
	var f := frame_of(p.pid, page)
	if f != -1:
		frames[f]["last_used"] = now
		hits += 1
		return {"result": "hit", "frame": f, "victim": ""}
	var target := _free_frame()
	var victim := ""
	if target == -1:
		target = _choose_victim()
		if target == -1:
			return {"result": "full", "frame": -1, "victim": ""}
		var old: Dictionary = frames[target]
		victim = "evicted P%d page %d from frame %d (%s)" % [old["pid"], old["page"], target, ALGORITHMS[algorithm]]
	page_faults += 1
	frames[target] = {"pid": p.pid, "page": page, "loaded_at": now, "last_used": now, "loading": true}
	return {"result": "fault", "frame": target, "victim": victim}

func _free_frame() -> int:
	for f in FRAME_COUNT:
		if frames[f] == null:
			return f
	return -1

## FIFO: the page that was loaded first.  LRU: the page used least recently.
## Frames still loading are skipped (they are pinned).
func _choose_victim() -> int:
	var best := -1
	var key := "loaded_at" if algorithm == 0 else "last_used"
	for f in FRAME_COUNT:
		var fr = frames[f]
		if fr == null or fr["loading"]:
			continue
		if best == -1 or fr[key] < frames[best][key]:
			best = f
	return best

## Called when the disk has finished loading a page into this frame.
func finish_load(frame: int, now: int) -> void:
	if frame >= 0 and frames[frame] != null:
		frames[frame]["loading"] = false
		frames[frame]["loaded_at"] = now
		frames[frame]["last_used"] = now

## Frees every frame of a process that ended.
func free_process(pid: int) -> void:
	for f in FRAME_COUNT:
		if frames[f] != null and frames[f]["pid"] == pid:
			frames[f] = null

func used_frames() -> int:
	var n := 0
	for fr in frames:
		if fr != null:
			n += 1
	return n

## Page table as text, e.g. "0:F3  1:--  2:F7"  (-- = not in memory)
func page_table_text(p: PCB) -> String:
	var parts := PackedStringArray()
	for page in p.page_count:
		var f := frame_of(p.pid, page)
		parts.append("%d:%s" % [page, "--" if f == -1 else "F%d" % f])
	return "  ".join(parts)

## Where a page lives in the swap area of the disk (cylinders 140-199).
static func swap_cylinder(pid: int, page: int) -> int:
	return 140 + (pid * 13 + page * 7) % 60
