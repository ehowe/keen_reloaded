class_name Episode
extends RefCounted
## A content module that registers its entity types into the global EntityRegistry
## catalog at boot. Episodes live under src/episodes/<id>/episode.gd and are
## auto-discovered by GameManager. type_ids are namespaced (e.g. "keen1.vorticon")
## so multiple episodes can coexist in one union catalog.

var id: String = ""
var title: String = ""


## Override: register this episode's entity types into `registry`.
func register_entities(_registry: Node) -> void:
	pass
