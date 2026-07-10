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
# Set by teleport(): the destination teleporter_id whose arrival animation
# LevelRuntime should play after the rebuilt scene spawns. Empty = normal spawn.
var pending_teleport_arrival_id: String = ""
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
	pending_level = null
	pending_teleport_arrival_id = ""
	return_scene = null
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


## Transition overworld -> level. Records the entrance tile so complete_level
## can place Keen back at this door.
func enter_level(target_level_id: String, from_tile: Vector2i) -> void:
	enter_level_no_scene_swap(target_level_id, from_tile)
	get_tree().change_scene_to_packed(RUNTIME_SCENE)


func enter_level_no_scene_swap(target_level_id: String, from_tile: Vector2i) -> void:
	var lvl := get_level_by_id(target_level_id)
	if lvl == null:
		push_warning("GameManager: unknown level id '%s'" % target_level_id)
		return
	current_level = lvl
	last_entrance_pos = from_tile
	pending_level = lvl
	pending_player_spawn = Vector2i(-1, -1)  # use the level's own player_spawn
	pending_teleport_arrival_id = ""
	state = State.LEVEL


## Transition level -> overworld at last_entrance_pos. Idempotently records
## completion so gate blockers clear on the rebuilt overworld.
func complete_level() -> void:
	complete_level_no_scene_swap()
	get_tree().change_scene_to_packed(RUNTIME_SCENE)


func complete_level_no_scene_swap() -> void:
	if current_level != null:
		mark_completed(current_level.level_id)
	pending_level = current_overworld
	pending_player_spawn = last_entrance_pos
	pending_teleport_arrival_id = ""
	current_level = null
	state = State.OVERWORLD


## Transition level -> overworld on death WITHOUT recording completion. Keen
## respawns at the entrance he walked in from, level stays uncompleted.
func fail_level() -> void:
	fail_level_no_scene_swap()
	get_tree().change_scene_to_packed(RUNTIME_SCENE)


func fail_level_no_scene_swap() -> void:
	pending_level = current_overworld
	pending_player_spawn = last_entrance_pos
	pending_teleport_arrival_id = ""
	current_level = null
	state = State.OVERWORLD


## Transition the player to a destination teleporter (same or different map).
## Resolves the destination level via get_level_by_id and the destination
## teleporter's tile by scanning that level's entities for a matching
## teleporter_id. Returns false (no scene swap) on dangling refs so the caller
## can restore any pre-teleport visual state (e.g. un-hide the player).
func teleport(destination_level_id: String, destination_teleporter_id: String) -> bool:
	if not teleport_no_scene_swap(destination_level_id, destination_teleporter_id):
		return false
	get_tree().change_scene_to_packed(RUNTIME_SCENE)
	return true


## Headless-testable core of teleport(); does not swap the scene. Returns true
## when the destination resolved and pending spawn state was set, false on a
## dangling/empty destination (caller should treat as a failed teleport).
func teleport_no_scene_swap(destination_level_id: String, destination_teleporter_id: String) -> bool:
	if destination_level_id == "" or destination_teleporter_id == "":
		push_warning("GameManager.teleport: empty destination (level='%s', teleporter='%s')" % [destination_level_id, destination_teleporter_id])
		return false
	var lvl := get_level_by_id(destination_level_id)
	if lvl == null:
		push_warning("GameManager.teleport: unknown level id '%s'" % destination_level_id)
		return false
	var tile := _find_teleporter_tile(lvl, destination_teleporter_id)
	if tile.x < 0:
		push_warning("GameManager.teleport: teleporter '%s' not found in level '%s'" % [destination_teleporter_id, destination_level_id])
		return false
	pending_level = lvl
	pending_player_spawn = tile
	pending_teleport_arrival_id = destination_teleporter_id
	if lvl.map_kind == LevelData.MapKind.LEVEL:
		current_level = lvl
		state = State.LEVEL
	else:
		current_level = null
		state = State.OVERWORLD
	return true


## Find the tile of the teleporter whose properties.teleporter_id == id within
## `level`. Returns Vector2i(-1, -1) if none. A teleporter is identified by
## carrying a `teleporter_id` property (type-agnostic, so any namespaced
## teleporter type resolves without core knowing the type id).
func _find_teleporter_tile(level: LevelData, teleporter_id: String) -> Vector2i:
	for def: EntityDef in level.entities:
		if String(def.properties.get("teleporter_id", "")) == teleporter_id:
			return Vector2i(def.x, def.y)
	return Vector2i(-1, -1)


## Boot the overworld loop for an episode: resolve + load its overworld, then
## swap to the runtime scene in OVERWORLD state.
func start_episode(ep_id: String) -> void:
	var ow := _resolve_overworld(ep_id)
	if ow == null:
		push_warning("GameManager: no overworld for episode '%s'" % ep_id)
		return
	start_episode_no_scene_swap(ep_id, ow)
	get_tree().change_scene_to_packed(RUNTIME_SCENE)


func start_episode_no_scene_swap(ep_id: String, ow: LevelData) -> void:
	current_episode_id = ep_id
	current_overworld = ow
	register_level(ow)
	# Register every LEVEL-kind map in the episode so level entrances resolve.
	var ep := _find_episode(ep_id)
	if ep != null:
		for lvl in ep.load_levels():
			register_level(lvl)
	pending_level = ow
	pending_player_spawn = Vector2i(-1, -1)
	state = State.OVERWORLD


## Boot a custom level pack: resolve its overworld, register every pack level,
## then swap to the runtime scene in OVERWORLD state. Reuses the existing
## enter/complete/fail loop. (Bundled episodes use start_episode instead.)
func start_pack(pack_id: String) -> void:
	var ow := PackLoader.get_overworld(pack_id)
	if ow == null:
		push_warning("GameManager: pack '%s' has no overworld" % pack_id)
		return
	start_pack_no_scene_swap(pack_id, ow)
	get_tree().change_scene_to_packed(RUNTIME_SCENE)


## Non-scene-swap variant for headless tests.
func start_pack_no_scene_swap(pack_id: String, ow: LevelData) -> void:
	# Custom packs always start a fresh session (progress is session-held; save = Plan 6).
	clear_progress()
	current_episode_id = pack_id
	current_overworld = ow
	# Explicit overworld register mirrors start_episode; the loop below re-registers
	# it (same cached instance) — idempotent and harmless.
	register_level(ow)
	for lvl in PackLoader.get_levels(pack_id):
		register_level(lvl)
	pending_level = ow
	pending_player_spawn = Vector2i(-1, -1)
	state = State.OVERWORLD


func _resolve_overworld(ep_id: String) -> LevelData:
	# Find the Episode instance for ep_id and ask it for its overworld.
	var ep := _find_episode(ep_id)
	if ep == null:
		return null
	return ep.load_overworld()


## Scan src/episodes/*/episode.gd, instantiate each Episode, and return the one
## whose id matches. Returns null if not found.
func _find_episode(ep_id: String) -> Episode:
	var dir := DirAccess.open(EPISODES_DIR)
	if dir == null:
		return null
	dir.list_dir_begin()
	var subdir := dir.get_next()
	while subdir != "":
		if dir.dir_exists(subdir) and dir.file_exists("%s/episode.gd" % subdir):
			var path := "%s/%s/episode.gd" % [EPISODES_DIR, subdir]
			var ep_script: GDScript = load(path)
			if ep_script != null:
				var ep: Episode = ep_script.new()
				if ep.id == ep_id:
					dir.list_dir_end()
					return ep
		subdir = dir.get_next()
	dir.list_dir_end()
	return null


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
	# Keyboard + D-pad + left-stick for movement; face buttons for actions.
	_add_action("move_left",  [_keyev(KEY_A), _btnev(JOY_BUTTON_DPAD_LEFT),  _axisev(JOY_AXIS_LEFT_X, -1.0)])
	_add_action("move_right", [_keyev(KEY_D), _btnev(JOY_BUTTON_DPAD_RIGHT), _axisev(JOY_AXIS_LEFT_X, 1.0)])
	_add_action("move_up",    [_keyev(KEY_W), _btnev(JOY_BUTTON_DPAD_UP),    _axisev(JOY_AXIS_LEFT_Y, -1.0)])
	_add_action("move_down",  [_keyev(KEY_S), _btnev(JOY_BUTTON_DPAD_DOWN),  _axisev(JOY_AXIS_LEFT_Y, 1.0)])
	_add_action("jump",     [_keyev(KEY_SPACE), _btnev(JOY_BUTTON_A)])
	_add_action("pogo",     [_keyev(KEY_P),     _btnev(JOY_BUTTON_B)])
	_add_action("shoot",    [_keyev(KEY_X),     _btnev(JOY_BUTTON_X)])
	_add_action("interact", [_keyev(KEY_UP),    _btnev(JOY_BUTTON_Y)])


## Create the action (if absent) and attach every event. Idempotent: if the
## action already exists (e.g. declared in project.godot or a prior run), it is
## left untouched so events are never duplicated.
func _add_action(action_name: String, events: Array) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	for ev in events:
		InputMap.action_add_event(action_name, ev)


func _keyev(keycode: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	return ev


func _btnev(button: int) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	return ev


func _axisev(axis: int, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	return ev
