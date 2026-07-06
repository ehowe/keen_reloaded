class_name Episode
extends RefCounted
## A content module that registers its entity types into the global EntityRegistry
## catalog at boot. Episodes live under src/episodes/<id>/episode.gd and are
## auto-discovered by GameManager. type_ids are namespaced (e.g. "keen1.vorticon")
## so multiple episodes can coexist in one union catalog.

var id: String = ""
var title: String = ""
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


## Override: register this episode's entity types into `registry`.
func register_entities(_registry: Node) -> void:
	pass
