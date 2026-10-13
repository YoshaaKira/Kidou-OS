extends VBoxContainer
## Settings app: change how the kernel behaves while it is running.

var _sched: OptionButton
var _quantum: SpinBox
var _memory: OptionButton
var _disk: OptionButton
var _locks: CheckButton
var _banker: CheckButton
var _recover: CheckButton

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var cpu_card := UI.card("CPU scheduling")
	var cpu_row := UI.hbox(12)
	cpu_row.add_child(UI.label("Algorithm", 14, UI.MUTED))
	_sched = UI.option(Scheduler.ALGORITHMS, Kernel.set_scheduler)
	cpu_row.add_child(_sched)
	cpu_row.add_child(UI.label("Round Robin quantum (ticks)", 14, UI.MUTED))
	_quantum = UI.spin(1, 10, 2, _on_quantum)
	cpu_row.add_child(_quantum)
	UI.content(cpu_card).add_child(cpu_row)
	UI.content(cpu_card).add_child(UI.paragraph("FCFS = first come, first served. SJF = least remaining work first. Priority = smallest priority number first. These three never interrupt a running process. Round Robin interrupts it after the quantum and sends it to the back of the ready queue.", UI.MUTED, 13))
	add_child(cpu_card)
	var mem_card := UI.card("Memory: page replacement")
	_memory = UI.option(MemoryManager.ALGORITHMS, Kernel.set_memory_algorithm)
	UI.content(mem_card).add_child(_memory)
	UI.content(mem_card).add_child(UI.paragraph("When all 12 frames are full and a page fault happens, FIFO throws out the page that was loaded first; LRU throws out the page that was used least recently.", UI.MUTED, 13))
	add_child(mem_card)
	var disk_card := UI.card("Disk scheduling")
	_disk = UI.option(DiskManager.ALGORITHMS, Kernel.set_disk_algorithm)
	UI.content(disk_card).add_child(_disk)
	UI.content(disk_card).add_child(UI.paragraph("FCFS serves requests in arrival order. SSTF serves the closest one. SCAN sweeps to the end of the disk and back (an elevator). C-SCAN sweeps up only, then jumps back to 0. LOOK is SCAN that turns at the last request.", UI.MUTED, 13))
	add_child(disk_card)
	var sync_card := UI.card("Synchronization and deadlocks")
	_locks = UI.toggle("Mutex locks enforced", true, Kernel.set_locks)
	UI.content(sync_card).add_child(_locks)
	_banker = UI.toggle("Banker's algorithm (refuse unsafe device requests)", false, Kernel.set_banker)
	UI.content(sync_card).add_child(_banker)
	_recover = UI.toggle("Automatic deadlock recovery (kill the youngest process in a deadlock)", false, Kernel.set_auto_recover)
	UI.content(sync_card).add_child(_recover)
	UI.content(sync_card).add_child(UI.paragraph("Switch locks OFF to allow race conditions. Switch Banker's ON to prevent deadlocks before they happen.", UI.MUTED, 13))
	add_child(sync_card)
	var system_card := UI.card("System")
	UI.content(system_card).add_child(UI.button("Reboot Kidou OS", Kernel.boot))
	UI.content(system_card).add_child(UI.paragraph("Kills every process, formats the disk and resets every setting.", UI.MUTED, 13))
	add_child(system_card)
	Kernel.changed.connect(_sync_controls, CONNECT_DEFERRED)
	_sync_controls()

func _on_quantum(value: float) -> void:
	Kernel.set_quantum(int(value))

## Makes the controls match the kernel (settings can also change from the
## terminal).
func _sync_controls() -> void:
	_sched.select(Kernel.scheduler.algorithm)
	_quantum.set_value_no_signal(Kernel.scheduler.quantum)
	_memory.select(Kernel.memory.algorithm)
	_disk.select(Kernel.disk.algorithm)
	_locks.set_pressed_no_signal(Kernel.locks_enabled)
	_banker.set_pressed_no_signal(Kernel.banker_enabled)
	_recover.set_pressed_no_signal(Kernel.auto_recover)
