extends VBoxContainer
## Resources & Sync app: devices, the live resource-allocation graph,
## deadlocks,
## semaphores, the shared counter (race conditions) and the shared buffer.

var _devices: GridContainer
var _status: Label
var _graph: RagGraph
var _sems: GridContainer
var _counter: Label
var _buffer: HBoxContainer

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var dev_card := UI.card("Devices and deadlocks")
	_devices = GridContainer.new()
	_devices.columns = 5
	UI.content(dev_card).add_child(_devices)
	_status = UI.paragraph("", UI.GOOD, 15)
	UI.content(dev_card).add_child(_status)
	_graph = RagGraph.new()
	UI.content(dev_card).add_child(_graph)
	UI.content(dev_card).add_child(UI.label("Blue arrow: device is held by process. Yellow arrow: process waits for device. Red: deadlock.", 12, UI.MUTED))
	add_child(dev_card)
	var sync_card := UI.card("Synchronization")
	_sems = GridContainer.new()
	_sems.columns = 4
	UI.content(sync_card).add_child(_sems)
	_counter = UI.paragraph("", UI.TEXT, 15)
	UI.content(sync_card).add_child(_counter)
	UI.content(sync_card).add_child(UI.label("Shared buffer (producer puts, consumer takes):", 13, UI.MUTED))
	_buffer = UI.hbox(8)
	UI.content(sync_card).add_child(_buffer)
	add_child(sync_card)
	Kernel.ticked.connect(_on_tick)
	Kernel.changed.connect(_refresh, CONNECT_DEFERRED)
	_refresh()

func _on_tick(_time: int) -> void:
	_refresh()

func _refresh() -> void:
	var res := Kernel.resources
	# --- devices ---
	UI.clear(_devices)
	for h in ["Device", "Total", "Free", "Held by", "Waiting"]:
		_devices.add_child(UI.label(h, 13, UI.MUTED, true))
	for dev in ResourceManager.TOTAL:
		_devices.add_child(UI.label(dev, 14, UI.TEXT, true))
		_devices.add_child(UI.mono(str(ResourceManager.TOTAL[dev])))
		_devices.add_child(UI.mono(str(res.available[dev])))
		_devices.add_child(UI.mono(_pids(res.holders(dev))))
		_devices.add_child(UI.mono(_pids(_waiting_for(dev))))
	if Kernel.deadlocked.is_empty():
		_set_label(_status, "No deadlock. Banker's avoidance: %s\nAuto recovery: %s" % [_on(Kernel.banker_enabled), _on(Kernel.auto_recover)], UI.GOOD)
	else:
		_set_label(_status, "DEADLOCK: %s are each waiting for a device another one holds, so none can ever continue. Click End in the Task Manager, type kill <pid>, or turn on auto recovery." % _pids(Kernel.deadlocked), UI.BAD)
	_graph.queue_redraw()
	# --- semaphores ---
	var s := Kernel.sync
	UI.clear(_sems)
	for h in ["Semaphore", "Type", "Value", "Waiting"]:
		_sems.add_child(UI.label(h, 13, UI.MUTED, true))
	for sem_name in s.semaphores:
		var sem: Dictionary = s.semaphores[sem_name]
		_sems.add_child(UI.mono(sem_name))
		_sems.add_child(UI.mono("mutex" if sem["mutex"] else "counting"))
		_sems.add_child(UI.mono(str(sem["value"])))
		_sems.add_child(UI.mono(_pids(sem["waiting"])))
	# --- shared counter ---
	var count: int = s.shared["count"]
	var should_be: int = s.expected["count"]
	if Kernel.race_detected():
		_set_label(_counter, "Shared count = %d but it should be %d.\nRACE CONDITION: %d update(s) were lost because two processes changed count at the same time without a lock." % [count, should_be, should_be - count], UI.BAD)
	else:
		_set_label(_counter, "Shared count = %d (should be %d)\nMutex locks: %s" % [count, should_be, _on(Kernel.locks_enabled)], UI.TEXT)
	# --- buffer ---
	UI.clear(_buffer)
	for i in SyncManager.BUFFER_SIZE:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(70, 46)
		var filled: bool = i < s.buffer.size()
		slot.add_theme_stylebox_override("panel", UI.box(UI.ACCENT if filled else UI.PANEL_LIGHT, 8))
		var slot_label := UI.label("#%d" % s.buffer[i] if filled else "empty", 14, UI.BG if filled else UI.MUTED, true)
		slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(slot_label)
		_buffer.add_child(slot)

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
	return ", ".join(parts)

func _on(value: bool) -> String:
	return "ON" if value else "OFF"

func _set_label(label: Label, text: String, color: Color) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
