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
## entity types into the global catalog (registration overwrites on type_id
## conflict). The metadata list is rebuilt on every call. Tests call this in
## after_each to restore the default catalog after clear().
func register_episodes() -> void:
	episodes.clear()
	var dir := DirAccess.open(EPISODES_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var subdir := dir.get_next()
	while subdir != "":
		if dir.dir_exists(subdir) and dir.file_exists("%s/episode.gd" % subdir):
			var path := "%s/%s/episode.gd" % [EPISODES_DIR, subdir]
			var ep_script: GDScript = load(path)
			if ep_script != null:
				var ep: Episode = ep_script.new()
				ep.register_entities(EntityRegistry)
				episodes.append({"id": ep.id, "title": ep.title})
		subdir = dir.get_next()
	dir.list_dir_end()


func _ensure_input_actions() -> void:
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("pogo", KEY_P)
	_add_key_action("shoot", KEY_X)
	_add_key_action("interact", KEY_UP)


func _add_key_action(action_name: String, keycode: int) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action_name, ev)
