# Blaster as Find-to-Own Global Inventory — Design Spec

**Date:** 2026-07-18
**Status:** Draft
**Parent spec:** `docs/superpowers/specs/2026-06-25-keen-reloaded-design.md`
**Related:**
- `docs/superpowers/specs/2026-07-15-pogo-stick-inventory-design.md` (global `Inventory` autoload this plan reuses)
- `docs/superpowers/specs/2026-07-18-door-keycard-entities-design.md` (intentionally per-level — contrasts with this plan)
**Engine:** Godot 4.7 (stable), GDScript

## 1. Overview

`ItemIDs.BLASTER` (`"keen1.blaster"`) is the inventory id gating Keen's shoot action. It is **technically** stored in the global `Inventory` autoload (persistent across levels + save/load, just like pogo), but `Player._ready()` auto-grants it on every spawn:

```gdscript
func _ready() -> void:
    add_to_group("player")
    Inventory.add_item(BLASTER)   # idempotent — re-granted every level
    ...
```

Because the `Player` node is freed + rebuilt on every level swap, the blaster is re-granted every time. Functionally this means Keen always has the weapon — there is no acquisition moment, no sense of carrying it across levels, and no way to lose or gate it. From the player's perspective the blaster behaves **per-level**, even though it sits in a global store.

This spec makes the blaster a **find-to-own** item, mirroring the pogo: Keen starts every episode without it, acquires it by picking up the existing `keen1.raygun` entity (already placed in `level1.tres`), and keeps it across levels and save/load cycles.

### Goals

| # | Goal |
|---|------|
| 1 | `Player._ready()` no longer auto-grants `BLASTER`. Keen starts every episode / new game without the weapon. |
| 2 | The existing `keen1.raygun` pickup entity grants `BLASTER` (idempotently) on first contact, in addition to its existing ammo grant. First pickup = weapon + ammo; later pickups = ammo only. |
| 3 | Shooting remains gated by `Inventory.has_item(BLASTER)` — no change to the gate, only to how the item is acquired. |
| 4 | Blaster ownership persists across levels, death, and save/load via the existing `Inventory` autoload + `GameManager.serialize()`/`deserialize()` seam. No new persistence code. |
| 5 | `clear_progress()` (new game / new pack) already clears inventory — so new games correctly start without the blaster. No change needed. |
| 6 | All existing shooting tests are updated to grant `BLASTER` explicitly in their setup, since it is no longer auto-granted. |

### Out of Scope

- **HUD inventory slot for blaster.** The overworld HUD inventory bar shows pogo + keen4 items as dimmable icons; the blaster is only shown as the icon next to the ammo counter. Adding a "blaster owned?" slot is a separate visual decision and not required for the mechanic to work. Deferred to a future plan if desired.
- **Distinct weapon vs. ammo entity types.** The existing `keen1.raygun` entity remains the single pickup; no new `keen1.blaster` entity type is introduced. (Original Keen 1 conflates these too: the raygun pickup is both weapon-source and ammo-source.)
- **Visual indication of "no weapon" on the HUD.** If Keen has no blaster, the ammo counter still renders `x0` next to a bright raygun icon. Polishing this (e.g. dimming the icon until owned) is deferred.
- **Acquisition cutscene / message overlay.** First pickup is silent except for the existing `pickup_ammo` SFX. A "raygun acquired" toast is a future polish item.
- **Old save migration.** Dev-era saves made before this change lack the blaster in their inventory payload (auto-grant masked it). On first load after this change, Keen will need to find a raygun pickup to shoot. Acceptable for the pre-release dev era.

## 2. Approach

**Decision: remove the auto-grant and have the existing `keen1.raygun` pickup entity grant the `BLASTER` inventory item on contact, ahead of its existing ammo grant.**

This is a four-line core change spread across two files:

1. **`src/runtime/player/player.gd`** — delete the `Inventory.add_item(BLASTER)` line in `_ready()`. The shoot gate (`if not Inventory.has_item(BLASTER): return`) at `player.gd:256` stays; it now does real work.
2. **`src/runtime/entities/ammo_pickup.gd`** — in `_handle_player`, call `Inventory.add_item(ItemIDs.BLASTER)` before `player.add_ammo(ammo_value)`. `Inventory.add_item` is idempotent and emits `item_collected` only on first acquisition — later pickups silently no-op the inventory write and still grant ammo.

No new entity type, no new autoload, no new persistence seam.

### Why this works

- `Inventory` is already the source of truth for cross-level owned items (pogo, future keen4 items). The blaster is already declared as `ItemIDs.BLASTER` and already queried by `shoot()`. Moving the acquisition from "auto-grant on spawn" to "grant on pickup" uses plumbing that all exists today.
- `keen1.raygun` is already placed in `level1.tres` and reachable in normal play, so the weapon is acquirable in the very first level — no softlock risk.
- `AmmoPickup._handle_player` is the existing contact-hook that grants ammo. Adding the inventory grant alongside it keeps the "raygun pickup = weapon + ammo" semantic in one place.
- `Inventory.add_item` emits `item_collected` on first acquisition, so any future HUD slot (deferred above) can wire to the existing signal without further pickup changes.

### Alternatives considered and rejected

- **New `keen1.blaster` entity type, distinct from `keen1.raygun`.** More flexibility (a level could place a weapon pickup without ammo), but it adds an entity registration, a scene, a test file, an episode.gd register call, and an editor palette entry — all for no concrete design need. Original Keen 1 does not distinguish them. Rejected for YAGNI.
- **Move ammo into `Inventory` too (count-based).** Tempting alignment, but `GameManager.ammo` already works, is serialized, is cleared on new game, and is consumed in exactly one place. Replacing it with `Inventory` count-semantics is a separate refactor with no payoff for this spec. Rejected.
- **Keep auto-grant but also grant on pickup (no-op).** Pointless — the auto-grant already covers every spawn. The whole point of the change is to *remove* the auto-grant.

## 3. Data Model

No schema changes. Existing state used as-is:

```gdscript
# src/core/inventory.gd — unchanged
var _items: Dictionary = {}  # item_id (String) -> true

# src/core/item_ids.gd — unchanged value, updated docstring
const BLASTER := "keen1.blaster"
```

`Inventory` remains presence-based: a key exists iff the item is owned. `BLASTER`'s presence in `_items` means "Keen has the weapon." Ammo remains a separate count on `GameManager.ammo` (unchanged).

### Save payload (unchanged shape)

```jsonc
// GameManager.serialize()
{
  "completed_levels": [...],
  "current_episode_id": "keen1",
  "current_scope_kind": "episode",
  "inventory": { "keen1.blaster": true },   // may also contain keen1.pogo, etc.
  "ammo": 5,
  "lives": 3
}
```

Old saves missing `keen1.blaster` in the `inventory` dict deserialize cleanly (Inventory just doesn't have the key → `has_item` returns false → Keen must find the raygun pickup). No migration code, no error.

## 4. Code Changes

### 4.1 `src/runtime/player/player.gd`

Delete the auto-grant in `_ready()`:

```gdscript
# Before
func _ready() -> void:
    add_to_group("player")
    Inventory.add_item(BLASTER)
    ammo = 0
    ammo_changed.emit(ammo)
    ...

# After
func _ready() -> void:
    add_to_group("player")
    ammo = 0
    ammo_changed.emit(ammo)
    ...
```

The shoot gate at line 256 stays unchanged:

```gdscript
func shoot() -> void:
    if not Inventory.has_item(BLASTER):
        return
    if ammo <= 0:
        return
    ...
```

Also update the `BLASTER` constant comment block (lines 20-22) from "Always owned (granted in _ready)" to reflect find-to-own via the raygun pickup.

### 4.2 `src/runtime/entities/ammo_pickup.gd`

Add the inventory grant at the top of `_handle_player`:

```gdscript
# Before
func _handle_player(player: Node) -> void:
    if player.has_method("add_ammo"):
        player.add_ammo(ammo_value)
    AudioManager.play_sfx("pickup_ammo")
    queue_free()

# After
func _handle_player(player: Node) -> void:
    Inventory.add_item(ItemIDs.BLASTER)
    if player.has_method("add_ammo"):
        player.add_ammo(ammo_value)
    AudioManager.play_sfx("pickup_ammo")
    queue_free()
```

`add_item` is idempotent: on a fresh game state, the first raygun contact emits `item_collected` and stores the key; subsequent contacts (and contacts after re-load) are silent no-ops on the inventory while still granting ammo. The SFX call is unchanged — players hear `pickup_ammo` on every contact, matching original Keen 1.

### 4.3 `src/core/item_ids.gd`

Update the BLASTER docstring to reflect acquisition:

```gdscript
# Before
## Raygun/blaster. Always owned (granted in Player._ready); gates shooting.
const BLASTER := "keen1.blaster"

# After
## Raygun/blaster. Find-to-own: granted by the keen1.raygun ammo pickup entity
## on first contact; gates shooting. Persists across levels + save/load via the
## Inventory autoload (like POGO). Cleared on new game by clear_progress().
const BLASTER := "keen1.blaster"
```

### 4.4 No changes to

- `src/core/inventory.gd` — already does what we need.
- `src/core/game_manager.gd` — `serialize`/`deserialize`/`clear_progress` already handle inventory round-trip and reset.
- `src/runtime/entities/pogo_stick.gd`, `ammo_pickup.tscn`, episode.gd registrations — all unaffected.
- `assets/levels/keen1/level1.tres` — already places a `keen1.raygun`; no relocation needed (verify reachable in manual check).

## 5. Tests

### 5.1 New and updated unit tests

| Suite | Change |
|---|---|
| `tests/unit/test_pickups.gd` | Existing `test_raygun_grants_ammo` extended: assert `Inventory.has_item(ItemIDs.BLASTER)` is true after contact. Add `test_raygun_pickup_idempotent_for_blaster`: two contacts (simulate by resetting the player node and re-triggering, or by directly calling `_handle_player` twice on a single pickup before `queue_free`) only emit `item_collected` once for `BLASTER`. Reset `Inventory` in `before_each`. |
| `tests/unit/test_player_shoot.gd` | `before_each` must now call `Inventory.add_item(ItemIDs.BLASTER)` explicitly. Existing shoot tests then pass unchanged. Add one new test: `test_shoot_no_blaster_no_projectile` — clear inventory, attempt shoot, assert no `Projectile` instantiated. |
| `tests/unit/test_inventory.gd` | Unchanged — already covers `add_item` idempotency and signal semantics generically. |
| `tests/unit/test_player.gd` | Any test that exercises shooting (if any) needs the same `Inventory.add_item(ItemIDs.BLASTER)` setup. Audit and patch. |
| `tests/unit/test_runtime_integration.gd`, `test_level_runtime.gd`, `test_completion.gd` | Audit: if any scenario asserts "player can shoot" without first providing a blaster, add the grant in setup. |
| `tests/unit/test_ammo_persistence.gd` | Verify setup; if it relies on shooting, grant blaster. If it only exercises `add_ammo`, no change. |

### 5.2 Regression coverage

- `test_inventory.gd` still passes (no behavior change in `Inventory`).
- `test_pogo_pickup.gd` still passes (pogo path unaffected).
- `test_game_manager_loop.gd` save/load round-trip still passes (inventory payload shape unchanged).
- `test_door.gd`, `test_keycard_pickup.gd` still pass (keycards are per-level on `Player`, not in global Inventory — unaffected).

### 5.3 Manual verification checklist

After implementation, run `make run-app` and confirm:

1. Start a new episode → enter level 1 → **cannot shoot** (no blaster). `shoot` input is silently ignored.
2. Walk to the `keen1.raygun` pickup → SFX plays → **can now shoot** (projectile fires, ammo decrements).
3. Die (re-enter level) → blaster still owned on respawn (global Inventory, not per-level).
4. Complete level 1 → return to overworld → re-enter another level → blaster still owned.
5. Save the game → quit → load → blaster still owned.
6. `make test` passes cleanly (`./tests/run_all.sh`).

## 6. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Tests that rely on auto-grant silently break | High | Low (mechanical fix) | Grep test suite for `shoot` and `Projectile` usage; patch each with explicit `Inventory.add_item(ItemIDs.BLASTER)` in setup. |
| Level 1 raygun placement unreachable → softlock | Low | High (player cannot progress if combat required) | Manual check during verification. If unreachable, relocate in `level1.tres` as part of the implementation plan. |
| Old dev-era saves regress (player loses weapon) | Certain | Low (pre-release) | Documented in Out of Scope. Acceptable. |
| HUD confusion: raygun icon bright but weapon not owned | Low | Cosmetic | Deferred to future HUD polish plan. |

## 7. Rollout

Single PR. No feature flag, no migration. Order of operations within the implementation plan:

1. Update test suites first (grant blaster explicitly in setup) — establishes the new contract before the source change.
2. Modify `ammo_pickup.gd` to grant `BLASTER`.
3. Modify `player.gd` to remove auto-grant + update comments.
4. Update `item_ids.gd` docstring.
5. Run `./tests/run_all.sh` — must pass clean.
6. Manual verification checklist (§5.3).
