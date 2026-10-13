class_name Shell
extends RefCounted

## The command interpreter behind the Terminal (a tiny version of bash).
## execute() takes one typed line and returns the text to print.

const HELP := """PROCESSES run <program...> [priority] ps top kill <pid> programs
SCHEDULING sched [fcfs|sjf|priority|rr] [quantum] step [n]
MEMORY mem mem <pid> mem fifo|lru
DISK disk disk fcfs|sstf|scan|cscan|look
FILES ls [dir] cd <dir> pwd mkdir <dir> touch <file> write <file> <text>
cat <file> rm <path> info <file> tree df
DEVICES res deadlock banker on|off recover on|off
SYNC sync locks on|off
SYSTEM log clear reboot help
Example: run print_job scan_job then press Play."""

const SCHED_NAMES := {"fcfs": 0, "sjf": 1, "priority": 2, "rr": 3}
const DISK_NAMES := {"fcfs": 0, "sstf": 1, "scan": 2, "cscan": 3, "look": 4}

var cwd := "/home/user" # current working directory

func execute(line: String) -> String:
	var words := line.strip_edges().split(" ", false)
	if words.is_empty():
		return ""
	var cmd := words[0].to_lower()
	var args := words.slice(1)
	match cmd:
		"help":
			return HELP
		"programs":
			return _programs()
		"run":
			return _run(args)
		"ps":
			return _ps()
		"top":
			return _top()
		"kill":
			return _kill(args)
		"sched":
			return _sched(args)
		"step":
			return _step(args)
		"mem":
			return _mem(args)
		"disk":
			return _disk(args)
		"res":
			return _res()
		"deadlock":
			return _deadlock()
		"banker", "recover", "locks":
			return _switch(cmd, args)
		"sync":
			return _sync()
		"log":
			return "\n".join(PackedStringArray(Kernel.log_lines.slice(-12)))
		"reboot":
			Kernel.boot()
			cwd = "/home/user"
			return "Rebooted. Kidou OS is up."
		"ls", "cd", "pwd", "mkdir", "touch", "write", "cat", "rm", "info", "tree", "df":
			return _files(cmd, args)
	return "Unknown command: %s (type help)" % cmd

# ---------- processes ----------
func _programs() -> String:
	var out := PackedStringArray()
	for n in Programs.names():
		out.append("%-10s %s" % [n, Programs.info(n)["about"]])
	return "\n".join(out)

func _run(args: PackedStringArray) -> String:
	if args.is_empty():
		return "usage: run <program> [more programs] [priority]\ne.g. run compiler editor"
	var priority := -1
	var names := []
	for a in args:
		if a.is_valid_int():
			priority = a.to_int()
		else:
			names.append(a.to_lower())
	var out := PackedStringArray()
	for n in names:
		var p := Kernel.spawn(n, priority)
		if p == null:
			out.append("run: no such program '%s' (type programs)" % n)
		else:
			out.append("Started P%d (%s). Press Play or Step to run it." % [p.pid, p.name])
	return "\n".join(out)

func _ps() -> String:
	if Kernel.processes.is_empty():
		return "No processes. Try: run compiler editor music"
	var out := PackedStringArray(["PID PROGRAM STATE PRI CPU WAIT DOING"])
	for p in Kernel.processes:
		out.append("%-4d %-11s %-9s %-4d %-4d %-5d %s" % [p.pid, p.name, p.state_name(), p.priority, p.cpu_time, p.wait_time, p.doing()])
	return "\n".join(out)

func _top() -> String:
	var s := Kernel.stats()
	var on_cpu := "idle"
	if Kernel.current != null:
		on_cpu = "P%d (%s)" % [Kernel.current.pid, Kernel.current.name]
	var lines := PackedStringArray()
	lines.append("Time t=%d CPU: %s Scheduler: %s (quantum %d)" % [Kernel.time, on_cpu, Scheduler.ALGORITHMS[Kernel.scheduler.algorithm], Kernel.scheduler.quantum])
	lines.append("Processes: %d alive, %d finished" % [Kernel.processes.size(), s["finished"]])
	lines.append("CPU utilisation %.0f%% Context switches %d" % [s["utilisation"], Kernel.context_switches])
	lines.append("Average waiting time %.1f ticks Average turnaround %.1f ticks" % [s["avg_wait"], s["avg_turnaround"]])
	lines.append("Page faults %d Disk head moved %d cylinders Free disk blocks %d" % [Kernel.memory.page_faults, Kernel.disk.total_movement, Kernel.fs.free_count()])
	return "\n".join(lines)

func _kill(args: PackedStringArray) -> String:
	if args.is_empty() or not args[0].is_valid_int():
		return "usage: kill <pid>"
	var pid := args[0].to_int()
	if Kernel.kill(pid):
		return "Killed P%d." % pid
	return "kill: no process with PID %d" % pid

# ---------- scheduling ----------
func _sched(args: PackedStringArray) -> String:
	if not args.is_empty():
		var key := args[0].to_lower()
		if not SCHED_NAMES.has(key):
			return "usage: sched fcfs|sjf|priority|rr [quantum]"
		Kernel.set_scheduler(SCHED_NAMES[key])
		if args.size() > 1 and args[1].is_valid_int():
			Kernel.set_quantum(args[1].to_int())
	return "Scheduler: %s, quantum %d" % [Scheduler.ALGORITHMS[Kernel.scheduler.algorithm], Kernel.scheduler.quantum]

func _step(args: PackedStringArray) -> String:
	var n := 1
	if not args.is_empty() and args[0].is_valid_int():
		n = clampi(args[0].to_int(), 1, 100)
	for i in n:
		Kernel.step()
	return "Ran %d tick(s). Now t=%d." % [n, Kernel.time]

# ---------- memory and disk ----------
func _mem(args: PackedStringArray) -> String:
	var m := Kernel.memory
	if not args.is_empty():
		var a := args[0].to_lower()
		if a == "fifo" or a == "lru":
			Kernel.set_memory_algorithm(0 if a == "fifo" else 1)
			return "Page replacement is now %s." % a.to_upper()
		if a.is_valid_int():
			var p := Kernel.find(a.to_int())
			if p == null:
				return "mem: no process with PID " + a
			return "Page table of P%d (%s): %s (page:frame, -- = still on disk)" % [p.pid, p.name, m.page_table_text(p)]
		return "usage: mem | mem <pid> | mem fifo|lru"
	var out := PackedStringArray()
	out.append("Frames used %d/%d Page faults %d Hits %d Replacement %s" % [m.used_frames(), MemoryManager.FRAME_COUNT, m.page_faults, m.hits, MemoryManager.ALGORITHMS[m.algorithm]])
	for f in MemoryManager.FRAME_COUNT:
		var fr = m.frames[f]
		if fr == null:
			out.append("F%-2d free" % f)
		else:
			out.append("F%-2d P%d page %d%s" % [f, fr["pid"], fr["page"], " (loading from disk)" if fr["loading"] else ""])
	return "\n".join(out)

func _disk(args: PackedStringArray) -> String:
	if not args.is_empty():
		var key := args[0].to_lower()
		if not DISK_NAMES.has(key):
			return "usage: disk | disk fcfs|sstf|scan|cscan|look"
		Kernel.set_disk_algorithm(DISK_NAMES[key])
	var d := Kernel.disk
	return "Algorithm %s Head at cylinder %d, moving %s Served %d Total head movement %d\nQueue: %s" % [DiskManager.ALGORITHMS[d.algorithm], d.head, d.direction_text(), d.served, d.total_movement, d.queue_text()]

# ---------- devices and deadlocks ----------
func _res() -> String:
	var r := Kernel.resources
	var out := PackedStringArray(["DEVICE TOTAL FREE HELD BY WAITING"])
	for dev in ResourceManager.TOTAL:
		out.append("%-8s %-6d %-5d %-14s %s" % [dev, ResourceManager.TOTAL[dev], r.available[dev], _pids(r.holders(dev)), _pids(_waiting_for(dev))])
	out.append("Banker's avoidance: %s Auto recovery: %s" % [_on(Kernel.banker_enabled), _on(Kernel.auto_recover)])
	return "\n".join(out)

func _deadlock() -> String:
	var found: Array = Kernel.resources.detect(Kernel.processes)
	if found.is_empty():
		return "No deadlock. Every waiting process can eventually get what it needs."
	return "DEADLOCK: %s can never continue. Fix it with kill <pid> or turn on recover on" % _pids(found)

func _switch(what: String, args: PackedStringArray) -> String:
	if args.is_empty() or not (args[0] == "on" or args[0] == "off"):
		return "usage: %s on|off" % what
	var on := args[0] == "on"
	match what:
		"banker":
			Kernel.set_banker(on)
		"recover":
			Kernel.set_auto_recover(on)
		"locks":
			Kernel.set_locks(on)
	return "%s is now %s." % [what, _on(on)]

func _sync() -> String:
	var s := Kernel.sync
	var out := PackedStringArray(["SEMAPHORE TYPE VALUE WAITING"])
	for sem_name in s.semaphores:
		var sem: Dictionary = s.semaphores[sem_name]
		out.append("%-10s %-9s %-6d %s" % [sem_name, "mutex" if sem["mutex"] else "counting", sem["value"], _pids(sem["waiting"])])
	out.append("Locks enforced: %s" % _on(Kernel.locks_enabled))
	var race := " RACE CONDITION: updates were lost!" if Kernel.race_detected() else ""
	out.append("Shared count = %d (should be %d)%s" % [s.shared["count"], s.expected["count"], race])
	out.append("Buffer %d/%d: %s" % [s.buffer.size(), SyncManager.BUFFER_SIZE, str(s.buffer)])
	return "\n".join(out)

func _waiting_for(dev: String) -> Array:
	var out := []
	for p in Kernel.processes:
		if p.state == PCB.WAITING and p.waiting_for == dev:
			out.append(p.pid)
	return out

func _pids(list: Array) -> String:
	if list.is_empty():
		return "-"
	var parts := PackedStringArray()
	for pid in list:
		parts.append("P%d" % pid)
	return ",".join(parts)

func _on(value: bool) -> String:
	return "ON" if value else "OFF"

# ---------- files ----------
func _files(cmd: String, args: PackedStringArray) -> String:
	var fs := Kernel.fs
	var target := cwd
	if not args.is_empty():
		target = FileSystem.normalize(cwd, args[0])
	var node := fs.lookup(target)
	match cmd:
		"pwd":
			return cwd
		"ls":
			if node.is_empty():
				return "ls: no such folder: " + target
			if node["type"] == "file":
				return target.get_file()
			var names := fs.list(target)
			if names.is_empty():
				return "(empty)"
			return " ".join(PackedStringArray(names))
		"cd":
			if args.is_empty():
				target = "/home/user"
				node = fs.lookup(target)
			if node.is_empty() or node["type"] != "dir":
				return "cd: no such folder: " + target
			cwd = target
			return ""
		"mkdir":
			if args.is_empty():
				return "usage: mkdir <folder>"
			var mkdir_error := fs.mkdir(target)
			return mkdir_error if mkdir_error != "" else "Created folder " + target
		"touch":
			if args.is_empty():
				return "usage: touch <file>"
			if not node.is_empty():
				return ""
			var touched := fs.write_file(target, "")
			if touched["error"] != "":
				return "touch: " + touched["error"]
			return "Created %s on blocks %s" % [target, str(touched["blocks"])]
		"write":
			if args.size() < 2:
				return "usage: write <file> <text...>"
			var text := " ".join(args.slice(1))
			var written := fs.write_file(target, text)
			if written["error"] != "":
				return "write: " + written["error"]
			var blocks: Array = written["blocks"]
			return "Wrote %d characters to %s. Index block %d, data blocks %s." % [text.length(), target, blocks[0], str(blocks.slice(1))]
		"cat":
			if args.is_empty():
				return "usage: cat <file>"
			var read_result := fs.read_file(target)
			if read_result["error"] != "":
				return "cat: " + read_result["error"]
			return read_result["content"]
		"rm":
			if args.is_empty():
				return "usage: rm <file or empty folder>"
			var rm_error := fs.remove(target)
			return rm_error if rm_error != "" else "Removed " + target
		"info":
			if args.is_empty():
				return "usage: info <file>"
			return fs.info(target)
		"tree":
			return fs.tree()
		"df":
			var free_blocks := fs.free_count()
			return "Disk: %d blocks of %d characters. Used %d, free %d." % [FileSystem.BLOCKS, FileSystem.BLOCK_SIZE, FileSystem.BLOCKS - free_blocks, free_blocks]
	return ""
