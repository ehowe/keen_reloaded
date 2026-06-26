extends Node
## Extensible entity catalog (autoload). This plan implements the DATA layer:
## register / lookup / palette entries, which the editor's entity palette reads.
## Plan 3 adds scene instantiation: instantiate(type_id, position, props) -> Node2D.

const CATEGORY_ENEMY := "enemy"
const CATEGORY_ITEM := "item"
const CATEGORY_HAZARD := "hazard"
const CATEGORY_SPECIAL := "special"

var _entries: Dictionary = {}  # type_id -> { type_id, category, label, properties }


func _ready() -> void:
	_register_defaults()


## Ships a small default set so the editor palette isn't empty before episodes
## register their own content (Plan 3+). Tests call clear() to start clean.
func _register_defaults() -> void:
	register("vorticon", CATEGORY_ENEMY, "Vorticon")
	register("yorp", CATEGORY_ENEMY, "Yorp")
	register("butler", CATEGORY_HAZARD, "Butler Robot")
	register("candy", CATEGORY_ITEM, "Candy")
	register("exit_door", CATEGORY_SPECIAL, "Exit Door")
	register("player_spawn", CATEGORY_SPECIAL, "Player Spawn")


func register(type_id: String, category: String, label: String, properties: Array = []) -> void:
	_entries[type_id] = {
		"type_id": type_id,
		"category": category,
		"label": label,
		"properties": properties,
	}


func has(type_id: String) -> bool:
	return _entries.has(type_id)


func get_entry(type_id: String) -> Dictionary:
	return _entries.get(type_id, {})


func get_palette_entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.assign(_entries.values())
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := String(a.get("category", ""))
		var cb := String(b.get("category", ""))
		if ca != cb:
			return ca < cb
		return String(a.get("label", "")) < String(b.get("label", "")))
	return list


func clear() -> void:
	_entries.clear()
