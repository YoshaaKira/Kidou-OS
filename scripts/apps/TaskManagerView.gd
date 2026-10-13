extends VBoxContainer
## Task Manager: every live process, its state, and what the CPU has been
## doing.

const STATE_COLORS := {
	"NEW": Color("#8a96b0"), "READY": Color("#ffca28"), "RUNNING": Color("#66bb6a"),
	"WAITING": Color("#ef5350"), "TERMINATED": Color("#4fc3f7"),
}

var _summary: Label
var _timeline: CpuTimeline
var _table: GridContainer
var _finished: Label
var _log: Label

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var cpu_card := UI.card("CPU (each block = one tick, number = PID)")
	_summary = UI.paragraph("", UI.TEXT, 14)
	UI.content(cpu_card).add_child(_summary)
	_timeline = CpuTimeline.new()
	UI.content(cpu_card).add_child(_timeline)
	add_child(cpu_card)
	var table_card := UI.card("Processes")
	_table = GridContainer.new()
	_table.columns = 9
	UI.content(table_card).add_child(_table)
	_finished = UI.paragraph("", UI.MUTED, 13)
	UI.content(table_card).add_child(_finished)
	add_child(table_card)
	var log_card := UI.card("Kernel log")
	_log = UI.mono("", 12, UI.MUTED)
	UI.content(log_card).add_child(_log)
	add_child(log_card)
	Kernel.ticked.connect(_on_tick)
	Kernel.changed.connect(_refresh, CONNECT_DEFERRED)
	_refresh()

func _on_tick(_time: int) -> void:
	_refresh()

func _refresh() -> void:
	var s := Kernel.stats()
	_summary.text = "Scheduler: %s (quantum %d) Alive: %d\nFinished: %d CPU utilisation: %.0f%%\nAverage waiting: %.1f ticks\nAverage turnaround: %.1f ticks Context switches: %d" % [
		Scheduler.ALGORITHMS[Kernel.scheduler.algorithm], Kernel.scheduler.quantum,
		Kernel.processes.size(), s["finished"], s["utilisation"], s["avg_wait"],
		s["avg_turnaround"], Kernel.context_switches
	]
	_timeline.queue_redraw()
	UI.clear(_table)
	for h in ["PID", "Program", "State", "Pri", "Doing now", "CPU", "Wait", "Faults", ""]:
		_table.add_child(UI.label(h, 13, UI.MUTED, true))
	for p in Kernel.processes:
		_table.add_child(UI.label("P%d" % p.pid, 14, UI.pid_color(p.pid), true))
		_table.add_child(UI.label(p.name, 14))
		var state: String = p.state_name()
		_table.add_child(UI.label(state, 14, STATE_COLORS[state], true))
		_table.add_child(UI.mono(str(p.priority)))
		var doing_label := UI.label(p.doing(), 13)
		doing_label.custom_minimum_size.x = 230
		doing_label.clip_text = true
		_table.add_child(doing_label)
		_table.add_child(UI.mono(str(p.cpu_time)))
		_table.add_child(UI.mono(str(p.wait_time)))
		_table.add_child(UI.mono(str(p.page_faults)))
		_table.add_child(UI.button("End", Kernel.kill.bind(p.pid)))
	if Kernel.processes.is_empty() and Kernel.finished.is_empty():
		_finished.text = "No processes yet. Click a program on the left, or type run compiler editor music in the terminal, then press Play."
	else:
		var lines := PackedStringArray(["Finished processes (latest 4):"])
		for p in Kernel.finished.slice(-4):
			lines.append(" P%d %s: %s at t=%d, turnaround %d, waited %d ticks" % [
				p.pid, p.name, p.exit_reason, p.finish_time,
				p.finish_time - p.arrival, p.wait_time
			])
		_finished.text = "\n".join(lines)
	_log.text = "\n".join(PackedStringArray(Kernel.log_lines.slice(-7)))
