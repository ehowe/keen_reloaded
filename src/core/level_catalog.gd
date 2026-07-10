class_name LevelCatalog
## Static utility: scans the project for LevelData resources and returns their
## level_ids. Used by the editor inspector to populate the destination_level_id
## dropdown so authors pick from real levels instead of typing free text. Pure
## data discovery — no state, no UI.

const DEFAULT_SCAN_DIRS := ["res://levels/", "res://assets/levels/", "user://levelpacks/"]
const ALLOWED_EXTS := ["tres", "res"]


## Walk `dirs` recursively for .tres/.res files, load each, and collect level_id
## from any that are LevelData. Returns a sorted, de-duplicated array of ids.
static func scan_level_ids(dirs: Array = DEFAULT_SCAN_DIRS) -> Array[String]:
	var ids: Dictionary = {}  # id -> true (ordered set for dedup)
	for d in dirs:
		_collect(d, ids)
	var out: Array[String] = []
	for k in ids:
		out.append(String(k))
	out.sort()
	return out


static func _collect(dir_path: String, ids: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path + name
		if dir.dir_exists(name):
			_collect(full + "/", ids)
		elif _is_level_file(name):
			_try_add(full, ids)
		name = dir.get_next()
	dir.list_dir_end()


static func _is_level_file(fname: String) -> bool:
	var ext := fname.get_extension().to_lower()
	return ALLOWED_EXTS.has(ext)


static func _try_add(path: String, ids: Dictionary) -> void:
	if not ResourceLoader.exists(path):
		return
	var res := load(path)
	if res != null and res is LevelData:
		var ld: LevelData = res
		if ld.level_id != "":
			ids[ld.level_id] = true
