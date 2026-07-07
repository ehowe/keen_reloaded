# Overworld Player Behavior — Design Spec

**Date:** 2026-07-07
**Status:** Draft
**Parent spec:** `docs/superpowers/specs/2026-07-05-map-kind-overworld-loop-design.md`
**Engine:** Godot 4.7 (stable), GDScript

## 1. Overview

The overworld loop shipped (Plan: map-kind-overworld-loop) but the Player still uses platformer physics everywhere — gravity, jump, pogo, shoot are all live on the overworld map. Four overworld-direction AnimatedSprite2D nodes (`OverworldUp`, `OverworldDown`, `OverworldLeft`, `OverworldRight`) were authored into `player.tscn` but nothing drives them.

This spec defines the behavioral and visual divergence: in OVERWORLD mode Keen is a top-down 4-directional walker. No gravity, no jump, no pogo, no shoot. The HUD is hidden. The four new sprites become the only visible ones, picked by last-faced direction, idle = static frame 0.

### Goals

| # | Goal |
|---|------|
| 1 | Player knows whether it is in LEVEL or OVERWORLD mode. |
| 2 | OVERWORLD movement is 4-directional (up/down/left/right), no gravity, no jump/pogo/shoot. |
| 3 | OVERWORLD plays the four directional sprites; idle shows static frame 0 of last-faced direction. |
| 4 | HUD is suppressed in OVERWORLD. |
| 5 | LEVEL behavior is unchanged. |

### Out of Scope

- Tuning overworld movement speed (a separate `@export` knob is added but the value is a starting default, not a tuned number).
- Shrinking the collision box to match the 64×64 overworld sprite. Current 48×96 box is reused as-is.
- New overworld mechanics (facing-aware interaction UX, etc.). The existing `LevelEntrance` proximity + `interact` action path is unchanged.
- Save/persistence (still Plan 6).

## 2. Approach

**Decision: a `Mode` enum on `Player`, set by `LevelRuntime` at spawn time.** Single Player scene, single Player script. `_physics_process` and `_sync_visual` branch on `_mode`.

Alternatives considered and rejected:

- **Two Player scenes (`player.tscn` + `player_overworld.tscn`):** Duplicates the scene tree and script. Easy drift between the two. No payoff: the divergence fits inside one script with two small branches.
- **Player reads `GameManager.state`:** Couples Player to GameManager and breaks in `State.TEST` (the editor's Test ▶ on an overworld map runs in TEST state, not OVERWORLD). Mode should be set explicitly by the spawner, not inferred from a global singleton.

### Why this works

The Player script already centralizes physics (`_physics_process`) and visual sync (`_sync_visual`). Adding one mode flag and one early-return branch keeps the divergence localized and testable. `LevelRuntime` is the natural place to set the flag because that is where `level.map_kind` is already known and where the player is instantiated.

## 3. Player Changes (`src/runtime/player/player.gd`)

### 3.1 Mode enum + state

```gdscript
enum Mode { LEVEL, OVERWORLD }
enum Direction { UP, DOWN, LEFT, RIGHT }

var _mode: int = Mode.LEVEL
var _overworld_dir: int = Direction.DOWN  # default facing on overworld entry

func set_mode(m: int) -> void:
    _mode = m
    _align_sprite_feet()
```

### 3.2 Sprite lists

The const `PLAYER_SPRITES` is replaced by two mode-specific lists:

```gdscript
const LEVEL_SPRITES := ["Idle", "Walking", "Jumping", "Shooting", "Pogo"]
const OVERWORLD_SPRITES := ["OverworldUp", "OverworldDown", "OverworldLeft", "OverworldRight"]
```

`_align_sprite_feet()` and `_sync_visual()` consult whichever list is active for `_mode`.

### 3.3 Physics

```gdscript
func _physics_process(delta: float) -> void:
    if _mode == Mode.OVERWORLD:
        _physics_overworld(delta)
        return
    # ...existing LEVEL physics unchanged...
```

New `_physics_overworld(delta)`:

- No gravity. No `velocity.y` accumulation. No max-fall clamp.
- Read input via `Input.get_vector("move_left", "move_right", "move_up", "move_down")`.
- `velocity = input_vec * overworld_speed`.
- When `input_vec != Vector2.ZERO`, update `_overworld_dir` to the dominant axis:
  - `|x| >= |y|`: RIGHT if `x > 0`, LEFT if `x < 0`.
  - else: DOWN if `y > 0`, UP if `y < 0`.
- Respect `_input_locked` / `_forced_dir`: when locked, `_forced_dir` is treated as a 2D vector (existing callers pass `-1/0/1` on x; overworld extension is a follow-up if a cutscene ever needs it — not wired here).
- `move_and_slide()` against tile collision (walls still block).
- Call `_sync_visual()` at the end, same as LEVEL.

New export knob:

```gdscript
@export var overworld_speed: float = 320.0
```

LEVEL's `run_speed` (480) is unchanged.

### 3.4 Visual sync

`_sync_visual()` gains an OVERWORLD branch:

- Active sprite list = `OVERWORLD_SPRITES`.
- Compute `moving := velocity.length() > 1.0`.
- Pick the sprite name from `_overworld_dir` via a helper:
  ```gdscript
  func _overworld_anim_name() -> String:
      match _overworld_dir:
          Direction.UP:    return "OverworldUp"
          Direction.DOWN:  return "OverworldDown"
          Direction.LEFT:  return "OverworldLeft"
          Direction.RIGHT: return "OverworldRight"
      return "OverworldDown"  # unreachable
  ```
- For each sprite in `OVERWORLD_SPRITES`:
  - `visible = (name == picked)`.
  - `flip_h = false` (each direction has its own sprite).
  - If not picked and `is_playing()`, `stop()`.
- For the picked sprite:
  - If `moving`: `play()` if not already playing (same re-trigger guard as LEVEL — only restart on transition).
  - If not moving: `stop()`, set `frame = 0`, `frame_progress = 0.0`.

LEVEL branch of `_sync_visual` and the `_current_anim()` helper are unchanged.

### 3.5 Sprite alignment

`_align_sprite_feet()` already reads each sprite's frame height dynamically (handles 64-tall overworld vs 96-tall level sprites correctly). It is re-run from `set_mode()` so the right set of sprites is aligned for the active mode.

### 3.6 What is NOT changed in Player

- All public API: `lock_input`, `set_camera_bounds`, `add_score`, `add_ammo`, `take_damage`, `shoot`, signals — unchanged.
- `_facing` (still used by LEVEL branch).
- `_jump_anim_duration`, projectile code, etc.
- `shoot()` remains callable but is never invoked in OVERWORLD (the `shoot` input is not polled in `_physics_overworld`).

## 4. LevelRuntime Changes (`src/runtime/level_runtime.gd`)

### 4.1 Mode set on spawn

`_spawn_player(level, ts)` adds one call after the player is added to the tree:

```gdscript
if level.map_kind == LevelData.MapKind.OVERWORLD:
    p.set_mode(Player.Mode.OVERWORLD)
```

(Default mode is LEVEL, so the LEVEL path needs no explicit call.)

### 4.2 HUD suppressed in OVERWORLD

`_build_hud(p)` becomes:

```gdscript
func _build_hud(p: Node) -> void:
    if _level.map_kind == LevelData.MapKind.OVERWORLD:
        return  # No score/ammo/HP HUD on the overworld.
    # ...existing HUD build unchanged...
```

HUD is fully suppressed (no CanvasLayer, no signal connections) on the overworld.

## 5. Edge Cases & Compatibility

- **Test ▶ on overworld map:** `LevelRuntime` still sees `level.map_kind == OVERWORLD`, so player gets OVERWORLD mode and HUD is hidden — consistent with a real playthrough.
- **Collision box size:** unchanged (48×96). The overworld sprite is 64×64, so Keen's collision footprint is taller than his art. Functional, just visually loose at the top of the head. Tuning deferred.
- **`LevelEntrance` interaction:** unchanged. Entrances emit `enter_requested` via their own proximity + `interact` polling; Player code is not involved.
- **`take_damage` from an overworld entity:** API still works, but no overworld entities call it today. If a future overworld hazard is added, HP changes silently (no HUD to show it). Out of scope.
- **`_forced_dir` in overworld:** existing `lock_input` callers pass x-axis only. If an overworld cutscene ever needs forced walking, the API will need a 2D variant. Not wired now.

## 6. Testing (GUT, headless)

| Area | Tests |
|------|-------|
| `Player.set_mode` | Default mode is LEVEL; `set_mode(OVERWORLD)` flips it; feet re-aligned. |
| Overworld physics | No gravity applied in OVERWORLD; velocity tracks input vector × `overworld_speed`; `_overworld_dir` updates on dominant axis; walls still block via `move_and_slide`. |
| Overworld anim | Moving → picked direction sprite plays; stopped → picked sprite stopped on frame 0; direction persists across stop; `flip_h` always false. |
| Level regression | LEVEL path unchanged: gravity, jump wind-up, pogo, shoot, coyote/buffer, `_current_anim`, `_facing` flip. |
| LevelRuntime | `_spawn_player` sets OVERWORLD mode when `map_kind == OVERWORLD`; `_build_hud` returns early for OVERWORLD (no HUD child added). |

Run via `./tests/run_all.sh` — must pass before commit.

## 7. Open Questions (non-blocking)

- **`overworld_speed` value:** 320 px/s is a placeholder. Tune after manual playtest.
- **Collision box shrink:** Should the overworld collision footprint shrink to match the 64×64 sprite? Deferred.
- **Forced-walk API for overworld cutscenes:** Not needed today; revisit when a cutscene lands.

## 8. Implementation Phasing

Each phase lands independently and is testable.

1. **Player mode + overworld physics** — `Mode`/`Direction` enums, `set_mode`, `_physics_overworld`, `overworld_speed`. Level path unchanged. Unit tests for overworld physics + level regression.
2. **Overworld visual sync** — `OVERWORLD_SPRITES`, `_overworld_anim_name`, idle-on-frame-0, alignment re-run from `set_mode`. Unit tests for anim pick + idle.
3. **LevelRuntime wiring** — `_spawn_player` calls `set_mode(OVERWORLD)`; `_build_hud` skips OVERWORLD. Integration test for spawn-time mode + HUD absence.
