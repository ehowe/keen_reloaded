# Door + Keycard Entities — Design Spec

**Date:** 2026-07-18
**Status:** Draft
**Parent spec:** `docs/superpowers/specs/2026-06-25-keen-reloaded-design.md`
**Related:**
- `docs/superpowers/specs/2026-07-15-pogo-stick-inventory-design.md` (global `Inventory` autoload — intentionally *not* used here)
- `docs/superpowers/specs/2026-07-08-entity-variant-properties-design.md` (`EntityVariant` enum-driven sprite visibility reused by both entities)
**Engine:** Godot 4.7 (stable), GDScript

## 1. Overview

The level roster needs **locked color doors** gated by matching **keycard pickups**. Four colors (red / blue / yellow / green) ship in the `Doors and Keycards.png` atlas; one door sprite + one keycard sprite per color. The door blocks the player until Keen carries the matching keycard, then plays a retract animation and disables its collision. The keycard is consumed per door (one keycard opens one door of its color).

Critical scope rule: **keycards are local to the level they are picked up in**. They must NOT ride the global `Inventory` autoload (which persists pogo/blaster across levels and across save/load). Storage is therefore per-`Player`-instance — `LevelRuntime` frees and rebuilds the `Player` node on every level swap, so the keycard state is naturally scoped to a single level playthrough.

### Goals

| # | Goal |
|---|------|
| 1 | A `Door` script attaches to the existing `Door.tscn` (4 variant sprites: Red/Blue/Yellow/Green). |
| 2 | A `Keycard` script + new `Keycard.tscn` (4 variant sprites from the same atlas) act as the matching pickups. |
| 3 | Both entities select their visible variant from an enum property `variant ∈ {red, blue, yellow, green}` via the existing `EntityVariant` helper — same pattern as `Spike.facing`. |
| 4 | Per-level keycard state lives on `Player` as a `color → count` Dictionary; isolated by level because `Player` is rebuilt per level. |
| 5 | Door is **always locked by default**; solid (blocks the player) until the player has the matching keycard. |
| 6 | On contact while the player holds a matching keycard, the door consumes one keycard, plays the `Retract` animation, then disables its `CollisionPolygon2D` and contact Area2D. |
| 7 | Keycard pickup grants one count of its color to the player, plays SFX, frees itself. |
| 8 | One keycard opens exactly one door of matching color (count-based). |
| 9 | Both entities pass the existing GUT test suite plus new unit tests for door open lifecycle, keycard pickup, and per-instance keycard isolation. |

### Out of Scope

- **HUD indicator for held keycards.** Player API exposes the data; no HUD element added this plan.
- **Door-open sound asset.** No `.wav` exists; `AudioManager.play_sfx("door_open")` will warn gracefully. The call site is wired so dropping the asset into `assets/audio/sfx/door_open.wav` later lights it up with no code change.
- **Door `starts_locked` designer toggle.** Door is always locked. A future plan can add an `@export` if level designers ever need unlocked doors.
- **Keycard respawn on death-retry.** Already automatic: `LevelRuntime` rebuilds every entity each entry, so the keycard reappears. Player's keycard dict also resets (new Player node).
- **Multi-color keycards / master keys.** Out of scope; one color per pickup.
- **Cross-episode keycard semantics.** Registered under `keen1.*` namespace only.

## 2. Approach

**Decision: `Player.keycards` Dictionary + `Door`/`Keycard` entities extending `Entity`, with `variant` enum property wired through `EntityVariant`.**

The global `Inventory` autoload is intentionally bypassed. It serializes through `GameManager.serialize()` and would carry keycards across levels and save/load — the opposite of the spec. Instead, keycard state lives as plain instance state on `Player`. `LevelRuntime._spawn_player` already frees the previous Player and instantiates a fresh one each build, so per-level isolation comes for free with no teardown code.

The four-color art already ships in `Doors and Keycards.png` (256×192): doors occupy the top half (row 0–127, 4 cells of 64×128), keycards occupy the bottom half (row 128–191, 4 cells of 64×64). The existing `Door.tscn` already wires the four door sprites and the `Retract` animation. A new `Keycard.tscn` mirrors that pattern for the four keycard sprites.

Alternatives considered and rejected:

- **Keycards in `Inventory` autoload, cleared on level swap.** Rejected — would wipe pogo/blaster on every level transition (those persist by design) unless we add a separate "session" vs "level" item namespace, which is more complex than a per-instance Dictionary with identical semantics.
- **New `LevelKeys` autoload cleared at `LevelRuntime.build`.** Adds an autoload + manual lifecycle wiring for what `Player` already gives us for free. Global access is not needed; only `Door` and `Keycard` ever query the state, and both reach the player through `_handle_player(player)`.
- **Keycard count on `LevelRuntime`.** Doors would need to walk up to the runtime node; couples a leaf entity to the scene root. Storing on `Player` keeps the entity contract local to the player (mirrors `add_score`, `take_damage`, `add_ammo`).
- **Door open = `queue_free()` the door.** Loses the visual "retracted door stays drawn" effect. The `Retract` animation slides the door sprite out of its clip mask — the intended effect is "drawn open", not "gone".
- **One keycard opens all matching doors (vs one-per-door).** Original Commander Keen 1 consumes a keycard per door; matches player expectation and gives level designers tighter tuning control.

### Why this works

The `Entity` base class already builds a contact `Area2D` (mask=player bit) and dispatches `_handle_player(player)` on body entry — the same seam used by `Collectible`, `AmmoPickup`, `PogoStick`, `ExitDoor`, and `Hazard`. `Door` and `Keycard` reuse it directly.

`EntityVariant.apply(type_id, properties, self)` already does enum-driven variant visibility — it walks descendants and shows the one whose name contains the chosen enum value. The `Door.tscn` sprites are already named `Red`/`Blue`/`Yellow`/`Green`; `Keycard.tscn` will use the same names. No changes to `EntityVariant` are needed.

The `Door.tscn` already ships the `AnimationPlayer` with a `Retract` animation (length 1.0s) that slides `DoorMask/Visual` from y=0 to y=128 — masked by the parent `Polygon2D`'s `clip_children=1`, the door visually slides downward out of view. `animation_finished` is the natural hook for disabling collision after the animation completes.

The only subtlety is the door's collision layer. `Entity._ready()` sets `collision_layer = 8` (items bit). The player's `collision_mask = 4` (tiles bit only), so items-layer bodies do not physically block the player. `Door._ready()` overrides `collision_layer = 4` (tiles bit) so the door's `CollisionPolygon2D` actually blocks Keen — matching the original game's solid-door behavior. Pickups (lollipop, ammo, etc.) stay on items layer because they should be walked through; doors are the exception.

## 3. Data Model

### 3.1 Keycard state — `Player.keycards`

```gdscript
var keycards: Dictionary = {}  # color (String) -> count (int)
```

Presence = owned. Count supports the one-keycard-per-door consumption rule (a future "3 keys open one door" variant needs no API change).

### 3.2 Variant identification

Both entities carry a `variant: String` property populated by `Entity.setup()` from the registered schema (default `"red"`). The value is one of `"red"`, `"blue"`, `"yellow"`, `"green"` — matched case-insensitively by `EntityVariant` to the descendant sprite whose name contains the value (e.g. `"red"` → matches the `Red` sprite).

Door and keycard "match" iff their `variant` strings are equal. No separate ID system; the color IS the matching key.

### 3.3 Serialization

None. `Player` is rebuilt per level and `Player.serialize()` is not part of the save/load contract (only `GameManager` round-trips through `SaveSystem`). Keycards correctly vanish on death-retry, on level exit, and on save/load — exactly the spec.

## 4. Player Changes — `src/runtime/player/player.gd`

### 4.1 New state + public API

```gdscript
## Per-level keycard counts. color (String) -> count (int). Cleared automatically:
## LevelRuntime frees and rebuilds the Player node on every level swap, so this
## Dictionary never crosses levels.
var keycards: Dictionary = {}


## True if the player holds at least one keycard of `color`.
func has_keycard(color: String) -> bool:
    return int(keycards.get(color, 0)) > 0


## Grant one keycard of `color`. Adds to the existing count if any.
func add_keycard(color: String) -> void:
    keycards[color] = int(keycards.get(color, 0)) + 1


## Decrement the `color` count by 1 (floors at 0). Returns true if a keycard
## was actually consumed (i.e. the player had at least one).
func consume_keycard(color: String) -> bool:
    if not has_keycard(color):
        return false
    keycards[color] = int(keycards[color]) - 1
    return true
```

### 4.2 Why no `clear_keycards()` method

The Dictionary starts empty on every new `Player` instance. No reset path is needed. If the level designer wants to strip mid-level keycards, they can use `player.keycards.clear()` directly — no wrapper.

### 4.3 Save/load impact

None. The existing `GameManager.serialize()`/`deserialize()` does not touch `Player` instance vars. `keycards` correctly resets on every level entry.

## 5. `Door` Entity — `src/runtime/entities/door.gd`

### 5.1 Script

```gdscript
class_name Door
extends Entity
## Color-locked door. Solid (collision on tiles bit) until the player carries a
## matching keycard; on contact the door consumes one keycard, plays "Retract",
## then disables both its CollisionPolygon2D and contact Area2D so the door
## stays open and cannot refire. Variant sprite is selected via EntityVariant.


var variant: String = "red"
var _opened: bool = false


func setup(p_type_id: String, p_props: Dictionary) -> void:
    super(p_type_id, p_props)
    EntityVariant.apply(type_id, properties, self)


func _ready() -> void:
    super()
    # Door sits on the tiles layer (bit 4 = value 4) so its CollisionPolygon2D
    # actually blocks the player (player.collision_mask = 4). Default items bit
    # (8) would let the player walk through.
    collision_layer = 4
    collision_mask = 0


func _handle_player(player: Node) -> void:
    if _opened:
        return
    if not player.has_method("has_keycard") or not player.has_keycard(variant):
        return  # Locked — player bumped, door stays solid.
    _opened = true
    player.consume_keycard(variant)
    AudioManager.play_sfx("door_open")  # warns gracefully until asset exists
    var anim := $AnimationPlayer as AnimationPlayer
    if anim == null:
        _disable_collision()
        return
    anim.animation_finished.connect(_on_retract_finished)
    anim.play("Retract")


func _on_retract_finished(_anim_name: String) -> void:
    _disable_collision()


func _disable_collision() -> void:
    var poly := get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
    if poly != null:
        poly.disabled = true
    if _area != null:
        _area.monitoring = false
```

### 5.2 Scene wiring — existing `Door.tscn`

No structural change. The script attaches at the root `CharacterBody2D`. The scene already provides:

- `DoorMask` (Polygon2D, `clip_children = 1`) → masks the retracting sprite
- `DoorMask/Visual` containing `Red` / `Blue` / `Yellow` / `Green` `Sprite2D` children — `EntityVariant` toggles `visible` based on `variant`
- `CollisionPolygon2D` — disabled after retract
- `AnimationPlayer` with `Retract` (length 1.0s, slides `DoorMask/Visual:position:y` 0 → 128)

One concern: `Entity._build_contact()` looks for a direct child named `"Visual"` and falls back to a `ColorRect` if absent. The Door scene has no direct `"Visual"` child (its sprites are nested under `DoorMask/Visual`), so `_build_contact` would add a stray `ColorRect` over the door. The fix: name the placeholder `ColorRect` should be skipped for Door. Cleanest is to override `_build_contact()` on Door to skip the fallback (still build the Area2D contact sensor). Alternative: add a do-nothing empty `Visual` node as a direct child to satisfy the check. Override preferred — avoids changing the scene.

```gdscript
func _build_contact() -> void:
    # Skip Entity's ColorRect fallback — the door's art lives at DoorMask/Visual
    # and we don't want a ColorRect drawn over it.
    _area = Area2D.new()
    _area.name = "Area2D"
    _area.monitoring = true
    _area.collision_layer = 0
    _area.collision_mask = 1  # player bit
    var shape := CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = Vector2(TILE, TILE)
    shape.shape = rect
    _area.add_child(shape)
    _area.body_entered.connect(_on_body_entered)
    add_child(_area)
```

(Extracted to a helper or factored into Entity as a `_skip_visual_fallback` flag — left to the implementation plan.)

### 5.3 Idempotency

`_opened` guards re-entry: if the Area2D fires twice before `monitoring` flips off (e.g. overlapping bodies), the second call returns immediately. After `_disable_collision()` flips `_area.monitoring = false`, the Area2D stops firing entirely.

### 5.4 Edge case: missing keycard method

If `_handle_player` is called with a body that lacks `has_keycard` (test stub or non-Player body in the player group), the door returns early. The body stays blocked by physics — safe.

## 6. `Keycard` Entity — `src/runtime/entities/keycard.gd` + `keycard.tscn`

### 6.1 Script

```gdscript
class_name Keycard
extends Entity
## Color keycard pickup. Grants one count of its variant color to the player on
## contact, plays pickup SFX, then frees itself. Variant sprite selected via
## EntityVariant (mirrors Door's variant system).


var variant: String = "red"


func setup(p_type_id: String, p_props: Dictionary) -> void:
    super(p_type_id, p_props)
    EntityVariant.apply(type_id, properties, self)


func _handle_player(player: Node) -> void:
    if player.has_method("add_keycard"):
        player.add_keycard(variant)
    AudioManager.play_sfx("pickup_score")
    queue_free()
```

### 6.2 Scene — new `Keycard.tscn`

Root: `CharacterBody2D` with `keycard.gd` attached. Children:

- `Visual` (Node2D, the wrapper `EntityVariant` walks into)
  - `Red` (Sprite2D, `AtlasTexture` region `Rect2(0, 128, 64, 64)`)
  - `Blue` (Sprite2D, region `Rect2(64, 128, 64, 64)`)
  - `Yellow` (Sprite2D, region `Rect2(128, 128, 64, 64)`)
  - `Green` (Sprite2D, region `Rect2(192, 128, 64, 64)`)

All four sprites hidden by default except `Red` (mirrors `Door.tscn`'s convention); `EntityVariant.apply` corrects visibility based on the runtime `variant` property.

Note: regions specified at standard 64-px stride along x; y=128 selects the keycard row (door row is 0–127). Implementation plan verifies the exact region against the actual atlas before committing — `Doors and Keycards.png` source is 256×192, so four 64-wide cells per row fit exactly.

### 6.3 Pickup contract

`Keycard` extends `Entity` directly (not `Collectible`) because keycards do not award score — original Keen 1 keycards grant no score. `AudioManager.play_sfx("pickup_score")` is reused as the pickup cue (same as `PogoStick`); a dedicated `pickup_keycard` SFX is a future asset swap with no code change.

## 7. Registration — `src/episodes/keen1/episode.gd`

Appended to `Keen1Episode.register_entities()`:

```gdscript
var door := preload("res://src/runtime/entities/Door.tscn")
registry.register("keen1.door", registry.CATEGORY_SPECIAL, "Door",
    [{name = "variant", default = "red", type = "enum",
      options = ["red", "blue", "yellow", "green"]}],
    door)
var keycard := preload("res://src/runtime/entities/Keycard.tscn")
registry.register("keen1.keycard", registry.CATEGORY_ITEM, "Keycard",
    [{name = "variant", default = "red", type = "enum",
      options = ["red", "blue", "yellow", "green"]}],
    keycard)
```

No `map_kinds` argument → defaults to `[LevelData.MapKind.LEVEL]`. Doors and keycards are LEVEL-only entities (the overworld uses level entrances/teleporters, not color-key doors). Editor palette will hide them on overworld maps.

`keen1.door` lands in the **special** category (alongside `exit_door`, `level_entrance`, `teleporter`, `message`); `keen1.keycard` lands in **item** (alongside pickups).

## 8. Editor Integration

No editor code changes. Both entities flow through the existing palette/inspector/spawn pipeline:

- `palette_panel.gd` lists `keen1.door` under "special" and `keen1.keycard` under "item" when editing a LEVEL map; hides both for OVERWORLD.
- `inspector_panel.gd` renders the `variant` enum as a dropdown (the existing enum-property UI used by `Spike.facing` and `LevelEntrance.variant`).
- `LevelRuntime._spawn_entities()` calls `EntityRegistry.instantiate("keen1.door", pos, props)` → `Door` node, `setup()` applies the variant.

Level designers place a door by selecting "Door" from the palette, clicking a tile, and choosing the color in the inspector. Same flow for keycards.

## 9. Testing (GUT, headless)

Run via `./tests/run_all.sh` — must pass before commit. New test files:

| File | Tests |
|---|---|
| `tests/unit/test_player_keycards.gd` | `add_keycard` increments; `has_keycard` true after add, false before; `has_keycard` false after consume to zero; `consume_keycard` returns false when empty; `consume_keycard` returns true and decrements when non-zero; counts per-color are independent; fresh `Player` instance starts with empty `keycards` (per-level isolation). |
| `tests/unit/test_keycard_pickup.gd` | `FakePlayer` stub in `player` group with `add_keycard` method; contact → `add_keycard(variant)` called with the right color; node `is_queued_for_deletion`; SFX called; variant propagation (Keycard with `variant=blue` grants `"blue"`). Mirrors `test_pogo_pickup.gd` structure. |
| `tests/unit/test_door.gd` | Door registered as `keen1.door`; `variant` schema has the 4 options; `collision_layer == 4` after `_ready` (tiles bit, blocks player); default state solid; `_handle_player` with empty keycards → door unchanged (still locked); with matching keycard → `_opened` true, `consume_keycard` called, `Retract` animation played; after `animation_finished` → `CollisionPolygon2D.disabled == true` and `_area.monitoring == false`; non-matching color → still locked; second contact after open → no-op (idempotent). |

Existing test suites (`test_inventory.gd`, `test_pogo_pickup.gd`, `test_entity_registry_*`, `test_entity_variant.gd`) must still pass unchanged — confirms no regression to global inventory or variant system.

The `test_door.gd` AnimationPlayer lifecycle test runs the animation manually: instantiate Door, call `_handle_player` with a fake player that has matching keycards, advance the AnimationPlayer to completion (either `play` + `advance` or directly emit `animation_finished`), assert collision disabled. Tests do not need a real rendered frame.

## 10. Implementation Phasing

Each phase lands independently and is testable before the next begins.

1. **Player keycard state** — add `keycards` Dictionary + `add_keycard` / `has_keycard` / `consume_keycard`. Land `test_player_keycards.gd`. No wiring yet; existing player tests must still pass.
2. **`Keycard` entity** — `keycard.gd` + `Keycard.tscn`; register in `keen1/episode.gd`. Land `test_keycard_pickup.gd`. Verify variant sprite visibility via existing `EntityVariant` tests still passing.
3. **`Door` entity** — `door.gd` (with `_build_contact` override); attach to existing `Door.tscn`; register in `keen1/episode.gd`. Land `test_door.gd`. Verify collision layer = tiles bit; verify animation lifecycle disables collision.
4. **End-to-end manual check** — place a red door + red keycard in a test level via editor; confirm: (a) door blocks Keen without keycard, (b) pickup grants the keycard (no HUD yet — verify by opening the door), (c) door plays `Retract` and disables collision on contact, (d) non-matching color door stays solid, (e) exit + re-enter level → all doors/keycards reset, (f) global inventory (pogo) still persists across the swap.

## 11. Open Questions (non-blocking)

- **`door_open.wav` SFX asset.** Not provided; call site is wired with graceful warning. Drop the file in `assets/audio/sfx/` later to activate.
- **HUD keycard indicator.** Player exposes the data; no HUD element added this plan. The `Entity` `player_touched` signal and a future `Player.keycards_changed` signal are the hooks.
- **`_build_contact` ColorRect fallback override.** Implementation plan decides between (a) a Door-local `_build_contact` override duplicating the Area2D build, or (b) a small refactor of `Entity._build_contact` to take a `_skip_visual_fallback` flag. (a) is local and lower-risk; (b) is cleaner if another non-Visual entity appears.
- **Atlas region verification.** The 64×64 keycard cells are inferred from the 256×192 atlas dimensions; the implementation plan should visually confirm the regions against the source `.aseprite` before committing `Keycard.tscn`.
