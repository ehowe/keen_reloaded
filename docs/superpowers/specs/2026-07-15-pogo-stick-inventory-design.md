# Pogo Stick Entity + Persistent Inventory — Design Spec

**Date:** 2026-07-15
**Status:** Draft
**Parent spec:** `docs/superpowers/specs/2026-06-25-keen-reloaded-design.md`
**Related:**
- `docs/superpowers/specs/2026-07-05-map-kind-overworld-loop-design.md` (overworld vs level distinction)
- `docs/superpowers/specs/2026-07-13-plan6c-persistence-design.md` (save/load seam this plan extends)
**Engine:** Godot 4.7 (stable), GDScript

## 1. Overview

Keen's pogo mechanic is fully implemented (`player.gd`: toggle on `pogo` input, auto-bounce `pogo_bounce=1019`) but **always available from the start** — no pickup gating, no inventory. Nothing the player carries persists across levels: `score`, `ammo`, and `health` are plain instance variables on the `Player` node, which is re-instantiated from `.tscn` on every scene swap. The only cross-level state is `GameManager.completed_levels`.

This spec introduces a **pogo stick pickup entity** and the **persistent inventory system** behind it. Once collected, the pogo is owned across all levels and across save/load cycles. The pogo is unavailable on the overworld (Keen must be inside a level to use it) and unavailable until the pickup is found.

### Goals

| # | Goal |
|---|------|
| 1 | A new `Inventory` autoload provides a Dictionary-based, extensible item store (item_id → owned). |
| 2 | A new `PogoStick` entity grants `"pogo"` on pickup, following the existing `Collectible`/`AmmoPickup` contact pattern. |
| 3 | The pogo mechanic in `player.gd` is gated behind `Inventory.has_item("pogo")` — Keen starts every episode without the pogo and must find it. |
| 4 | Inventory state persists to disk via `GameManager.serialize()`/`deserialize()` → `SaveSystem` slot files (no new I/O). |
| 5 | The pogo pickup is placeable only on LEVEL-kind maps (editor palette hides it for overworld). The pogo toggle is processed only in LEVEL physics mode. |
| 6 | The inventory system is general enough that future items (ship parts, keys) reuse it without new autoloads. |

### Out of Scope

- **HUD icon for pogo ownership.** The `Inventory.item_collected` signal is emitted for future HUD wiring, but no HUD element is added in this plan.
- **Score bonus on pogo pickup.** Original Keen grants no score for the pogo; this plan matches that.
- **Ship parts / keys / other inventory items.** The autoload is ready for them, but no other items are implemented here. The existing `ship.gd` stub (`collect_part`) is left untouched — it migrates to `Inventory` in a future plan.
- **Pogo ammo / durability.** Once owned, pogo is infinite use.
- **Per-level pickup state.** If Keen dies and re-enters a level, the pogo pickup respawns (entities are spawned fresh each `LevelRuntime.build()`). Once owned, Keen keeps the pogo regardless — the flag lives in `Inventory`, not in the level.

## 2. Approach

**Decision: a dedicated `Inventory` autoload + a `PogoStick` entity extending `Entity`.**

`Inventory` is a new autoload singleton owning the item Dictionary. `GameManager.serialize()`/`deserialize()` delegate to `Inventory.serialize()`/`deserialize()`, so `SaveSystem` needs no changes — the inventory rides inside the existing `data` payload. `PogoStick` follows the established entity pattern: extends `Entity`, overrides `_handle_player(player)`, calls `Inventory.add_item("pogo")`, plays SFX, `queue_free()`.

Alternatives considered and rejected:

- **Inventory folded into `GameManager`:** fewer files, but `GameManager` already owns the state machine, transitions, episode discovery, input registration, and teleport resolution (416 lines). Adding item tracking bloats it and makes item logic harder to test in isolation. A dedicated autoload matches the existing pattern (`EntityRegistry`, `TileSetRegistry`, `AudioManager`, `SaveSystem` each own one concern).
- **Inventory on `Player`, shuttled via `GameManager` pending state:** the `Player` node is rebuilt every level, so state must round-trip through `GameManager` anyway (like `pending_player_spawn`). Redundant and more complex for no benefit.
- **A single `has_pogo` bool on `GameManager` instead of a Dictionary:** solves pogo only; the next item (ship parts/keys) redoes the persistence wiring. The Dictionary costs nothing extra and is forward-compatible.

### Why this works

The existing `serialize()`/`deserialize()` seam in `GameManager` (wired to disk by Plan 6c) was designed to carry arbitrary session state. The entity contact pattern (`Entity._handle_player`) is already used by `Collectible` (score) and `AmmoPickup` (ammo) — `PogoStick` is a direct analogue. The pogo input gate is a single `has_item` check at the toggle site; the bounce logic needs no change because `_pogo` can never become true without owning the item.

## 3. Data Model

### 3.1 Inventory state

```gdscript
var _items: Dictionary = {}  # item_id (String) -> true
```

Presence-based for v1: a key exists if and only if the item is owned. Values are `true` (reserved for future count-based items like ammo stacks). This keeps `serialize()` a clean Dictionary round-trip and makes `has_item()` an O(1) key lookup.

### 3.2 Serialized shape

Inventory nests inside the existing `GameManager.serialize()` payload:

```json
{
  "completed_levels": ["keen1.lvl1"],
  "current_episode_id": "keen1",
  "current_scope_kind": "episode",
  "inventory": { "pogo": true }
}
```

Old saves (pre-this-plan) lack the `inventory` key. `deserialize()` defaults to `{}`, so they load without error and yield an empty inventory (Keen must re-find the pogo — consistent with the era before the pogo existed).

### 3.3 Item IDs

Namespaced strings, episode-prefixed: `"keen1.pogo"`. This mirrors entity `type_id` namespacing and avoids collisions when future episodes add their own items.

## 4. `Inventory` Autoload

New autoload, registered in `project.godot` after `SaveSystem` (boot order: `PackLoader`, `GameManager`, `EntityRegistry`, `TileSetRegistry`, `AudioManager`, `SaveSystem`, `Inventory`). Source: `src/core/inventory.gd`.

### 4.1 Public API

```gdscript
class_name Inventory extends Node

signal item_collected(item_id: String)

var _items: Dictionary = {}  # item_id -> true

## True if the player owns (has collected) `item_id`.
func has_item(item_id: String) -> bool

## Mark `item_id` as collected. Idempotent. Emits item_collected (only on the
## first collection of a given id in a session, so HUD listeners do not re-fire
## on duplicate pickups — though the PogoStick queue_free()s on first contact).
func add_item(item_id: String)

## Remove `item_id` from the inventory (e.g. for dev cheats or future consuming).
func remove_item(item_id: String)

## Full reset. Called by GameManager.clear_progress() on new game / new pack.
func clear()

## Snapshot for save. Returns a deep copy of _items.
func serialize() -> Dictionary

## Restore from save data. Replaces _items entirely.
func deserialize(data: Dictionary)
```

### 4.2 Signal semantics

`item_collected` emits exactly once per `item_id` per session (guard: only emit if the key was not already present). This lets a future HUD show a "Pogo acquired!" toast without worrying about duplicate-fire edge cases. `add_item` is still idempotent (re-adding an owned item is a no-op beyond the guard check).

## 5. `PogoStick` Entity

### 5.1 Script — `src/runtime/entities/pogo_stick.gd`

```gdscript
class_name PogoStick extends Entity

const POGO_ITEM_ID := "keen1.pogo"

func _handle_player(player: Player) -> void:
    Inventory.add_item(POGO_ITEM_ID)
    AudioManager.play_sfx("pickup_score")
    queue_free()
```

Extends `Entity` (not `Collectible`) because the pogo grants an inventory item, not score. The base `Entity._build_contact()` builds the Area2D contact sensor (64×64, mask=player bit) and the fallback `ColorRect` visual if no `"Visual"` child sprite is present.

### 5.2 Scene — `src/runtime/entities/pogo_stick.tscn`

Root: `CharacterBody2D` with `pogo_stick.gd` attached. Child: a `ColorRect` named `"Visual"` (placeholder art — a distinct color, e.g. bright yellow/green, so it is identifiable in the editor). Swappable for a `Sprite2D` later without touching the script (`Entity._build_contact` uses an existing `"Visual"` child as-is).

### 5.3 Registration — `src/episodes/keen1/episode.gd`

```gdscript
registry.register("keen1.pogo_stick", EntityRegistry.CATEGORY_ITEM, "Pogo Stick", [],
    preload("res://src/runtime/entities/pogo_stick.tscn"))
```

No `map_kinds` argument → defaults to `[LevelData.MapKind.LEVEL]`. Consequences:
- Editor palette (`palette_panel.gd`) hides it when editing an overworld map — the pogo pickup cannot be placed on the overworld by design.
- `LevelRuntime._spawn_entities()` only spawns entities whose `map_kinds` include the active map's kind; a pogo placed in a level data file is skipped on overworld builds.

## 6. Pogo Mechanic Gating — `player.gd`

### 6.1 The gate

One line changes at the pogo toggle site (`player.gd`, currently line 164):

```gdscript
# Before:
if not _input_locked and Input.is_action_just_pressed("pogo"):
    _pogo = not _pogo

# After:
if not _input_locked and Inventory.has_item("keen1.pogo") and Input.is_action_just_pressed("pogo"):
    _pogo = not _pogo
```

### 6.2 Why only the toggle needs guarding

- **Bounce logic** (`if _pogo and on_floor ...`) never fires because `_pogo` can only become `true` via the guarded toggle.
- **Jump windup suppression** (`and not _pogo` at the jump-windup condition) stays correct: without the pogo, `_pogo` is always false, so normal jumps work normally.
- **Visual selection** (`_current_anim` returns `"Pogo"` when `_pogo` is true) naturally never selects the pogo sprite when the item is unowned.
- **OVERWORLD mode** never reaches this code — the pogo toggle lives inside the LEVEL-mode `_physics_process` branch, after the `if _mode == Mode.OVERWORLD: _physics_overworld(delta); return` early exit.

### 6.3 Overworld exclusion (triple-enforced)

1. Entity registered LEVEL-only → pickup cannot be placed/spawned on overworld.
2. Pogo toggle only processed in LEVEL physics branch → no pogo input on overworld.
3. Overworld mode ignores `pogo` input entirely (top-down walk only).

## 7. Persistence Wiring

### 7.1 `GameManager.serialize()`

```gdscript
func serialize() -> Dictionary:
    return {
        "completed_levels": completed_levels.duplicate(),
        "current_episode_id": current_episode_id,
        "current_scope_kind": current_scope_kind,
        "inventory": Inventory.serialize(),
    }
```

### 7.2 `GameManager.deserialize()`

```gdscript
func deserialize(data: Dictionary) -> void:
    completed_levels.clear()
    var loaded: Array = data.get("completed_levels", [])
    for id in loaded:
        completed_levels.append(String(id))
    current_episode_id = String(data.get("current_episode_id", ""))
    current_scope_kind = String(data.get("current_scope_kind", "episode"))
    Inventory.deserialize(data.get("inventory", {}))
```

The `data.get("inventory", {})` default ensures pre-this-plan saves load cleanly (empty inventory → Keen must find the pogo, consistent with the pre-pogo era).

### 7.3 `GameManager.clear_progress()`

Adds `Inventory.clear()` so a new game / new pack starts with an empty inventory:

```gdscript
func clear_progress() -> void:
    state = State.MENU
    completed_levels.clear()
    ...
    Inventory.clear()
```

`Inventory.clear()` is co-located with the existing `completed_levels.clear()` in `clear_progress()`. This means inventory clearing follows the **exact same** new-game semantics as level-completion progress: wherever `completed_levels` resets, inventory resets too. `start_pack()` (new pack game) calls `clear_progress()` and gets inventory clearing for free. `start_episode()` does not call `clear_progress()` today (pre-existing behavior — it also does not clear `completed_levels`); this plan introduces no new asymmetry. Any future fix to new-game clearing for episodes will automatically cover inventory because both resets live in the same method.

## 8. Editor Integration

No editor code changes required. The `PogoStick` entity flows through the existing palette/inspector/spawn pipeline:

- `EntityRegistry.get_palette_entries_for_kind(MapKind.LEVEL)` includes `keen1.pogo_stick` automatically (registered with default map_kinds).
- `palette_panel.gd` renders it in the "item" category when editing a LEVEL map; hides it for OVERWORLD maps.
- `inspector_panel.gd` renders an empty properties schema (no configurable properties — the pogo is a simple pickup).
- `LevelRuntime._spawn_entities()` → `EntityRegistry.instantiate("keen1.pogo_stick", pos, props)` → `PogoStick` node.

Level designers place the pogo in any level by selecting it from the palette and clicking a tile, exactly like placing a lollipop or ammo pickup.

## 9. Testing (GUT, headless)

Run via `./tests/run_all.sh` — must pass before commit.

| Area | Tests |
|---|---|
| `Inventory` core | `add_item` then `has_item` true; `remove_item` then false; `clear` empties; idempotent re-add; `serialize`/`deserialize` round-trip; deserialize replaces (not merges); empty-dict deserialize is a no-op. |
| `Inventory` signal | `item_collected` emits on first `add_item`; does not emit on duplicate add. |
| `PogoStick` pickup | `FakePlayer` stub (mirrors `test_pickups.gd`); contact → `Inventory.has_item("keen1.pogo")` true; node `is_queued_for_deletion`; SFX called. Reset inventory in `before_each`. |
| Pogo gate | Player pogo toggle is ignored when `Inventory` empty; toggles normally when `"keen1.pogo"` owned. (Tested via a minimal Player instance or by exercising the toggle condition; may require a thin seam if input mocking is heavy — see implementation plan.) |
| Persistence | `GameManager.serialize()` includes inventory; `deserialize()` restores it; `clear_progress()` clears inventory. Existing `test_game_manager_loop.gd` extended. |
| Registration | `keen1.pogo_stick` appears in `EntityRegistry.get_palette_entries_for_kind(LEVEL)` and not in `OVERWORLD`; `instantiate` returns a `PogoStick`. Extends `test_entity_registry_instantiate.gd`. |
| Old-save compat | Deserialize with a payload missing `"inventory"` → empty inventory, no error. |

## 10. Implementation Phasing

Each phase lands independently and is testable before the next begins. (Step detail belongs in the implementation plan, not here.)

1. **`Inventory` autoload** — `src/core/inventory.gd`, registered in `project.godot`. Full unit tests (`test_inventory.gd`). No wiring yet.
2. **Persistence wiring** — `GameManager.serialize()`/`deserialize()`/`clear_progress()` call `Inventory`. Extend `test_game_manager_loop.gd`. Verify existing save/load still passes.
3. **`PogoStick` entity** — `pogo_stick.gd` + `pogo_stick.tscn`; register in `keen1/episode.gd`. Pickup test (`test_pogo_pickup.gd`).
4. **Pogo gate** — one-line change in `player.gd`; pogo-gate test.
5. **End-to-end manual check** — place pogo in a test level via editor, confirm: (a) pogo input does nothing pre-pickup, (b) pickup grants pogo, (c) pogo works in this level, (d) exit + re-enter another level → pogo still owned, (e) overworld → no pogo input, (f) save + quit + load → pogo still owned.

## 11. Open Questions (non-blocking)

- **Visual art for the pogo pickup.** Placeholder `ColorRect` for now; real sprite swapped later via the scene's `"Visual"` child. No script change needed.
- **Distinct pickup SFX.** Reuses `pickup_score`; a dedicated `pickup_pogo` SFX can be added when audio assets exist (`AudioManager` registry driven by `AudioSampleBank` — see Plan 6a).
- **HUD pogo indicator.** Deferred; `item_collected` signal is the hook.
- **Ship-parts migration to `Inventory`.** `ship.gd`'s `collect_part()` stub stays as-is for now; a future plan migrates it to `Inventory.add_item("keen1.ship_part.<name>")`.
