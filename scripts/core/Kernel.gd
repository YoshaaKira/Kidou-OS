extends Node
## Kernel (autoload): the heart of Kidou OS.
## Owns the clock, the process table and every subsystem. Every tick:
## 1. new processes join the ready queue
## 2. the disk head moves; a finished request wakes its process
## 3. if the CPU is free, the scheduler dispatches a process
## 4. the running process executes ONE instruction
## 5. waiting time is counted and deadlocks are checked

signal ticked(time: int) # after every tick
signal changed # something changed outside a tick (command, setting)
signal state_changed # play / pause / speed changed
signal log_added(line: String, quiet: bool)

const BASE_INTERVAL := 0.7 # seconds per tick at 1x speed
const HISTORY := 60 # how many ticks the CPU timeline remembers

# ---------- clock ----------
var time := 0
var running := false
var speed := 1.0
var _timer: Timer

# ---------- processes ----------
var processes: Array = [] # live processes (PCB), oldest first
var finished: Array = [] # terminated processes, for statistics
var current: PCB = null # the process on the CPU right now
var next_pid := 1
var busy_ticks := 0
var context_switches := 0
var cpu_history: Array = [] # PID that ran on each recent tick (0 = idle)
var deadlocked: Array = [] # PIDs stuck in a deadlock right now
var log_lines: Array = []

# ---------- subsystems (steps 6 to 9) ----------
var scheduler: Scheduler
var memory: MemoryManager
var disk: DiskManager
var fs: FileSystem
var resources: ResourceManager
var sync: SyncManager

# ---------- settings (Settings app or terminal) ----------
var locks_enabled := true
var banker_enabled := false
var auto_recover := false

func _ready() -> void:
	_timer = Timer.new()
	_timer.timeout.connect(step)
	add_child(_timer)
	boot()

## Starts (or restarts) the whole OS from nothing.
func boot() -> void:
	pause()
	time = 0
	processes.clear()
	finished.clear()
	current = null
	next_pid = 1
	busy_ticks = 0
	context_switches = 0
	cpu_history.clear()
	deadlocked.clear()
	log_lines.clear()
	scheduler = Scheduler.new()
	memory = MemoryManager.new()
	disk = DiskManager.new()
	fs = FileSystem.new()
	resources = ResourceManager.new()
	sync = SyncManager.new()
	locks_enabled = true
	banker_enabled = false
	auto_recover = false
	for program_name in Programs.names():
		fs.write_file("/bin/" + program_name, "#!kidou " + program_name)
	klog("Kidou OS booted. %d programs installed in /bin." % Programs.names().size())
	changed.emit()

# ---------- clock controls ----------
func play() -> void:
	running = true
	_timer.start(BASE_INTERVAL / speed)
	state_changed.emit()

func pause() -> void:
	running = false
	if _timer != null:
		_timer.stop()
	state_changed.emit()

func toggle() -> void:
	if running:
		pause()
	else:
		play()

func set_speed(value: float) -> void:
	speed = value
	if running:
		_timer.start(BASE_INTERVAL / speed)
	state_changed.emit()

# ---------- process management (these are the "system calls") ----------
## Creates a new process running `program_name`. Returns null if no such
## program.
func spawn(program_name: String, priority: int = -1) -> PCB:
	if not Programs.exists(program_name):
		return null
	var info: Dictionary = Programs.info(program_name)
	var p := PCB.new()
	p.pid = next_pid
	next_pid += 1
	p.name = program_name
	p.program = info["code"]
	p.priority = priority if priority >= 0 else info["priority"]
	p.page_count = info["pages"]
	p.max_claim = info["max"]
	p.arrival = time
	processes.append(p)
	klog("P%d (%s) created with priority %d." % [p.pid, p.name, p.priority])
	changed.emit()
	return p

## Ends a process right now (like `kill` in Linux).
func kill(pid: int) -> bool:
	var p := find(pid)
	if p == null:
		return false
	_terminate(p, "killed")
	changed.emit()
	return true

func find(pid: int) -> PCB:
	for p in processes:
		if p.pid == pid:
			return p
	return null

# ---------- one tick of the whole machine ----------
func step() -> void:
	time += 1

	# 1. Processes created since the last tick join the ready queue.
	for p in processes:
		if p.state == PCB.NEW:
			p.state = PCB.READY
			scheduler.add(p)

	# 2. The disk moves its head; a finished request wakes its process.
	var done = disk.tick()
	if done != null:
		_io_finished(done)

	# 3. If the CPU is free, the scheduler dispatches the next process.
	if current == null:
		current = scheduler.pick()
		if current != null:
			current.state = PCB.RUNNING
			current.slice = 0
			context_switches += 1
			if current.start_time < 0:
				current.start_time = time

	# 4. The CPU executes one instruction of the running process.
	if current != null:
		busy_ticks += 1
		cpu_history.append(current.pid)
		_execute(current)
	else:
		cpu_history.append(0)

	if cpu_history.size() > HISTORY:
		cpu_history.pop_front()

	# 5. Everyone still in the ready queue waited this tick; look for
	# deadlocks.
	for p in scheduler.ready:
		p.wait_time += 1
	_check_deadlock()
	ticked.emit(time)

## Runs ONE instruction of process p.
func _execute(p: PCB) -> void:
	p.cpu_time += 1
	if p.pc >= p.program.size():
		_terminate(p, "finished")
		return
	var ins: Array = p.program[p.pc]
	match ins[0]:
		"CPU":
			if p.cpu_left <= 0:
				p.cpu_left = ins[1]
			p.cpu_left -= 1
			if p.cpu_left == 0:
				p.pc += 1
		"MEM":
			_do_memory(p, ins[1])
		"IO":
			disk.add(p.pid, ins[1], "io")
			p.pending_io = 1
			_block(p, "disk I/O")
		"READ":
			_do_file(p, ins[1], -1)
		"WRITE":
			_do_file(p, ins[1], ins[2])
		"REQ":
			_do_request(p, ins[1])
		"REL":
			resources.release(p.pid, ins[1])
			p.pc += 1
			_wake_device_waiters()
		"WAIT":
			if sync.wait(p, ins[1], locks_enabled):
				p.pc += 1
			else:
				_block(p, "waiting on " + ins[1])
		"SIGNAL":
			var woken: int = sync.post(p, ins[1], locks_enabled)
			p.pc += 1
			if woken > 0:
				_wake(find(woken))
		"LOAD":
			p.reg = sync.shared[ins[1]]
			p.in_critical = true
			p.pc += 1
		"STORE":
			sync.store(ins[1], p.reg + ins[2], ins[2])
			p.in_critical = false
			p.pc += 1
		"PUT":
			sync.put()
			p.pc += 1
		"GET":
			sync.take()
			p.pc += 1
		"LOOP":
			var count: int = p.loop_counts.get(p.pc, 0) + 1
			if count < ins[2]:
				p.loop_counts[p.pc] = count
				p.pc = ins[1]
			else:
				p.loop_counts.erase(p.pc)
				p.pc += 1

	# If the instruction blocked or ended the process, we are done.
	if p.state != PCB.RUNNING:
		return
	if p.pc >= p.program.size():
		_terminate(p, "finished")
		return

	# Round Robin: the time slice is used up -> back to the end of the
	# ready queue.
	p.slice += 1
	if scheduler.algorithm == Scheduler.RR and p.slice >= scheduler.quantum:
		_preempt(p)

## MEM instruction: hit, or page fault (load the page from the swap area of
## the disk).
func _do_memory(p: PCB, page: int) -> void:
	var result: Dictionary = memory.access(p, page, time)
	match result["result"]:
		"hit":
			p.pc += 1
		"fault":
			p.page_faults += 1
			disk.add(p.pid, MemoryManager.swap_cylinder(p.pid, page), "page", result["frame"])
			p.pending_io = 1
			_block(p, "page fault (page %d)" % page)
			if result["victim"] != "":
				klog("P%d page fault: %s." % [p.pid, result["victim"]], true)
		"full":
			_preempt(p)

## READ / WRITE instruction: the file system finds or allocates blocks, the
## disk reads/writes them.
func _do_file(p: PCB, path_template: String, blocks: int) -> void:
	var path := path_template.replace("{pid}", str(p.pid))
	var result: Dictionary
	if blocks < 0:
		result = fs.read_file(path)
	else:
		result = fs.write_file(path, "Data written by P%d (%s) at t=%d" % [p.pid, p.name, time], blocks)
	if result["error"] != "":
		klog("P%d: %s" % [p.pid, result["error"]])
		p.pc += 1
		return
	var block_list: Array = result["blocks"]
	for b in block_list:
		disk.add(p.pid, FileSystem.cylinder_of(b), "file")
	p.pending_io = block_list.size()
	_block(p, "file I/O: " + path.get_file())

## REQ instruction: ask the resource manager for a device.
func _do_request(p: PCB, res: String) -> void:
	var answer := resources.request(p, res, banker_enabled, processes)
	if answer == "granted":
		p.waiting_for = ""
		p.pc += 1
		return
	p.waiting_for = res
	if answer == "unsafe":
		_block(p, res + " refused: unsafe (Banker's)")
	else:
		_block(p, res + " is busy")

# ---------- state changes ----------
func _block(p: PCB, reason: String) -> void:
	p.state = PCB.WAITING
	p.wait_reason = reason
	if current == p:
		current = null

func _wake(p: PCB) -> void:
	if p == null or p.state != PCB.WAITING:
		return
	p.state = PCB.READY
	p.wait_reason = ""
	scheduler.add(p)

func _preempt(p: PCB) -> void:
	p.state = PCB.READY
	scheduler.add(p)
	if current == p:
		current = null

## A device was released: everyone waiting for a device tries again.
func _wake_device_waiters() -> void:
	for q in processes:
		if q.state == PCB.WAITING and q.waiting_for != "":
			_wake(q)

## The disk finished a request.
func _io_finished(req: Dictionary) -> void:
	var p := find(req["pid"])
	if p == null:
		return
	if req["kind"] == "page":
		memory.finish_load(req["frame"], time)
	p.pending_io -= 1
	if p.pending_io <= 0 and p.state == PCB.WAITING:
		p.pc += 1 # the MEM / IO / READ / WRITE instruction is complete
		_wake(p)

## Ends a process and gives back everything it held.
func _terminate(p: PCB, reason: String) -> void:
	p.state = PCB.TERMINATED
	p.exit_reason = reason
	p.finish_time = time
	if current == p:
		current = null
	scheduler.remove(p)
	disk.cancel(p.pid)
	memory.free_process(p.pid)
	resources.release_all(p.pid)
	var to_wake: Array = sync.release_all(p)
	processes.erase(p)
	finished.append(p)
	for pid in to_wake:
		_wake(find(pid))
	_wake_device_waiters()
	klog("P%d (%s) %s." % [p.pid, p.name, reason])

# ---------- deadlocks ----------
func _check_deadlock() -> void:
	var found: Array = resources.detect(processes)
	if not found.is_empty() and found != deadlocked:
		var names := PackedStringArray()
		for pid in found:
			names.append("P%d" % pid)
		klog("DEADLOCK detected: %s are waiting for each other forever." % ", ".join(names))
		deadlocked = found
	if auto_recover and not deadlocked.is_empty():
		var victim: int = deadlocked.max()
		klog("Recovery: killing P%d (the youngest) to break the deadlock." % victim)
		_terminate(find(victim), "killed (deadlock recovery)")
		deadlocked = resources.detect(processes)

# ---------- information for the apps and the terminal ----------
## True when `count` lost an update and nobody is in the middle of changing
## it.
func race_detected() -> bool:
	for p in processes:
		if p.in_critical:
			return false
	return sync.shared["count"] != sync.expected["count"]

func stats() -> Dictionary:
	var n := finished.size()
	var total_wait := 0.0
	var total_turnaround := 0.0
	for p in finished:
		total_wait += p.wait_time
		total_turnaround += p.finish_time - p.arrival
	return {
		"finished": n,
		"avg_wait": total_wait / n if n > 0 else 0.0,
		"avg_turnaround": total_turnaround / n if n > 0 else 0.0,
		"utilisation": 100.0 * busy_ticks / time if time > 0 else 0.0,
	}

## Writes a line to the kernel log. quiet = true keeps it out of the
## terminal.
func klog(text: String, quiet: bool = false) -> void:
	var line := "[t=%d] %s" % [time, text]
	log_lines.append(line)
	if log_lines.size() > 200:
		log_lines.pop_front()
	log_added.emit(line, quiet)

# ---------- settings ----------
func set_scheduler(index: int) -> void:
	scheduler.algorithm = index
	klog("CPU scheduler set to %s." % Scheduler.ALGORITHMS[index])
	changed.emit()

func set_quantum(q: int) -> void:
	scheduler.quantum = clampi(q, 1, 10)
	klog("Round Robin time quantum set to %d." % scheduler.quantum)
	changed.emit()

func set_memory_algorithm(index: int) -> void:
	memory.algorithm = index
	klog("Page replacement set to %s." % MemoryManager.ALGORITHMS[index])
	changed.emit()

func set_disk_algorithm(index: int) -> void:
	disk.algorithm = index
	klog("Disk scheduling set to %s." % DiskManager.ALGORITHMS[index])
	changed.emit()

func set_locks(on: bool) -> void:
	locks_enabled = on
	klog("Mutex locks %s." % ("ENABLED" if on else "DISABLED (race conditions possible)"))
	changed.emit()

func set_banker(on: bool) -> void:
	banker_enabled = on
	klog("Banker's algorithm %s." % ("ON (deadlock avoidance)" if on else "OFF"))
	changed.emit()

func set_auto_recover(on: bool) -> void:
	auto_recover = on
	klog("Automatic deadlock recovery %s." % ("ON" if on else "OFF"))
	changed.emit()
