# Ice Cannon Hazard — Design Spec

**Date:** 2026-07-26
**Status:** Draft
**Engine:** Godot 4.7 (stable)
**Language:** GDScript

## 1. Overview

Adds a new directional hazard — **Ice Cannon** — that periodically fires a
spinning icicle projectile in a chosen direction. The cannon body is solid
(Keen bumps into it / stands on it) but harmless; only the projectile kills
on contact. Projectiles travel in a perfectly straight line until they hit
a solid tile, then despawn instantly.

The existing `ice_cannon.tscn` ships eight directional `Sprite2D` children
(`Up`, `Down`, `Left`, `Right`, `UpRight`, `UpLeft`, `DownRight`,
`DownLeft`) plus one hidden `AnimatedSprite2D` projectile template. Each
directional sprite carries two metadata fields that fully describe its
firing solution:

- `metadata/projectile_start_position` — `PackedInt32Array(x, y)` offset
  from the cannon center where the projectile spawns (the muzzle).
- `metadata/projectile_vector` — `float` degrees, 0 = straight up,
  **counter-clockwise visually on screen** (so 90 = left, 180 = down,
  270 = right, 315 = up-right, 45 = up-left, etc.).

### Requirements

| # | Requirement |
|---|-------------|
| 1 | All eight non-projectile sprites carry collision; the cannon body is solid and Keen does not die on contact with it. |
| 2 | The projectile has its own collision that follows it as it travels; touching it instakills Keen via the shared `_instakill` helper. |
| 3 | The projectile travels in a perfectly straight line at constant velocity from its muzzle `projectile_start_position`. |
| 4 | The projectile despawns instantly the frame it intersects any solid (non-one-way) tile. |
| 5 | Direction is selected per-instance via an inspector enum `facing` with the eight sprite names; default `UpRight` (matches the current scene's only visible sprite). |
| 6 | The cannon fires on a periodic timer with a 1.0s default period, looping, autostart. |
| 7 | Entity registers as `keen1.ice_cannon` under `CATEGORY_HAZARD`, appears in the editor palette, spawns at runtime. |
| 8 | All existing GUT tests pass; new tests lock firing cadence, projectile motion, instakill, solid-tile despawn, and palette registration. |

### Out of scope

- **Player-projectile interaction** — Keen's raygun bolts do not destroy the
  ice cannon projectile (it has no `take_damage` method, matching the
  Clapper/Spike family). Bolts may overlap it harmlessly.
- **Sound effects** — no ice cannon SFX asset yet.
- **Aiming / tracking** — the cannon fires a fixed direction regardless of
  player position. No proximity trigger.
- **Projectile persistence / fade** — instant despawn on solid hit, no
  lingering icicle.
- **Multiple simultaneous directions** — one cannon fires one direction;
  designers place multiple cannons for coverage.

## 2. Background — the gap this closes

The hazard family covers stationary contact killers (Spike, Fire, Clapper,
Green Dangly Stuff) but nothing fires projectiles at the player. The
sprite assets (`assets/sprites/Ice Cannon Projectile.png` 8-frame spin,
`assets/tilesets/Ice Cannon.png` 8 directional bodies) and a placeholder
`ice_cannon.tscn` already exist. This spec fills in the scene rewrite,
the cannon script, a dedicated projectile scene + script, and the registry
plumbing.

## 3. Approach

Reuse the `Hazard` base class (for `_instakill()` and the `Entity` plumbing)
but override `_ready()` to **skip** the default player-contact `Area2D` —
the cannon body must not kill, so it has no contact sensor. Instead the
cannon is a solid `CharacterBody2D` on the tiles collision layer; the kill
happens on the projectile, which is a separate `Area2D`-rooted scene.

The projectile mirrors the existing player `Projectile` (raygun bolt)
architecture: `Area2D` root, linear `global_position += velocity * delta`,
per-frame solid-tile probe, despawn on hit. To avoid duplicating the
solid-tile logic, the new projectile reuses the **static**
`Projectile.is_solid_tile_at()` helper.

The cannon's eight `Sprite2D` children already encode per-direction firing
solutions as metadata. The active direction is selected at runtime by an
exact-name match against an enum property (`facing`). `EntityVariant` is
deliberately **not** used here: its substring-match rule (`Up` is a
substring of `UpRight`/`UpLeft`) would mis-select cardinal directions when
a diagonal option is chosen. A four-line exact match in `setup()` is
unambiguous and self-documenting.

## 4. Detailed Design

### 4.1 Scene rewrite: `src/runtime/entities/ice_cannon.tscn`

The placeholder scene's root changes from `Node2D` to `CharacterBody2D`
(required by `Entity`/`Hazard` which extend `CharacterBody2D`). The
`ice_cannon.gd` script is attached to the root.

The eight directional `Sprite2D` children (`Up`, `Down`, `Left`, `Right`,
`UpRight`, `UpLeft`, `DownRight`, `DownLeft`) are **left intact** — their
textures, rotations, visibility defaults, and `metadata/projectile_*`
fields stay exactly as authored.

The embedded `Projectile` `AnimatedSprite2D` and its supporting
`SpriteFrames` + eight `AtlasTexture` sub-resources are **removed** from
this scene: they relocate verbatim into the new dedicated projectile scene
(§4.3). Keeping a hidden, never-shown animation child in the cannon would
be dead weight and a second source of truth for the spin frames.

No `CollisionShape2D`, `Area2D`, or `Timer` nodes are placed in the scene
file — all three are built at runtime by the script (matches the
`Entity._build_contact_area()` / Door / Green Dangly Stuff pattern of
runtime-constructed physics children).

### 4.2 Script: `src/runtime/entities/ice_cannon.gd`

```gdscript
class_name IceCannon
extends Hazard
## Directional cannon. Solid body (Keen can stand on / bump into, no
## damage). Periodically fires a straight-line icicle projectile from the
## active facing sprite's muzzle metadata; the projectile instakills on
## contact and despawns on the first solid tile it touches.

const _BODY_SIZE := 128.0            # cannon sprite footprint, px
const _PROJECTILE_SCENE := preload("res://src/runtime/entities/ice_cannon_projectile.tscn")

@export var period: float = 1.0      # seconds between shots
@export var projectile_speed: float = 300.0

var _timer: Timer


func setup(p_type_id: String, p_props: Dictionary) -> void:
    super(p_type_id, p_props)
    _apply_facing()


func _ready() -> void:
    # Deliberately do NOT call super._ready(): the cannon body does not kill,
    # so it must not build the default player-contact Area2D. Build only the
    # solid body + firing timer.
    collision_layer = 4   # tiles bit -> Keen collides with / lands on body
    collision_mask = 0
    _add_body_shape()
    _add_timer()


func _handle_player(_player: Node) -> void:
    # No contact Area2D is built, so this is never invoked; kept as a no-op
    # guard against the base Hazard contract.
    pass


func _apply_facing() -> void:
    # Exact-name match (NOT EntityVariant): the eight sprite names
    # substring-collide (Up ⊂ UpRight/UpLeft), which would break
    # EntityVariant's first-substring-wins rule.
    var facing := String(properties.get("facing", "UpRight"))
    var want := facing.to_lower()
    for c in get_children():
        if c is Sprite2D:
            c.visible = (String(c.name).to_lower() == want)


func _add_body_shape() -> void:
    var shape := CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = Vector2(_BODY_SIZE, _BODY_SIZE)
    shape.shape = rect
    add_child(shape)


func _add_timer() -> void:
    _timer = Timer.new()
    _timer.wait_time = period
    _timer.autostart = true
    _timer.one_shot = false
    _timer.timeout.connect(_fire)
    add_child(_timer)


func _fire() -> void:
    var muzzle_sprite := _active_facing_sprite()
    if muzzle_sprite == null:
        return
    var start_offset: Vector2 = _read_start_offset(muzzle_sprite)
    var direction: Vector2 = _read_direction(muzzle_sprite)
    var proj: IceCannonProjectile = _PROJECTILE_SCENE.instantiate()
    get_parent().add_child(proj)
    proj.global_position = global_position + start_offset
    proj.launch(direction * projectile_speed)


func _active_facing_sprite() -> Sprite2D:
    for c in get_children():
        if c is Sprite2D and c.visible:
            return c
    return null


func _read_start_offset(sprite: Sprite2D) -> Vector2:
    var arr: PackedInt32Array = sprite.get_meta("projectile_start_position", PackedInt32Array())
    if arr.size() >= 2:
        return Vector2(float(arr[0]), float(arr[1]))
    return Vector2.ZERO


func _read_direction(sprite: Sprite2D) -> Vector2:
    # projectile_vector is degrees, 0 = straight up, counter-clockwise
    # visually on screen (Y-down). Verified against all eight sprites:
    #   Up=0 -> (0,-1), Left=90 -> (-1,0), Down=180 -> (0,1),
    #   Right=270 -> (1,0), UpRight=315 -> (0.707,-0.707), etc.
    var deg := float(sprite.get_meta("projectile_vector", 0.0))
    var rad := deg_to_rad(deg)
    return Vector2(-sin(rad), -cos(rad))
```

Rationale for `_handle_player` no-op: the base `Entity._on_body_entered`
calls it, but since no contact `Area2D` is constructed, the signal never
fires. The guard exists purely to satisfy the override contract and
documents intent.

### 4.3 Projectile scene + script

#### `src/runtime/entities/ice_cannon_projectile.tscn`

`Area2D` root named `IceCannonProjectile`, script attached. Children:

- **`CollisionShape2D`** — `RectangleShape2D` 32×32 (half the 64×64 frame;
  tight hitbox, generous dodge window).
- **`AnimatedSprite2D`** named `Spin` — the relocated `SpriteFrames`
  (eight 64×64 atlas frames from `assets/sprites/Ice Cannon Projectile.png`,
  10 fps, looping), autoplay `default`.

`Area2D.collision_layer = 0`, `collision_mask = 1` (player bit only — the
projectile senses the player for the kill trigger but does not physically
collide with anything, so it never blocks or is blocked).

#### `src/runtime/entities/ice_cannon_projectile.gd`

```gdscript
class_name IceCannonProjectile
extends Area2D
## Icicle fired by IceCannon. Straight-line motion at constant velocity;
## despawns instantly on touching a solid (non-one-way) tile, or instakills
## Keen on contact. Reuses Projectile.is_solid_tile_at() for tile probing
## so one-way platforms (jump-through floors) remain passable.

var velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
    if body_entered.is_connected(_on_body_entered) == false:
        body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
    global_position += velocity * delta
    # Per-frame solid-tile probe: body_entered fires once per TileMapLayer,
    # so a fast projectile could tunnel past the entry frame into a solid
    # cell. Mirrors the player Projectile's approach; honors one-way skip.
    for body in get_overlapping_bodies():
        if body is TileMapLayer and Projectile.is_solid_tile_at(body, global_position):
            queue_free()
            return


func launch(p_velocity: Vector2) -> void:
    velocity = p_velocity


func _on_body_entered(body: Node) -> void:
    # Only the player is on the mask; any body that enters is the player.
    # Drain all health via the shared instakill contract.
    if body != null and body.is_in_group("player") \
            and body.has_method("take_damage") and "health" in body:
        body.take_damage(body.health)
```

Note: the projectile cannot use `Hazard._instakill()` directly because it
does not extend `Hazard` (it extends `Area2D`, not `CharacterBody2D`).
The two-line drain mirrors `_instakill`'s contract verbatim. An alternative
is to make the projectile call into a cannon reference, but the projectile
outlives its spawn cannon in principle and should be self-contained.

#### Projectile ↔ cannon non-interaction

The projectile is an `Area2D` (sensor), not a physics body, so it cannot
physically collide with the cannon's `CharacterBody2D` body — it passes
through freely. Its `collision_mask = 1` (player only) means `body_entered`
fires exclusively for Keen; the cannon body never triggers it. Solid-tile
despawn uses `is_solid_tile_at`, which probes `TileMapLayer` cells only, so
the cannon body (a `CharacterBody2D`, not a tile) never causes a premature
despawn. Spawn position is the muzzle offset (±32 or ±64 from center), at
or beyond the 128×128 body's edge, so the projectile never starts inside
the body region.

### 4.4 Registration: `src/episodes/keen1/episode.gd`

Add alongside the other hazard preloads and registrations, mirroring the
Green Dangly Stuff registration shape:

```gdscript
var ice_cannon := preload("res://src/runtime/entities/ice_cannon.tscn")
registry.register("keen1.ice_cannon", registry.CATEGORY_HAZARD, "Ice Cannon",
    [{name = "facing", default = "UpRight", type = "enum",
        options = ["Up", "UpRight", "Right", "DownRight", "Down",
                   "DownLeft", "Left", "UpLeft"]}],
    ice_cannon)
```

Map kind defaults to `LEVEL` only (hazards do not appear on the overworld,
matching Clapper/Spike/Fire/Green Dangly Stuff).

### 4.5 Tests

Extend `tests/unit/test_hazard.gd` with the cannon-specific cases (or a
sibling `test_ice_cannon.gd` if the hazard file is getting large —
prefer a sibling file for focus):

- `test_ice_cannon_fires_on_timer_period()` — instantiate, advance the
  `Timer` by `period`, assert exactly one `IceCannonProjectile` child
  spawned as a sibling at the muzzle offset.
- `test_ice_cannon_body_is_solid_no_kill()` — assert `collision_layer == 4`,
  `mask == 0`, has a direct-child `CollisionShape2D` (128×128), and no
  child `Area2D` named `Area2D` (i.e., the kill-contact sensor was not
  built).
- `test_ice_cannon_facing_selects_matching_sprite()` — set `facing` to
  each of the eight values, assert exactly that `Sprite2D` is visible and
  the other seven are hidden.
- `test_ice_cannon_direction_vector_for_each_facing()` — table-driven:
  for each sprite, assert `_read_direction()` returns the expected
  normalized vector (`Up`→(0,-1), `Left`→(-1,0), `Down`→(0,1),
  `Right`→(1,0), `UpRight`→(0.707,-0.707), `UpLeft`→(-0.707,-0.707),
  `DownRight`→(0.707,0.707), `DownLeft`→(-0.707,0.707)).

A separate projectile test file `tests/unit/test_ice_cannon_projectile.gd`:

- `test_projectile_moves_in_straight_line()` — set velocity, step two
  frames, assert position = velocity × elapsed (no drift).
- `test_projectile_despawns_on_solid_tile()` — place over a solid
  `TileMapLayer` cell, step, assert `queued_for_deletion`.
- `test_projectile_passes_one_way_platform()` — place over a one-way
  tile, step, assert still alive.
- `test_projectile_instakills_player_on_contact()` — fake a player body
  in group `"player"` with `take_damage` + `health`, emit `body_entered`,
  assert health drained to zero.

A separate addition to `test_episode.gd`:

- `test_ice_cannon_registered_as_hazard_with_facing_schema()` — asserts
  `keen1.ice_cannon` is registered, is a hazard, has the 8-option `facing`
  enum with default `UpRight`.

## 5. Data Flow

1. Editor palette enumerates the registry and shows "Ice Cannon" under
   Hazards.
2. Designer places the entity, optionally switches `facing` in the
   inspector; the choice persists in the level's `EntityDef.properties`.
3. At level load, `EntityRegistry.instantiate` creates the `IceCannon`
   scene, calls `setup(type_id, props)`, which runs `_apply_facing()` →
   exactly the matching `Sprite2D` is visible.
4. `_ready()` builds the solid body shape (tiles layer) and the firing
   `Timer` (autostart, `period` seconds, looping).
5. On each `timeout`, `_fire()` reads the visible sprite's
   `projectile_start_position` + `projectile_vector` metadata, computes
   spawn position and direction, instantiates `IceCannonProjectile` as a
   sibling, positions it at the muzzle, and launches it.
6. The projectile steps `global_position += velocity * delta` each physics
   frame; per-frame it probes `is_solid_tile_at` for its current cell.
7. On Keen contact (`body_entered`, mask = player), the projectile drains
   all health → `Player.died`. On solid-tile intersection, the projectile
   `queue_free()`s instantly.

## 6. Risk & Rollback

- **Root type change** (`Node2D` → `CharacterBody2D`): required because
  `Hazard` extends `CharacterBody2D`. The eight sprite children and their
  metadata are unaffected by the root type change. If the embedded
  `Projectile` `AnimatedSprite2D` is referenced anywhere (it is not, per
  codebase search), removing it would break that reference — verified no
  GDScript loads `IceCannon/Projectile`.
- **Substring collision in `facing` options**: deliberately sidestepped by
  using exact-name match in `_apply_facing()` rather than `EntityVariant`.
  If a future refactor moves all variant selection through `EntityVariant`,
  this entity must be exempted or `EntityVariant` must gain an exact-match
  mode.
- **Projectile tunneling at high speed**: mitigated by the per-frame
  `is_solid_tile_at` probe (same defense the player `Projectile` uses). At
  300 px/s and 60 fps the per-frame step is 5 px, far below the 64 px tile
  size, so tunneling is not realistically possible.
- **Projectile spawned inside cannon body**: the muzzle offsets (±32,
  ±64) sit at or beyond the 128×128 body's half-extent (64), so the
  projectile's 32×32 hitbox starts at the body edge, not inside it. The
  projectile is an `Area2D` regardless and cannot physically collide with
  the cannon body.
- **Rollback**: the change is additive — one rewritten scene, one new
  scene + script, one cannon script, one registration block, and new test
  files. Reverting is a single commit.

## 7. Test Plan

| Test | Verifies |
|------|----------|
| `test_ice_cannon_fires_on_timer_period` | Timer-driven spawn at correct muzzle offset |
| `test_ice_cannon_body_is_solid_no_kill` | `collision_layer=4`, no contact `Area2D`, body shape present |
| `test_ice_cannon_facing_selects_matching_sprite` | All 8 `facing` values show exactly the right sprite |
| `test_ice_cannon_direction_vector_for_each_facing` | Angle→vector math correct for all 8 sprites |
| `test_projectile_moves_in_straight_line` | Constant velocity, no drift |
| `test_projectile_despawns_on_solid_tile` | Solid tile → `queue_free` |
| `test_projectile_passes_one_way_platform` | One-way tile not treated as solid |
| `test_projectile_instakills_player_on_contact` | `body_entered` drains all health |
| `test_ice_cannon_registered_as_hazard_with_facing_schema` | Registry entry, category, 8-option enum default `UpRight` |
| Existing suite | No regressions (run `./tests/run_all.sh`) |

## 8. Open Questions

None at spec time. The chosen defaults (projectile speed 300 px/s,
projectile hitbox 32×32, default facing `UpRight`, fire period 1.0 s) are
tunable via `@export` / inspector and can be adjusted after playtesting
without code changes.
