# Battery Collectible — Design

**Date:** 2026-07-18
**Status:** Approved (verbal)
**Scope:** Add `keen1.battery` level pickup that grants the existing global-inventory battery slot; wire `Ship` placeholder to read `Inventory`.

## Context

The HUD already renders a battery icon in the overworld inventory bar (keys on a raw
`"keen4.battery"` string, dims until owned). The `Ship` entity has a documented
placeholder holding session-only ship-parts state, awaiting a "real inventory".
Neither is wired to an actual pickup. This spec closes that loop for the battery
only; other ship parts (joystick, vacuum, everclear) remain forward-declarations.

## Decisions

| Decision | Choice | Reason |
|---|---|---|
| Episode placement | Register in `keen1` (only existing episode) | User: "each episode will have ship parts" — start with keen1 |
| Item ID | `keen1.battery` (per-episode) | Matches existing `ItemIDs.POGO = "keen1.pogo"` convention |
| Sprite | Temporary placeholder ColorRect | Supplied by `Entity._build_contact()` fallback via `_color()` override |
| Score | None — inventory-only | Mirrors pogo precedent; battery is a quest item |
| Ship wiring | Replace session dict with `Inventory.has_item()` reads | Closes the documented placeholder gap |
| HUD | Rename all four `keen4.*` slots to `keen1.*` via `ItemIDs.*` | Namespace consistency |
| Sound | Reuse existing `pickup_score` sfx | Pogo does the same; no new asset |

## Architecture

Battery pickup = inventory-granting entity, same tier as `PogoStick`. Picked up
once per save (idempotent via `Inventory.add_item`). Persisted across levels via
existing `GameManager.serialize()` path. Boolean ownership — no count, no score.

### Components

**1. `src/core/item_ids.gd`** — add 4 constants:

```gdscript
const BATTERY   := "keen1.battery"
const JOYSTICK  := "keen1.joystick"   # placeholder, no granter yet
const VACUUM    := "keen1.vacuum"     # placeholder
const EVERCLEAR := "keen1.everclear"  # placeholder
```

**2. `src/runtime/entities/battery_pickup.gd`** (new) — mirrors `pogo_stick.gd`:

```gdscript
class_name BatteryPickup
extends Entity

func _handle_player(_player: Node) -> void:
    Inventory.add_item(ItemIDs.BATTERY)
    AudioManager.play_sfx("pickup_score")
    queue_free()

func _color() -> Color:
    return Color(0.18, 0.45, 0.95, 0.8)  # matches HUD battery blue
```

No `Visual` child required — `Entity._build_contact()` builds a `ColorRect`
fallback using `_color()`.

**3. `src/runtime/entities/battery_pickup.tscn`** (new) — minimal scene:

```
[gd_scene format=3 uid="uid://..."]
[ext_resource type="Script" path="res://src/runtime/entities/battery_pickup.gd" id="1_battery"]
[node name="BatteryPickup" type="CharacterBody2D"]
script = ExtResource("1_battery")
```

**4. `src/episodes/keen1/episode.gd`** — add registration:

```gdscript
var battery := preload("res://src/runtime/entities/battery_pickup.tscn")
registry.register("keen1.battery", registry.CATEGORY_ITEM, "Battery", [], battery)
```

**5. `src/ui/hud.gd`** — replace raw `"keen4.*"` strings with `ItemIDs.*`
constants in `OVERWORLD_ITEM_TEX` and `OVERWORLD_ITEM_ORDER`. Behavior
unchanged: pickup emits `Inventory.item_collected("keen1.battery")`, existing
`_on_item_collected` handler brightens the icon.

**6. `src/runtime/entities/ship.gd`** — wire to Inventory:

```gdscript
const REQUIRED_PARTS := [
    {name = "Battery",              id = ItemIDs.BATTERY},
    {name = "Joystick",             id = ItemIDs.JOYSTICK},
    {name = "Vacuum Cleaner",       id = ItemIDs.VACUUM},
    {name = "Whisky Bottle (Fuel)", id = ItemIDs.EVERCLEAR},
]

func collected_count() -> int:
    var n := 0
    for part in REQUIRED_PARTS:
        if Inventory.has_item(part.id):
            n += 1
    return n

func is_part_collected(part_name: String) -> bool:
    for part in REQUIRED_PARTS:
        if part.name == part_name:
            return Inventory.has_item(part.id)
    return false
```

- Remove `_collected` session dict and `collect_part()` — inventory is now the
  single source of truth.
- Update docstring to drop "placeholder" language.
- `progress_requested` signal payload unchanged (`(collected, total, parts)`)
  so existing consumers and tests continue to work.

## Data Flow

```
Player body_entered → Entity._on_body_entered → _handle_player
  → Inventory.add_item("keen1.battery")
      → _items["keen1.battery"] = true
      → item_collected.emit("keen1.battery")
          → HUD._on_item_collected → set_item_owned → icon brightens
  → AudioManager.play_sfx("pickup_score")
  → queue_free()

Ship.attempt_show_progress (overworld interact)
  → collected_count() iterates REQUIRED_PARTS, counts Inventory.has_item
  → progress_requested.emit(n, total, parts)
```

## Persistence

Already handled by existing infrastructure:
- `GameManager.serialize()` includes `"inventory": Inventory.serialize()`.
- `GameManager.deserialize()` restores it.
- `GameManager.clear_progress()` calls `Inventory.clear()`.

No new save/load code required.

## Error Handling

- `Inventory.add_item` is idempotent; re-pickup is a silent no-op (pickup node
  is freed on first contact anyway).
- `AudioManager.play_sfx("pickup_score")` — stream exists.
- `Ship.is_part_collected("Unknown")` → returns `false`.

## Testing (GUT)

Following existing patterns in `test_pogo_pickup.gd` and `test_ship.gd`:

- **`test_battery_pickup.gd`** (new):
  - Pickup → player contact → `Inventory.has_item(ItemIDs.BATTERY)` is true.
  - Pickup is queued for deletion after contact.
  - Registration: `EntityRegistry.get_entry("keen1.battery")` has category
    `"item"`, available on LEVEL maps.
  - Instantiation: `EntityRegistry.instantiate("keen1.battery", …)` returns a
    `BatteryPickup` with `type_id == "keen1.battery"` and in group `"entity"`.

- **`test_ship.gd`** (extend):
  - `collected_count()` returns 0 with empty inventory, 1 after
    `Inventory.add_item(ItemIDs.BATTERY)`.
  - `is_part_collected("Battery")` reflects `Inventory` state.
  - `is_part_collected("Unknown")` returns `false`.
  - Existing proximity/interact tests unchanged (signal payload preserved).

- **`test_inventory.gd`**: no new tests — battery id rides existing generic
  `add_item`/`has_item` paths.

- **`test_hud.gd`**: adjust any references that hard-coded `"keen4.battery"` to
  `ItemIDs.BATTERY`; behavior tests (icon brightens on collect) unchanged.

## Out of Scope

- Joystick / vacuum / everclear pickups (constants only; no scenes or scripts).
- Per-episode ship-parts metadata in the `Episode` base class.
- Battery pickup sprite art (placeholder ColorRect per decision).
- New sound effect (reuses `pickup_score`).
- Level placement in shipped keen1 levels (level designer's responsibility;
  tests cover registration + behavior).
