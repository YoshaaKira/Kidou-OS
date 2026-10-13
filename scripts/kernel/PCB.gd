class_name PCB
extends RefCounted
## Process Control Block: everything the kernel knows about ONE process.

enum { NEW, READY, RUNNING, WAITING, TERMINATED }
const STATE_NAMES := ["NEW", "READY", "RUNNING", "WAITING", "TERMINATED"]

# --- identity ---
var pid := 0
var name := ""
var program: Array = [] # the instructions it runs (from Programs.gd)
var priority := 3 # smaller number = more important
var page_count := 1 # how many virtual pages its program uses
var max_claim: Dictionary = {} # most devices it may ever hold (needed by Banker's)

# --- execution state ---
var state := NEW
var pc := 0 # program counter: index of the next instruction
var cpu_left := 0 # ticks left in the current CPU instruction
var slice := 0 # ticks used in the current Round Robin time slice
var loop_counts: Dictionary = {}
var reg := 0 # private register used by LOAD / STORE
var in_critical := false # true between LOAD and STORE
var pending_io := 0 # disk requests it is still waiting for
var wait_reason := "" # why it is WAITING, in words
var waiting_for := "" # device it is blocked on ("" = none)
var held_locks: Array = [] # mutexes it currently holds

# --- statistics ---
var arrival := 0
var start_time := -1
var finish_time := -1
var cpu_time := 0
var wait_time := 0
var page_faults := 0
var exit_reason := ""

func state_name() -> String:
	return STATE_NAMES[state]

## What the process is doing right now, in words.
func doing() -> String:
	if state == WAITING:
		return wait_reason
	if pc >= program.size():
		return "exiting"
	return Programs.describe(program[pc])

## Estimated CPU ticks still needed (used by SJF). Loops are not counted.
func remaining_cpu() -> int:
	var total := 0
	for i in range(pc, program.size()):
		var ins: Array = program[i]
		total += ins[1] if ins[0] == "CPU" else 1
	if cpu_left > 0:
		total -= program[pc][1] - cpu_left
	return total
