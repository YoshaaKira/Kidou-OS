class_name Programs
extends RefCounted
## The programs installed in Kidou OS. Each one is a list of instructions
## that the kernel executes one per tick:
## ["CPU", n] compute for n ticks
## ["MEM", page] use a virtual page (may cause a page fault)
## ["IO", cylinder] read the disk at that cylinder
## ["READ", path] read a file ["WRITE", path, blocks] write a file
## ["REQ", device] request a device ["REL", device] release it
## ["WAIT", sem] semaphore wait ["SIGNAL", sem] semaphore signal
## ["LOAD", var] register = shared variable
## ["STORE", var, d] shared variable = register + d
## ["PUT"] / ["GET"] add to / take from the shared buffer
## ["LOOP", to, n] jump back to instruction `to`, n times in total
## "{pid}" in a file path is replaced by the process ID.

const LIBRARY := {
	"compiler": {
		"about": "CPU-heavy. Compiles code, then writes an object file.",
		"priority": 3, "pages": 3, "max": {},
		"code": [["CPU", 4], ["MEM", 0], ["CPU", 3], ["MEM", 1],
		["CPU", 3], ["MEM", 2], ["WRITE", "/tmp/build_{pid}.o", 2], ["CPU", 1]],
	},
	"editor": {
		"about": "Interactive. Short bursts, reads a file, saves notes.",
		"priority": 1, "pages": 2, "max": {},
		"code": [["MEM", 0], ["CPU", 1], ["READ", "/home/user/readme.txt"],
		["CPU", 1], ["MEM", 1], ["WRITE", "/home/user/notes_{pid}.txt", 1], ["CPU", 1]],
	},
	"music": {
		"about": "I/O-heavy. Streams audio from the disk in small chunks.",
		"priority": 2, "pages": 1, "max": {},
		"code": [["MEM", 0], ["IO", 40], ["CPU", 1], ["IO", 110],
		["CPU", 1], ["LOOP", 1, 3]],
	},
	"memhog": {
		"about": "Memory-heavy. Touches 8 pages twice to stress paging.",
		"priority": 4, "pages": 8, "max": {},
		"code": [["MEM", 0], ["MEM", 1], ["MEM", 2], ["MEM", 3],
		["MEM", 4], ["MEM", 5], ["MEM", 6], ["MEM", 7], ["CPU", 1], ["LOOP", 0, 2]],
	},
	"print_job": {
		"about": "Takes the PRINTER, then the SCANNER. Deadlock demo.",
		"priority": 2, "pages": 1, "max": {"PRINTER": 1, "SCANNER": 1},
		"code": [["REQ", "PRINTER"], ["CPU", 2], ["REQ", "SCANNER"],
		["CPU", 2], ["REL", "SCANNER"], ["REL", "PRINTER"]],
	},
	"scan_job": {
		"about": "Takes the SCANNER, then the PRINTER. Deadlock demo.",
		"priority": 2, "pages": 1, "max": {"PRINTER": 1, "SCANNER": 1},
		"code": [["REQ", "SCANNER"], ["CPU", 2], ["REQ", "PRINTER"],
		["CPU", 2], ["REL", "PRINTER"], ["REL", "SCANNER"]],
	},
	"backup": {
		"about": "Needs both TAPE drives. Banker's algorithm demo.",
		"priority": 3, "pages": 1, "max": {"TAPE": 2},
		"code": [["REQ", "TAPE"], ["CPU", 1], ["REQ", "TAPE"],
		["READ", "/home/user/readme.txt"], ["CPU", 2], ["WRITE", "/tmp/backup_{pid}.bak", 1],
		["REL", "TAPE"], ["REL", "TAPE"]],
	},
	"counter": {
		"about": "Adds 1 to a shared counter 5 times. Race-condition demo.",
		"priority": 2, "pages": 1, "max": {},
		"code": [["WAIT", "mutex"], ["LOAD", "count"], ["CPU", 1],
		["STORE", "count", 1], ["SIGNAL", "mutex"], ["LOOP", 0, 5]],
	},
	"producer": {
		"about": "Puts 6 items into the shared 5-slot buffer.",
		"priority": 2, "pages": 1, "max": {},
		"code": [["CPU", 1], ["WAIT", "empty"], ["WAIT", "buf_lock"],
		["PUT"], ["SIGNAL", "buf_lock"], ["SIGNAL", "full"], ["LOOP", 0, 6]],
	},
	"consumer": {
		"about": "Takes 6 items out of the shared buffer.",
		"priority": 2, "pages": 1, "max": {},
		"code": [["WAIT", "full"], ["WAIT", "buf_lock"], ["GET"],
		["SIGNAL", "buf_lock"], ["SIGNAL", "empty"], ["CPU", 2], ["LOOP", 0, 6]],
	},
}

static func names() -> Array:
	return LIBRARY.keys()

static func exists(program_name: String) -> bool:
	return LIBRARY.has(program_name)

static func info(program_name: String) -> Dictionary:
	return LIBRARY[program_name]

## ["CPU", 4] -> "CPU 4"
static func describe(ins: Array) -> String:
	var parts := PackedStringArray()
	for x in ins:
		parts.append(str(x))
	return " ".join(parts)
