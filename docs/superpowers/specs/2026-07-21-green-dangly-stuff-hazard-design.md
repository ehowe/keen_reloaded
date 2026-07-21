# Green Dangly Stuff Hazard — Design Spec

**Date:** 2026-07-21
**Status:** Draft
**Engine:** Godot 4.7 (stable)
**Language:** GDScript

## 1. Overview

Adds a new stationary hazard — **Green Dangly Stuff** — that hangs from
the ceiling and behaves like a one-way platform whose underside is deadly.
Keen can walk on top safely; touching the bottom portion (jumping into it
from below or walking into it from the side) instakills him, matching the
existing Spike / Fire / Clapper family.

Art (`assets/sprites/Green Dangly Stuff.png`, 256×192) ships three visual
variants — **Left Edge**, **Normal**, **Right Edge** — one per sprite-sheet
row. The empty placeholder `green_dangly_stuff.tscn` becomes a real scene
with three `AnimatedSprite2D` children and uses the existing
`EntityVariant` mechanism to pick one at spawn time.

### Requirements

| # | Requirement |
|---|-------------|
| 1 | Keen landing on top of a Green Dangly Stuff tile stands on it like a one-way platform — he does not fall through. |
| 2 | Keen touching the bottom ~48 px of the tile (the dangly mass) instakills him via the same `_instakill` helper used by Spike/Fire/Clapper. |
| 3 | Three visual variants are selectable in the inspector via an enum property `variant` with options `Left Edge`, `Normal`, `Right Edge`; default `Normal`. |
| 4 | Variants map to the three rows of the source sprite sheet (row 1 → Left Edge, row 2 → Normal, row 3 → Right Edge), each a 4-frame animation. |
| 5 | Entity registers as `keen1.green_dangly_stuff` under `CATEGORY_HAZARD`, appears in the editor palette, and spawns at runtime. |
| 6 | All existing GUT tests pass; new tests lock the hitbox split, instakill behavior, variant schema, and palette registration. |

### Out of scope

- **Sound effects** (no `green_dangly` SFX asset yet; revisit when the
  audio table grows).
- **Projectile / stomp interaction** — the hazard is invincible and
  immovable, like Clapper. Bolts pass through harmlessly (no
  `take_damage` method).
- **Directional variation of the kill zone** — the kill zone is always the
  bottom ~48 px regardless of which visual variant is selected.
- **Partial damage / non-instakill modes** — single behavior, matches the
  rest of the instakill family.

## 2. Background — the gap this closes

The instakill hazard family (Spike, Fire, Clapper) covers floor and
full-contact hazards but nothing hangs from the ceiling. The sprite asset
already exists, and a placeholder `.tscn` was committed earlier as an
empty `Node2D`. This spec fills both gaps: a real scene and the script +
registry plumbing for a hazard that is solid from above and deadly from
below.

## 3. Approach

Reuse the existing `Hazard` base class and its `_instakill()` helper. The
novel behavior is split-collision: the body is solid-as-one-way on the
full tile, while the contact `Area2D` only covers the bottom portion.
Pattern is borrowed from `Door._ready()` (entity on the tiles bit, Area2D
shape resized post-construction) and `Spike` (scripted Hazard with a
schema-driven variant enum).

The one-way behavior comes from setting `one_way_collision = true` on the
body's `CollisionShape2D`, which Godot 4.7 supports on any
`PhysicsBody2D`. The player's `CharacterBody2D.move_and_slide` already
honors one-way platforms via its floor/block detection, so no player-side
change is needed.

## 4. Detailed Design

### 4.1 Scene: `src/runtime/entities/green_dangly_stuff.tscn`

Root `CharacterBody2D` named `GreenDanglyStuff`, scripted. Children:

- **`Visual`** (`Node2D`) — variant container, mirrored from
  `assets/sprites/Spike.tscn` structure. Three `AnimatedSprite2D`
  children, named exactly the enum options so `EntityVariant` substring
  matching is unambiguous:
  - `Left Edge` — visible by default = false; uses row 1 (y=0..64)
  - `Normal` — visible by default = true; uses row 2 (y=64..128)
  - `Right Edge` — visible by default = false; uses row 3 (y=128..192)
  - Each holds a 4-frame `SpriteFrames` at 5 fps, autoplay `default`.
- **No `CollisionShape2D` or `Area2D` in the scene** — both are built at
  runtime by the script (matches `Entity._build_contact_area()` and the
  Door pattern).

The three `SpriteFrames` resources slice the source texture into 64×64
atlas regions:

| Variant    | Frame regions (Rect2 x, y, 64, 64) |
|------------|-----------------------------------|
| Left Edge  | (0,0), (64,0), (128,0), (192,0)   |
| Normal     | (0,64), (64,64), (128,64), (192,64)|
| Right Edge | (0,128), (64,128), (128,128), (192,128) |

### 4.2 Script: `src/runtime/entities/green_dangly_stuff.gd`

```
class_name GreenDanglyStuff
extends Hazard
## Ceiling hazard: one-way platform on top, instakill dangly mass below.
## Three visual variants (Left Edge / Normal / Right Edge) map to the
## three sprite-sheet rows and are selected via the `variant` schema enum.

const _KILL_HEIGHT := 48.0   # px of the bottom of the tile that kills
const _TOP_SOLID := 16.0     # px of the top of the tile that is non-deadly

func setup(p_type_id: String, p_props: Dictionary) -> void:
    super(p_type_id, p_props)
    EntityVariant.apply(type_id, properties, self)

func _ready() -> void:
    # Build the player-contact Area2D via the base, then shrink its shape
    # to the bottom _KILL_HEIGHT px of the tile so only the dangly mass
    # kills. Player standing on top (feet above the kill zone) is safe.
    _build_contact()
    _shrink_contact_to_bottom()
    # Body is a one-way platform: layer=tiles so player lands on it,
    # one_way_collision=true so player can rise through from below.
    collision_layer = 4  # tiles bit
    collision_mask = 0
    _add_one_way_body_shape()

func _handle_player(player: Node) -> void:
    _instakill(player)

func _shrink_contact_to_bottom() -> void:
    var col := _area.get_child(0) as CollisionShape2D
    if col != null and col.shape is RectangleShape2D:
        var rect := col.shape as RectangleShape2D
        rect.size = Vector2(TILE, _KILL_HEIGHT)
        col.position = Vector2(0, (TILE - _KILL_HEIGHT) / 2.0)

func _add_one_way_body_shape() -> void:
    var shape := CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = Vector2(TILE, TILE)
    shape.shape = rect
    shape.one_way_collision = true
    add_child(shape)
```

Rationale for `_TOP_SOLID` being a named const despite not affecting the
body shape (the body is the full tile with one-way): it documents the
"safe strip" that pairs 1:1 with `_KILL_HEIGHT` (`_TOP_SOLID +
_KILL_HEIGHT = TILE = 64`). The kill Area2D's vertical extent is what
actually enforces the split; the body shape handles landability.

### 4.3 Registration: `src/episodes/keen1/episode.gd`

Add alongside the other hazard preloads and registrations:

```
var green_dangly := preload("res://src/runtime/entities/green_dangly_stuff.tscn")
registry.register("keen1.green_dangly_stuff", registry.CATEGORY_HAZARD, "Green Dangly Stuff",
    [{name = "variant", default = "Normal", type = "enum",
        options = ["Left Edge", "Normal", "Right Edge"]}],
    green_dangly)
```

Map kind defaults to `LEVEL` only (hazards do not appear on the
overworld, matching Clapper/Spike/Fire).

### 4.4 Tests: `tests/unit/test_hazard.gd`

Extend the existing instakill-family characterization with one new case
and a hitbox assertion:

- `test_green_dangly_stuff_instakills_on_contact()` — mirrors the
  Spike/Fire/Clapper cases: drain all health.
- `test_green_dangly_stuff_contact_area_is_bottom_half()` — instantiate,
  read `_area.get_child(0).shape.size`, assert `Vector2(64, 48)` and the
  CollisionShape2D's local position centers the rect in the lower half.
- `test_green_dangly_stuff_body_is_one_way_platform()` — assert the
  body's direct-child `CollisionShape2D` (distinct from the Area2D's
  shape) has `one_way_collision == true` and the root body has
  `collision_layer == 4`.

A separate addition to `test_episode.gd`:

- `test_green_dangly_stuff_registered_as_hazard_with_variant_schema()` —
  mirrors the spike test: `keen1.green_dangly_stuff` is registered, is a
  hazard, has the 3-option `variant` enum with default `Normal`.

## 5. Data Flow

1. Editor palette enumerates the registry and shows "Green Dangly Stuff"
   under Hazards.
2. Designer places the entity, optionally switches `variant` in the
   inspector; the choice persists in the level's `EntityDef.properties`.
3. At level load, `EntityRegistry.instantiate` creates the
   `GreenDanglyStuff` scene, calls `setup(type_id, props)`, which applies
   `EntityVariant` → only the matching variant's `AnimatedSprite2D` is
   visible.
4. `_ready()` builds the contact Area2D (bottom-half kill zone) and the
   one-way body shape; the entity is now solid-on-top and deadly-on-
   bottom.
5. Player contact from above lands on the platform; contact from below
   or the side enters the Area2D → `_on_body_entered` →
   `_handle_player()` → `_instakill()` → `Player.take_damage(health)` →
   `Player.died`.

## 6. Risk & Rollback

- **One-way on a CharacterBody2D root**: Godot 4.7 supports
  `CollisionShape2D.one_way_collision` on any `PhysicsBody2D`. If
  empirical testing reveals the entity body needs to be a
  `StaticBody2D` for one-way semantics to fire, the design falls back to
  a `StaticBody2D` child carrying the one-way shape (root stays
  `CharacterBody2D` for `Hazard`/`Entity` compatibility).
- **Kill-zone gap**: with `_KILL_HEIGHT = 48` px and a player collision
  box smaller than 48 px tall, a player on top of the tile cannot clip
  into the kill zone; verified by the hitbox assertion.
- **Rollback**: the change is additive — three new files plus one
  registration line and one test file. Reverting is a single commit.

## 7. Test Plan

| Test | Verifies |
|------|----------|
| `test_green_dangly_stuff_instakills_on_contact` | Instakill contract identical to Spike/Fire/Clapper |
| `test_green_dangly_stuff_contact_area_is_bottom_half` | Area2D shape = 64×48, centered on lower half |
| `test_green_dangly_stuff_body_is_one_way_platform` | `one_way_collision=true`, `collision_layer=4` |
| `test_green_dangly_stuff_registered_as_hazard_with_variant_schema` | Registry entry, category, 3-option `variant` enum default `Normal` |
| Existing suite | No regressions (run `./tests/run_all.sh`) |

## 8. Open Questions

None at spec time. The variant row-mapping (row 1 → Left Edge, row 2 →
Normal, row 3 → Right Edge) assumes the artist laid the sheet out
top-to-bottom in that order; if the `.aseprite` shows a different
ordering, swap the y-offsets in §4.1's table before implementing.
