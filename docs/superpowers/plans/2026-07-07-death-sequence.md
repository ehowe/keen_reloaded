# Keen Death Sequence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When Keen's health hits 0, switch to the (already-wired) `Death` sprite, launch him off-screen on a constant up-left vector at 60°, and return to the overworld (or fallback) without marking the level complete.

**Architecture:** A single `_dead` flag on `Player` + a private `_die()` method owns the entire death state (input lock, collision disable, launch velocity, sprite switch). All damage sources already funnel through `Player.take_damage()`, so lethal hits — enemy contact, hazards, the clapper, projectiles, and lethal pit falls — route through one path. `LevelRuntime` listens to the existing `Player.died` signal, polls the player's position each frame, and triggers a scene transition once Keen leaves the camera viewport. `GameManager.fail_level()` mirrors `complete_level()` minus `mark_completed`.

**Tech Stack:** Godot 4.7, GDScript, GUT (Godot Unit Test), CharacterBody2D physics.

**Spec:** `docs/superpowers/specs/2026-07-07-death-sequence-design.md`

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `src/runtime/player/player.gd` | Player avatar (movement, modes, damage) | Add `_dead`, `_die()`, `death_launch_speed`, death branches in `_physics_process`/`_sync_visual`, guard in `take_damage`, align `Death` sprite feet |
| `src/runtime/level_runtime.gd` | Builds scene from `LevelData`, owns runtime glue | Connect `died`, `_dying` flag, off-screen poll + `_complete_death`, fix kill-zone respawn guard |
| `src/core/game_manager.gd` | Top-level game-state autoload | Add `fail_level()` + `fail_level_no_scene_swap()` |
| `tests/unit/test_player.gd` | Player unit tests | Add death-state, launch-vector, idempotency, visual-sync tests |
| `tests/unit/test_game_manager_loop.gd` | GameManager loop tests | Add `fail_level_no_scene_swap` test |
| `tests/unit/test_level_runtime.gd` | LevelRuntime tests | Add kill-zone lethal/non-lethal + `died`-wiring tests |

`player.tscn` needs **no** changes — the `Death` AnimatedSprite2D node (child of Player) is already wired to `Keen Death.png` with `loop=1`, `visible=false`.

## Commands

- **Run a single test class (fast iteration):**
  ```bash
  GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
  "$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
    -gdir=res://tests/unit -gselect=<TestClassName> -gexit -gdisable_colors
  ```
- **Run the full suite (before each commit):** `./tests/run_all.sh`

---

### Task 1: Player death flag + idempotent take_damage

**Files:**
- Modify: `src/runtime/player/player.gd` (the `take_damage` method, ~line 215; add `_dead` var near the other state vars ~line 53)
- Test: `tests/unit/test_player.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_player.gd`:

```gdscript
func test_take_damage_lethal_sets_dead():
	var p := Player.new()
	add_child(p)
	var died_count := 0
	p.died.connect(func() -> void: died_count += 1)
	p.take_damage(p.health)
	assert_true(p._dead, "health to 0 sets _dead")
	assert_eq(died_count, 1, "died emitted exactly once")


func test_take_damage_after_dead_is_noop():
	var p := Player.new()
	add_child(p)
	p._dead = true
	p.health = 5
	var died_count := 0
	p.died.connect(func() -> void: died_count += 1)
	p.take_damage(3)
	assert_eq(p.health, 5, "health unchanged once dead")
	assert_eq(died_count, 0, "no further died emit once dead")
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=TestPlayer -gexit -gdisable_colors
```
Expected: FAIL — `_dead` property does not exist on `Player`.

- [ ] **Step 3: Add the `_dead` var**

In `src/runtime/player/player.gd`, in the state-var block (right after `var _bounce_vx: float = 0.0`, ~line 58), add:

```gdscript
var _dead: bool = false
```

- [ ] **Step 4: Rewrite `take_damage` to guard + route to `_die()`**

Replace the existing `take_damage` method (lines 215-219):

```gdscript
func take_damage(amount: int) -> void:
	if _dead:
		return
	health -= amount
	health_changed.emit(health)
	if health <= 0:
		_die()
```

- [ ] **Step 5: Add a minimal `_die()` stub** (full body comes in Task 2)

Insert immediately after `take_damage`:

```gdscript
func _die() -> void:
	if _dead:
		return
	_dead = true
	_input_locked = true
	died.emit()
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=TestPlayer -gexit -gdisable_colors
```
Expected: PASS (both new tests + all existing).

- [ ] **Step 7: Run full suite**

```bash
./tests/run_all.sh
```
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add src/runtime/player/player.gd tests/unit/test_player.gd
git commit -m "feat(player): _dead flag + idempotent take_damage routes to _die()"
```

---

### Task 2: Death launch velocity + collision disable

**Files:**
- Modify: `src/runtime/player/player.gd` (flesh out `_die()`; add `DEATH_LAUNCH_ANGLE_DEG` const + `death_launch_speed` export)
- Test: `tests/unit/test_player.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_player.gd`:

```gdscript
func test_die_sets_upleft_launch_vector():
	var p := _new_player()
	var speed := p.death_launch_speed
	p.take_damage(p.health)
	var rad := deg_to_rad(60.0)
	var expected := Vector2(-cos(rad), -sin(rad)) * speed
	assert_almost_eq(p.velocity.x, expected.x, 0.1, "vx = -speed*cos60")
	assert_almost_eq(p.velocity.y, expected.y, 0.1, "vy = -speed*sin60")


func test_die_disables_collision_shape():
	var p := _new_player()
	var col := p.get_node("CollisionShape2D") as CollisionShape2D
	assert_false(col.disabled, "collision enabled before death")
	p.take_damage(p.health)
	assert_true(col.disabled, "collision disabled on death so Keen flies through walls")


func test_death_launch_speed_default_is_800():
	var p := Player.new()
	assert_eq(p.death_launch_speed, 800.0, "tunable default")
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=TestPlayer -gexit -gdisable_colors
```
Expected: FAIL — `death_launch_speed` property does not exist.

- [ ] **Step 3: Add the const + export**

In `src/runtime/player/player.gd`, next to the other `const` block (after `const SHOOT_POSE_TIME`, ~line 22), add:

```gdscript
const DEATH_LAUNCH_ANGLE_DEG := 60.0
```

And in the `@export` tuning block (after `@export var bounce_decay`, ~line 38), add:

```gdscript
@export var death_launch_speed: float = 800.0
```

- [ ] **Step 4: Replace the `_die()` stub with the full body**

Replace the stub added in Task 1:

```gdscript
func _die() -> void:
	if _dead:
		return
	_dead = true
	_input_locked = true
	# Disable collision so Keen passes through walls and exits the level cleanly.
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null:
		col.disabled = true
	var rad := deg_to_rad(DEATH_LAUNCH_ANGLE_DEG)
	velocity = Vector2(-cos(rad), -sin(rad)) * death_launch_speed
	died.emit()
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=TestPlayer -gexit -gdisable_colors
```
Expected: PASS (all three new tests + existing).

- [ ] **Step 6: Run full suite + commit**

```bash
./tests/run_all.sh
git add src/runtime/player/player.gd tests/unit/test_player.gd
git commit -m "feat(player): death launches Keen up-left at 60 deg, collision off"
```

---

### Task 3: Death visual sync + sprite alignment

**Files:**
- Modify: `src/runtime/player/player.gd` (`_sync_visual` dispatch, new `_sync_visual_death`, extend `_align_sprite_feet` to align `Death`)
- Test: `tests/unit/test_player.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_player.gd`:

```gdscript
func test_dead_shows_death_sprite_and_hides_all_others():
	var p := _new_player()
	p._die()
	var death := p.get_node_or_null("Death") as AnimatedSprite2D
	assert_not_null(death, "Death node exists")
	assert_true(death.visible, "Death sprite visible when dead")
	assert_true(death.is_playing(), "Death sprite playing")
	for name in Player.LEVEL_SPRITES + Player.OVERWORLD_SPRITES:
		var n := p.get_node_or_null(name) as AnimatedSprite2D
		if n == null:
			continue
		assert_false(n.visible, "%s hidden when dead" % name)


func test_death_sprite_feet_aligned_to_collision():
	var p := _new_player()
	var death := p.get_node("Death") as AnimatedSprite2D
	# Death frame is 64px tall, collision is 96px tall.
	# offset.y = -(64*0.5 - 96*0.5) = -(-16) = 16
	assert_almost_eq(death.offset.y, 16.0, 0.01, "Death feet rest on collision bottom")
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=TestPlayer -gexit -gdisable_colors
```
Expected: FAIL — `Death` sprite stays hidden; offset unaligned.

- [ ] **Step 3: Add the death branch to `_sync_visual`**

In `src/runtime/player/player.gd`, replace the existing `_sync_visual` (lines 222-226):

```gdscript
func _sync_visual() -> void:
	if _dead:
		_sync_visual_death()
		return
	if _mode == Mode.OVERWORLD:
		_sync_visual_overworld()
		return
	_sync_visual_level()
```

- [ ] **Step 4: Add `_sync_visual_death`**

Insert immediately after `_sync_visual`:

```gdscript
func _sync_visual_death() -> void:
	_hide_sprites(LEVEL_SPRITES)
	_hide_sprites(OVERWORLD_SPRITES)
	var d := get_node_or_null("Death") as AnimatedSprite2D
	if d == null:
		return
	d.visible = true
	if not d.is_playing():
		d.play()
```

- [ ] **Step 5: Extend `_align_sprite_feet` to align the `Death` sprite**

Replace the existing `_align_sprite_feet` (lines 322-334):

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
	# Death sprite is mode-independent — align it too so feet rest on the
	# collision bottom regardless of which sprite set is active.
	var death := get_node_or_null("Death") as AnimatedSprite2D
	if death != null:
		var dh := _frame_height(death)
		if dh > 0.0:
			death.offset.y = -(dh * 0.5 - foot_y)
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=TestPlayer -gexit -gdisable_colors
```
Expected: PASS (both new tests + existing).

- [ ] **Step 7: Run full suite + commit**

```bash
./tests/run_all.sh
git add src/runtime/player/player.gd tests/unit/test_player.gd
git commit -m "feat(player): death visual sync shows Death sprite, feet aligned"
```

---

### Task 4: Player physics branch when dead (constant velocity, no gravity)

**Files:**
- Modify: `src/runtime/player/player.gd` (`_physics_process` early-return when dead)
- Test: `tests/unit/test_player.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_player.gd`:

```gdscript
func test_dead_physics_keeps_velocity_constant_no_gravity():
	var p := _new_player()
	p.take_damage(p.health)  # triggers _die(), sets launch velocity
	var v_before := p.velocity
	# Simulate several frames. No floor in the test scene, so if gravity were
	# applied, velocity.y would rise (fall). It must stay exactly constant.
	for i in 5:
		p._physics_process(0.016)
	assert_almost_eq(p.velocity.x, v_before.x, 0.001, "vx unchanged (no input/friction)")
	assert_almost_eq(p.velocity.y, v_before.y, 0.001, "vy unchanged (no gravity applied)")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=TestPlayer -gexit -gdisable_colors
```
Expected: FAIL — `velocity.y` increases because gravity is applied.

- [ ] **Step 3: Add the dead early-return to `_physics_process`**

In `src/runtime/player/player.gd`, replace the top of `_physics_process` (lines 83-86):

```gdscript
func _physics_process(delta: float) -> void:
	if _mode == Mode.OVERWORLD:
		_physics_overworld(delta)
		return
	if _dead:
		move_and_slide()
		_sync_visual()
		return
	velocity.y += gravity * delta
```

- [ ] **Step 4: Run test to verify it passes**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=TestPlayer -gexit -gdisable_colors
```
Expected: PASS.

- [ ] **Step 5: Run full suite + commit**

```bash
./tests/run_all.sh
git add src/runtime/player/player.gd tests/unit/test_player.gd
git commit -m "feat(player): dead physics holds launch velocity (no gravity)"
```

---

### Task 5: GameManager.fail_level (non-completing overworld return)

**Files:**
- Modify: `src/core/game_manager.gd` (add `fail_level` + `fail_level_no_scene_swap`, next to the complete_level helpers ~line 87)
- Test: `tests/unit/test_game_manager_loop.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_game_manager_loop.gd` (which already has `before_each` calling `GameManager.clear_progress()`):

```gdscript
func test_fail_level_returns_to_overworld_without_completing():
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
	GameManager.fail_level_no_scene_swap()
	assert_eq(GameManager.state, GameManager.State.OVERWORLD)
	assert_eq(GameManager.pending_level, ow)
	assert_eq(GameManager.pending_player_spawn, Vector2i(5, 6))
	assert_false(GameManager.is_level_completed("keen1_01"), "death must NOT mark level complete")
	assert_null(GameManager.current_level, "current_level cleared")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=TestGameManagerLoop -gexit -gdisable_colors
```
Expected: FAIL — `fail_level_no_scene_swap` does not exist.

- [ ] **Step 3: Add `fail_level` helpers**

In `src/core/game_manager.gd`, insert immediately after `complete_level_no_scene_swap` (after line 93):

```gdscript

## Transition level -> overworld on death WITHOUT recording completion. Keen
## respawns at the entrance he walked in from, level stays uncompleted.
func fail_level() -> void:
	fail_level_no_scene_swap()
	get_tree().change_scene_to_packed(RUNTIME_SCENE)


func fail_level_no_scene_swap() -> void:
	pending_level = current_overworld
	pending_player_spawn = last_entrance_pos
	current_level = null
	state = State.OVERWORLD
```

- [ ] **Step 4: Run test to verify it passes**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=TestGameManagerLoop -gexit -gdisable_colors
```
Expected: PASS.

- [ ] **Step 5: Run full suite + commit**

```bash
./tests/run_all.sh
git add src/core/game_manager.gd tests/unit/test_game_manager_loop.gd
git commit -m "feat(core): GameManager.fail_level returns to overworld w/o completing"
```

---

### Task 6: Kill zone routes lethal falls through death (no respawn clobber)

**Files:**
- Modify: `src/runtime/level_runtime.gd` (`_on_kill_zone_body_entered`, ~line 249)
- Test: `tests/unit/test_level_runtime.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_level_runtime.gd`:

```gdscript
func test_kill_zone_lethal_fall_does_not_respawn():
	# Lethal fall: HP=1 -> take_damage kills -> _die() owns launch velocity.
	# The kill zone must NOT teleport/zero the player afterward.
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	var lvl := _level()
	rt.build(lvl)
	var p := rt.player
	p.health = 1
	var pos_before := p.position
	p.take_damage(1)  # would-be lethal even without kill zone
	rt._on_kill_zone_body_entered(p)
	assert_eq(p.position, pos_before, "lethal fall: position untouched by respawn")
	assert_true((p.velocity - Vector2(-cos(deg_to_rad(60.0)), -sin(deg_to_rad(60.0))) * p.death_launch_speed).length() < 0.2, "launch velocity preserved")
	assert_true(p._dead, "player is dead")


func test_kill_zone_nonlethal_fall_respawns():
	# Non-lethal fall: HP>1 -> take_damage(1) leaves HP>0 -> respawn at spawn.
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	var lvl := _level()
	rt.build(lvl)
	var p := rt.player
	p.health = 3
	rt._on_kill_zone_body_entered(p)
	assert_eq(p.health, 2, "non-lethal fall costs 1 HP")
	var ts := lvl.tile_size
	var expected_spawn := Vector2(lvl.player_spawn.x * ts + ts / 2.0, lvl.player_spawn.y * ts + ts / 2.0)
	assert_almost_eq(p.position.x, expected_spawn.x, 0.01, "respawned at spawn x")
	assert_almost_eq(p.position.y, expected_spawn.y, 0.01, "respawned at spawn y")
	assert_eq(p.velocity, Vector2.ZERO, "velocity zeroed on respawn")
	assert_false(p._dead, "player still alive")
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=TestLevelRuntime -gexit -gdisable_colors
```
Expected: FAIL — current code teleports+zeros before damaging, so lethal-fall position changes and velocity is zeroed.

- [ ] **Step 3: Rewrite `_on_kill_zone_body_entered`**

Replace the existing method (lines 249-256) in `src/runtime/level_runtime.gd`:

```gdscript
func _on_kill_zone_body_entered(body: Node2D) -> void:
	if body != player or not is_instance_valid(player):
		return
	# Damage first. A lethal fall triggers Player._die() inside take_damage,
	# which owns the launch velocity and must not be overwritten.
	if player.has_method("take_damage"):
		player.take_damage(1)
	# Respawn ONLY if still alive.
	if is_instance_valid(player) and int(player.get("health")) > 0:
		player.position = _cell_center(_level.player_spawn, _tile_size)
		player.velocity = Vector2.ZERO
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=TestLevelRuntime -gexit -gdisable_colors
```
Expected: PASS (both new tests + existing).

- [ ] **Step 5: Run full suite + commit**

```bash
./tests/run_all.sh
git add src/runtime/level_runtime.gd tests/unit/test_level_runtime.gd
git commit -m "fix(runtime): kill zone routes lethal falls through death, respawns only if alive"
```

---

### Task 7: LevelRuntime death wiring + off-screen transition

**Files:**
- Modify: `src/runtime/level_runtime.gd` (connect `died` in `_spawn_player`; add `_dying` var, off-screen poll in `_process`, `_player_offscreen`, `_complete_death`)
- Test: `tests/unit/test_level_runtime.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_level_runtime.gd`:

```gdscript
func test_player_died_signal_sets_dying_flag():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level())
	assert_false(rt._dying, "_dying false before death")
	rt.player.died.emit()
	assert_true(rt._dying, "_dying set when player.died emits")


func test_died_is_connected_after_build():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level())
	assert_true(rt.player.has_signal("died") and rt.player.died.is_connected(rt._on_player_died), "died -> _on_player_died wired")
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=TestLevelRuntime -gexit -gdisable_colors
```
Expected: FAIL — `_dying` property does not exist; signal not connected.

- [ ] **Step 3: Add the `_dying` var**

In `src/runtime/level_runtime.gd`, in the var block (after `var _completed: bool = false`, ~line 24), add:

```gdscript
var _dying: bool = false
```

- [ ] **Step 4: Connect `died` in `_spawn_player`**

In `src/runtime/level_runtime.gd`, at the end of `_spawn_player` (after the `set_mode` / `_build_hud` calls, ~line 112), add before the closing of the function:

```gdscript
	if player.has_signal("died"):
		player.died.connect(_on_player_died)
```

So the tail of `_spawn_player` reads:

```gdscript
	if level.map_kind == LevelData.MapKind.OVERWORLD:
		p.set_mode(Player.Mode.OVERWORLD)
	_build_hud(p)
	if p.has_signal("died"):
		p.died.connect(_on_player_died)
```

- [ ] **Step 5: Add `_on_player_died` + the off-screen poll in `_process` + helpers**

Replace the existing `_process` (lines 46-48):

```gdscript
func _process(delta: float) -> void:
	if not _completed:
		elapsed += delta
	if _dying and not _completed and is_instance_valid(player):
		if _player_offscreen():
			_complete_death()


func _on_player_died() -> void:
	_dying = true


## True when the player has left the visible camera viewport (camera is clamped
## to world bounds, so a flying corpse eventually exits the rendered rect).
func _player_offscreen() -> bool:
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	var vp := get_viewport_rect()
	var center := cam.get_screen_center_position() if cam != null else player.global_position
	var visible_rect := Rect2(center - vp.size * 0.5, vp.size)
	return not visible_rect.has_point(player.global_position)


func _complete_death() -> void:
	if _completed:
		return
	_dying = false
	_completed = true  # guard: exactly one transition, also halts elapsed timer
	if GameManager != null and GameManager.return_scene != null:
		# Test ▶ from the editor: return to the editor.
		get_tree().change_scene_to_packed(GameManager.return_scene)
	elif GameManager != null and GameManager.current_overworld != null:
		# Overworld loop: return to overworld WITHOUT marking the level complete.
		GameManager.fail_level()
	else:
		get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")
```

- [ ] **Step 6: Reset `_dying` in `_clear`**

In `_clear` (around line 195), add `_dying = false` next to the other resets. The reset block becomes:

```gdscript
func _clear() -> void:
	player = null
	entities_spawned.clear()
	layers.clear()
	_level = null
	_tile_size = 64
	_completed = false
	_dying = false
	elapsed = 0.0
	for c in get_children():
		c.queue_free()
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=TestLevelRuntime -gexit -gdisable_colors
```
Expected: PASS (both new tests + existing).

- [ ] **Step 8: Run full suite + commit**

```bash
./tests/run_all.sh
git add src/runtime/level_runtime.gd tests/unit/test_level_runtime.gd
git commit -m "feat(runtime): death flies player off-screen, transitions to overworld"
```

---

### Task 8: Manual verification + full-suite gate

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

```bash
./tests/run_all.sh
```
Expected: all tests pass, zero failures.

- [ ] **Step 2: Manual visual check via the editor's Test ▶**

```bash
make edit
```
In the editor:
1. Open a level with an enemy or hazard near spawn.
2. Press **Test ▶**.
3. Walk Keen into the enemy / hazard until health hits 0.
4. Verify: Keen switches to the Death sprite (looping), launches up-left at ~60°, passes through walls, and exits the viewport.
5. Verify: scene transitions back to the editor (because `return_scene` is set during Test ▶).

- [ ] **Step 3: Manual check — pit fall death**

In the editor:
1. Open a level with a bottom pit (or drop Keen off the bottom edge).
2. Set Keen's health to 1 via the inspector (or take 2 hits first).
3. Fall into the pit.
4. Verify: the **same** death animation + launch plays from where he fell (no teleport-to-spawn). Scene transitions as in Step 2.

- [ ] **Step 4: Manual check — overworld loop return (if an overworld is wired)**

If the episode has an overworld reachable from the main menu:
1. Start the episode, enter a level.
2. Die (health to 0).
3. Verify: Keen returns to the overworld at the entrance door he walked in from, level is **not** marked completed (the gate/door is still locked if it was locked before).

- [ ] **Step 5: Final commit (if any fixups were made)**

Only if Steps 2–4 surfaced a fix:
```bash
./tests/run_all.sh
git add -A
git commit -m "fix(runtime): death sequence polish from manual verification"
```

---

## Self-Review

**1. Spec coverage:**
- §5.1 Player death state (`_dead`, `_die`, take_damage guard) → Task 1 + Task 2 ✓
- §5.2 Player physics while dead → Task 4 ✓
- §5.3 Player visual sync while dead → Task 3 ✓
- §5.4 LevelRuntime wiring + off-screen → Task 7 ✓
- §5.5 GameManager fail_level → Task 5 ✓
- §5.6 Kill zone fix → Task 6 ✓
- §6 Files table matches tasks ✓
- §7 Testing strategy — every test in the spec maps to a task step ✓

**2. Placeholder scan:** none. Every code step shows full code; every command shows the exact invocation + expected result.

**3. Type/name consistency:** `_dead`, `_die()`, `_dying`, `_on_player_died`, `_player_offscreen`, `_complete_death`, `fail_level`, `fail_level_no_scene_swap`, `DEATH_LAUNCH_ANGLE_DEG`, `death_launch_speed` — used consistently across all tasks and tests. The `died` signal already exists on `Player` (player.gd:17) and is not redeclared. The `Death` AnimatedSprite2D node already exists in `player.tscn`.
