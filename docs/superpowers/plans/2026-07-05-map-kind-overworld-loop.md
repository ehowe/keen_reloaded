# Map Kind & Overworld Loop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a `LevelData` be flagged as LEVEL or OVERWORLD, and implement the full boot→overworld→level→overworld gameplay loop with keypress-entered level entrances and solid-until-cleared gates.

**Architecture:** A `map_kind` enum on `LevelData` is the single switch point. Runtime and editor branch on it. A new `LevelEntrance` entity (overworld-only) carries `target_level_id` + `blocks_until_completed`; `GameManager` owns the state machine, the in-memory `completed_levels` set, and all scene transitions. Completion is session-held with `serialize()/deserialize()` hooks so Plan 6 can wire disk save later.

**Tech Stack:** Godot 4.7, GDScript, GUT (headless tests at `tests/unit/`, run via `./tests/run_all.sh`).

**Spec:** `docs/superpowers/specs/2026-07-05-map-kind-overworld-loop-design.md`

**Conventions (from existing code):**
- Tabs for indentation, `:=` for inferred types, `@export` for resource fields.
- Entities extend `Entity` (a `CharacterBody2D`) or are plain `Node2D`; `EntityRegistry.instantiate` calls `setup(type_id, props)` if present.
- Autoloads: `GameManager`, `EntityRegistry`, `TileSetRegistry`, `PackLoader` (stub).
- Collision layers (from `project.godot`): 1=player, 2=enemies, 3=tiles(bit 4), 4=items(bit 8). `LevelRuntime.COLLISION_LAYER_TILES := 4`, `COLLISION_LAYER_PLAYER := 1`.
- keen1 entity registration is in `src/episodes/keen1/episode.gd::register_entities` (there is **no** separate `entity_registry.gd`; the spec's reference to that name is a typo — use `episode.gd`).

**Spec correction carried into this plan:** spec §3.3 says register the entrance in `keen1/entity_registry.gd`; the real file is `src/episodes/keen1/episode.gd`. All tasks below use the real path.

---

## File Map

**Create:**
- `src/runtime/entities/level_entrance.gd` — `LevelEntrance` class (Node2D): proximity Area2D + blocker StaticBody2D + Visual; emits `enter_requested(target_level_id, tile)`.
- `src/runtime/entities/level_entrance.tscn` — scene wrapping the script with a Visual child.
- `tests/unit/test_map_kind.gd` — `LevelData.map_kind` + runtime branch tests.
- `tests/unit/test_game_manager_loop.gd` — state machine, completed set, enter/complete/start transitions, serialize/deserialize.
- `tests/unit/test_level_entrance.gd` — proximity, enter-attempt, gate solidity.
- `tests/unit/test_editor_map_kind.gd` — inspector dropdown + palette filtering + String/bool property editing.

**Modify:**
- `src/data/level_data.gd` — add `MapKind` enum + `map_kind` export.
- `src/core/game_manager.gd` — `State` enum, loop state, completed set, transitions, `interact` action, level-id registry seam, `pending_player_spawn`.
- `src/core/episode.gd` — `overworld_level_id` + `overworld_path` + `load_overworld()`.
- `src/core/entity_registry.gd` — optional `map_kinds` arg on `register`/`register_sprite`; filter helper.
- `src/runtime/level_runtime.gd` — branch `build`/`_build_bounds` on `map_kind`; spawn-time `set_tile` on entrances; overworld interact wiring; `_on_completion_dismissed` loop branch; pending-player-spawn override.
- `src/editor/inspector_panel.gd` — `map_kind` OptionButton; String/Bool property editors.
- `src/editor/palette_panel.gd` — filter entity list by active `map_kind`; repopulate on kind change.
- `src/episodes/keen1/episode.gd` — register `keen1.level_entrance` (OVERWORLD only).
- `src/ui/main_menu.gd` (+ `.tscn`) — Play button → `GameManager.start_episode("keen1")`.

---

# Phase 1 — `map_kind` foundation

### Task 1: `MapKind` enum + field on `LevelData`

**Files:**
- Modify: `src/data/level_data.gd:6-14` (add enum near the layer consts; add export in Metadata area)
- Test: `tests/unit/test_map_kind.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_map_kind.gd`:

```gdscript
extends GutTest

func test_map_kind_enum_exists():
	assert_eq(LevelData.MapKind.LEVEL, 0)
	assert_eq(LevelData.MapKind.OVERWORLD, 1)

func test_default_map_kind_is_level():
	var ld := LevelData.new()
	assert_eq(ld.map_kind, LevelData.MapKind.LEVEL)

func test_map_kind_round_trip():
	var ld := LevelData.new()
	ld.level_id = "ow1"
	ld.width = 2
	ld.height = 2
	ld.fill_blank()
	ld.map_kind = LevelData.MapKind.OVERWORLD
	var path := "user://tests/test_map_kind.tres"
	DirAccess.make_dir_recursive_absolute("user://tests/")
	assert_eq(ResourceSaver.save(ld, path), OK)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	assert_not_null(loaded)
	assert_eq(loaded.map_kind, LevelData.MapKind.OVERWORLD)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `LevelData` has no property `map_kind` / enum `MapKind`.

- [ ] **Step 3: Implement the enum + field**

In `src/data/level_data.gd`, after the `LAYER_*` consts (line 8), add:

```gdscript
enum MapKind { LEVEL, OVERWORLD }
```

In the `@export_group("Metadata")` block, after the `order` export (line 14), add:

```gdscript
@export var map_kind: MapKind = MapKind.LEVEL
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS for the three new tests; all prior tests still pass.

- [ ] **Step 5: Commit**

```bash
git add src/data/level_data.gd tests/unit/test_map_kind.gd
git commit -m "feat(data): add MapKind enum to LevelData (LEVEL default)"
```

---

### Task 2: `LevelRuntime` branches on `map_kind` (overworld = no fall-death)

**Files:**
- Modify: `src/runtime/level_runtime.gd:47-67` (`build`) and `:187-209` (`_build_bounds`)
- Test: `tests/unit/test_map_kind.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_map_kind.gd`:

```gdscript
func test_overworld_build_has_no_kill_zone():
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.map_kind = LevelData.MapKind.OVERWORLD
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	assert_equal(rt.find_child("BoundsKillZone", true, false), null,
		"overworld must not add a kill zone")

func test_level_build_has_kill_zone():
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.map_kind = LevelData.MapKind.LEVEL
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	assert_not_null(rt.find_child("BoundsKillZone", true, false),
		"level keeps the kill zone")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — overworld build still adds `BoundsKillZone`.

- [ ] **Step 3: Gate the kill zone on `map_kind`**

In `src/runtime/level_runtime.gd`, change the end of `_build_bounds` (the kill-zone block, lines 196-209) to skip creation when the level is an overworld. Replace the `# Bottom kill zone:` block with:

```gdscript
	# Bottom kill zone: levels only. Overworld is non-lethal (no fall death).
	if _level.map_kind == LevelData.MapKind.LEVEL:
		var kz := Area2D.new()
		kz.name = "BoundsKillZone"
		kz.collision_mask = COLLISION_LAYER_PLAYER
		kz.monitorable = true
		kz.monitoring = true
		var kshape := RectangleShape2D.new()
		kshape.size = Vector2(w_px + t * 2.0, t)
		var kcol := CollisionShape2D.new()
		kcol.shape = kshape
		kz.add_child(kcol)
		kz.position = Vector2(w_px * 0.5, h_px + t * 0.5)
		kz.body_entered.connect(_on_kill_zone_body_entered)
		add_child(kz)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/runtime/level_runtime.gd tests/unit/test_map_kind.gd
git commit -m "feat(runtime): overworld maps disable the bottom kill zone"
```

---

### Task 3: Inspector `map_kind` dropdown

**Files:**
- Modify: `src/editor/inspector_panel.gd:14-62` (add field + control in `build`) and `:64-79` (`refresh`) and handlers
- Test: `tests/unit/test_editor_map_kind.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_editor_map_kind.gd`:

```gdscript
extends GutTest

func _make_editor() -> LevelEditor:
	var ed := LevelEditor.new()
	add_child_autofree(ed)
	ed._ready()  # builds blank level + UI
	return ed

func test_inspector_writes_map_kind():
	var ed := _make_editor()
	ed.level.map_kind = LevelData.MapKind.LEVEL
	ed._inspector.refresh(ed)
	var picker: OptionButton = ed._inspector.find_child("MapKindPicker", true, false)
	assert_not_null(picker)
	picker.select(int(LevelData.MapKind.OVERWORLD))
	picker.item_selected.emit(int(LevelData.MapKind.OVERWORLD))
	assert_eq(ed.level.map_kind, LevelData.MapKind.OVERWORLD)

func test_inspector_reflects_map_kind():
	var ed := _make_editor()
	ed.level.map_kind = LevelData.MapKind.OVERWORLD
	ed._inspector.refresh(ed)
	var picker: OptionButton = ed._inspector.find_child("MapKindPicker", true, false)
	assert_eq(picker.selected, int(LevelData.MapKind.OVERWORLD))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — no `MapKindPicker` node.

- [ ] **Step 3: Add the dropdown**

In `src/editor/inspector_panel.gd`, add a field near the other `_xxx_edit` declarations (after line 16):

```gdscript
var _map_kind_picker: OptionButton
```

In `build(e)`, inside the "Level" section (after the `_order_spin` block, before the dimensions — around line 33), insert:

```gdscript
	_map_kind_picker = OptionButton.new()
	_map_kind_picker.name = "MapKindPicker"
	_map_kind_picker.add_item("Level", LevelData.MapKind.LEVEL)
	_map_kind_picker.add_item("Overworld", LevelData.MapKind.OVERWORLD)
	_map_kind_picker.item_selected.connect(_on_map_kind_selected)
	add_child(_labeled("Map Kind", _map_kind_picker))
```

In `refresh(e)` (after the `_order_spin.set_value_no_signal` line, ~line 69), add:

```gdscript
	_map_kind_picker.select(int(e.level.map_kind))
```

In the handlers section (near the other `_on_*_changed`, ~line 130), add:

```gdscript
func _on_map_kind_selected(index: int) -> void:
	_e.level.map_kind = index as LevelData.MapKind
	_e._broadcast()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/editor/inspector_panel.gd tests/unit/test_editor_map_kind.gd
git commit -m "feat(editor): map kind dropdown in inspector"
```

---

# Phase 2 — `GameManager` loop core + `interact` action

### Task 4: Register the `interact` input action

**Files:**
- Modify: `src/core/game_manager.gd:41-46` (`_ensure_input_actions`)
- Test: `tests/unit/test_game_manager.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_game_manager.gd`:

```gdscript
func test_interact_action_registered():
	assert_true(InputMap.has_action("interact"))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — no `interact` action.

- [ ] **Step 3: Register the action**

In `src/core/game_manager.gd`, in `_ensure_input_actions` (after the `shoot` line, ~line 46), add:

```gdscript
	_add_key_action("interact", KEY_UP)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/game_manager.gd tests/unit/test_game_manager.gd
git commit -m "feat(core): register interact input action (Up arrow)"
```

---

### Task 5: `GameManager` state machine + completion set + save hooks

**Files:**
- Modify: `src/core/game_manager.gd:1-11` (vars) and add methods
- Test: `tests/unit/test_game_manager_loop.gd` (create)

This task adds state, the completed set, the level-id registry seam, and `serialize/deserialize`. It does **not** wire scene transitions yet (Task 9).

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_game_manager_loop.gd`:

```gdscript
extends GutTest

func before_each():
	GameManager.clear_progress()

func test_is_level_completed_false_by_default():
	assert_false(GameManager.is_level_completed("keen1_01"))

func test_mark_completed_then_query():
	GameManager.mark_completed("keen1_01")
	assert_true(GameManager.is_level_completed("keen1_01"))

func test_mark_completed_is_idempotent():
	GameManager.mark_completed("keen1_01")
	GameManager.mark_completed("keen1_01")
	assert_eq(GameManager.completed_levels.count("keen1_01"), 1)

func test_clear_progress():
	GameManager.mark_completed("keen1_01")
	GameManager.clear_progress()
	assert_false(GameManager.is_level_completed("keen1_01"))

func test_register_and_get_level():
	var ld := LevelData.new()
	ld.level_id = "ow_x"
	GameManager.register_level(ld)
	assert_eq(GameManager.get_level_by_id("ow_x"), ld)

func test_serialize_deserialize_round_trip():
	GameManager.mark_completed("a")
	GameManager.mark_completed("b")
	GameManager.current_episode_id = "keen1"
	var data := GameManager.serialize()
	GameManager.clear_progress()
	GameManager.current_episode_id = ""
	GameManager.deserialize(data)
	assert_true(GameManager.is_level_completed("a"))
	assert_true(GameManager.is_level_completed("b"))
	assert_eq(GameManager.current_episode_id, "keen1")

func test_default_state_is_menu():
	# state is reset by clear_progress in before_each
	assert_eq(GameManager.state, GameManager.State.MENU)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — no `State`, `completed_levels`, `mark_completed`, etc.

- [ ] **Step 3: Add state + methods**

Replace the top of `src/core/game_manager.gd` (the `extends Node` docblock + var block, lines 1-11) with:

```gdscript
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
```

Then, immediately above `_ready()` (or anywhere in the body), add these methods:

```gdscript
## Session-reset helper (also used by tests).
func clear_progress() -> void:
	state = State.MENU
	completed_levels.clear()
	current_episode_id = ""
	current_overworld = null
	current_level = null
	last_entrance_pos = Vector2i.ZERO
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/game_manager.gd tests/unit/test_game_manager_loop.gd
git commit -m "feat(core): GameManager loop state, completion set, save hooks"
```

---

# Phase 3 — `LevelEntrance` entity + enter/return loop

### Task 6: `LevelEntrance` class + scene

**Files:**
- Create: `src/runtime/entities/level_entrance.gd`
- Create: `src/runtime/entities/level_entrance.tscn`
- Test: `tests/unit/test_level_entrance.gd` (create)

The entity extends `Node2D` (not `Entity`) for clean control over a proximity `Area2D` + a blocker `StaticBody2D`. `EntityRegistry.instantiate` calls `setup(type_id, props)` if present, which we define.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_level_entrance.gd`:

```gdscript
extends GutTest

const TILE := 64

func before_each():
	GameManager.clear_progress()

func _make_entrance(target := "keen1_01", gate := false) -> Node2D:
	var e := LevelEntrance.new()
	add_child_autofree(e)
	e.setup("keen1.level_entrance", {"target_level_id": target, "blocks_until_completed": gate})
	e.set_tile(Vector2i(3, 4))
	return e

func test_setup_reads_properties():
	var e := _make_entrance("lvl2", true)
	assert_eq(e.target_level_id, "lvl2")
	assert_true(e.blocks_until_completed)

func test_set_tile_records_position():
	var e := _make_entrance()
	assert_eq(e.tile, Vector2i(3, 4))

func test_non_gate_never_blocks():
	var e := _make_entrance("a", false)
	assert_false(e.is_blocking())

func test_gate_blocks_when_uncompleted():
	var e := _make_entrance("a", true)
	assert_true(e.is_blocking())

func test_gate_unblocks_when_completed():
	GameManager.mark_completed("a")
	var e := _make_entrance("a", true)
	assert_false(e.is_blocking())

func test_attempt_enter_requires_nearby():
	var e := _make_entrance("a", false)
	assert_false(e.attempt_enter(true))   # nobody nearby
	e._set_nearby_for_test(true)
	assert_true(e.attempt_enter(true))    # nearby + interact

func test_attempt_enter_requires_interact():
	var e := _make_entrance("a", false)
	e._set_nearby_for_test(true)
	assert_false(e.attempt_enter(false))

func test_attempt_enter_emits_signal():
	var e := _make_entrance("lvl_x", false)
	e._set_nearby_for_test(true)
	var captured := {"target": "", "tile": Vector2i(-1, -1)}
	e.enter_requested.connect(func(t: String, tile: Vector2i) -> void:
		captured["target"] = t
		captured["tile"] = tile)
	e.attempt_enter(true)
	assert_eq(captured["target"], "lvl_x")
	assert_eq(captured["tile"], Vector2i(3, 4))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `LevelEntrance` class does not exist.

- [ ] **Step 3: Write the class**

Create `src/runtime/entities/level_entrance.gd`:

```gdscript
class_name LevelEntrance
extends Node2D
## Overworld-only entity: a level door. Player presses `interact` while nearby to
## enter the linked level. When `blocks_until_completed` is set and the target
## level is not yet completed, a solid StaticBody2D blocks overworld passage.
##
## Does NOT own completion state — reads GameManager.is_level_completed(). The
## runtime emits `enter_requested(target_level_id, tile)`; LevelRuntime wires it
## to GameManager.enter_level().

signal enter_requested(target_level_id: String, tile: Vector2i)

const TILE := 64
const PROXIMITY_RADIUS := 1  # tiles around the door in each direction (3x3 zone)

var type_id: String = ""
var target_level_id: String = ""
var blocks_until_completed: bool = false
var tile: Vector2i = Vector2i(-1, -1)

var _nearby: bool = false
var _proximity: Area2D
var _blocker: StaticBody2D
var _blocker_shape: CollisionShape2D


## Called by EntityRegistry.instantiate. Reads editor-set properties.
func setup(p_type_id: String, p_props: Dictionary) -> void:
	type_id = p_type_id
	target_level_id = String(p_props.get("target_level_id", ""))
	blocks_until_completed = bool(p_props.get("blocks_until_completed", false))


## Called by LevelRuntime after instantiate so the entrance knows its tile.
func set_tile(t: Vector2i) -> void:
	tile = t


func _ready() -> void:
	_build_proximity()
	_build_blocker()
	_build_visual()


func _build_proximity() -> void:
	_proximity = Area2D.new()
	_proximity.name = "Proximity"
	_proximity.monitoring = true
	_proximity.collision_layer = 0
	_proximity.collision_mask = 1  # player bit
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	var zone := float(TILE * (1 + PROXIMITY_RADIUS * 2))
	rect.size = Vector2(zone, zone)
	shape.shape = rect
	_proximity.add_child(shape)
	_proximity.body_entered.connect(_on_body_entered)
	_proximity.body_exited.connect(_on_body_exited)
	add_child(_proximity)


func _build_blocker() -> void:
	_blocker = StaticBody2D.new()
	_blocker.name = "Blocker"
	_blocker.collision_layer = 4  # tiles bit -> blocks the player
	_blocker_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	_blocker_shape.shape = rect
	_blocker.add_child(_blocker_shape)
	_blocker.add_to_group("level_entrance_blocker")
	add_child(_blocker)
	_apply_blocking()


func _build_visual() -> void:
	if has_node("Visual"):
		return
	var vis := ColorRect.new()
	vis.name = "Visual"
	vis.size = Vector2(TILE, TILE)
	vis.position = Vector2(-TILE / 2.0, -TILE / 2.0)
	vis.color = Color(0.95, 0.75, 0.2, 1)
	add_child(vis)


func _process(_delta: float) -> void:
	attempt_enter(Input.is_action_just_pressed("interact"))


## Returns true and emits enter_requested when a player is nearby and the
## interact control is pressed. `interact_pressed` is a parameter (not read from
## Input) so tests are deterministic.
func attempt_enter(interact_pressed: bool) -> bool:
	if not _nearby or not interact_pressed:
		return false
	if target_level_id == "":
		return false
	enter_requested.emit(target_level_id, tile)
	return true


func is_blocking() -> bool:
	return blocks_until_completed and not GameManager.is_level_completed(target_level_id)


## Recompute the blocker's solidity from GameManager state. Called on build and
## after a level is completed.
func refresh_blocking() -> void:
	_apply_blocking()


func _apply_blocking() -> void:
	if _blocker_shape == null:
		return
	_blocker_shape.set_deferred("disabled", not is_blocking())


func _on_body_entered(_body: Node) -> void:
	_nearby = true


func _on_body_exited(_body: Node) -> void:
	_nearby = false


# --- test seam ---
func _set_nearby_for_test(v: bool) -> void:
	_nearby = v
```

- [ ] **Step 4: Create the scene**

Create `src/runtime/entities/level_entrance.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/runtime/entities/level_entrance.gd" id="1_le"]

[node name="LevelEntrance" type="Node2D"]
script = ExtResource("1_le")
```

No `uid` is specified — Godot assigns one on first import. If the worker prefers, the scene can instead be generated by launching Godot headless once (`make import`); the textual form above is sufficient and will import on first run.

- [ ] **Step 5: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS. (The blocker's `set_deferred("disabled", ...)` is safe in tests; `is_blocking()` reads GameManager.)

- [ ] **Step 6: Commit**

```bash
git add src/runtime/entities/level_entrance.gd src/runtime/entities/level_entrance.tscn tests/unit/test_level_entrance.gd
git commit -m "feat(runtime): LevelEntrance entity — door + proximity + gate blocker"
```

---

### Task 7: Register the entrance (OVERWORLD-only) + palette filtering

**Files:**
- Modify: `src/core/entity_registry.gd:17-38` (add `map_kinds` arg) and `:49-58` (`get_palette_entries`)
- Modify: `src/episodes/keen1/episode.gd:12-37` (register entrance)
- Modify: `src/editor/palette_panel.gd:20-22` (fields), `:67-82` (build entities w/ filter), `:132-141` (`_populate_entities`), `:147-161` (`refresh` repopulates on kind change)
- Test: `tests/unit/test_editor_map_kind.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_editor_map_kind.gd`:

```gdscript
func test_palette_filters_by_map_kind():
	# Ensure keen1 entities are registered (GameManager.register_episodes runs
	# at autoload boot).
	var ed_level := LevelEditor.new()
	add_child_autofree(ed_level)
	ed_level._ready()
	ed_level.level.map_kind = LevelData.MapKind.LEVEL
	ed_level._palette.refresh(ed_level)
	var level_ids := ed_level._palette.get_entity_ids_for_test()
	assert_true(level_ids.has("keen1.vorticon"), "level palette shows gameplay entities")
	assert_false(level_ids.has("keen1.level_entrance"), "level palette hides overworld-only entrance")

	ed_level.level.map_kind = LevelData.MapKind.OVERWORLD
	ed_level._palette.refresh(ed_level)
	var ow_ids := ed_level._palette.get_entity_ids_for_test()
	assert_true(ow_ids.has("keen1.level_entrance"), "overworld palette shows the entrance")
	assert_false(ow_ids.has("keen1.vorticon"), "overworld palette hides gameplay entities")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `get_entity_ids_for_test` / `map_kind_set_for_test` don't exist; entrance not registered.

- [ ] **Step 3: Add `map_kinds` to the registry**

In `src/core/entity_registry.gd`, change `register` (line 17) to accept `map_kinds` and default it:

```gdscript
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
```

Apply the same change to `register_sprite` (line 31): add the `map_kinds: Array[int] = []` parameter with the same default and store `"map_kinds": map_kinds` in the entry dict.

- [ ] **Step 4: Register the entrance (OVERWORLD-only)**

In `src/episodes/keen1/episode.gd`, in `register_entities` (after the `exit_sign` registration at the end, ~line 37), add:

```gdscript
	var level_entrance := preload("res://src/runtime/entities/level_entrance.tscn")
	registry.register("keen1.level_entrance", registry.CATEGORY_SPECIAL, "Level Entrance",
		[], level_entrance, [LevelData.MapKind.OVERWORLD])
```

- [ ] **Step 5: Filter the palette by `map_kind`**

In `src/editor/palette_panel.gd`:

Add fields near the other `_entity_*` vars (after line 21):

```gdscript
var _last_map_kind: int = -1
```

Change `_populate_entities` (lines 132-141) to accept the active kind and filter:

```gdscript
func _populate_entities(map_kind: int) -> void:
	_entity_list.clear()
	_entity_ids.clear()
	var filter := _selected_category()
	for entry in EntityRegistry.get_palette_entries():
		var cat: String = entry.get("category", "")
		if filter != "" and cat != filter:
			continue
		var kinds: Array = entry.get("map_kinds", [LevelData.MapKind.LEVEL])
		if not kinds.has(map_kind):
			continue
		_entity_ids.append(entry.get("type_id", ""))
		_entity_list.add_item(entry.get("label", ""))
```

Update the two call sites. In `build(e)` (line 79), change `_populate_entities()` to:

```gdscript
	_last_map_kind = int(e.level.map_kind)
	_populate_entities(_last_map_kind)
```

In `refresh(e)` (after the `_update_preview` line at the end, or before `_sync_entity_selection`), add a repopulate-on-change block:

```gdscript
	if int(e.level.map_kind) != _last_map_kind:
		_last_map_kind = int(e.level.map_kind)
		_populate_entities(_last_map_kind)
```

Add the test-seam helper at the end of `PalettePanel`:

```gdscript
func get_entity_ids_for_test() -> Array[String]:
	return _entity_ids.duplicate()
```

- [ ] **Step 6: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS. (Clean up the dead `map_kind_set_for_test(...)` line in the test if it errors — it is guarded by `has_method`, so it is a no-op when absent; once added it simply sets the field. The test primarily drives `map_kind` directly via `ed_level.level.map_kind` + `refresh`.)

- [ ] **Step 7: Commit**

```bash
git add src/core/entity_registry.gd src/episodes/keen1/episode.gd src/editor/palette_panel.gd tests/unit/test_editor_map_kind.gd
git commit -m "feat(editor): filter entity palette by map kind; register Level Entrance"
```

---

### Task 8: Inspector edits String/Bool entity properties

**Files:**
- Modify: `src/editor/inspector_panel.gd:110-120` (`_rebuild_entity_box` property loop)
- Test: `tests/unit/test_editor_map_kind.gd` (append)

Needed so `target_level_id` (String) and `blocks_until_completed` (bool) on the entrance are editable. Existing code only renders numeric properties.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_editor_map_kind.gd`:

```gdscript
func test_inspector_edits_string_and_bool_props():
	var ed := LevelEditor.new()
	add_child_autofree(ed)
	ed._ready()
	var def := EntityDef.new("keen1.level_entrance", 1, 1,
		{"target_level_id": "lvl1", "blocks_until_completed": true})
	ed.level.entities.append(def)
	ed.select_entity(ed.level.entities.size() - 1)
	# Find the LineEdit for target_level_id and change it.
	var le: LineEdit = ed._inspector.find_child("Prop_target_level_id", true, false)
	assert_not_null(le, "String property should render as a LineEdit")
	le.text = "lvl2"
	le.text_changed.emit("lvl2")
	assert_eq(def.properties["target_level_id"], "lvl2")
	# Find the CheckBox for blocks_until_completed and toggle it.
	var cb: CheckBox = ed._inspector.find_child("Prop_blocks_until_completed", true, false)
	assert_not_null(cb, "Bool property should render as a CheckBox")
	cb.set_pressed_no_signal(false)
	cb.toggled.emit(false)
	assert_eq(def.properties["blocks_until_completed"], false)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — no `Prop_target_level_id` / `Prop_blocks_until_completed` controls.

- [ ] **Step 3: Render String and Bool properties**

In `src/editor/inspector_panel.gd`, replace the property-rendering loop inside `_rebuild_entity_box` (lines 110-120) with a `match` over the value type:

```gdscript
	# numeric properties only (int-valued) for MVP
	for key in ent.properties.keys():
		var val = ent.properties[key]
		match typeof(val):
			TYPE_INT, TYPE_FLOAT:
				var ps := SpinBox.new()
				ps.min_value = -9999
				ps.max_value = 9999
				ps.set_value_no_signal(val)
				var k: Variant = key
				ps.value_changed.connect(func(_v: float) -> void: ent.properties[k] = int(ps.value))
				_entity_box.add_child(_labeled(str(key), ps))
			TYPE_BOOL:
				var cb := CheckBox.new()
				cb.name = "Prop_" + str(key)
				cb.set_pressed_no_signal(val)
				var kb: Variant = key
				cb.toggled.connect(func(p: bool) -> void: ent.properties[kb] = p)
				_entity_box.add_child(_labeled(str(key), cb))
			TYPE_STRING:
				var sle := LineEdit.new()
				sle.name = "Prop_" + str(key)
				sle.text = val
				var sk: Variant = key
				sle.text_changed.connect(func(t: String) -> void: ent.properties[sk] = t)
				_entity_box.add_child(_labeled(str(key), sle))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/editor/inspector_panel.gd tests/unit/test_editor_map_kind.gd
git commit -m "feat(editor): edit String/Bool entity properties in inspector"
```

---

### Task 9: Wire the enter/return loop (`GameManager.enter_level` / `complete_level`, runtime integration)

**Files:**
- Modify: `src/core/game_manager.gd` (add `enter_level`, `complete_level`, `start_episode` bodies)
- Modify: `src/runtime/level_runtime.gd:30-32` (`_ready`), `:95-105` (`_spawn_player` spawn override), `:129-136` (`_spawn_entities` entrance wiring), `:157-162` (`_on_completion_dismissed`)
- Test: `tests/unit/test_game_manager_loop.gd` (append) and `tests/unit/test_level_runtime.gd` (append — see note)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_game_manager_loop.gd`:

```gdscript
func test_enter_level_sets_pending_and_state():
	var lvl := LevelData.new()
	lvl.level_id = "keen1_01"
	lvl.width = 2
	lvl.height = 2
	lvl.fill_blank()
	GameManager.register_level(lvl)
	# Avoid real scene swap during the test:
	GameManager.enter_level_no_scene_swap("keen1_01", Vector2i(3, 4))
	assert_eq(GameManager.state, GameManager.State.LEVEL)
	assert_eq(GameManager.pending_level, lvl)
	assert_eq(GameManager.last_entrance_pos, Vector2i(3, 4))
	assert_eq(GameManager.pending_player_spawn, Vector2i(-1, -1))

func test_complete_level_returns_to_overworld():
	var ow := LevelData.new()
	ow.level_id = "ow"
	ow.width = 2
	ow.height = 2
	ow.fill_blank()
	ow.map_kind = LevelData.MapKind.OVERWORLD
	var lvl := LevelData.new()
	lvl.level_id = "keen1_01"
	lvl.width = 2
	lvl.height = 2
	lvl.fill_blank()
	GameManager.register_level(ow)
	GameManager.register_level(lvl)
	GameManager.current_overworld = ow
	GameManager.enter_level_no_scene_swap("keen1_01", Vector2i(5, 6))
	GameManager.complete_level_no_scene_swap()
	assert_eq(GameManager.state, GameManager.State.OVERWORLD)
	assert_eq(GameManager.pending_level, ow)
	assert_eq(GameManager.pending_player_spawn, Vector2i(5, 6))
	assert_true(GameManager.is_level_completed("keen1_01"))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — no `enter_level_no_scene_swap` / `complete_level_no_scene_swap`.

- [ ] **Step 3: Add transition methods (with test-seam no-swap variants)**

In `src/core/game_manager.gd`, add:

```gdscript
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
	current_level = null
	state = State.OVERWORLD
```

- [ ] **Step 4: Runtime — spawn override + entrance wiring + completion branch**

In `src/runtime/level_runtime.gd`:

4a. In `_ready()` (lines 30-32), guard the pending level, consume the pending player spawn override, and clear it:

```gdscript
func _ready() -> void:
	if GameManager != null and GameManager.pending_level != null:
		var lv := GameManager.pending_level
		GameManager.pending_level = null
		build(lv)
		if GameManager.pending_player_spawn.x >= 0 and is_instance_valid(player):
			player.position = _cell_center(GameManager.pending_player_spawn, _tile_size)
		GameManager.pending_player_spawn = Vector2i(-1, -1)
```

4b. In `_spawn_entities` (lines 129-136), after instantiating each node, wire up `LevelEntrance` instances:

```gdscript
func _spawn_entities(level: LevelData, ts: int) -> void:
	for def: EntityDef in level.entities:
		var node := EntityRegistry.instantiate(def.type, _cell_center(Vector2i(def.x, def.y), ts), def.properties)
		if node != null:
			add_child(node)
			entities_spawned.append(node)
			if node is LevelEntrance:
				(node as LevelEntrance).set_tile(Vector2i(def.x, def.y))
				(node as LevelEntrance).refresh_blocking()
				(node as LevelEntrance).enter_requested.connect(_on_enter_requested)
			elif node.has_signal("level_completed"):
				node.level_completed.connect(_on_level_completed)
```

Add the handler (near `_on_level_completed`):

```gdscript
func _on_enter_requested(target_level_id: String, _tile: Vector2i) -> void:
	if GameManager != null:
		GameManager.enter_level(target_level_id, _tile)
```

4c. In `_on_completion_dismissed` (lines 157-162), branch on whether this is a Test ▶ round-trip (`return_scene` set) or the real overworld loop:

```gdscript
func _on_completion_dismissed() -> void:
	get_tree().paused = false
	if GameManager != null and GameManager.return_scene != null:
		# Test ▶ from the editor: go back to the editor.
		get_tree().change_scene_to_packed(GameManager.return_scene)
	elif GameManager != null and GameManager.current_overworld != null:
		# Overworld loop: return to the overworld at the entrance tile.
		GameManager.complete_level()
	else:
		get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")
```

- [ ] **Step 5: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/core/game_manager.gd src/runtime/level_runtime.gd tests/unit/test_game_manager_loop.gd
git commit -m "feat(runtime): wire enter/return overworld loop through GameManager"
```

---

# Phase 4 — Gates + boot flow

### Task 10: Gate solidity refresh after completion

**Files:**
- Modify: `src/runtime/level_runtime.gd` (`_spawn_entities` already calls `refresh_blocking` — verify); add nothing if already correct. The blocker re-reads `GameManager.completed_levels` at build time.
- Test: `tests/unit/test_level_entrance.gd` (append — re-blocking after mark_completed)

The blocker is already rebuilt from `GameManager` state whenever the overworld is built (Task 9 calls `refresh_blocking()` on spawn). This task confirms the round-trip with a test and locks the behavior.

- [ ] **Step 1: Write the test**

Append to `tests/unit/test_level_entrance.gd`:

```gdscript
func test_refresh_blocking_clears_after_completion():
	var e := _make_entrance("a", true)
	assert_true(e.is_blocking())            # not completed yet
	GameManager.mark_completed("a")
	e.refresh_blocking()
	assert_false(e.is_blocking())           # completed -> unblocked
	# Blocker shape should now be disabled (deferred).
	# is_blocking() is the authoritative check; assert it directly.
```

- [ ] **Step 2: Run the test**

Run: `./tests/run_all.sh`
Expected: PASS (Task 6 + Task 9 already implement this). If it fails, fix `refresh_blocking` / `_apply_blocking` so `disabled` reflects `is_blocking()`.

- [ ] **Step 3: Commit (test pinning the behavior)**

```bash
git add tests/unit/test_level_entrance.gd
git commit -m "test(entrance): pin gate clearance after level completion"
```

---

### Task 11: Boot flow — `Episode.overworld_level_id` + `start_episode` + Play button

**Files:**
- Modify: `src/core/episode.gd:8-9` (add fields + method)
- Modify: `src/core/game_manager.gd` (add `start_episode`)
- Modify: `src/episodes/keen1/episode.gd:7-9` (`_init` — set defaults; leave blank until a bundled overworld exists)
- Modify: `src/ui/main_menu.gd` (Play button handler) + `src/ui/main_menu.tscn` (add `%PlayButton`)
- Test: `tests/unit/test_game_manager_loop.gd` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_game_manager_loop.gd`:

```gdscript
func test_episode_load_overworld_from_path():
	# Build a tiny overworld .tres, point an Episode at it, load.
	var ow := LevelData.new()
	ow.level_id = "ow_test"
	ow.level_name = "Test Overworld"
	ow.width = 2
	ow.height = 2
	ow.fill_blank()
	ow.map_kind = LevelData.MapKind.OVERWORLD
	var path := "res://tests/tmp_overworld.tres"
	# Save into res:// so ResourceLoader.load(path) works headless.
	DirAccess.make_dir_recursive_absolute("res://tests/")
	assert_eq(ResourceSaver.save(ow, path), OK)
	var ep := Episode.new()
	ep.id = "t"
	ep.title = "T"
	ep.overworld_level_id = "ow_test"
	ep.overworld_path = path
	var loaded := ep.load_overworld()
	assert_not_null(loaded)
	assert_eq(loaded.level_id, "ow_test")
	assert_eq(loaded.map_kind, LevelData.MapKind.OVERWORLD)

func test_start_episode_sets_overworld_state():
	var ow := LevelData.new()
	ow.level_id = "ow_s"
	ow.width = 2
	ow.height = 2
	ow.fill_blank()
	ow.map_kind = LevelData.MapKind.OVERWORLD
	GameManager.register_level(ow)
	# start_episode_no_scene_swap takes the resolved overworld directly so the
	# test avoids directory scanning + scene swaps.
	GameManager.start_episode_no_scene_swap("fake", ow)
	assert_eq(GameManager.state, GameManager.State.OVERWORLD)
	assert_eq(GameManager.current_overworld, ow)
	assert_eq(GameManager.pending_level, ow)
	assert_eq(GameManager.current_episode_id, "fake")
```

(Note: `start_episode_no_scene_swap` takes the resolved overworld directly so the test avoids `register_episodes`/disk. The real `start_episode(ep_id)` resolves via `Episode.load_overworld()` then delegates.)

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — no `overworld_path`, `load_overworld`, `start_episode_no_scene_swap`.

- [ ] **Step 3: Extend `Episode`**

In `src/core/episode.gd`, add fields and a loader (after `title`):

```gdscript
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
```

- [ ] **Step 4: Add `start_episode` to `GameManager`**

In `src/core/game_manager.gd`, add (the real method resolves the episode; the `_no_scene_swap` variant is exercised by tests):

```gdscript
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
	pending_level = ow
	pending_player_spawn = Vector2i(-1, -1)
	state = State.OVERWORLD


func _resolve_overworld(ep_id: String) -> LevelData:
	# Find the Episode instance for ep_id and ask it for its overworld.
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
					return ep.load_overworld()
		subdir = dir.get_next()
	dir.list_dir_end()
	return null
```

- [ ] **Step 5: Add the Play button**

In `src/ui/main_menu.tscn`, add a `PlayButton` node (Button, name `PlayButton`, text "Play", unique-name accessible as `%PlayButton`) alongside the existing `EditorButton` / `QuitButton`. (If the worker cannot edit the `.tscn` by hand cleanly, they may add it via code in `main_menu.gd`'s `_ready` instead — see below.)

Code path (add to `src/ui/main_menu.gd`):

```gdscript
extends Control

const EDITOR_SCENE := preload("res://src/editor/level_editor.tscn")

func _ready() -> void:
	_ensure_play_button()
	%EditorButton.pressed.connect(_open_editor)
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())

func _ensure_play_button() -> void:
	if has_node("%PlayButton"):
		(%PlayButton as Button).pressed.connect(_play)
		return
	var play := Button.new()
	play.name = "PlayButton"
	play.text = "Play"
	play.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(play)
	play.set("theme_type_variation", "Button")
	(%PlayButton as Button).pressed.connect(_play)

func _play() -> void:
	GameManager.start_episode("keen1")

func _open_editor() -> void:
	get_tree().change_scene_to_packed(EDITOR_SCENE)
```

(The `_ensure_play_button` code path makes the feature work even if the `.tscn` is not hand-edited; if the worker adds the node to the `.tscn`, the `has_node("%PlayButton")` branch wires it up.)

- [ ] **Step 6: Run all tests**

Run: `./tests/run_all.sh`
Expected: PASS for all tests, including the new boot-flow tests.

- [ ] **Step 7: Manual smoke (documented, not automated)**

After authoring a keen1 overworld `.tres` in the editor (set its `map_kind = OVERWORLD`, place a `keen1.level_entrance` entity with a `target_level_id`, and point `src/episodes/keen1/episode.gd::_init` at its path via `overworld_path`), launch the game, press **Play**, walk to the entrance, press **Up** to enter, reach the level exit, and confirm the return to the overworld at the entrance tile with the gate (if any) now cleared. This is a content task, not a code task — tracked separately.

- [ ] **Step 8: Commit**

```bash
git add src/core/episode.gd src/core/game_manager.gd src/ui/main_menu.gd src/ui/main_menu.tscn src/episodes/keen1/episode.gd tests/unit/test_game_manager_loop.gd
git commit -m "feat(core): boot flow — start_episode + Episode.load_overworld + Play button"
```

---

## Post-implementation

- Run the full suite once more: `./tests/run_all.sh` — must be green.
- Optionally launch the editor (`make edit`) and verify the Map Kind dropdown appears and the entity palette swaps when toggled.

## Notes on seams left for Plan 5 / Plan 6

- `GameManager.register_level` / `get_level_by_id` is the level-resolution seam. Plan 5 (`PackLoader`) will populate `_levels_by_id` from `res://levels/` + `user://levelpacks/` instead of ad-hoc registration.
- `GameManager.serialize()` / `deserialize()` are the save seams. Plan 6 wires them to `user://save.json`.
- `interact` keybind (Up arrow) is hardcoded in `_ensure_input_actions`; Plan 6 (gamepad/rebind) generalizes input.
