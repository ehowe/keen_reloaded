# Keen Death Sequence — Design Spec

**Date:** 2026-07-07
**Status:** Draft
**Engine:** Godot 4.7 (stable)
**Language:** GDScript

## 1. Overview

When Keen's health reaches 0, play a death animation, launch him out of the
level on a straight up-left vector at ~60°, and return to the overworld (or
appropriate fallback). All death sources — enemy contact, hazards, the clapper,
projectiles, and lethal pit falls — route through one path so the death sequence
is identical regardless of cause.

## 2. Goals

- Health hitting 0 triggers a single, consistent death sequence.
- Death sprite plays (loops) during flight; all other sprites hidden.
- Keen launches up-left at a 60° angle, constant velocity, **no gravity**,
  passing through geometry so he cleanly exits the level.
- Scene transitions the moment Keen leaves the visible camera viewport.
- Return destination mirrors level-completion logic but does **not** mark the
  level complete.
- Lethal pit falls trigger the same death animation (no special-casing).

## 3. Non-Goals

- Lives counter / extra-life system.
- Death message overlay or score tally on death.
- Sound effects (wired later in Plan 6 polish).
- Overworld death (overworld is non-lethal; player is in OVERWORLD mode).

## 4. Existing Assets & State

| Asset / Symbol | Location | Status |
|----------------|----------|--------|
| `Keen Death.png` (132×64 = 2 frames × 64px) | `assets/sprites/` | Imported, UID assigned |
| `Death` AnimatedSprite2D node | `player.tscn` (child of Player) | Present, wired to `SpriteFrames_o820e`, `visible=false` |
| `signal died` | `player.gd:17` | Emitted at `health<=0`, **no listeners** |
| `take_damage(amount)` | `player.gd:215` | Reduces health, emits `health_changed`, emits `died` at 0 |
| `GameManager.complete_level()` | `game_manager.gd:82` | Returns to overworld AND marks complete |
| Kill zone | `level_runtime.gd:249` | `take_damage(1)` then respawn — fights death |

The `Death` node and its frames already exist in the scene; the `LEVEL_SPRITES`
/ `OVERWORLD_SPRITES` constants do not list it, and `_sync_visual()` never
shows it. This spec activates existing plumbing rather than adding art.

## 5. Design

### 5.1 Player death state

Add an idempotent `_dead: bool` to `Player`. Death is entered exactly once via a
private `_die()` method; all later `take_damage` calls are ignored.

```gdscript
const DEATH_LAUNCH_ANGLE_DEG := 60.0

@export var death_launch_speed: float = 800.0

var _dead: bool = false


func take_damage(amount: int) -> void:
    if _dead:
        return
    health -= amount
    health_changed.emit(health)
    if health <= 0:
        _die()


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

### 5.2 Player physics while dead

In `_physics_process`, branch on `_dead` **before** applying gravity so the
launch vector stays constant (no gravity arc):

```gdscript
func _physics_process(delta: float) -> void:
    if _mode == Mode.OVERWORLD:
        _physics_overworld(delta)
        return
    if _dead:
        move_and_slide()
        _sync_visual()
        return
    # ...existing gravity/input/pogo/shoot logic unchanged...
```

No gravity, no input, no bounce impulse, no wind-up — just the constant launch
velocity. `move_and_slide()` still runs but, with the collision shape disabled,
Keen passes through all geometry.

### 5.3 Player visual sync while dead

Add a death branch to `_sync_visual()` that hides every level + overworld sprite
and shows the `Death` node, playing it (looping — the SpriteFrames resource is
already `loop=1`):

```gdscript
func _sync_visual() -> void:
    if _dead:
        _sync_visual_death()
        return
    if _mode == Mode.OVERWORLD:
        _sync_visual_overworld()
        return
    _sync_visual_level()


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

The `Death` node is **not** added to `LEVEL_SPRITES` or `OVERWORLD_SPRITES`, so
the existing `_hide_sprites()` calls in the level/overworld syncs leave it
hidden during normal play.

### 5.4 LevelRuntime: wiring + off-screen detection

`LevelRuntime` connects `Player.died` in `_spawn_player` and polls the player's
position each frame in `_process`:

```gdscript
var _dying: bool = false

# in _spawn_player, after the player is created/configured:
if p.has_signal("died"):
    p.died.connect(_on_player_died)


func _on_player_died() -> void:
    _dying = true


func _process(delta: float) -> void:
    if not _completed:
        elapsed += delta
    if _dying and not _completed and is_instance_valid(player):
        if _player_offscreen():
            _complete_death()


func _player_offscreen() -> bool:
    var cam := player.get_node_or_null("Camera2D") as Camera2D
    var vp := get_viewport_rect()
    var center := cam.get_screen_center_position() if cam != null else player.global_position
    var visible_rect := Rect2(center - vp.size * 0.5, vp.size)
    return not visible_rect.has_point(player.global_position)


func _complete_death() -> void:
    _dying = false
    _completed = true  # guard: exactly one transition, also halts elapsed timer
    if GameManager != null and GameManager.return_scene != null:
        get_tree().change_scene_to_packed(GameManager.return_scene)
    elif GameManager != null and GameManager.current_overworld != null:
        GameManager.fail_level()
    else:
        get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")
```

`Camera2D`'s limits are already set to world bounds via `set_camera_bounds()` in
`_spawn_player`. As Keen flies up-left, the camera clamps at the top-left limit;
Keen keeps moving and exits the viewport — at which point the off-screen check
fires and the scene transitions.

### 5.5 GameManager: non-completing return

Add `fail_level()` / `fail_level_no_scene_swap()`, mirroring the completion
helpers but **without** `mark_completed()`:

```gdscript
func fail_level() -> void:
    fail_level_no_scene_swap()
    get_tree().change_scene_to_packed(RUNTIME_SCENE)


func fail_level_no_scene_swap() -> void:
    pending_level = current_overworld
    pending_player_spawn = last_entrance_pos
    current_level = null
    state = State.OVERWORLD
```

Keen re-spawns at `last_entrance_pos` on the overworld (the door he entered
from), health resets to its default (3) because the runtime re-instantiates a
fresh Player, and the level is **not** added to `completed_levels` (gates stay
locked).

### 5.6 Kill zone: route lethal falls through `_die()`

The bottom kill zone (`_on_kill_zone_body_entered`) currently damages then
unconditionally respawns + zeroes velocity, which would clobber the launch. Fix
the ordering and guard the respawn:

```gdscript
func _on_kill_zone_body_entered(body: Node2D) -> void:
    if body != player or not is_instance_valid(player):
        return
    if player.has_method("take_damage"):
        player.take_damage(1)
    # Respawn ONLY if still alive. A lethal fall triggers _die() inside
    # take_damage — which owns the launch velocity and must not be overwritten.
    if is_instance_valid(player) and int(player.get("health")) > 0:
        player.position = _cell_center(_level.player_spawn, _tile_size)
        player.velocity = Vector2.ZERO
```

One rule: `take_damage` → `_die()` is the sole authority on death. The kill
zone only handles the non-lethal case.

## 6. Files Changed

| File | Change |
|------|--------|
| `src/runtime/player/player.gd` | `_dead` flag, `_die()`, `death_launch_speed` export, death branch in `_physics_process` + `_sync_visual`, guard in `take_damage`, `_sync_visual_death()` |
| `src/runtime/level_runtime.gd` | connect `died` in `_spawn_player`, `_dying` flag, off-screen poll + `_complete_death()` in `_process`, kill-zone respawn guard |
| `src/core/game_manager.gd` | add `fail_level()` + `fail_level_no_scene_swap()` |
| `src/runtime/player/player.tscn` | none — `Death` node already wired |
| `tests/unit/test_player.gd` | death state, launch vector, idempotent `take_damage`, sprite shown |
| `tests/unit/test_game_manager_loop.gd` | `fail_level_no_scene_swap` returns to overworld without marking complete |
| `tests/unit/test_level_runtime.gd` | `_on_kill_zone_body_entered` lethal vs non-lethal fall |

## 7. Testing Strategy

GUT unit tests, run headless via `./tests/run_all.sh`:

1. **`Player.take_damage` lethal → DEAD state**: health to 0 sets `_dead`,
   emits `died` exactly once, sets velocity to the 60° up-left launch vector.
2. **`Player.take_damage` after death is a no-op**: `_dead` player ignores
   further damage; `health` and `died` count unchanged.
3. **`Player` visual sync**: when `_dead`, `Death` sprite `visible` and playing,
   every level + overworld sprite hidden.
4. **`GameManager.fail_level_no_scene_swap`**: sets `pending_level` to
   `current_overworld`, `pending_player_spawn` to `last_entrance_pos`,
   `state=OVERWORLD`, does **not** append to `completed_levels`.
5. **`LevelRuntime` kill zone lethal fall**: when the player's health is 1 and
   the kill zone fires, `take_damage` is called and the player is **not**
   teleported/zeroed (death owns the launch). When health > 1, the player is
   teleported to spawn and velocity zeroed as before.

Off-screen transition (step in 5.4) is verified manually via the editor's
Test ▶ since it depends on a live viewport/camera; the seam
(`fail_level_no_scene_swap`) is unit-tested.

## 8. Open Questions

None — all ambiguities resolved in brainstorming:
- Flight model: straight line, no gravity.
- Transition trigger: off-screen (camera viewport rect).
- Death anim playback: loop during flight (SpriteFrames already `loop=1`).
