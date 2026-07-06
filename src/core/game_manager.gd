extends Node
## Top-level game state singleton (autoload). Registers player input actions in
## code and discovers + registers all episodes into the global EntityRegistry at
## boot. Owns the overworld gameplay loop state machine and the per-level
## completion set (session-held now; serialize/deserialize ready for Plan 6 save).

const EPISODES_DIR := "res://src/episodes"
const RUNTIME_SCENE := preload("res://src/runtime/level_runtime.tscn")

enum State { MENU, OVERWORLD, LEVEL, TEST }

var state: State = State.MENU
var pending_level: LevelData = null
var pending_player_spawn: Vector2i = Vector2i(-1, -1)
var return_scene: PackedScene = null
var episodes: Array = []  # registered Episode metadata ({id, title})

var current_episode_id: String = ""
var current_overworld: LevelData = null
var current_level: LevelData = null
var completed_levels: Array[String] = []
var last_entrance_pos: Vector2i = Vector2i.ZERO

var _levels_by_id: Dictionary = {}  # level_id -> LevelData (registry seam; Plan 5 fills via PackLoader)


## Session-reset helper (also used by tests).
func clear_progress() -> void:
	state = State.MENU
	completed_levels.clear()
	current_episode_id = ""
	current_overworld = null
	current_level = null
	last_entrance_pos = Vector2i.ZERO
	pending_player_spawn = Vector2i(-1, -1)
	_levels_by_id.clear()


func is_level_completed(level_id: String) -> bool:
	return completed_levels.has(level_id)


## Idempotent: marks a level completed and records it for gate clearance.
func mark_completed(level_id: String) -> void:
	if not completed_levels.has(level_id):
		completed_levels.append(level_id)


## Registry seam: tests and (future) PackLoader register resolvable levels here.
func register_level(ld: LevelData) -> void:
	if ld.level_id != "":
		_levels_by_id[ld.level_id] = ld


func get_level_by_id(level_id: String) -> LevelData:
	return _levels_by_id.get(level_id, null)


## Save-ready hooks (not wired to disk this spec; Plan 6 calls these).
func serialize() -> Dictionary:
	return {
		"completed_levels": completed_levels.duplicate(),
		"current_episode_id": current_episode_id,
	}


func deserialize(data: Dictionary) -> void:
	completed_levels.clear()
	var loaded: Array = data.get("completed_levels", [])
	for id in loaded:
		completed_levels.append(String(id))
	current_episode_id = String(data.get("current_episode_id", ""))


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
