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


func register(type_id: String, category: String, label: String, properties: Array = [], scene: PackedScene = null) -> void:
	_entries[type_id] = {
		"type_id": type_id,
		"category": category,
		"label": label,
		"properties": properties,
		"scene": scene,
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


## Instantiate a node for `type_id` at `pos` with `props`. Uses the registered
## PackedScene if present, else a default base-class node by category. Adds the
## node to group "entity". Returns null for unknown types.
func instantiate(type_id: String, pos: Vector2, props: Dictionary = {}) -> Node2D:
	if not _entries.has(type_id):
		push_warning("EntityRegistry: unknown entity type '%s'" % type_id)
		return null
	var entry: Dictionary = _entries[type_id]
	var node: Node2D = null
	var scene: Variant = entry.get("scene", null)
	if scene != null and scene is PackedScene:
		node = (scene as PackedScene).instantiate()
	else:
		node = _default_node_for_category(String(entry.get("category", "")))
	if node == null:
		return null
	if node.has_method("setup"):
		node.setup(type_id, props)
	else:
		node.set("type_id", type_id)
		node.set("properties", props)
	node.position = pos
	node.add_to_group("entity")
	return node


func _default_node_for_category(category: String) -> Node2D:
	match category:
		CATEGORY_ENEMY:
			return Enemy.new()
		CATEGORY_ITEM:
			return Collectible.new()
		CATEGORY_HAZARD:
			return Hazard.new()
		CATEGORY_SPECIAL:
			return Special.new()
	return Entity.new()
