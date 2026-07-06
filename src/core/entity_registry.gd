extends Node
## Extensible entity catalog (autoload). A pure union catalog: episodes register
## their namespaced types at boot via GameManager.register_episodes(); nothing
## is hardcoded here. The editor palette reads get_palette_entries(); the runtime
## spawns via instantiate(type_id, pos, props).

const CATEGORY_ENEMY := "enemy"
const CATEGORY_ITEM := "item"
const CATEGORY_HAZARD := "hazard"
const CATEGORY_SPECIAL := "special"
const CATEGORY_DECOR := "decor"

var _entries: Dictionary = {}  # type_id -> { type_id, category, label, properties, scene | scene_path }


## Register (or overwrite) one entity type.
func register(type_id: String, category: String, label: String, properties: Array = [], scene: PackedScene = null, map_kinds: Array[int] = []) -> void:
	if map_kinds.is_empty():
		map_kinds = [LevelData.MapKind.LEVEL]
	_entries[type_id] = {
		"type_id": type_id,
		"category": category,
		"label": label,
		"properties": properties,
		"scene": scene,
		"map_kinds": map_kinds,
	}


## Register a pure-decoration sprite scene (.tscn under assets/sprites/) as a
## placeable entity. The scene is loaded lazily at spawn time, so a missing file
## is skipped gracefully. Mirrors register()'s entry shape but stores a path
## string (scene_path) instead of a preloaded PackedScene.
func register_sprite(type_id: String, category: String, label: String, scene_path: String, properties: Array = [], map_kinds: Array[int] = []) -> void:
	if map_kinds.is_empty():
		map_kinds = [LevelData.MapKind.LEVEL]
	_entries[type_id] = {
		"type_id": type_id,
		"category": category,
		"label": label,
		"properties": properties,
		"scene_path": scene_path,
		"map_kinds": map_kinds,
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


## Palette entries filtered to those valid for the given map kind.
func get_palette_entries_for_kind(map_kind: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in get_palette_entries():
		var kinds: Array = entry.get("map_kinds", [LevelData.MapKind.LEVEL])
		if kinds.has(map_kind):
			out.append(entry)
	return out


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
	var scene_path: String = String(entry.get("scene_path", ""))
	if scene is PackedScene:
		node = scene.instantiate()
	elif scene_path != "":
		if not ResourceLoader.exists(scene_path, "PackedScene"):
			push_warning("EntityRegistry: sprite scene not found '%s'" % scene_path)
			return null
		var wrapper := SpriteEntity.new()
		var packed := load(scene_path) as PackedScene
		wrapper.attach_sprite(packed.instantiate())
		node = wrapper
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
