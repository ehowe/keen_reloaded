class_name Episode
extends RefCounted
## A content module that registers its entity types into the global EntityRegistry
## catalog at boot. Episodes live under src/episodes/<id>/episode.gd and are
## auto-discovered by GameManager. type_ids are namespaced (e.g. "keen1.vorticon")
## so multiple episodes can coexist in one union catalog.

var id: String = ""
var title: String = ""
# Plan 5 (PackLoader) will consume overworld_level_id to resolve the overworld
# from the level catalog instead of the direct path below.
var overworld_level_id: String = ""
var overworld_path: String = ""  # res:// path to the bundled overworld .tres; empty until authored


## Loads this episode's overworld LevelData, or returns null if none is configured.
## Prefers a sibling .res (binary) over the authored .tres: Godot 4.7's export
## converter strips PackedInt32Array data from .tres during text→binary
## conversion, so we ship a pre-converted .res that preserves tile arrays.
func load_overworld() -> LevelData:
	if overworld_path == "":
		return null
	var bin_path := _binary_sibling(overworld_path)
	var path := overworld_path
	if bin_path != "" and ResourceLoader.exists(bin_path):
		path = bin_path
	if not ResourceLoader.exists(path):
		push_warning("Episode '%s': overworld not found at %s" % [id, overworld_path])
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData


## Returns the .res path matching a .tres path, or "" if the input isn't .tres.
static func _binary_sibling(tres_path: String) -> String:
	if tres_path.get_extension().to_lower() != "tres":
		return ""
	return tres_path.get_basename() + ".res"


## Loads every LEVEL-kind LevelData in the overworld's directory. Prefers
## sibling .res over .tres (see load_overworld for why). The overworld itself
## (map_kind OVERWORLD) is excluded — GameManager registers it separately.
## Returns an empty array if no overworld_path is configured.
func load_levels() -> Array:
	if overworld_path == "":
		return []
	var dir_path := overworld_path.get_base_dir() + "/"
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return []
	var levels: Array = []
	# Collect candidate basenames (prefer .res; fall back to .tres). Directory
	# listing returns both siblings; we dedupe by basename and pick the binary
	# form when present.
	var seen: Dictionary = {}  # basename_no_ext -> chosen full fname
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		var ext := fname.get_extension().to_lower()
		if ext == "res" or ext == "tres":
			var base := fname.get_basename()
			var chosen: String = seen.get(base, "")
			if chosen == "" or (ext == "res" and chosen.get_extension().to_lower() == "tres"):
				seen[base] = fname
		fname = dir.get_next()
	dir.list_dir_end()
	for base in seen:
		var pick: String = seen[base]
		if pick == overworld_path.get_file():
			continue  # skip the overworld itself
		var res := load(dir_path + pick)
		if res is LevelData and res.map_kind in [LevelData.MapKind.LEVEL, LevelData.MapKind.MESSAGE]:
			levels.append(res)
	return levels


## Override: register this episode's entity types into `registry`.
func register_entities(_registry: Node) -> void:
	pass
