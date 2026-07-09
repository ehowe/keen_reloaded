extends Node
## Scans user://levelpacks for custom level packs. Each pack is a directory
## containing a manifest.json (parsed via LevelPack.from_json) + .tres LevelData
## files. Exposes lookups and zip import. Pure data + IO — no UI.

var root_dir := "user://levelpacks/"
const TMP_IMPORT := "user://levelpacks/.tmp_import/"
const ALLOWED_EXTS := ["tres", "res"]

var _packs: Dictionary = {}       # pack_id -> LevelPack
var _levels: Dictionary = {}      # pack_id -> { level_id -> LevelData }
var _overworlds: Dictionary = {}  # pack_id -> LevelData (map_kind == OVERWORLD)


func _ready() -> void:
	scan()


## Clear caches and walk root_dir/*/manifest.json. Idempotent + safe when the
## directory does not exist yet (no packs installed).
func scan() -> void:
	_packs.clear()
	_levels.clear()
	_overworlds.clear()
	var root := DirAccess.open(root_dir)
	if root == null:
		return
	root.list_dir_begin()
	var subdir := root.get_next()
	while subdir != "":
		if not subdir.begins_with(".") and root.dir_exists(subdir):
			_scan_pack(root_dir.path_join(subdir) + "/")
		subdir = root.get_next()
	root.list_dir_end()


func reload() -> void:
	scan()


func _scan_pack(pack_dir: String) -> void:
	var manifest_path := pack_dir + "manifest.json"
	if not FileAccess.file_exists(manifest_path):
		push_warning("PackLoader: no manifest.json in %s" % pack_dir)
		return
	var pack := LevelPack.from_json(FileAccess.get_file_as_string(manifest_path))
	if pack == null:
		push_warning("PackLoader: invalid manifest in %s" % pack_dir)
		return
	var lvl_map: Dictionary = {}
	var ow: LevelData = null
	for entry in pack.levels:
		var file: String = entry.get("file", "")
		var lid: String = entry.get("level_id", "")
		var path := pack_dir + file
		if not ResourceLoader.exists(path):
			push_warning("PackLoader: cannot load level '%s' in %s" % [file, pack_dir])
			continue
		var res: Resource = load(path)
		if res == null or not (res is LevelData):
			push_warning("PackLoader: cannot load level '%s' in %s" % [file, pack_dir])
			continue
		var ld: LevelData = res
		lvl_map[lid] = ld
		if ld.map_kind == LevelData.MapKind.OVERWORLD:
			if ow == null:
				ow = ld
			else:
				push_warning("PackLoader: multiple overworlds in '%s'; using first" % pack.pack_id)
	if ow == null:
		push_warning("PackLoader: no overworld in pack '%s'" % pack.pack_id)
		return
	_packs[pack.pack_id] = pack
	_levels[pack.pack_id] = lvl_map
	_overworlds[pack.pack_id] = ow


# ---- queries ---------------------------------------------------------------

func get_packs() -> Array:
	return _packs.values()


func get_pack(pack_id: String) -> LevelPack:
	return _packs.get(pack_id)


func get_levels(pack_id: String) -> Array:
	var m: Dictionary = _levels.get(pack_id, {})
	return m.values()


func get_level(pack_id: String, level_id: String) -> LevelData:
	var m: Dictionary = _levels.get(pack_id, {})
	return m.get(level_id)


func get_overworld(pack_id: String) -> LevelData:
	return _overworlds.get(pack_id)


func is_installed(pack_id: String) -> bool:
	return _packs.has(pack_id)


# ---- filesystem helpers (static; reused by import + tests) -----------------

static func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			if dir.dir_exists(name):
				_remove_dir_recursive(path.path_join(name))
			else:
				dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


## Import a level-pack zip. Extracts to TMP_IMPORT with path-traversal + file-
## type hardening, parses the manifest to learn pack_id, then moves to the
## canonical dir root_dir/<pack_id>/ and re-scans. Returns {ok, error, pack_id}.
func import_zip(zip_path: String) -> Dictionary:
	_reset_tmp()
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		reader.close()
		return _fail("cannot read zip")
	var entries := reader.get_files()
	# 1. validate every entry before writing anything to disk
	for entry in entries:
		if entry.ends_with("/"):
			continue  # directory entry; allowed, nothing to write
		if _safe_entry_path(entry) == "":
			reader.close()
			_reset_tmp()
			return _fail("unsafe/disallowed path: %s" % entry)
	# 2. extract to TMP_IMPORT
	DirAccess.make_dir_recursive_absolute(TMP_IMPORT)
	for entry in entries:
		if entry.ends_with("/"):
			continue
		var dest := TMP_IMPORT + _safe_entry_path(entry)
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var f := FileAccess.open(dest, FileAccess.WRITE)
		if f == null:
			reader.close()
			_reset_tmp()
			return _fail("cannot write extracted file: %s" % dest)
		f.store_buffer(reader.read_file(entry))
		f.close()
	reader.close()
	# 3. parse manifest to learn pack_id
	var manifest_path := TMP_IMPORT + "manifest.json"
	if not FileAccess.file_exists(manifest_path):
		_reset_tmp()
		return _fail("no manifest.json")
	var pack := LevelPack.from_json(FileAccess.get_file_as_string(manifest_path))
	if pack == null:
		_reset_tmp()
		return _fail("invalid manifest")
	# 4. move to canonical dir (overwrite if re-importing)
	var canon := root_dir + pack.pack_id + "/"
	_remove_dir_recursive(canon)
	DirAccess.make_dir_recursive_absolute(root_dir)
	var err := DirAccess.rename_absolute(TMP_IMPORT, canon)
	if err != OK:
		_reset_tmp()
		return _fail("cannot install pack dir (err=%d)" % err)
	scan()
	return {"ok": true, "error": "", "pack_id": pack.pack_id}


## Returns a safe relative path for a zip entry, or "" if it is absolute,
## traverses with "..", or has a disallowed extension. Allowlist:
## manifest.json, *.tres, *.res.
static func _safe_entry_path(raw: String) -> String:
	var p := raw.replace("\\", "/").strip_edges()
	if p.is_empty() or p.begins_with("/") or p.begins_with("res://") or p.begins_with("user://"):
		return ""
	if p.length() >= 2 and p[1] == ":":
		return ""  # Windows drive letter (e.g. C:)
	for seg in p.split("/"):
		if seg == "..":
			return ""
	var fname := p.get_file()
	if fname != "manifest.json" and not ALLOWED_EXTS.has(fname.get_extension().to_lower()):
		return ""
	return p


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "pack_id": ""}


func _reset_tmp() -> void:
	_remove_dir_recursive(TMP_IMPORT)
