class_name ResourceManager
extends RefCounted

## Devices that processes must request before use: PRINTER x1, SCANNER x1,
## TAPE x2.
## Handles requests and releases, Banker's avoidance and deadlock detection.

const TOTAL := {"PRINTER": 1, "SCANNER": 1, "TAPE": 2}

var available: Dictionary = {}
var allocation: Dictionary = {} # pid -> {device: how many it holds}

func _init() -> void:
	available = TOTAL.duplicate()

func held(pid: int, res: String) -> int:
	return allocation.get(pid, {}).get(res, 0)

## Returns "granted", "busy" (none free) or "unsafe" (Banker's says no).
func request(p: PCB, res: String, use_banker: bool, live: Array) -> String:
	if available.get(res, 0) <= 0:
		return "busy"
	if use_banker and not _safe_if_granted(p, res, live):
		return "unsafe"
	available[res] -= 1
	if not allocation.has(p.pid):
		allocation[p.pid] = {}
	allocation[p.pid][res] = held(p.pid, res) + 1
	return "granted"

func release(pid: int, res: String) -> void:
	if held(pid, res) > 0:
		allocation[pid][res] -= 1
		available[res] += 1

## Gives back everything a process holds (used when it ends or is killed).
func release_all(pid: int) -> void:
	if allocation.has(pid):
		for res in allocation[pid]:
			available[res] += allocation[pid][res]
		allocation.erase(pid)

## PIDs that currently hold at least one of this device.
func holders(res: String) -> Array:
	var out := []
	for pid in allocation:
		if allocation[pid].get(res, 0) > 0:
			out.append(pid)
	return out

func holds_anything(pid: int) -> bool:
	for res in allocation.get(pid, {}):
		if allocation[pid][res] > 0:
			return true
	return false

## BANKER'S ALGORITHM (avoidance).
## Pretend to give one `res` to p, then check that every live process could
## still finish in some order, each using at most its declared maximum (a
## SAFE state).
func _safe_if_granted(p: PCB, res: String, live: Array) -> bool:
	var work: Dictionary = available.duplicate()
	work[res] -= 1
	var alloc := {}
	for q in live:
		alloc[q.pid] = allocation.get(q.pid, {}).duplicate()
	alloc[p.pid][res] = alloc[p.pid].get(res, 0) + 1
	var unfinished: Array = live.duplicate()
	var progress := true
	while progress:
		progress = false
		for q in unfinished.duplicate():
			if _fits(_need(q, alloc[q.pid]), work):
				for r in alloc[q.pid]:
					work[r] = work.get(r, 0) + alloc[q.pid][r]
				unfinished.erase(q)
				progress = true
	return unfinished.is_empty()

## Need = Max - Allocation
func _need(q: PCB, held_now: Dictionary) -> Dictionary:
	var need := {}
	for r in q.max_claim:
		need[r] = maxi(0, q.max_claim[r] - held_now.get(r, 0))
	return need

func _fits(want: Dictionary, work: Dictionary) -> bool:
	for r in want:
		if want[r] > work.get(r, 0):
			return false
	return true

## DEADLOCK DETECTION (textbook algorithm; works with several units per
## device).
## Repeatedly "finish" any process whose current request can be met, giving
## back what it holds. Whoever can never finish is deadlocked.
## Returns their PIDs ([] = no deadlock).
func detect(live: Array) -> Array:
	var work: Dictionary = available.duplicate()
	var unfinished := []
	for q in live:
		if holds_anything(q.pid) or (q.state == PCB.WAITING and q.waiting_for != ""):
			unfinished.append(q)
	var progress := true
	while progress:
		progress = false
		for q in unfinished.duplicate():
			var wanted := {}
			if q.state == PCB.WAITING and q.waiting_for != "":
				wanted[q.waiting_for] = 1
			if _fits(wanted, work):
				var holding: Dictionary = allocation.get(q.pid, {})
				for r in holding:
					work[r] = work.get(r, 0) + holding[r]
				unfinished.erase(q)
				progress = true
	var pids := []
	for q in unfinished:
		pids.append(q.pid)
	pids.sort()
	return pids
