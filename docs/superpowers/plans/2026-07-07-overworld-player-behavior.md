# Overworld Player Behavior Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Player a top-down 4-directional movement mode for OVERWORLD maps, drive the four `OverworldUp/Down/Left/Right` sprites, and suppress the HUD there.

**Architecture:** Add a `Mode` enum and an overworld branch inside the existing Player script. `LevelRuntime._spawn_player` flips the mode (and suppresses HUD) based on `level.map_kind`. Two new input actions (`move_up`, `move_down`) join the existing `move_left`/`move_right`. Single Player scene, single script, no new files except one focused test file.

**Tech Stack:** Godot 4.7 (stable), GDScript, GUT (Godot Unit Test) headless tests under `tests/unit/`, run via `./tests/run_all.sh`.

**Spec:** `docs/superpowers/specs/2026-07-07-overworld-player-behavior-design.md`

---

## File Structure

| File | Role |
|------|------|
| `src/core/game_manager.gd` | Register `move_up`/`move_down` input actions alongside existing `move_left`/`move_right`. |
| `src/runtime/player/player.gd` | Add `Mode`/`Direction` enums, `_mode`/`_overworld_dir` state, `set_mode()`, `_physics_overworld()`, overworld branch in `_sync_visual()`, `_overworld_anim_name()`, mode-aware sprite lists. LEVEL path unchanged. |
| `src/runtime/level_runtime.gd` | `_spawn_player` calls `set_mode(OVERWORLD)` when `map_kind == OVERWORLD`. `_build_hud` returns early when `map_kind == OVERWORLD`. |
| `tests/unit/test_player_overworld.gd` | New file. All overworld-mode player tests (mode flag, physics, visual sync, alignment). |
| `tests/unit/test_game_manager.gd` | Extend with `move_up`/`move_down` action assertions. |
| `tests/unit/test_level_runtime.gd` | Extend with: overworld map spawns player in OVERWORLD mode. |
| `tests/unit/test_hud.gd` | Extend with: overworld map has no HUD. |

---

## Task 1: Register `move_up` and `move_down` input actions

**Files:**
- Modify: `src/core/game_manager.gd:182-187` (the `_ensure_input_actions` block — exact name may differ; locate the cluster of `_add_key_action("move_…")` calls)
- Test: `tests/unit/test_game_manager.gd:18-19` (extend the existing `move_left`/`move_right` assertions)

- [ ] **Step 1: Write the failing test**

Open `tests/unit/test_game_manager.gd` and find the existing test that asserts `move_left` / `move_right` exist (around lines 18–19). Add two assertions to the same test (or add a new test below it):

```gdscript
func test_movement_actions_registered():
	assert_true(InputMap.has_action("move_left"))
	assert_true(InputMap.has_action("move_right"))
	assert_true(InputMap.has_action("move_up"))
	assert_true(InputMap.has_action("move_down"))
```

If the existing test has a different name, keep its name and just add the two new `assert_true` lines inside it. Do not delete the old assertions.

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `assert_true(InputMap.has_action("move_up"))` fails because the action is not registered yet.

- [ ] **Step 3: Register the actions**

In `src/core/game_manager.gd`, find the cluster of `_add_key_action` calls inside the input-action setup method (search for `_add_key_action("move_left", KEY_A)`). Add two new lines immediately after the `move_right` line:

```gdscript
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("move_up", KEY_W)
	_add_key_action("move_down", KEY_S)
```

Use W and S to match the existing A/D lateral mapping. (Arrow keys are intentionally avoided — `interact` is bound to `KEY_UP` and the overworld should not collide with it.)

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/game_manager.gd tests/unit/test_game_manager.gd
git commit -m "feat(core): register move_up/move_down input actions for overworld"
```

---

## Task 2: Add `Mode`/`Direction` enums + `set_mode()` plumbing

This task adds the state only — no behavior change yet. LEVEL physics and visuals continue to work because the default mode is LEVEL and no code branches on `_mode` until later tasks.

**Files:**
- Modify: `src/runtime/player/player.gd` (add enums, vars, `set_mode()` near the existing state vars around lines 29–44)
- Test: `tests/unit/test_player_overworld.gd` (create new file)

- [ ] **Step 1: Create the test file with the failing test**

Create `tests/unit/test_player_overworld.gd`:

```gdscript
extends GutTest


func _new_player() -> Player:
	var p: Player = add_child_autofree(load("res://src/runtime/player/player.tscn").instantiate())
	return p


func test_default_mode_is_level():
	var p := _new_player()
	assert_eq(p._mode, Player.Mode.LEVEL, "player starts in LEVEL mode")


func test_set_mode_flips_to_overworld():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	assert_eq(p._mode, Player.Mode.OVERWORLD, "set_mode(OVERWORLD) flips mode")


func test_overworld_dir_defaults_down():
	var p := _new_player()
	assert_eq(p._overworld_dir, Player.Direction.DOWN, "default overworld facing is DOWN")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — parse error or `Player.Mode` does not exist.

- [ ] **Step 3: Add the enums, vars, and `set_mode()`**

In `src/runtime/player/player.gd`, just below the existing `class_name Player` / `extends CharacterBody2D` lines and the docstring (around line 6), add the two enums:

```gdscript
enum Mode { LEVEL, OVERWORLD }
enum Direction { UP, DOWN, LEFT, RIGHT }
```

Among the existing state vars (around lines 33–44), add:

```gdscript
var _mode: int = Mode.LEVEL
var _overworld_dir: int = Direction.DOWN
```

Add the setter anywhere in the script (place it near `lock_input()` for visibility, around line 56–60):

```gdscript
## Switches the player between LEVEL (platformer) and OVERWORLD (top-down) rules.
## Re-runs sprite alignment so the active sprite set is positioned correctly.
func set_mode(m: int) -> void:
	_mode = m
	_align_sprite_feet()
```

Note: `_align_sprite_feet()` already exists and safely no-ops on missing nodes. It will be made mode-aware in Task 4; for now it iterates whatever set it currently does (the LEVEL set), which is fine because the LEVEL sprites are still in the scene.

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS for the three new tests, and all existing tests still pass (no behavior changed).

- [ ] **Step 5: Commit**

```bash
git add src/runtime/player/player.gd tests/unit/test_player_overworld.gd
git commit -m "feat(player): add Mode/Direction enums + set_mode() plumbing"
```

---

## Task 3: Overworld physics — 4-directional movement, no gravity

**Files:**
- Modify: `src/runtime/player/player.gd` — add `overworld_speed` export, add `_physics_overworld()`, branch at top of `_physics_process()`.
- Test: `tests/unit/test_player_overworld.gd` — append physics tests.

- [ ] **Step 1: Append the failing tests**

Append to `tests/unit/test_player_overworld.gd`:

```gdscript
func test_overworld_applies_no_gravity():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	p.velocity = Vector2(0, 0)
	p._physics_process(0.016)
	assert_almost_eq(p.velocity.y, 0.0, 0.01, "no gravity applied in overworld")


func test_overworld_velocity_tracks_input_vector():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	Input.action_press("move_right")
	Input.action_press("move_down")
	p._physics_process(0.016)
	var expected := Vector2(1, 1).normalized() * p.overworld_speed
	assert_almost_eq(p.velocity.x, expected.x, 0.5, "velocity.x = input * overworld_speed")
	assert_almost_eq(p.velocity.y, expected.y, 0.5, "velocity.y = input * overworld_speed")
	Input.action_release("move_right")
	Input.action_release("move_down")


func test_overworld_no_input_zeros_velocity():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	p.velocity = Vector2(123, 456)
	p._physics_process(0.016)
	assert_almost_eq(p.velocity.x, 0.0, 0.01, "no input -> zero velocity")
	assert_almost_eq(p.velocity.y, 0.0, 0.01, "no input -> zero velocity")


func test_overworld_dir_updates_on_dominant_axis_horizontal():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	Input.action_press("move_left")
	p._physics_process(0.016)
	assert_eq(p._overworld_dir, Player.Direction.LEFT, "pure-left input -> LEFT")
	Input.action_release("move_left")


func test_overworld_dir_updates_on_dominant_axis_vertical():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	Input.action_press("move_up")
	p._physics_process(0.016)
	assert_eq(p._overworld_dir, Player.Direction.UP, "pure-up input -> UP")
	Input.action_release("move_up")


func test_overworld_dir_prefers_horizontal_on_tie():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	Input.action_press("move_right")  # magnitude tie with up -> horizontal wins
	Input.action_press("move_up")
	p._physics_process(0.016)
	assert_eq(p._overworld_dir, Player.Direction.RIGHT, "tied magnitude -> horizontal dominant")
	Input.action_release("move_right")
	Input.action_release("move_up")


func test_overworld_dir_persists_when_stopped():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	Input.action_press("move_up")
	p._physics_process(0.016)
	Input.action_release("move_up")
	p._physics_process(0.016)
	assert_eq(p._overworld_dir, Player.Direction.UP, "direction persists after release")


func test_overworld_lock_input_forces_x_axis():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	p.lock_input(1.0, 1.0)  # forced rightward
	p._physics_process(0.016)
	assert_almost_eq(p.velocity.x, p.overworld_speed, 0.5, "locked -> forced x velocity")
	assert_almost_eq(p.velocity.y, 0.0, 0.01, "locked -> no y velocity")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_all.sh`
Expected: FAIL — overworld mode still applies gravity (test 1 fails immediately), `_physics_overworld` doesn't exist.

- [ ] **Step 3: Add the `overworld_speed` export**

In `src/runtime/player/player.gd`, among the existing `@export var …` lines (around lines 16–27), add:

```gdscript
@export var overworld_speed: float = 320.0
```

- [ ] **Step 4: Add the overworld physics method and branch**

At the top of `_physics_process()` (currently line 62), insert an early return for overworld mode. The first three lines of the existing function currently are:

```gdscript
func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta
	if velocity.y > max_fall:
		velocity.y = max_fall
```

Change the function opening to:

```gdscript
func _physics_process(delta: float) -> void:
	if _mode == Mode.OVERWORLD:
		_physics_overworld(delta)
		return
	velocity.y += gravity * delta
	if velocity.y > max_fall:
		velocity.y = max_fall
	# ...rest unchanged...
```

Leave the rest of the LEVEL branch (the existing body) exactly as is.

Then add the new method immediately after `_physics_process` ends (before `shoot()` is a good spot — around line 120):

```gdscript
## Top-down 4-directional movement for OVERWORLD maps. No gravity, no jump/pogo/shoot.
func _physics_overworld(delta: float) -> void:
	var input_vec: Vector2
	if _input_locked:
		input_vec = Vector2(_forced_dir, 0.0)
	else:
		input_vec = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_vec * overworld_speed
	if input_vec != Vector2.ZERO:
		# Pick dominant axis. Ties go horizontal to match original Keen feel.
		if absf(input_vec.x) >= absf(input_vec.y):
			_overworld_dir = Direction.RIGHT if input_vec.x > 0.0 else Direction.LEFT
		else:
			_overworld_dir = Direction.DOWN if input_vec.y > 0.0 else Direction.UP
	move_and_slide()
	_sync_visual()
```

Notes:
- `Input.get_vector` returns a normalized vector when multiple actions are pressed, so diagonal speed is not faster than cardinal speed.
- `_input_locked` honors existing `lock_input()` callers — overworld cutscenes are not wired today, but if one is added the existing x-axis API still works.
- `move_and_slide()` against tile collision is unchanged — walls still block in the overworld.

- [ ] **Step 5: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS for all 8 overworld physics tests. All existing LEVEL tests still pass (early-return means LEVEL physics is byte-for-byte unchanged).

- [ ] **Step 6: Commit**

```bash
git add src/runtime/player/player.gd tests/unit/test_player_overworld.gd
git commit -m "feat(player): overworld physics — 4-directional top-down movement, no gravity"
```

---

## Task 4: Overworld visual sync + sprite alignment

**Files:**
- Modify: `src/runtime/player/player.gd`:
  - Replace the `PLAYER_SPRITES` const with `LEVEL_SPRITES` + `OVERWORLD_SPRITES`.
  - Make `_sync_visual()` mode-aware.
  - Add `_overworld_anim_name()` helper.
  - Make `_align_sprite_feet()` iterate the active sprite set.
- Test: `tests/unit/test_player_overworld.gd` — append visual tests.

- [ ] **Step 1: Append the failing tests**

Append to `tests/unit/test_player_overworld.gd`:

```gdscript
func _visible_sprite(p: Player) -> AnimatedSprite2D:
	for n in p.get_children():
		if n is AnimatedSprite2D and (n as AnimatedSprite2D).visible:
			return n
	return null


func test_overworld_shows_down_sprite_by_default():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	p._sync_visual()
	var vis := _visible_sprite(p)
	assert_not_null(vis, "one sprite visible")
	assert_eq(vis.name, "OverworldDown", "default facing -> OverworldDown visible")


func test_overworld_shows_direction_sprite():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	for dir_name in ["Up", "Down", "Left", "Right"]:
		var dir: int = {
			"Up": Player.Direction.UP,
			"Down": Player.Direction.DOWN,
			"Left": Player.Direction.LEFT,
			"Right": Player.Direction.RIGHT,
		}[dir_name]
		p._overworld_dir = dir
		p._sync_visual()
		var vis := _visible_sprite(p)
		assert_eq(vis.name, "Overworld" + dir_name, "direction %s -> matching sprite visible" % dir_name)


func test_overworld_moving_plays_anim():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	p._overworld_dir = Player.Direction.RIGHT
	p.velocity = Vector2(p.overworld_speed, 0)  # moving
	p._sync_visual()
	var vis := _visible_sprite(p)
	assert_true(vis.is_playing(), "moving -> anim playing")


func test_overworld_stopped_stops_on_frame_zero():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	p._overworld_dir = Player.Direction.UP
	p.velocity = Vector2(p.overworld_speed, 0)
	p._sync_visual()  # starts playing
	p.velocity = Vector2.ZERO  # now stopped
	p._sync_visual()
	var vis := _visible_sprite(p)
	assert_false(vis.is_playing(), "stopped -> anim stopped")
	assert_eq(vis.frame, 0, "stopped -> frame 0")


func test_overworld_no_flip_h():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	p._overworld_dir = Player.Direction.LEFT
	p._sync_visual()
	var vis := _visible_sprite(p)
	assert_false(vis.flip_h, "overworld sprites never flip (each direction has its own)")


func test_overworld_sprite_feet_aligned():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	var down := p.get_node("OverworldDown") as AnimatedSprite2D
	# collision 96 tall (foot_y=48), overworld sprite 64 tall (half=32) -> offset.y = -(32-48) = 16
	assert_almost_eq(down.offset.y, 16.0, 0.5, "overworld sprite feet align to collision bottom")
```

Note on the alignment math: collision box is 48×96 (foot at +48 from origin), overworld sprite is 64 tall (center at 0 → bottom at +32). To put sprite-bottom on collision-bottom, offset.y must shift the sprite down by `48 - 32 = 16`. The existing `_align_sprite_feet` uses the formula `offset.y = -(h*0.5 - foot_y)` which evaluates to `-(32 - 48) = 16` — same result. The test asserts the math.

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_all.sh`
Expected: FAIL — `_sync_visual()` still iterates `PLAYER_SPRITES` (which doesn't exist after this task renames it) or, if the const hasn't been renamed yet, the LEVEL branch shows `Idle` instead of `OverworldDown`.

- [ ] **Step 3: Replace the sprite const with two mode-aware lists**

In `src/runtime/player/player.gd`, find (around line 13):

```gdscript
const PLAYER_SPRITES := ["Idle", "Walking", "Jumping", "Shooting", "Pogo"]
```

Replace with:

```gdscript
const LEVEL_SPRITES := ["Idle", "Walking", "Jumping", "Shooting", "Pogo"]
const OVERWORLD_SPRITES := ["OverworldUp", "OverworldDown", "OverworldLeft", "OverworldRight"]
```

- [ ] **Step 4: Make `_align_sprite_feet()` mode-aware**

Find `_align_sprite_feet()` (around line 210). It currently iterates `PLAYER_SPRITES`. Replace the iteration source to pick the list based on `_mode`:

```gdscript
func _align_sprite_feet() -> void:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null or not (col.shape is RectangleShape2D):
		return
	var foot_y := (col.shape as RectangleShape2D).size.y * 0.5
	var sprites := OVERWORLD_SPRITES if _mode == Mode.OVERWORLD else LEVEL_SPRITES
	for name in sprites:
		var n := get_node_or_null(name) as AnimatedSprite2D
		if n == null:
			continue
		var h := _frame_height(n)
		if h > 0.0:
			n.offset.y = -(h * 0.5 - foot_y)
```

- [ ] **Step 5: Make `_sync_visual()` mode-aware**

Find `_sync_visual()` (around line 168). It currently iterates `PLAYER_SPRITES` and uses `_current_anim(...)` + `_facing`. Replace it with a mode-aware dispatcher:

```gdscript
func _sync_visual() -> void:
	if _mode == Mode.OVERWORLD:
		_sync_visual_overworld()
		return
	_sync_visual_level()
```

Move the existing body into a new `_sync_visual_level()` (rename only — body byte-identical except the iterated const is now `LEVEL_SPRITES`):

```gdscript
func _sync_visual_level() -> void:
	var anim := _current_anim(is_on_floor(), absf(velocity.x) > 1.0, _pogo, _shoot_timer > 0.0, _windup > 0.0)
	for name in LEVEL_SPRITES:
		var n := get_node_or_null(name) as AnimatedSprite2D
		if n == null:
			continue
		var show: bool = (name == anim)
		n.visible = show
		n.flip_h = _facing < 0
		if not show and n.is_playing():
			n.stop()
	if anim != _anim:
		_anim = anim
		var nn := get_node_or_null(anim) as AnimatedSprite2D
		if nn != null and nn.sprite_frames != null:
			nn.stop()
			nn.play()
```

(Use `nn` for the inner re-declaration to avoid shadowing the outer `n` cleanly.)

Add the new `_sync_visual_overworld()`:

```gdscript
func _sync_visual_overworld() -> void:
	var picked := _overworld_anim_name()
	var moving := velocity.length() > 1.0
	for name in OVERWORLD_SPRITES:
		var n := get_node_or_null(name) as AnimatedSprite2D
		if n == null:
			continue
		var show: bool = (name == picked)
		n.visible = show
		n.flip_h = false
		if not show and n.is_playing():
			n.stop()
	var picked_node := get_node_or_null(picked) as AnimatedSprite2D
	if picked_node == null or picked_node.sprite_frames == null:
		return
	if moving:
		if not picked_node.is_playing():
			picked_node.play()
	else:
		if picked_node.is_playing():
			picked_node.stop()
		picked_node.frame = 0
```

Add the helper above `_sync_visual_overworld`:

```gdscript
func _overworld_anim_name() -> String:
	match _overworld_dir:
		Direction.UP:
			return "OverworldUp"
		Direction.DOWN:
			return "OverworldDown"
		Direction.LEFT:
			return "OverworldLeft"
		Direction.RIGHT:
			return "OverworldRight"
	return "OverworldDown"
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all 6 new overworld-visual tests pass. All existing LEVEL tests still pass (`_sync_visual` dispatches to `_sync_visual_level` for LEVEL mode, body unchanged).

If any LEVEL test fails, the most likely cause is a typo in the renamed `_sync_visual_level` body — diff it against the original `_sync_visual` to confirm only the const name and the local var `n → nn` change.

- [ ] **Step 7: Commit**

```bash
git add src/runtime/player/player.gd tests/unit/test_player_overworld.gd
git commit -m "feat(player): overworld visual sync — 4 sprites, idle on frame 0, no flip"
```

---

## Task 5: LevelRuntime wires mode + suppresses HUD for overworld

**Files:**
- Modify: `src/runtime/level_runtime.gd:100-111` (`_spawn_player`) and `src/runtime/level_runtime.gd:113-128` (`_build_hud`).
- Test: `tests/unit/test_level_runtime.gd` — append spawn-mode test.
- Test: `tests/unit/test_hud.gd` — append overworld-suppression test.

- [ ] **Step 1: Append the failing tests**

Append to `tests/unit/test_level_runtime.gd`:

```gdscript
func test_build_sets_player_mode_for_overworld():
	GameManager.pending_level = null
	var ld := LevelData.new()
	ld.map_kind = LevelData.MapKind.OVERWORLD
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.player_spawn = Vector2i(0, 1)
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	assert_not_null(rt.player, "player spawned")
	assert_eq(rt.player._mode, Player.Mode.OVERWORLD, "player spawned in OVERWORLD mode on overworld map")


func test_build_keeps_player_mode_for_level():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level())
	assert_eq(rt.player._mode, Player.Mode.LEVEL, "player stays in LEVEL mode on level map")
```

Append to `tests/unit/test_hud.gd`:

```gdscript
func test_no_hud_on_overworld():
	GameManager.pending_level = null
	var ld := LevelData.new()
	ld.map_kind = LevelData.MapKind.OVERWORLD
	ld.width = 6
	ld.height = 4
	ld.tile_size = 16
	ld.fill_blank()
	ld.player_spawn = Vector2i(1, 1)
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	var hud := rt.find_child("HUD", true, false)
	assert_null(hud, "no HUD canvas layer on overworld")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_all.sh`
Expected: FAIL — overworld player spawns in LEVEL mode; HUD is created on every map.

- [ ] **Step 3: Wire mode set + HUD guard in LevelRuntime**

In `src/runtime/level_runtime.gd`, find `_spawn_player` (around line 100). It currently ends with:

```gdscript
	p.set_camera_bounds(world_bounds)
	_build_hud(p)
```

Add one line between them so the function becomes:

```gdscript
func _spawn_player(level: LevelData, ts: int) -> void:
	var p := preload("res://src/runtime/player/player.tscn").instantiate()
	p.position = _cell_center(level.player_spawn, ts)
	add_child(p)
	player = p
	var world_bounds := Rect2(
		Vector2.ZERO,
		Vector2(level.width * ts, level.height * ts) * RUNTIME_SCALE
	)
	p.set_camera_bounds(world_bounds)
	if level.map_kind == LevelData.MapKind.OVERWORLD:
		p.set_mode(Player.Mode.OVERWORLD)
	_build_hud(p)
```

(`set_mode` is called after `add_child` so `_ready` has already run; this matches the design — alignment re-runs inside `set_mode` for the overworld sprite set.)

Then find `_build_hud` (around line 113). Add an early return at the top:

```gdscript
func _build_hud(p: Node) -> void:
	if _level.map_kind == LevelData.MapKind.OVERWORLD:
		return  # No score/ammo/HP HUD on the overworld.
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	# ...rest unchanged...
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — both new tests pass. All existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add src/runtime/level_runtime.gd tests/unit/test_level_runtime.gd tests/unit/test_hud.gd
git commit -m "feat(runtime): overworld spawns player in OVERWORLD mode + suppresses HUD"
```

---

## Task 6: Full-suite verification + manual smoke check

**Files:** none modified.

- [ ] **Step 1: Run the full headless suite**

Run: `./tests/run_all.sh`
Expected: all tests pass. Specifically scan the summary for:
- `test_player.gd` — every LEVEL test still green (regression baseline).
- `test_player_overworld.gd` — every overworld test green.
- `test_level_runtime.gd` — both new mode tests green.
- `test_hud.gd` — overworld HUD suppression test green.
- `test_game_manager.gd` — `move_up`/`move_down` action test green.

If anything fails, do not commit a fix as part of this task — go back to the relevant task above and address the root cause.

- [ ] **Step 2: Import the project to refresh the .tscn cache**

Run: `make import`
Expected: exits cleanly with no errors about the player scene or its animations.

- [ ] **Step 3: Manual smoke (optional but recommended)**

Run: `make edit`, open the keen1 overworld map (`assets/levels/keen1/overworld.tres`), press Test ▶. Confirm:
- Keen appears facing down on spawn.
- WASD moves him in 4 directions; facing matches movement.
- Releasing all keys stops the walk anim on frame 0 of the last-faced direction.
- No score/ammo/HP HUD in the corner.
- Walking into a wall stops him; walking into a `level_entrance` and pressing Up (interact) still triggers entry.
- Jump/Space, P (pogo), X (shoot) do nothing.

- [ ] **Step 4: No commit (verification only)**

This task produces no changes. If everything passed, the feature is done.

---

## Self-Review Notes

- **Spec coverage:** every goal row in spec §1 maps to at least one task: G1 (mode flag) → T2; G2 (4-dir physics, no jump/pogo/shoot) → T3; G3 (4 sprites, idle frame 0) → T4; G4 (HUD suppressed) → T5; G5 (LEVEL unchanged) → T3 + T4 keep LEVEL paths intact, T6 verifies regression.
- **Placeholder scan:** no TBDs, no "add error handling" vagueness. Every code step shows the full code.
- **Type/name consistency:** `Mode`/`Direction` enums introduced in T2 and referenced consistently as `Player.Mode.OVERWORLD` / `Player.Direction.UP|DOWN|LEFT|RIGHT` in T3, T4, T5. `_overworld_dir` named identically across tasks. `_overworld_anim_name()` defined in T4 and used only in T4. `overworld_speed` export introduced in T3 and read in T3/T4 tests. `LEVEL_SPRITES`/`OVERWORLD_SPRITES` const names stable from T4 onward.
- **Out-of-scope items from spec §1.1 (collision box shrink, overworld_speed tuning, forced-walk 2D cutscene variant) are deliberately not implemented** — they are listed as open questions in the spec and excluded by design.
