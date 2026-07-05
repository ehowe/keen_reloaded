# Map Kind & Overworld Loop — Design Spec

**Date:** 2026-07-05
**Status:** Draft
**Parent spec:** `docs/superpowers/specs/2026-06-25-keen-reloaded-design.md`
**Engine:** Godot 4.7 (stable), GDScript

## 1. Overview

Today every `LevelData` is treated identically — there is no way to mark a map as a **level** (a platforming stage with enemies, hazards, and an exit) versus an **overworld** (the traversable hub Keen walks between level entrances). This spec introduces a `map_kind` distinction and the full overworld gameplay loop:

```
MainMenu → Overworld → (enter level) → Level → (reach exit) → Overworld …
```

It is a faithful-in-spirit take on the Commander Keen 1 Mars-surface hub: the overworld is a non-lethal scrolling map dotted with level-entrance "doors." Some entrances are **gates** — solid walls that block overworld passage until their associated level is completed.

### Goals

| # | Goal |
|---|------|
| 1 | A `LevelData` can be flagged as `LEVEL` or `OVERWORLD`. |
| 2 | Runtime and editor branch behavior on the flag. |
| 3 | Overworld supports level-entrance entities; entering one transitions into the linked level. |
| 4 | Gate entrances block overworld movement until their level is completed; completion clears them. |
| 5 | `GameManager` owns the boot→overworld→level→overworld state machine and the per-level completion set. |
| 6 | Completion state is session-held now, with an API designed so disk-save is a drop-in for Plan 6. |

### Out of Scope

- Disk-based save/persistence (Plan 6). The completion set lives in memory this spec; `serialize()/deserialize()` hooks are defined but not wired to a file.
- Online catalog / server (long-term, separate).
- Multi-episode progression sharing.
- Overworld enemies/hazards (overworld is non-lethal; no entities beyond entrances are modeled here).

## 2. Approach

**Decision: single `LevelData` resource + a `map_kind` enum field.** Runtime/editor branch on it; entry/gate behavior lives in the entity layer, not in a separate data class.

Alternatives considered and rejected:

- **Subclasses (`LevelMapData`, `OverworldMapData`):** Existing editor and runtime reference `LevelData` concretely (Plans 1–3 shipped against it). Subclassing forces broad refactor and Godot `.tres` subclass serialization is error-prone (type header changes break existing files). No payoff: the divergence is behavioral, not structural.
- **Unrelated resources sharing a `MapData` base:** Cleanest in theory, largest refactor, no gain over the enum-field approach since overworld-specific data is carried by entrance entities.

### Why this works

The real divergence between a level and an overworld is *which ruleset the runtime applies* and *which entity roster is valid* — not the data shape. Both still need tiles, entities, dimensions, spawn. Overworld-specific concerns (which level an entrance leads to, whether it gates passage) are properties of entrance **entities**, not fields on the map. Therefore one enum + entity-driven entrances = minimal blast radius across already-shipped Plans 1–3.

## 3. Data Model

### 3.1 `LevelData` — new `map_kind`

```gdscript
# src/data/level_data.gd
enum MapKind { LEVEL, OVERWORLD }

@export_group("Map")
@export var map_kind: MapKind = MapKind.LEVEL
```

- Default `LEVEL` so every existing `.tres` deserializes unchanged with no migration step.
- The field is the single switch point for runtime and editor branching.

### 3.2 `Episode` — overworld reference

```gdscript
# src/core/episode.gd
var overworld_level_id: String = ""
```

`GameManager` reads this to know which `LevelData.level_id` is the episode's overworld. **One overworld per episode** (matches Keen 1). Keen episodes that ship without an overworld leave this empty and play level-direct.

### 3.3 New entity type: `level_entrance`

Registered as an overworld-only entity, e.g. `"keen1.level_entrance"`, in `src/episodes/keen1/entity_registry.gd`. Its `EntityDef.properties`:

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `target_level_id` | `String` | `""` | The `LevelData.level_id` this door leads to. |
| `blocks_until_completed` | `bool` | `false` | Gate flag. When true and `target_level_id` is not completed, the entrance is solid. |

The entrance is a **door**, not a walk-over trigger:

- **Entry is always via the `interact` input action** (see §4.2). There is no auto-enter on contact — this prevents accidental re-entry and unifies gated and non-gated entrances under one interaction.
- **Solidity** is a runtime concern, recomputed from `GameManager.completed_levels` whenever the overworld is built or a level completes:
  - Solid when `blocks_until_completed == true && not GameManager.is_level_completed(target_level_id)`.
  - Non-solid otherwise (non-gate entrances are always non-solid; gates become non-solid once cleared).
- When solid, Keen physically cannot walk through it (collision body blocks movement); they stand adjacent and press `interact` to enter.
- When non-solid, Keen walks onto it and presses `interact` to enter.

The entity does **not** own its completion state. `GameManager` is the single source of truth; the entity only reads it to set its collision body.

## 4. Runtime

### 4.1 `LevelRuntime.build` branches on `map_kind`

| Concern | LEVEL (existing) | OVERWORLD (new) |
|---------|------------------|-----------------|
| Tile/collision build | Identical | Identical |
| Camera (player-follow, scroll) | Identical | Identical |
| Hazards | Lethal | **Non-lethal** — Keen cannot die on the overworld |
| Exit fields (`exit_type`, `exit_position`) | Reaching exit calls `GameManager.complete_level()` → return to overworld | Unused |
| `exit_target_level_id` | **Not used by the overworld loop.** Kept on `LevelData` for a possible future level→level chaining mode (out of scope here). | Unused |
| `level_entrance` entities | Not spawned (LEVEL-only entity roster) | Spawned; solidity set from `completed_levels` |
| `interact` action | Inactive | Polled for level entry |

Everything else is shared. The overworld is built from the same `LevelData` pipeline; the only differences are hazard lethality, exit handling, and entrance-entity handling.

### 4.2 New input action: `interact`

`GameManager._ensure_input_actions()` registers:

```gdscript
_add_key_action("interact", KEY_UP)
```

- **Up arrow** is the proposed bind (matches "enter a door" convention). Easily remapped; gamepad mapping deferred to Plan 6.
- In overworld mode, pressing `interact` while the player is within **1 tile (Manhattan distance)** of a `level_entrance` triggers `GameManager.enter_level(that_entrance)`.
- The 1-tile zone applies regardless of whether the entrance is currently solid, so the interaction is uniform for gated and non-gated doors.

### 4.3 Player return placement

On `complete_level()`, Keen returns to the overworld at `GameManager.last_entrance_pos` — the tile of the entrance used to enter the level. This is recorded at enter time so the player reappears at the right door even if the overworld has multiple entrances to the same level.

## 5. GameManager State Machine

`GameManager` (autoload, `src/core/game_manager.gd`) gains:

```gdscript
enum State { MENU, OVERWORLD, LEVEL, TEST }

var state: State = State.MENU
var current_episode_id: String = ""
var current_overworld: LevelData = null
var current_level: LevelData = null
var completed_levels: Array[String] = []   # set semantics; in-memory now
var last_entrance_pos: Vector2i = Vector2i.ZERO
```

Transitions:

| Method | Effect |
|--------|--------|
| `start_episode(ep_id)` | Resolve episode, load its overworld `LevelData` by `overworld_level_id`, set `current_overworld`, `state = OVERWORLD`, build runtime. |
| `enter_level(entrance)` | Record `last_entrance_pos = entrance` tile, load `LevelData` matching `entrance.target_level_id`, set `current_level`, `state = LEVEL`, build runtime. |
| `complete_level()` | Append `current_level.level_id` to `completed_levels` (idempotent), reload `current_overworld`, place player at `last_entrance_pos`, `state = OVERWORLD`. |
| `is_level_completed(level_id) -> bool` | Lookup used by entrance entities and UI. |

The level's existing exit-reached logic calls `GameManager.complete_level()` (which returns Keen to the overworld) instead of following `exit_target_level_id`. This centralizes the loop in `GameManager`. Note: `exit_target_level_id` remains on `LevelData` but is deliberately unused by this loop — it is reserved for a possible future level→level chaining mode and is out of scope here.

### Save-readiness hooks

```gdscript
func serialize() -> Dictionary:
    return { "completed_levels": completed_levels.duplicate(),
             "current_episode_id": current_episode_id }

func deserialize(data: Dictionary) -> void:
    completed_levels = data.get("completed_levels", [])
    current_episode_id = data.get("current_episode_id", "")
```

Defined now, **not** wired to disk. Plan 6 will call these from its save-file layer. This keeps the session-held behavior simple while guaranteeing the API is right.

## 6. Editor Changes

- **Inspector:** `map_kind` enum dropdown under a new "Map" group. New level defaults to `LEVEL`.
- **Entity palette filtering:** `EntityRegistry.register()` gains an optional `map_kinds` mask argument (default: `[LEVEL]`). Gameplay entities (vorticon, yorp, items, hazards) register as LEVEL-only; `level_entrance` registers as OVERWORLD-only. The palette panel reads the active `LevelData.map_kind` and shows only matching entities.
  - If the designer switches `map_kind` on a map that contains now-invalid entities, the editor **warns** (does not auto-delete; the designer resolves manually).
- **Entrance properties:** selecting a `level_entrance` shows `target_level_id` (text) and `blocks_until_completed` (checkbox) in the inspector via the standard entity-properties path — no special-casing.
- **Test ▶:** honors `map_kind` — an overworld map test-runs in overworld mode (non-lethal, `interact` active), a level map test-runs as today.

## 7. Testing (GUT, headless)

| Area | Tests |
|------|-------|
| `LevelData.map_kind` | Serialization round-trip; default `LEVEL` for files authored before this change. |
| `GameManager` | State transitions MENU→OVERWORLD→LEVEL→OVERWORLD; `completed_levels` add is idempotent; `is_level_completed` query; `serialize/deserialize` round-trip. |
| `level_entrance` solidity | Solid when `blocks_until_completed && !completed`; non-solid when non-gate; non-solid when gate completed. |
| Interaction | `enter_level` fires only when player within 1 tile **and** `interact` pressed; ignored otherwise. |
| Runtime branch | Overworld build disables lethal hazards; level build keeps them. |
| Editor | Palette filters by `map_kind`; inspector enum writes back to `LevelData`; `map_kind` switch with invalid entities warns. |

Run via `./tests/run_all.sh` — must pass before commit.

## 8. Implementation Phasing

Each phase is independently testable and lands before the next begins. (Detail belongs in the implementation plan, not here.)

1. **Foundation** — `MapKind` enum + field + serialization; `map_kind` default-LEVEL preserves old files; editor inspector selector; `LevelRuntime` branch stub (overworld disables lethal hazards). No new entities yet.
2. **Entry loop** — `"interact"` action; `level_entrance` entity (non-gate: `blocks_until_completed = false`, always non-solid); `GameManager` state machine + `enter_level` / `complete_level` + `last_entrance_pos` return; overworld `interact` polling.
3. **Gates** — `blocks_until_completed` solidity driven by `completed_levels`; recomputed on overworld build and on level completion; `is_level_completed` wiring.
4. **Boot flow** — `MainMenu` → `start_episode` → overworld → loop; `Episode.overworld_level_id` authoring; end-to-end manual test via Test ▶ and full game start.

## 9. Open Questions (non-blocking)

- **`interact` keybind:** Up arrow proposed. Confirm or change in implementation.
- **Multiple entrances to one level:** Return placement uses `last_entrance_pos` (the door actually used), which handles this correctly; no design change needed.
- **Replaying completed levels:** Allowed (entrance remains enterable after completion; only solidity clears). Matches original Keen behavior; revisit if undesired.
