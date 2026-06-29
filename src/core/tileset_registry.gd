extends Node
## Catalog of known TileSets for the editor's TileSet picker (autoload). The
## picker can't DirAccess-scan res:// in an exported .pck (directory listing
## doesn't work over the packed virtual filesystem), so the catalog is explicit.
## Mirrors EntityRegistry's shape. Entries whose resource file is absent (e.g.
## untracked on a fresh checkout) are skipped via available().

var _entries: Dictionary = {}  # path -> { "path": ..., "label": ... }


func _ready() -> void:
	_register_defaults()


## Re-register built-ins. Tests that clear() call this in after_each (the
## autoload _ready only fires once, at boot).
func register_defaults() -> void:
	_register_defaults()


func _register_defaults() -> void:
	register("res://assets/tilesets/Invasion of the Vorticons.tres", "Vorticons")


func register(path: String, label: String) -> void:
	_entries[path] = {"path": path, "label": label}


func has(path: String) -> bool:
	return _entries.has(path)


## All registered entries, insertion-ordered (Dictionary preserves order in 4.x).
func get_entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.assign(_entries.values())
	return list


## Registered entries whose resource resolves to a TileSet (export-safe via
## ResourceLoader.exists + TileSet type hint). Use this in the picker.
func available() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for e in _entries.values():
		var d: Dictionary = e
		var p: String = String(d.get("path", ""))
		if p != "" and ResourceLoader.exists(p, "TileSet"):
			list.append(d)
	return list


func clear() -> void:
	_entries.clear()
