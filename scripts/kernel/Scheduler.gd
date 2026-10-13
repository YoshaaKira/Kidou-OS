class_name Scheduler
extends RefCounted
## CPU scheduler: holds the ready queue and decides which process runs next.

const ALGORITHMS := ["FCFS", "SJF", "Priority", "Round Robin"]
const FCFS := 0
const SJF := 1
const PRIORITY := 2
const RR := 3

var algorithm := RR
var quantum := 2
var ready: Array = [] # the ready queue, oldest first

func add(p: PCB) -> void:
	if not ready.has(p):
		ready.append(p)

func remove(p: PCB) -> void:
	ready.erase(p)

## Takes the next process out of the ready queue (null if it is empty).
## FCFS and Round Robin: whoever is first in the queue.
## SJF: the least remaining CPU work. Priority: the smallest priority number.
## FCFS, SJF and Priority never interrupt a running process (non-preemptive);
## Round Robin interrupts it after `quantum` ticks (the kernel does that part).
func pick() -> PCB:
	if ready.is_empty():
		return null
	var best: PCB = ready[0]
	for p in ready:
		if algorithm == SJF and p.remaining_cpu() < best.remaining_cpu():
			best = p
		elif algorithm == PRIORITY and p.priority < best.priority:
			best = p
	ready.erase(best)
	return best
