# Teleporter Entity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a directional, cross-map Teleporter entity (valid in LEVEL + OVERWORLD) that moves the player to a destination teleporter on proximity + `interact`.

**Architecture:** New `Teleporter` Node2D mirrors `LevelEntrance` (proximity Area2D + interact). It carries 3 string props (`teleporter_id`, `destination_level_id`, `destination_teleporter_id`) and emits `teleport_requested`. `LevelRuntime` wires the signal to `GameManager.teleport()`, which resolves the destination level via `get_level_by_id`, scans that level's entities for the matching `teleporter_id` tile, and swaps the scene with the player spawning on that tile.

**Tech Stack:** Godot 4.7, GDScript, GUT (Godot Unit Test).

**Spec:** `docs/superpowers/specs/2026-07-09-teleporter-design.md`

**Test command:** `./tests/run_all.sh` (must pass before commit)

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `src/runtime/entities/teleporter.gd` | Runtime node: proximity + interact → emit `teleport_requested` | **Create** |
| `src/runtime/entities/teleporter.tscn` | Minimal scene wrapping the script (mirror `level_entrance.tscn`) | **Create** |
| `src/episodes/keen1/episode.gd` | Register `keen1.teleporter` (SPECIAL, both map kinds, 3-prop schema) | **Modify** |
| `src/core/game_manager.gd` | `teleport()` + `teleport_no_scene_swap()` + `_find_teleporter_tile()` | **Modify** |
| `src/runtime/level_runtime.gd` | `_spawn_entities` Teleporter branch + `_on_teleport_requested` | **Modify** |
| `tests/unit/test_teleporter.gd` | Teleporter node unit tests | **Create** |
| `tests/unit/test_game_manager_teleport.gd` | GameManager teleport resolution tests | **Create** |
| `tests/unit/test_level_runtime.gd` | Teleporter signal-wiring test | **Modify** |

**Type-agnostic resolution note:** `_find_teleporter_tile` matches on the `teleporter_id` *property*, not the type string — so `GameManager` (core) never hardcodes `keen1.*`. Any future namespaced teleporter resolves without core changes.

---

## Task 1: Teleporter runtime node + scene (TDD)

**Files:**
- Create: `src/runtime/entities/teleporter.gd`
- Create: `src/runtime/entities/teleporter.tscn`
- Test: `tests/unit/test_teleporter.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_teleporter.gd`:

```gdscript
extends GutTest

func _make_teleporter(tid := "a", dlevel := "lvl1", dtp := "b") -> Node2D:
	var t := Teleporter.new()
	add_child_autofree(t)
	t.setup("keen1.teleporter", {
		"teleporter_id": tid,
		"destination_level_id": dlevel,
		"destination_teleporter_id": dtp,
	})
	return t

func test_setup_reads_properties():
	var t := _make_teleporter("alpha", "lvl2", "beta")
	assert_eq(t.teleporter_id, "alpha")
	assert_eq(t.destination_level_id, "lvl2")
	assert_eq(t.destination_teleporter_id, "beta")

func test_setup_defaults_empty():
	var t := Teleporter.new()
	add_child_autofree(t)
	t.setup("keen1.teleporter", {})
	assert_eq(t.teleporter_id, "")
	assert_eq(t.destination_level_id, "")
	assert_eq(t.destination_teleporter_id, "")

func test_attempt_teleport_requires_nearby():
	var t := _make_teleporter()
	assert_false(t.attempt_teleport(true))
	t._set_nearby_for_test(true)
	assert_true(t.attempt_teleport(true))

func test_attempt_teleport_requires_interact():
	var t := _make_teleporter()
	t._set_nearby_for_test(true)
	assert_false(t.attempt_teleport(false))

func test_attempt_teleport_requires_destination_fields():
	var t := _make_teleporter("a", "", "")
	t._set_nearby_for_test(true)
	assert_false(t.attempt_teleport(true))

func test_attempt_teleport_emits_configured_destination():
	var t := _make_teleporter("a", "lvl_x", "b")
	t._set_nearby_for_test(true)
	var captured := {"level": "", "teleporter": ""}
	t.teleport_requested.connect(func(lvl: String, tp: String) -> void:
		captured["level"] = lvl
		captured["teleporter"] = tp)
	assert_true(t.attempt_teleport(true))
	assert_eq(captured["level"], "lvl_x")
	assert_eq(captured["teleporter"], "b")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh` (or target the file)
Expected: FAIL — `Teleporter` class not found / identifier undefined.

- [ ] **Step 3: Write minimal implementation**

Create `src/runtime/entities/teleporter.gd`:

```gdscript
class_name Teleporter
extends Node2D
## Special entity valid in both LEVEL and OVERWORLD maps. Player stands near it
## and presses `interact` to request a teleport to a destination teleporter,
## which may live in this map or a different one. Emits `teleport_requested`;
## LevelRuntime wires it to GameManager.teleport().
##
## Directional: each teleporter has exactly one destination. A two-way link is
## two teleporters pointing at each other. Resolution (finding the destination
## tile) is GameManager's job — this node only carries the configured IDs.

signal teleport_requested(destination_level_id: String, destination_teleporter_id: String)

const TILE := 64
const PROXIMITY_RADIUS := 1  # tiles around the teleporter in each direction (3x3 zone)

var type_id: String = ""
var teleporter_id: String = ""
var destination_level_id: String = ""
var destination_teleporter_id: String = ""

var _nearby: bool = false
var _proximity: Area2D


## Called by EntityRegistry.instantiate after constructing the node.
func setup(p_type_id: String, props: Dictionary) -> void:
	type_id = p_type_id
	teleporter_id = String(props.get("teleporter_id", ""))
	destination_level_id = String(props.get("destination_level_id", ""))
	destination_teleporter_id = String(props.get("destination_teleporter_id", ""))


func _ready() -> void:
	_build_proximity()
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


func _build_visual() -> void:
	if has_node("Visual"):
		return
	var vis := ColorRect.new()
	vis.name = "Visual"
	vis.size = Vector2(TILE, TILE)
	vis.position = Vector2(-TILE / 2.0, -TILE / 2.0)
	vis.color = Color(0.9, 0.3, 0.9, 1)  # magenta placeholder
	add_child(vis)


func _process(_delta: float) -> void:
	attempt_teleport(Input.is_action_just_pressed("interact"))


## Returns true and emits teleport_requested when a player is nearby, the
## interact control is pressed, and both destination fields are set.
## `interact_pressed` is a parameter (not read from Input) so tests are
## deterministic.
func attempt_teleport(interact_pressed: bool) -> bool:
	if not _nearby or not interact_pressed:
		return false
	if destination_level_id == "" or destination_teleporter_id == "":
		return false
	teleport_requested.emit(destination_level_id, destination_teleporter_id)
	return true


func _on_body_entered(_body: Node) -> void:
	_nearby = true


func _on_body_exited(_body: Node) -> void:
	_nearby = false


# --- test seam ---
func _set_nearby_for_test(v: bool) -> void:
	_nearby = v
```

Create `src/runtime/entities/teleporter.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/runtime/entities/teleporter.gd" id="1_tp"]

[node name="Teleporter" type="Node2D"]
script = ExtResource("1_tp")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS — all 6 teleporter tests green; no regressions.

- [ ] **Step 5: Commit**

```bash
git add src/runtime/entities/teleporter.gd src/runtime/entities/teleporter.tscn tests/unit/test_teleporter.gd
git commit -m "feat(entities): add Teleporter node (proximity+interact, emits teleport_requested)"
```

---

## Task 2: Register keen1.teleporter in the episode

**Files:**
- Modify: `src/episodes/keen1/episode.gd` (end of `register_entities()`, after the Ship registration)

- [ ] **Step 1: Add the registration block**

Append before the function's closing, reusing the existing `all_kinds` local (defined at line 37 as `[LEVEL, OVERWORLD]`):

```gdscript
	var teleporter := preload("res://src/runtime/entities/teleporter.tscn")
	registry.register("keen1.teleporter", registry.CATEGORY_SPECIAL, "Teleporter",
		[
			{name = "teleporter_id", default = "", type = "string"},
			{name = "destination_level_id", default = "", type = "string"},
			{name = "destination_teleporter_id", default = "", type = "string"},
		],
		teleporter, all_kinds)
```

- [ ] **Step 2: Verify it is registered and valid in both map kinds**

Run: `./tests/run_all.sh`
Expected: PASS — existing `test_editor_map_kind.gd` still green (it only asserts specific entries; adding one in both kinds doesn't break it). No regressions.

(If any test asserts an exact palette count/list, update it. Otherwise no new test needed here — Task 4 exercises instantiation end-to-end.)

- [ ] **Step 3: Commit**

```bash
git add src/episodes/keen1/episode.gd
git commit -m "feat(entities): register keen1.teleporter (SPECIAL, level+overworld)"
```

---

## Task 3: GameManager.teleport resolution (TDD)

**Files:**
- Modify: `src/core/game_manager.gd` (add `teleport()`, `teleport_no_scene_swap()`, `_find_teleporter_tile()`)
- Test: `tests/unit/test_game_manager_teleport.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_game_manager_teleport.gd`:

```gdscript
extends GutTest

func before_each():
	GameManager.clear_progress()

func after_each():
	GameManager.clear_progress()

func _add_teleporter(ld: LevelData, id: String, x: int, y: int, dlevel := "", dtp := "") -> void:
	ld.entities.append(EntityDef.new("keen1.teleporter", x, y, {
		"teleporter_id": id,
		"destination_level_id": dlevel,
		"destination_teleporter_id": dtp,
	}))

func _level(level_id: String, map_kind: int) -> LevelData:
	var ld := LevelData.new()
	ld.level_id = level_id
	ld.width = 4
	ld.height = 4
	ld.fill_blank()
	ld.map_kind = map_kind
	return ld

func test_same_map_teleport_sets_spawn_and_state():
	var lvl := _level("lvl1", LevelData.MapKind.LEVEL)
	_add_teleporter(lvl, "src", 1, 1, "lvl1", "dst")
	_add_teleporter(lvl, "dst", 5, 6, "lvl1", "src")
	GameManager.register_level(lvl)
	GameManager.teleport_no_scene_swap("lvl1", "dst")
	assert_eq(GameManager.pending_level, lvl)
	assert_eq(GameManager.pending_player_spawn, Vector2i(5, 6))
	assert_eq(GameManager.state, GameManager.State.LEVEL)
	assert_eq(GameManager.current_level, lvl)

func test_cross_map_teleport_into_level():
	var ow := _level("ow", LevelData.MapKind.OVERWORLD)
	_add_teleporter(ow, "ow_north", 2, 3, "lvl_secret", "secret")
	var secret := _level("lvl_secret", LevelData.MapKind.LEVEL)
	_add_teleporter(secret, "secret", 7, 8, "ow", "ow_north")
	GameManager.register_level(ow)
	GameManager.register_level(secret)
	GameManager.teleport_no_scene_swap("lvl_secret", "secret")
	assert_eq(GameManager.pending_level, secret)
	assert_eq(GameManager.pending_player_spawn, Vector2i(7, 8))
	assert_eq(GameManager.state, GameManager.State.LEVEL)
	assert_eq(GameManager.current_level, secret)

func test_teleport_to_overworld_sets_overworld_state():
	var ow := _level("ow", LevelData.MapKind.OVERWORLD)
	_add_teleporter(ow, "ow_tp", 3, 3)
	var lvl := _level("lvl1", LevelData.MapKind.LEVEL)
	_add_teleporter(lvl, "lvl_tp", 0, 0, "ow", "ow_tp")
	GameManager.register_level(ow)
	GameManager.register_level(lvl)
	GameManager.teleport_no_scene_swap("ow", "ow_tp")
	assert_eq(GameManager.state, GameManager.State.OVERWORLD)
	assert_null(GameManager.current_level)
	assert_eq(GameManager.pending_player_spawn, Vector2i(3, 3))

func test_dangling_level_id_is_noop():
	var lvl := _level("lvl1", LevelData.MapKind.LEVEL)
	_add_teleporter(lvl, "a", 1, 1)
	GameManager.register_level(lvl)
	var state_before := GameManager.state
	GameManager.teleport_no_scene_swap("nope", "a")
	assert_eq(GameManager.state, state_before, "state unchanged on dangling level")
	assert_null(GameManager.pending_level, "pending_level untouched on dangling level")

func test_dangling_teleporter_id_is_noop():
	var lvl := _level("lvl1", LevelData.MapKind.LEVEL)
	_add_teleporter(lvl, "a", 1, 1)
	GameManager.register_level(lvl)
	GameManager.teleport_no_scene_swap("lvl1", "missing")
	assert_eq(GameManager.pending_player_spawn, Vector2i(-1, -1), "spawn untouched when teleporter missing")

func test_empty_destination_is_noop():
	GameManager.teleport_no_scene_swap("", "")
	assert_eq(GameManager.state, GameManager.State.MENU, "state unchanged on empty destination")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `teleport_no_scene_swap` not defined on GameManager.

- [ ] **Step 3: Write minimal implementation**

Add to `src/core/game_manager.gd` (after `fail_level_no_scene_swap`, before `start_episode`):

```gdscript
## Transition the player to a destination teleporter (same or different map).
## Resolves the destination level via get_level_by_id and the destination
## teleporter's tile by scanning that level's entities for a matching
## teleporter_id. No-op (push_warning) on dangling refs.
func teleport(destination_level_id: String, destination_teleporter_id: String) -> void:
	teleport_no_scene_swap(destination_level_id, destination_teleporter_id)
	get_tree().change_scene_to_packed(RUNTIME_SCENE)


## Headless-testable core of teleport(); does not swap the scene.
func teleport_no_scene_swap(destination_level_id: String, destination_teleporter_id: String) -> void:
	if destination_level_id == "" or destination_teleporter_id == "":
		push_warning("GameManager.teleport: empty destination (level='%s', teleporter='%s')" % [destination_level_id, destination_teleporter_id])
		return
	var lvl := get_level_by_id(destination_level_id)
	if lvl == null:
		push_warning("GameManager.teleport: unknown level id '%s'" % destination_level_id)
		return
	var tile := _find_teleporter_tile(lvl, destination_teleporter_id)
	if tile.x < 0:
		push_warning("GameManager.teleport: teleporter '%s' not found in level '%s'" % [destination_teleporter_id, destination_level_id])
		return
	pending_level = lvl
	pending_player_spawn = tile
	if lvl.map_kind == LevelData.MapKind.LEVEL:
		current_level = lvl
		state = State.LEVEL
	else:
		current_level = null
		state = State.OVERWORLD


## Find the tile of the teleporter whose properties.teleporter_id == id within
## `level`. Returns Vector2i(-1, -1) if none. A teleporter is identified by
## carrying a `teleporter_id` property (type-agnostic, so any namespaced
## teleporter type resolves without core knowing the type id).
func _find_teleporter_tile(level: LevelData, teleporter_id: String) -> Vector2i:
	for def: EntityDef in level.entities:
		if String(def.properties.get("teleporter_id", "")) == teleporter_id:
			return Vector2i(def.x, def.y)
	return Vector2i(-1, -1)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS — all 6 teleport-resolution tests green; no regressions.

- [ ] **Step 5: Commit**

```bash
git add src/core/game_manager.gd tests/unit/test_game_manager_teleport.gd
git commit -m "feat(game): GameManager.teleport resolves cross-map teleporter destination"
```

---

## Task 4: LevelRuntime signal wiring (TDD)

**Files:**
- Modify: `src/runtime/level_runtime.gd` (`_spawn_entities` branch + new `_on_teleport_requested`)
- Test: `tests/unit/test_level_runtime.gd` (append one test)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_level_runtime.gd`:

```gdscript
func test_build_wires_teleporter_signal():
	GameManager.pending_level = null
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.player_spawn = Vector2i(0, 1)
	ld.entities.append(EntityDef.new("keen1.teleporter", 2, 1, {
		"teleporter_id": "a",
		"destination_level_id": "ow",
		"destination_teleporter_id": "b",
	}))
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	var tp: Teleporter = null
	for n in rt.entities_spawned:
		if n is Teleporter:
			tp = n
			break
	assert_not_null(tp, "teleporter spawned")
	assert_true(tp.teleport_requested.get_connections().size() >= 1, "teleport_requested wired to runtime")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — teleporter spawns but `teleport_requested` has 0 connections (wiring branch not added yet).

- [ ] **Step 3: Write minimal implementation**

In `src/runtime/level_runtime.gd` `_spawn_entities`, insert a `Teleporter` branch between the `LevelEntrance` and `level_completed` branches so the final shape is:

```gdscript
		if node is LevelEntrance:
			(node as LevelEntrance).set_tile(Vector2i(def.x, def.y))
			(node as LevelEntrance).refresh_blocking()
			(node as LevelEntrance).enter_requested.connect(_on_enter_requested)
		elif node is Teleporter:
			(node as Teleporter).teleport_requested.connect(_on_teleport_requested)
		elif node.has_signal("level_completed"):
			node.level_completed.connect(_on_level_completed)
```

Add the handler near `_on_enter_requested`:

```gdscript
func _on_teleport_requested(destination_level_id: String, destination_teleporter_id: String) -> void:
	if GameManager != null:
		GameManager.teleport(destination_level_id, destination_teleporter_id)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS — wiring test green; no regressions.

- [ ] **Step 5: Commit**

```bash
git add src/runtime/level_runtime.gd tests/unit/test_level_runtime.gd
git commit -m "feat(runtime): wire Teleporter.teleport_requested to GameManager.teleport"
```

---

## Task 5: Full suite verification

- [ ] **Step 1: Run the entire suite clean**

Run: `./tests/run_all.sh`
Expected: All tests PASS, zero failures. Pay attention to any test that asserts exact palette contents (e.g. `test_editor_map_kind.gd`) — none should break, but verify.

- [ ] **Step 2: Headless import sanity (optional)**

Run: `make import`
Expected: exits cleanly (no script parse errors from the new class_name/scene).

---

## Self-Review

- **Spec coverage:** directional single-dest (Task 1 props + Task 3) ✓; string IDs (Task 1) ✓; proximity+interact (Task 1) ✓; both map kinds (Task 2) ✓; cross-map (Task 3) ✓; no anti-bounce (interact-based, N/A) ✓; GameManager resolution + dangling no-ops (Task 3) ✓; LevelRuntime wiring (Task 4) ✓.
- **Type consistency:** signal name `teleport_requested`, props `teleporter_id`/`destination_level_id`/`destination_teleporter_id`, methods `attempt_teleport`/`teleport`/`teleport_no_scene_swap`/`_find_teleporter_tile` — consistent across all tasks. ✓
- **Placeholders:** none — all code blocks complete. ✓
