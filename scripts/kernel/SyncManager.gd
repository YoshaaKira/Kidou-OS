class_name SyncManager
extends RefCounted

## Semaphores, mutexes and the shared data used by cooperating processes.
const BUFFER_SIZE := 5

var semaphores := {} # name -> {"value": int, "mutex": bool, "waiting": [pids]}
var shared := {"count": 0} # shared variable(s)
var expected := {"count": 0} # what they SHOULD be if no update was ever lost
var buffer: Array = [] # bounded buffer for producer / consumer
var next_item := 1

func _init() -> void:
	_create("mutex", 1, true) # protects `count`
	_create("buf_lock", 1, true) # protects the buffer
	_create("empty", BUFFER_SIZE, false) # free slots
	_create("full", 0, false) # filled slots

func _create(sem_name: String, value: int, is_mutex: bool) -> void:
	semaphores[sem_name] = {"value": value, "mutex": is_mutex, "waiting": []}

## wait() / P(): take one unit, or return false so the kernel blocks the
## process.
func wait(p: PCB, sem_name: String, locks_enabled: bool) -> bool:
	var s: Dictionary = semaphores[sem_name]
	if s["mutex"] and not locks_enabled:
		return true # locks switched off: no mutual exclusion at all
	if s["value"] > 0:
		s["value"] -= 1
		s["waiting"].erase(p.pid)
		if s["mutex"]:
			p.held_locks.append(sem_name)
		return true
	if not s["waiting"].has(p.pid):
		s["waiting"].append(p.pid)
	return false

## signal() / V(): give one unit back. Returns the PID of a waiting process
## to wake up, or -1.
func post(p: PCB, sem_name: String, locks_enabled: bool) -> int:
	var s: Dictionary = semaphores[sem_name]
	if s["mutex"] and not locks_enabled:
		return -1
	s["value"] += 1
	if s["mutex"]:
		s["value"] = mini(s["value"], 1)
		p.held_locks.erase(sem_name)
	if s["waiting"].is_empty():
		return -1
	return s["waiting"].pop_front()

## When a process dies, give back the locks it held so nobody is stuck
## forever.
## Returns the PIDs that should be woken up.
func release_all(p: PCB) -> Array:
	var to_wake := []
	for sem_name in semaphores:
		semaphores[sem_name]["waiting"].erase(p.pid)
	for sem_name in p.held_locks:
		var s: Dictionary = semaphores[sem_name]
		s["value"] = 1
		if not s["waiting"].is_empty():
			to_wake.append(s["waiting"].pop_front())
	p.held_locks.clear()
	return to_wake

## STORE: write the new value, and remember what it should have become.
func store(var_name: String, value: int, delta: int) -> void:
	shared[var_name] = value
	expected[var_name] += delta

func put() -> void:
	if buffer.size() < BUFFER_SIZE:
		buffer.append(next_item)
		next_item += 1

func take() -> void:
	if not buffer.is_empty():
		buffer.pop_front()
