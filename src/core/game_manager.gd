extends Node
## Top-level game state singleton (autoload). Registers player input actions in
## code and discovers + registers all episodes into the global EntityRegistry at
## boot. Holds the Test ▶ round-trip state.

const EPISODES_DIR := "res://src/episodes"

var pending_level: LevelData = null
var return_scene: PackedScene = null
var episodes: Array = []  # registered Episode metadata ({id, title})


func _ready() -> void:
	_ensure_input_actions()
	register_episodes()


## Scan src/episodes/*/episode.gd, instantiate each Episode, and register its
## entity types into the global catalog. Idempotent: re-registering overwrites
## (last-wins on type_id conflict). Tests call this in after_each to restore the
## default catalog after clear().
func register_episodes() -> void:
	var dir := DirAccess.open(EPISODES_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.dir_exists(name) and dir.file_exists("%s/episode.gd" % name):
			var path := "%s/%s/episode.gd" % [EPISODES_DIR, name]
			var EpScript: GDScript = load(path)
			if EpScript != null:
				var ep: Episode = EpScript.new()
				ep.register_entities(EntityRegistry)
				episodes.append({"id": ep.id, "title": ep.title})
		name = dir.get_next()
	dir.list_dir_end()


func _ensure_input_actions() -> void:
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("pogo", KEY_P)
	_add_key_action("shoot", KEY_X)


func _add_key_action(action_name: String, keycode: int) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action_name, ev)
