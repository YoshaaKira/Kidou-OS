extends VBoxContainer
## Storage app: the disk (head movement + request queue) and the file system
## (blocks + folders).

var _disk_info: Label
var _chart: DiskChart
var _fs_info: Label
var _blocks: BlockGrid
var _tree: Label

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var row := UI.hbox(10)
	add_child(row)
	var disk_card := UI.card("Disk: 200 cylinders, the head moves up to 25 per tick")
	disk_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_disk_info = UI.paragraph("", UI.TEXT, 13)
	UI.content(disk_card).add_child(_disk_info)
	_chart = DiskChart.new()
	UI.content(disk_card).add_child(_chart)
	UI.content(disk_card).add_child(UI.paragraph("Red dots = waiting requests. Blue line = where the head went (top = 40 ticks ago). Dark band = swap area (cylinders 140-199) used by page faults.", UI.MUTED, 12))
	row.add_child(disk_card)
	var fs_card := UI.card("File system: 64 blocks, indexed allocation")
	fs_card.custom_minimum_size.x = 320
	_fs_info = UI.paragraph("", UI.TEXT, 13)
	UI.content(fs_card).add_child(_fs_info)
	_blocks = BlockGrid.new()
	UI.content(fs_card).add_child(_blocks)
	UI.content(fs_card).add_child(UI.paragraph("Grey = superblock Yellow = index block Blue = data block Dark = free", UI.MUTED, 12))
	row.add_child(fs_card)
	var tree_card := UI.card("Folders and files (try: write notes.txt hello, then info notes.txt)")
	_tree = UI.mono("", 13)
	UI.content(tree_card).add_child(_tree)
	add_child(tree_card)
	Kernel.ticked.connect(_on_tick)
	Kernel.changed.connect(_refresh, CONNECT_DEFERRED)
	_refresh()

func _on_tick(_time: int) -> void:
	_refresh()

func _refresh() -> void:
	var d := Kernel.disk
	_disk_info.text = "Algorithm: %s Head: cylinder %d, moving %s\nServed: %d Total head movement: %d cylinders\nQueue: %s" % [
		DiskManager.ALGORITHMS[d.algorithm], d.head, d.direction_text(), d.served,
		d.total_movement, d.queue_text()
	]
	_chart.queue_redraw()
	var fs := Kernel.fs
	var free_blocks := fs.free_count()
	_fs_info.text = "Used %d of %d blocks, %d free" % [FileSystem.BLOCKS - free_blocks, FileSystem.BLOCKS, free_blocks]
	_blocks.queue_redraw()
	_tree.text = fs.tree()
