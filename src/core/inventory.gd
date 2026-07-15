extends Node
## Persistent item store (autoload). Dictionary-based: an item_id key exists if
## and only if the player owns it. Wired into GameManager.serialize()/deserialize()
## so items survive save/load. Emits item_collected on first acquisition of each id.

signal item_collected(item_id: String)

var _items: Dictionary = {}  # item_id (String) -> true


func has_item(item_id: String) -> bool:
	return _items.has(item_id)


func add_item(item_id: String) -> void:
	if _items.has(item_id):
		return
	_items[item_id] = true
	item_collected.emit(item_id)


func remove_item(item_id: String) -> void:
	_items.erase(item_id)


func clear() -> void:
	_items.clear()


func serialize() -> Dictionary:
	return _items.duplicate(true)


func deserialize(data: Dictionary) -> void:
	_items = data.duplicate(true)
