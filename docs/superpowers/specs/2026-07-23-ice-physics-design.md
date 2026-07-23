# Ice Physics — Design Spec

**Date:** 2026-07-23
**Status:** Draft
**Engine:** Godot 4.7 (stable)
**Language:** GDScript

## 1. Overview

Adds two distinct ice-surface types that modify Keen's ground movement,
matching the original Commander Keen games:

- **Type 1 (low-friction ice):** preserves momentum, walking animation
  continues, player can speed up / slow down / turn by holding movement keys.
  Zero friction while on the ice surface — Keen glides until he steers or hits
  a wall.
- **Type 2 (forced-slide ice):** Keen slides at maximum speed in his entry
  direction, switches to the idle animation, and cannot be steered with
  movement keys. The only action available is jumping (normal jump rules).

Both types share a **coast** behavior on exit: when Keen leaves ice onto normal
ground, his momentum bleeds off over a **fixed 1.5-tile distance**, the walking
animation plays, and he comes to rest at the center of the 2nd tile past the
ice edge.

This spec also introduces a **unified acceleration model** for normal ground
movement (the original games accelerate/decelerate; the current remake
instant-snaps). Ice becomes a parameter variation on that unified model rather
than a special case.

### Requirements

| # | Requirement |
|---|-------------|
| 1 | A tile can be marked as Ice Type 1 or Ice Type 2 via a TileSet custom-data layer named `surface_type`. Unmarked tiles behave as normal ground (no behavior change). |
| 2 | **Type 1:** while grounded on an ice tile, releasing input preserves horizontal velocity (zero friction); holding a direction accelerates toward `ice_max_speed_cap` at `ice_accel`; turning decelerates through zero then accelerates opposite. Walking animation plays while moving. |
| 3 | **Type 2:** on entry (first grounded frame on the tile with non-zero horizontal velocity), Keen is pinned to `entry_dir * ice2_slide_speed`; movement keys are ignored for horizontal motion; idle animation plays. The only available action is jumping (normal jump rules). |
| 4 | **Type 2 edges:** (a) hitting a wall zeroes horizontal velocity and leaves Keen stopped on the tile (jump only); (b) landing on a Type 2 tile with no horizontal velocity produces no slide — Keen stands and can only jump. |
| 5 | **Coast:** transitioning from any ice surface to normal ground (grounded, moving, not jumping) enters a coast state that decelerates Keen to a stop over exactly `Constants.TILE * 1.5` (96 px), regardless of entry speed. Walking animation plays. The guaranteed stop point holds for an uninterrupted coast. |
| 6 | **Coast input:** holding a direction during coast suspends the auto-decel and applies Type 1 steering (ice-rate accel); releasing input recomputes the decel from the current speed; jumping cancels the coast. |
| 7 | **Jump from ice:** all normal jump rules apply (coyote time, jump buffer, wind-up). Launch sets horizontal velocity per the existing jump model. Landing back on ice resumes that ice type's rules; landing on normal ground enters coast if moving. |
| 8 | **Entry cap (Type 1):** on entering an ice surface, `|velocity.x|` is capped to `ice_max_speed_cap` (configurable; default `run_speed`). |
| 9 | **Normal ground accel/decel:** ground movement now accelerates toward `run_speed` (`ground_accel`) and decelerates toward 0 (`ground_decel`) instead of instant-snapping. |
| 10 | The player reads the surface under its feet each grounded frame via the geometry `TileMapLayer`; missing/unknown custom data resolves to normal ground. |
| 11 | Pogo, enemies, projectiles, and overworld mode are unaffected by ice. |
| 12 | All existing GUT tests pass (with updates to player-movement tests that asserted instant-snap); new tests lock the ice/coast/accel math and the surface query. |

### Out of scope

- **Pogo on ice** — pogo uses its own physics and ignores the surface type
  (bounces are unaffected even off an ice tile).
- **Enemies / projectiles on ice** — no enemy or projectile reads or reacts to
  the surface type. (Future: some original-game enemies slide on ice.)
- **Overworld mode** — ice affects LEVEL mode only.
- **Per-tile metadata authoring tooling beyond the custom-data layer** — the
  TileSet editor's native custom-data authoring is the authoring path; no new
  level-editor paint mode is added (see §3 — Approach B was chosen over a
  sidecar surface array partly for this reason).
- **Reverse-engineered original-binary accel tables** — tuning values are
  `@export` defaults dialed in by feel, not extracted from the original.

## 2. Background — the gap this closes

Today the player's ground movement instant-snaps horizontal velocity to
`dir * run_speed` (`player.gd:170`):

```gdscript
elif on_floor:
    velocity.x = dir * run_speed * (_speed_scale if _input_locked else 1.0)
```

There is no friction or acceleration model on the ground (only air/pogo use
`move_toward`). The original Commander Keen games *do* accelerate and
decelerate on normal ground, and ship dedicated ice tiles with the two
behaviors above. There is also no per-tile metadata today
(`docs/future-work.md:20` flags custom-data layers as not-yet-done), so no
mechanism exists to mark a tile as ice. This spec fills both gaps: a unified
accel model and a surface-type system that selects ice behavior.

Two existing patterns make this low-risk:

- **Tile reading** — `projectile.is_solid_tile_at` (`projectile.gd:88`)
  already does `TileMapLayer.local_to_map` + `get_cell_tile_data` at a
  position. The surface query reuses this.
- **Forced-direction / input-lock** — the `_bounce_vx` impulse
  (`player.gd:78`) and `lock_input(dir, speed_scale)` (`player.gd:102`)
  already override horizontal input and force a direction. Type 2's forced
  slide is a close relative.

## 3. Approach

### Marking tiles: TileSet custom-data layer (Approach B)

A single integer custom-data layer named `surface_type` is added to the
level's TileSet. Values:

| Value | Meaning |
|------:|---------|
| 0 | `NONE` — normal ground (default) |
| 1 | `ICE1` — Type 1 low-friction ice |
| 2 | `ICE2` — Type 2 forced-slide ice |

**Authoring needs no custom editor tooling.** The custom data is authored on
the TileSet *resource* via Godot's built-in TileSet panel (add the
`surface_type` layer, then set the value per tile). The level editor
(`level_editor.gd`) paints tile ids into `LevelData` exactly as before; it does
not need to know about surface types — the data lives in the TileSet, not in
the level.

**Runtime tileset selection** (`level_runtime.gd:120-126`):

- **Authored path** (`level.tileset_ref != null`): the geometry layer uses
  `tileset_ref` directly, so the authored custom data is readable at runtime
  via the geometry `TileMapLayer`. ✓ This is the primary path.
- **Procedural fallback** (`ProceduralTileSet.build`): builds a fresh TileSet
  with no custom data. The builder is extended to add the `surface_type`
  custom-data layer and tag a configurable set of solid-color dev tile ids as
  `ICE1` / `ICE2`, so dev/test levels can exercise ice. The player-facing
  contract stays uniform — it always reads custom data.

**Rejected alternatives:**

- *Approach A — surface registry keyed by tile id.* Lightest, but couples
  ice-ness to tile identity; atlas reorganization breaks the mapping. Re-author
  per tileset.
- *Approach C — sidecar `surface_tiles` array in `LevelData` + a new editor
  surface-paint mode.* Most flexible (any floor can be ice regardless of art),
  but the most editor work and requires injecting the array into the player.
  Right upgrade later if decoupling surface from art becomes desirable.

### Movement: unified acceleration model

Normal ground, ice, and coast all share the `move_toward(vx, target, rate*delta)`
shape already used by air/pogo. Ice and coast are parameter variations:

| State | Input held | No input |
|-------|-----------|----------|
| Normal ground | accel toward `dir*run_speed` at `ground_accel` | decel toward 0 at `ground_decel` |
| Ice 1 | accel toward `dir*ice_max_speed_cap` at `ice_accel` | **no change** (zero friction) |
| Ice 2 | (input ignored) pinned to `entry_dir*ice2_slide_speed` | (n/a — pinned) |
| Coast | accel toward `dir*ice_max_speed_cap` at `ice_accel` (auto-decel suspended) | decel toward 0 at `coast_decel` |

### Surface reading: injected geometry TileMapLayer

`LevelRuntime` already configures the player at spawn (`set_camera_bounds`,
`set_mode`, ammo seeding in `_spawn_player`, `level_runtime.gd:180`). A new
`Player.set_ground_tilemap(tml)` injection is added: `LevelRuntime` passes the
geometry `TileMapLayer` (`layers[LevelData.LAYER_GEOMETRY]`) to the player. The
player never hardcodes node paths.

Each grounded frame the player samples the cell under its feet (bottom-center
of the Level collision shape, nudged ~1 px down to land in the tile below) and
reads `TileData.get_custom_data("surface_type")`. Reuses the
`local_to_map` / `get_cell_tile_data` pattern from `projectile.gd:88`.

## 4. Detailed behavior

### 4.1 Normal ground (accel model)

Replaces `player.gd:170`. On the ground, not coasting, surface `NONE`:

```gdscript
var target := dir * run_speed * (_speed_scale if _input_locked else 1.0)
if dir != 0.0:
    velocity.x = move_toward(velocity.x, target, ground_accel * delta)
    if not _input_locked:
        _facing = signi(dir)
else:
    velocity.x = move_toward(velocity.x, 0.0, ground_decel * delta)
```

Turning decelerates through zero and accelerates opposite, naturally.

### 4.2 Type 1 ice (ICE1)

On the ground, surface `ICE1`:

```gdscript
# Entry cap (first frame transitioning onto ICE1):
if absf(velocity.x) > ice_max_speed_cap:
    velocity.x = signf(velocity.x) * ice_max_speed_cap

if dir != 0.0:
    velocity.x = move_toward(velocity.x, dir * ice_max_speed_cap, ice_accel * delta)
    _facing = signi(dir)
# else: velocity.x unchanged (zero friction — keeps gliding)
```

A single `move_toward` covers speed-up, slow-down (toward cap), and
turn-through-zero. Animation is already velocity-based
(`moving = absf(velocity.x) > 1.0`, `player.gd:415`), so gliding with no input
shows Walking with no anim change.

### 4.3 Type 2 ice (ICE2)

On the ground, surface `ICE2`:

- **Entry** (first grounded ICE2 frame with `|velocity.x| > 0`):
  `entry_dir = signf(velocity.x)`; `velocity.x = entry_dir * ice2_slide_speed`;
  `_ice2_locked = true`.
- **Each locked frame:** `velocity.x = entry_dir * ice2_slide_speed` (held at
  max). Movement keys ignored for X.
- **No entry velocity** (`|velocity.x| == 0` on entry, e.g. dropped straight
  down): no slide; `velocity.x` stays 0; Keen stands; jump only.
- **Wall hit** (`get_wall_normal()` fires while locked): `velocity.x = 0`. Keen
  stays stopped on the ICE2 tile; movement keys still ignored; jump only.
  (Re-slide requires a new entry, i.e. landing with horizontal velocity.)
- **Jump:** normal launch (`velocity.x = _jump_dir * leap_speed` at wind-up
  end). On re-landing on ICE2 with horizontal velocity → new slide; without →
  stand.
- **Anim:** Idle while `_ice2_locked`, even though `|velocity.x| > 0`. One
  override at the `_current_anim` call site (`player.gd:415`): pass
  `moving = false` (or add an `ice2_locked` param) while locked. Shooting /
  pogo / jump poses short-circuit earlier in `_current_anim` and are
  unaffected.

### 4.4 Coast

**Enter coast** when, on a grounded frame: previous surface was ICE1 or ICE2,
current surface is NONE, `|velocity.x| > 0`, and the player did not jump this
frame. On entry, record `v0 = |velocity.x|` and compute:

```gdscript
coast_decel = v0 * v0 / (2.0 * coast_distance)   # coast_distance = Constants.TILE * 1.5 = 96
```

(constant deceleration covering exactly `coast_distance`.) Set `_coasting = true`.

**Each coast frame:**

- **No movement input:** `velocity.x = move_toward(velocity.x, 0.0, coast_decel * delta)`.
  Reaches 0 at exactly `+coast_distance` from the ice edge (guaranteed stop at
  center of 2nd tile) for an uninterrupted coast.
- **Movement input held:** suspend `coast_decel`; apply Type 1 steering
  (`move_toward(velocity.x, dir * ice_max_speed_cap, ice_accel * delta)`).
  Releasing input recomputes `coast_decel` from the *current* speed, so the
  guaranteed-1.5-tile stop holds only for an uninterrupted coast (matches the
  original-game observation, which assumes no input during the coast).
- **Jump:** cancels coast (`_coasting = false`) → normal air.
- **`|velocity.x|` reaches ~0:** exit coast (`_coasting = false`) → normal
  ground.

Anim: Walking (`|velocity.x| > 0` already drives `moving`).

### 4.5 State / dispatch summary

Grounded-frame dispatch in `_physics_process` (replacing `player.gd:169-177`):

```gdscript
var surface := _read_surface_under_feet()   # NONE / ICE1 / ICE2
match surface:
    SurfaceType.ICE2:
        _step_ice2()
    SurfaceType.ICE1:
        _step_ice1(dir, delta)
    _:
        if _coasting:
            _step_coast(dir, delta)
        else:
            _step_ground(dir, delta)

# Coast entry detection (after stepping):
_update_coast_state(surface, previous_surface, jumped_this_frame)
previous_surface = surface
```

`_input_locked` (exits, teleport arrival) and `_forced_dir` take precedence as
today; ice rules apply only to normal player-controlled ground movement.

## 5. New code units

### 5.1 `SurfaceType` (`src/core/surface_type.gd`)

```gdscript
class_name SurfaceType
extends RefCounted
## Tile surface types. Values match the TileSet `surface_type` custom-data layer.
enum Kind { NONE = 0, ICE1 = 1, ICE2 = 2 }
```

### 5.2 `SurfacePhysics` (`src/runtime/player/surface_physics.gd`)

Pure `(vx, ...) -> float` helpers, unit-testable without a Player scene:

```gdscript
class_name SurfacePhysics
extends RefCounted

static func step_ground(vx, dir, run_speed, speed_scale, accel, decel, delta) -> float
static func step_ice1(vx, dir, cap, accel, delta) -> float
static func step_ice1_entry(vx, cap) -> float           # entry cap
static func step_ice2(vx, entry_dir, slide_speed) -> float
static func coast_decel_for(v0, distance) -> float
static func step_coast(vx, coast_decel, delta) -> float
```

The player's physics loop is a thin dispatcher that reads surface, manages the
`_coasting` / `_ice2_locked` / `entry_dir` flags, and delegates the velocity
math to these.

### 5.3 Player changes (`src/runtime/player/player.gd`)

- New `@export` tunables:
  - `ground_accel: float`
  - `ground_decel: float`
  - `ice_accel: float`
  - `ice_max_speed_cap: float` (default `run_speed`)
  - `ice2_slide_speed: float` (default `run_speed`)
  - `coast_distance: float` (default `Constants.TILE * 1.5`)
- New state: `_coasting: bool`, `_ice2_locked: bool`, `_ice2_entry_dir: float`,
  `_coast_decel: float`, `_prev_surface: int`.
- New `set_ground_tilemap(tml: TileMapLayer)` + `_ground_tml` ref + a private
  `_read_surface_under_feet() -> int` (reuses `projectile.gd:88` pattern).
- `_current_anim` call site (`player.gd:415`) passes `moving = false` (or a new
  param) while `_ice2_locked`, so Idle plays during a slide.
- The ground branch of `_physics_process` (`player.gd:169-177`) becomes the
  surface dispatch (§4.5).
- `_ice2_locked` is cleared whenever the player leaves the ICE2 surface
  (slides onto another surface, slides off an edge into the air, or jumps) so a
  stale lock can't survive a surface change.

### 5.4 ProceduralTileSet extension (`src/runtime/procedural_tileset.gd`)

`build()` gains optional `ice1_ids: Array[int]` and `ice2_ids: Array[int]`
params; when non-empty it adds the `surface_type` custom-data layer (physics
layers are unaffected) and tags those atlas cells. Defaults empty → current
behavior unchanged.

### 5.5 LevelRuntime change (`src/runtime/level_runtime.gd`)

After building the geometry layer and spawning the player
(`_spawn_player`, `level_runtime.gd:180`), inject the geometry `TileMapLayer`:
`player.set_ground_tilemap(layers[LevelData.LAYER_GEOMETRY])`.

## 6. Data flow

```
LevelData (tile ids)
   │
   ├── level.tileset_ref (authored, has surface_type custom-data layer)
   │        │
   │        └── Godot TileSet editor: author sets surface_type per tile
   │
   └── LevelRuntime.build()
            │
            ├── geometry TileMapLayer <- tileset_ref (or ProceduralTileSet w/ custom data)
            │
            └── Player.set_ground_tilemap(geometry TileMapLayer)

Player._physics_process (grounded):
   _read_surface_under_feet()  ──►  TileMapLayer.get_cell_tile_data(foot_cell)
                                          └── get_custom_data("surface_type") -> NONE/ICE1/ICE2
   dispatch ──► SurfacePhysics.step_*  ──► velocity.x
```

## 7. Testing

GUT, following the `tests/unit/test_player*.gd` pattern.

**New: `tests/unit/test_surface_physics.gd`** — pure-function tests of
`SurfacePhysics`:

- `step_ground`: accel toward `run_speed`, decel toward 0, turn-through-zero,
  `speed_scale` honored.
- `step_ice1`: accel toward `ice_max_speed_cap`; **velocity unchanged when
  `dir == 0`** (zero friction — the core assertion); entry cap clamps
  overspeed.
- `step_ice2`: pins `entry_dir * slide_speed`; wall case handled by the player
  (velocity zeroed externally), so the helper just pins.
- `coast_decel_for`: for a sample `v0`, the analytic decel brings velocity to 0
  over exactly `coast_distance` (integrate `move_toward` steps, assert total
  distance ≈ 96 px within epsilon).
- `step_coast`: monotonic decel toward 0; never overshoots.

**New: `tests/unit/test_player_surface.gd`** — integration with a real Player:

- Surface query: a procedural tileset tagged ICE1/ICE2 reads back correctly
  from the geometry TileMapLayer; a tileset with no custom-data layer resolves
  to NONE (migration safety).
- Ice1 grounded step preserves velocity with no input; accelerates with input.
- Ice2 entry pins velocity to `entry_dir * slide_speed`; wall zeroes velocity;
  no-slide when entry velocity is 0.
- Coast enters on ICE→NONE transition, decelerates over ~96 px, exits at 0;
  input suspends auto-decel; jump cancels coast.
- Anim: `_ice2_locked` forces Idle while `|velocity.x| > 0`.

**Existing: `tests/unit/test_player.gd`** — update cases that asserted
instant-snap to the new accel/decel model.

All tests must pass via `./tests/run_all.sh`.

## 8. Risks / notes

- **Whole-game feel change.** Introducing `ground_accel`/`ground_decel` alters
  every level's walking feel, not just ice. Defaults will need dialing in by
  feel; the plan should include a playtest pass over existing levels. Existing
  player-movement tests will need updating.
- **`get_collision_polygon_count()` hang.** Not touched here (we read custom
  data, not collision polygons), but surface reading uses
  `get_cell_tile_data` + `get_custom_data`, which are safe in 4.7 headless
  (already used by `projectile.is_solid_tile_at`).
- **Coast distance vs. tile alignment.** The 1.5-tile stop assumes the ice edge
  is tile-aligned (it is — surfaces are per-tile). Sub-pixel start positions
  are absorbed by the constant-decel integration; the stop point is exact for
  an uninterrupted coast.
- **Type 2 re-entry ambiguity.** After a wall stop on an ICE2 tile, Keen has
  zero velocity and cannot slide again without jumping — consistent with
  "movement keys do nothing." This is intentional and matches the original.
