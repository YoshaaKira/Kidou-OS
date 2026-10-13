class_name FileSystem
extends RefCounted
## A small file system stored on the simulated disk.
## 64 blocks. Block 0 = superblock. Files use INDEXED allocation:
## one index block lists the file's data blocks, which can be anywhere.

const BLOCKS := 64
const BLOCK_SIZE := 32 # characters per data block

var owner: Array = [] # owner[b] = "" if block b is free, otherwise what uses it
var root: Dictionary = {}

func _init() -> void:
	owner.resize(BLOCKS)
	owner.fill("")
	owner[0] = "superblock"
	root = {"type": "dir", "children": {}}
	mkdir("/bin")
	mkdir("/home")
	mkdir("/home/user")
	mkdir("/tmp")
	write_file("/home/user/readme.txt", "Welcome to Kidou OS! This file is stored on the simulated disk using indexed allocation.")

# ---------- paths ----------
## Turns what the user typed into a clean absolute path.
## Example: normalize("/home/user", "../tmp/a.txt") -> "/home/tmp/a.txt"
static func normalize(cwd: String, path: String) -> String:
	var full := path if path.begins_with("/") else cwd + "/" + path
	var parts := []
	for part in full.split("/", false):
		if part == ".":
			continue
		elif part == "..":
			if not parts.is_empty():
				parts.pop_back()
		else:
			parts.append(part)
	return "/" + "/".join(PackedStringArray(parts))

## Finds a file or folder. Returns {} if it does not exist.
func lookup(path: String) -> Dictionary:
	var node: Dictionary = root
	for part in path.split("/", false):
		if node["type"] != "dir" or not node["children"].has(part):
			return {}
		node = node["children"][part]
	return node

## "/home/user/a.txt" -> ["/home/user", "a.txt"]
func _split(path: String) -> Array:
	var i := path.rfind("/")
	var parent := path.substr(0, i)
	if parent == "":
		parent = "/"
	return [parent, path.substr(i + 1)]

# ---------- folders ----------
## Returns "" if it worked, or an error message.
func mkdir(path: String) -> String:
	if path == "/":
		return "mkdir: / already exists"
	var parts := _split(path)
	var parent := lookup(parts[0])
	if parent.is_empty() or parent["type"] != "dir":
		return "mkdir: no such directory: " + str(parts[0])
	if parent["children"].has(parts[1]):
		return "mkdir: already exists: " + path
	parent["children"][parts[1]] = {"type": "dir", "children": {}}
	return ""

## Names inside a folder, sorted. Folders end with "/".
func list(path: String) -> Array:
	var node := lookup(path)
	if node.is_empty() or node["type"] != "dir":
		return []
	var names := []
	for child_name in node["children"]:
		var child: Dictionary = node["children"][child_name]
		names.append(child_name + "/" if child["type"] == "dir" else child_name)
	names.sort()
	return names

# ---------- files ----------
## Creates or overwrites a file. data_blocks = -1 means "as many as the text needs".
## Returns {"error": "", "blocks": [index block, data block, data block, ...]}
func write_file(path: String, text: String, data_blocks: int = -1) -> Dictionary:
	var parts := _split(path)
	var parent := lookup(parts[0])
	if parent.is_empty() or parent["type"] != "dir":
		return {"error": "no such directory: " + str(parts[0]), "blocks": []}
	var existing: Dictionary = parent["children"].get(parts[1], {})
	if not existing.is_empty() and existing["type"] == "dir":
		return {"error": path + " is a directory", "blocks": []}
	if data_blocks < 0:
		data_blocks = maxi(1, ceili(text.length() / float(BLOCK_SIZE)))
	if not existing.is_empty():
		_free_blocks(existing)
		parent["children"].erase(parts[1])
	var blocks := _allocate(data_blocks + 1, path)
	if blocks.is_empty():
		return {"error": "disk full: cannot write " + path, "blocks": []}
	owner[blocks[0]] = "index:" + path
	parent["children"][parts[1]] = {
		"type": "file",
		"index": blocks[0],
		"data": blocks.slice(1),
		"content": text
	}
	return {"error": "", "blocks": blocks}

## Returns {"error": "", "content": text, "blocks": [index block, data blocks...]}
func read_file(path: String) -> Dictionary:
	var node := lookup(path)
	if node.is_empty():
		return {"error": "no such file: " + path, "content": "", "blocks": []}
	if node["type"] != "file":
		return {"error": path + " is a directory", "content": "", "blocks": []}
	var blocks: Array = [node["index"]]
	blocks.append_array(node["data"])
	return {"error": "", "content": node["content"], "blocks": blocks}

## Deletes a file or an EMPTY folder. Returns "" if it worked, or an error message.
func remove(path: String) -> String:
	if path == "/":
		return "rm: cannot remove /"
	var node := lookup(path)
	if node.is_empty():
		return "rm: no such file or directory: " + path
	if node["type"] == "dir" and not node["children"].is_empty():
		return "rm: directory not empty: " + path
	if node["type"] == "file":
		_free_blocks(node)
	var parts := _split(path)
	var parent := lookup(parts[0])
	parent["children"].erase(parts[1])
	return ""

## Takes `count` free blocks (first free ones; indexed allocation does not need them together).
func _allocate(count: int, path: String) -> Array:
	var found := []
	for b in BLOCKS:
		if owner[b] == "":
			found.append(b)
		if found.size() == count:
			break
	if found.size() < count:
		return []
	for b in found:
		owner[b] = "data:" + path
	return found

func _free_blocks(file: Dictionary) -> void:
	owner[file["index"]] = ""
	for b in file["data"]:
		owner[b] = ""

# ---------- information ----------
func free_count() -> int:
	var n := 0
	for o in owner:
		if o == "":
			n += 1
	return n

## Which disk cylinder a block sits on.
static func cylinder_of(block: int) -> int:
	return block * 2

## Explains where a file is stored (used by the `info` command).
func info(path: String) -> String:
	var node := lookup(path)
	if node.is_empty():
		return "info: no such file: " + path
	if node["type"] == "dir":
		return "%s is a folder with %d entries." % [path, node["children"].size()]
	var blocks: Array = [node["index"]]
	blocks.append_array(node["data"])
	var cylinders := PackedStringArray()
	for b in blocks:
		cylinders.append(str(cylinder_of(b)))
	return "%s\n size: %d characters\n index block: %d\n data blocks: %s\n disk cylinders: %s" % [path, node["content"].length(), node["index"], str(node["data"]), ", ".join(cylinders)]

## The whole folder tree as text (used by the `tree` command and the Storage app).
func tree() -> String:
	var out := ["/"]
	_tree(root, " ", out)
	return "\n".join(PackedStringArray(out))

func _tree(node: Dictionary, indent: String, out: Array) -> void:
	var names: Array = node["children"].keys()
	names.sort()
	for child_name in names:
		var child: Dictionary = node["children"][child_name]
		if child["type"] == "dir":
			out.append(indent + child_name + "/")
			_tree(child, indent + " ", out)
		else:
			out.append("%s%s (%d blocks)" % [indent, child_name, child["data"].size() + 1])
