# Teleporter Overworld/Level Entity — Design Spec

**Date:** 2026-07-09
**Status:** Approved
**Engine:** Godot 4.7 (stable)
**Language:** GDScript
**Plan phase:** Plan 3 (Runtime core) extension

## 1. Overview

Add a **Teleporter** entity — a special, interactable node that moves the player to a destination teleporter when the player stands near it and presses `interact`. Teleporters are **directional** (each has exactly one destination); a two-way link is simply two teleporters pointing at each other.

Teleporters are unique among existing entities in two ways:

1. **They work in both maps.** Registered with `map_kinds = [LEVEL, OVERWORLD]` — the first gameplay entity (besides `player_spawn`) valid in both. A teleporter may sit in the overworld *or* be hidden inside a level.
2. **Cross-map links.** A teleporter's destination may live in a *different* `LevelData` than the teleporter itself (e.g. overworld ↔ hidden inside a level).

### Core Requirements

| # | Requirement |
|---|-------------|
| 1 | Directional: each teleporter has exactly one destination; bidirectional = a pair pointing at each other |
| 2 | Destination references another teleporter via stable string IDs (not tile coords or array index) |
| 3 | Trigger = proximity + `interact` press (consistent with `LevelEntrance` / `Ship`) |
| 4 | Valid in both LEVEL and OVERWORLD maps |
| 5 | Cross-map: destination may be in a different `LevelData` |
| 6 | No anti-bounce logic needed (interact-based trigger does not auto-re-fire) |

### Out of Scope

- Enum/dropdown destination pickers in the editor (free-string fields for now; see Approach C in brainstorm)
- Real art / animation (placeholder color rect; art pipeline is Plan 4)
- Globally-unique teleporter_id resolution across all levels (Approach B — rejected)
- Multiple destinations per teleporter

## 2. Destination Reference Model — Approach A (Compound String Refs)

Each teleporter carries three string properties:

| Property | Type | Description |
|----------|------|-------------|
| `teleporter_id` | `String` | This teleporter's own stable ID. Must be unique within its `LevelData`. |
| `destination_level_id` | `String` | `level_id` of the map containing the destination teleporter. |
| `destination_teleporter_id` | `String` | `teleporter_id` of the destination teleporter within that map. |

**Why:** mirrors the existing `LevelEntrance.target_level_id` free-string pattern exactly. The inspector auto-builds `LineEdit` controls from the registry schema. Resolution is a single-level scan, not a global search.

**Bidirectional example:** teleporter `ow_north` (in overworld `keen1`) sets `destination_level_id="keen1_lvl3"`, `destination_teleporter_id="lvl3_secret"`. The `lvl3_secret` teleporter sets `destination_level_id="keen1"` (the overworld's level_id), `destination_teleporter_id="ow_north"`. The pair now teleports both ways.

## 3. Registration

- **type_id:** `keen1.teleporter` (namespaced per convention; generic enough to lift to a shared/core episode later if reused).
- **category:** `SPECIAL` (extends the `Special` family conceptually; implemented as its own `Node2D` like `LevelEntrance`/`Ship`).
- **map_kinds:** `[LevelData.MapKind.LEVEL, LevelData.MapKind.OVERWORLD]`.
- **scene:** `res://src/runtime/entities/teleporter.tscn` wrapping `teleporter.gd`.
- **schema:** three `string`-typed entries (no enum options), so the inspector builds `LineEdit`s and the editor's instance-key fallback never triggers.

Registered in `src/episodes/keen1/episode.gd::register_entities()`.

## 4. Runtime Node — `teleporter.gd`

`class_name Teleporter extends Node2D`. Structurally mirrors `LevelEntrance`:

- `setup(type_id, props)` — reads `teleporter_id`, `destination_level_id`, `destination_teleporter_id` from props.
- `_ready()` — builds a proximity `Area2D` (mask = player bit, `PROXIMITY_RADIUS = 1` → 3×3 zone) and a placeholder `ColorRect` visual (color distinct from other specials, e.g. magenta).
- `_process()` — calls `attempt_teleport(Input.is_action_just_pressed("interact"))`.
- `attempt_teleport(interact_pressed) -> bool` — starts the **departure** sequence when nearby AND interact pressed AND both destination fields are non-empty AND idle. Returns true on start; `teleport_requested` emits AFTER the source animation finishes (not from this call). Interact flag is a parameter for deterministic tests.
- `play_arrival(player)` — drives the **arrival** sequence; called by `LevelRuntime` after a teleport-built scene spawn.
- Test seams `_set_nearby_for_test(v)`, `_set_player_for_test(p)`.

```gdscript
signal teleport_requested(destination_level_id: String, destination_teleporter_id: String)
signal arrival_finished()
```

### 4.1 Visual / Animation Sequence

The scene carries a static `Visual` (Sprite2D, shown when idle) and an `AnimatedSprite2D` (hidden when idle, plays the `default` animation once on activation). On interact, the full sequence is:

1. **Depart (source):** hide + freeze the player (`visible=false`, `process_mode=DISABLED`), hide `Visual`, play source anim once.
2. On anim finish → emit `teleport_requested` → `GameManager.teleport` rebuilds the runtime scene.
3. **Arrive (destination):** new scene builds; `GameManager.pending_teleport_arrival_id` tells `LevelRuntime` which teleporter just arrived on. `LevelRuntime` calls `play_arrival(player)` → hide + freeze player, play destination anim once.
4. On anim finish → restore `Visual`, show + unfreeze player, emit `arrival_finished`.

Because `GameManager.teleport` **always rebuilds the scene** (even same-map), same-map and cross-map links follow the identical path — "both sides animate one loop" falls out naturally (departure anim in the old scene, arrival anim in the new scene). The player is hidden+frozen for the whole transit, so no drift/gravity and no visible "jump".

## 5. LevelRuntime Wiring

`LevelRuntime._spawn_entities()` adds a branch (alongside the existing `LevelEntrance` and `level_completed` branches):

```gdscript
if node is Teleporter:
    (node as Teleporter).teleport_requested.connect(_on_teleport_requested)
```

`_on_teleport_requested(dest_level_id, dest_teleporter_id)` forwards to `GameManager.teleport(dest_level_id, dest_teleporter_id)` (null-guarded for headless tests where `GameManager` may be absent).

After `build()`, `_ready()` also checks `GameManager.pending_teleport_arrival_id`; if set, it finds the matching spawned `Teleporter` and calls `play_arrival(player)` to play the destination-side animation (consuming the flag).

## 6. GameManager.teleport()

New method, modeled on `enter_level` / `enter_level_no_scene_swap`:

```gdscript
func teleport(destination_level_id: String, destination_teleporter_id: String) -> void:
    teleport_no_scene_swap(destination_level_id, destination_teleporter_id)
    get_tree().change_scene_to_packed(RUNTIME_SCENE)
```

`teleport_no_scene_swap` (the headless-testable core):

1. `lvl := get_level_by_id(destination_level_id)` — if null, `push_warning` + return (dangling level ref, no-op).
2. Scan `lvl.entities` for an `EntityDef` whose `type` is a teleporter type AND `properties.teleporter_id == destination_teleporter_id`. Helper `_find_teleporter_tile(level, teleporter_id) -> Vector2i` returns the tile, or `Vector2i(-1, -1)` if not found.
3. If not found, `push_warning` + return (dangling teleporter ref, no-op).
4. Set `pending_level = lvl`, `pending_player_spawn = <dest tile>`, `pending_teleport_arrival_id = destination_teleporter_id`, `current_level = lvl if lvl.map_kind == LEVEL else null`, `state = LEVEL if lvl.map_kind == LEVEL else OVERWORLD`.
5. Leave `current_overworld` untouched when teleporting within/to a level; leave it untouched when teleporting within the overworld.

`pending_teleport_arrival_id` is reset to `""` by `clear_progress()` and on every non-teleport scene-swap path (`enter_level`, `complete_level`, `fail_level`) so a stale flag can't trigger a spurious arrival animation.

**Self-teleport guard:** if `destination_level_id == current_level/overworld level_id` and `destination_teleporter_id == this teleporter's own id`, resolution simply returns the current tile — harmless, no special-case needed (the player ends up where they already are).

**Map-kind detection:** "is `lvl` the overworld?" is answered by `lvl.map_kind == LevelData.MapKind.OVERWORLD` (not by identity with `current_overworld`), so cross-pack/episode resolution stays robust.

## 7. Precondition & Limitations

- **Destination level must be registered** in `GameManager._levels_by_id` for `get_level_by_id` to resolve it. Today this is true for: the overworld (registered on episode/pack boot) and all levels in a custom **pack** (`start_pack` registers every pack level). It is **not** true for bundled-episode individual levels (`start_episode` registers only the overworld).
- This is the **same precondition** `LevelEntrance.enter_level` already relies on — the teleporter does not make it worse. Bundled-episode level registration is a separate, pre-existing gap (tracked under Plan 4 / episode boot) and is out of scope here.
- Practical effect: cross-map teleport works fully for packs and for overworld↔overworld links; teleporting *into* a bundled-episode level requires that level to be registered first.

## 8. Edge Cases & Validation

| Case | Behavior |
|------|----------|
| `destination_level_id` empty | `attempt_teleport` returns false, no emit |
| `destination_teleporter_id` empty | `attempt_teleport` returns false, no emit |
| Destination level not registered | `GameManager` push_warning, no scene swap |
| Destination teleporter_id missing in that level | `GameManager` push_warning, no scene swap |
| Self-referential destination | Resolves to own tile; harmless no-op visually |
| Destination is in the same map (incl. same level) | Works — `destination_level_id` = current map's id |
| Player not near / interact not pressed | No emit |

The editor does **not** block dangling refs at save time (consistent with `LevelEntrance`). A future enhancement (Approach C enum pickers) can add live validation.

## 9. Testing (GUT)

New/updated test files under `tests/unit/`:

- **`test_teleporter.gd`** (new) — `Teleporter` unit:
  - `setup()` reads the three id props.
  - `attempt_teleport` emits only when nearby + interact + both fields set; no-op otherwise.
  - Emitted args match configured destination fields.
- **`test_game_manager_teleport.gd`** (new) — `GameManager.teleport_no_scene_swap` resolution:
  - Same-map teleport (dest teleporter in the current level): `pending_player_spawn` = dest tile, state correct.
  - Cross-map teleport (dest in a different registered level): `pending_level` swapped, `pending_player_spawn` = dest tile.
  - Dangling level id → no-op (state unchanged, no crash).
  - Dangling teleporter_id → no-op.
  - Self-referential → resolves to own tile without error.
- **`test_level_runtime.gd`** (extend) — wiring: a teleporter spawning with a valid destination fires `GameManager.teleport` path (use `teleport_no_scene_swap` to avoid scene swap in headless).

All existing tests must still pass: `./tests/run_all.sh`.

## 10. Files Touched

| File | Change |
|------|--------|
| `src/runtime/entities/teleporter.gd` | **New** — runtime node |
| `src/runtime/entities/teleporter.tscn` | **New** — minimal scene wrapping the script (mirror `level_entrance.tscn`) |
| `src/episodes/keen1/episode.gd` | Register `keen1.teleporter` (SPECIAL, `[LEVEL, OVERWORLD]`, 3-prop schema) |
| `src/runtime/level_runtime.gd` | `_spawn_entities` branch + `_on_teleport_requested` handler |
| `src/core/game_manager.gd` | `teleport()` + `teleport_no_scene_swap()` + `_find_teleporter_tile()` helper |
| `tests/unit/test_teleporter.gd` | **New** |
| `tests/unit/test_game_manager_teleport.gd` | **New** |
| `tests/unit/test_level_runtime.gd` | Extend with teleport-wiring test |

No changes to `LevelData`, `EntityDef`, `EntityRegistry`, or the inspector (schema-driven `LineEdit`s cover all three props).
