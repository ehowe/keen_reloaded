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
func load_overworld() -> LevelData:
	if overworld_path == "":
		return null
	if not ResourceLoader.exists(overworld_path):
		push_warning("Episode '%s': overworld not found at %s" % [id, overworld_path])
		return null
	return ResourceLoader.load(overworld_path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData


## Loads every LEVEL-kind LevelData .tres in the overworld's directory. The
## overworld itself (map_kind OVERWORLD) is excluded — GameManager registers it
## separately. Returns an empty array if no overworld_path is configured.
func load_levels() -> Array:
	if overworld_path == "":
		return []
	var dir_path := overworld_path.get_base_dir() + "/"
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return []
	var levels: Array = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		var ext := fname.get_extension().to_lower()
		if (ext == "tres" or ext == "res") and fname != overworld_path.get_file():
			var res := load(dir_path + fname)
			if res is LevelData and res.map_kind == LevelData.MapKind.LEVEL:
				levels.append(res)
		fname = dir.get_next()
	dir.list_dir_end()
	return levels


## Override: register this episode's entity types into `registry`.
func register_entities(_registry: Node) -> void:
	pass
