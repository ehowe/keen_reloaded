# Plan 6c — Persistence (Save/Load) — Design Spec

**Date:** 2026-07-13
**Status:** Draft
**Parent spec:** `docs/superpowers/specs/2026-06-25-keen-reloaded-design.md`
**Related:** `docs/superpowers/specs/2026-07-05-map-kind-overworld-loop-design.md` (defines `GameManager.serialize()`/`deserialize()` seams this plan wires to disk)
**Engine:** Godot 4.7 (stable), GDScript

## 1. Overview

Progress is currently session-held: `GameManager` tracks `completed_levels` and `current_episode_id` in memory, and the existing `serialize()`/`deserialize()` hooks are defined but unwired to disk. Quitting loses all progress. This spec implements Plan 6c — disk-based save/load with 6 named slots, auto-save at overworld transitions, and manual save via a pause menu.

### Goals

| # | Goal |
|---|------|
| 1 | A new `SaveSystem` autoload owns all slot file I/O; `GameManager` stays focused on session state. |
| 2 | 6 global named slots at `user://saves/slot_<N>.json`. Each slot holds one playthrough (episode or pack). |
| 3 | Auto-save fires on every transition into the overworld (level complete, level fail/death, teleport to overworld). |
| 4 | Manual save via an in-game pause menu (Esc), gated to overworld state. |
| 5 | Loading a slot restores `completed_levels` + `current_episode_id` and resumes at the overworld's authored spawn. |
| 6 | Both bundled episodes and custom level packs are saveable. Pack saves degrade gracefully when a pack is uninstalled. |
| 7 | Atomic writes (temp + rename) with a `.bak` rollback so a crash mid-write never corrupts the previous good save. |
| 8 | Schema versioning (`version: 1`) so future migrations can refuse or transform older/newer files. |

### Out of Scope

- **Mid-level save.** Manual save is gated to overworld; loading always resumes on the overworld. Capturing live player position / enemy state / picked-up items inside a level is explicitly deferred.
- **Per-slot player stats** (lives, score, ammo, items). The game does not currently track these on `GameManager`; if/when they arrive they extend `serialize()`, not this plan.
- **Cloud sync / online saves.** Local `user://` only.
- **Save-file encryption.** JSON is plaintext; tampering is the player's problem.
- **Eager orphan cleanup on pack uninstall.** Orphaned pack saves are surfaced lazily in the slot-select UI with a delete affordance; no hook into pack removal.

## 2. Approach

**Decision: a dedicated `SaveSystem` autoload writing JSON slot files.**

`SaveSystem` is the single owner of file I/O and the active-slot concept. It calls `GameManager.serialize()` to produce the payload and `GameManager.deserialize()` to apply it. `GameManager` gains exactly one new call site per state→OVERWORLD transition (`SaveSystem.save_active()`); its existing `serialize()`/`deserialize()` signatures are unchanged.

Alternatives considered and rejected:

- **Save logic folded into `GameManager`:** fewer files, but `GameManager` already owns the boot→overworld→level state machine, episode discovery, input-action registration, and teleport resolution. Adding slot/file/versioning concerns bloats it and makes it harder to test in isolation. Separation wins.
- **Godot `ConfigFile` format instead of JSON:** less hand-rolled parsing, but `ConfigFile`'s section/key model is awkward for the `completed_levels` array (would need a comma-joined string or numeric keys), and the parent spec already names `user://save.json` as the target. JSON is debuggable with any text editor and round-trips Godot arrays/dicts natively via `JSON.stringify`/`JSON.parse`.

### Why this works

The existing `serialize()`/`deserialize()` seam was designed exactly for this plan (see overworld-loop spec §5 "Save-readiness hooks"). The session-state shape is already stable; Plan 6c only adds the file layer, the active-slot concept, and the UI to pick/create/clear slots. No existing `GameManager` field changes type or meaning.

## 3. Data Model

### 3.1 Slot file location

```
user://saves/
  slot_1.json
  slot_2.json
  ...
  slot_6.json
```

Flat directory, one file per slot. **Empty slot = file absent** (no placeholder files). A missing `user://saves/` directory is created lazily on first save.

### 3.2 Slot is global

Each slot holds exactly one playthrough — either an episode run or a pack run. The slot records which scope it belongs to via `kind` + `scope_id`. Starting a new game in an occupied slot overwrites it after a confirm prompt. Slots are **not** partitioned per-episode; a player may keep a Keen 1 run in slot 1 and a Keen 2 run in slot 2.

### 3.3 Slot file schema (v1)

```json
{
  "version": 1,
  "kind": "episode",
  "scope_id": "keen1",
  "scope_title": "Keen 1",
  "saved_at": 1720800000,
  "completed_count": 3,
  "data": {
    "completed_levels": ["keen1.lvl1", "keen1.lvl2"],
    "current_episode_id": "keen1"
  }
}
```

| Field | Type | Description |
|---|---|---|
| `version` | `int` | Schema version. Current: `1`. |
| `kind` | `String` | `"episode"` or `"pack"`. |
| `scope_id` | `String` | Episode id (e.g. `"keen1"`) or pack id. |
| `scope_title` | `String` | Human-readable scope name, **cached at save time** so the slot-select screen can render without resolving episodes/packs. |
| `saved_at` | `int` | Unix timestamp of the save (seconds, `int(Time.get_unix_time_from_system())`). |
| `completed_count` | `int` | Length of `data.completed_levels`, **cached at save time** for fast slot-select rendering. |
| `data` | `Dictionary` | Verbatim payload from `GameManager.serialize()`. |

`scope_title` and `completed_count` are denormalized caches. The slot-select screen reads metadata for all 6 slots on every open; caching avoids resolving every registered episode and every installed pack just to paint the grid. The full `data` payload is only deserialized when the player actually loads a slot.

## 4. `SaveSystem` Autoload

New autoload, registered in `project.godot` after `GameManager` (so it may reference it). Source: `src/core/save_system.gd`.

### 4.1 Public API

```gdscript
extends Node

const SLOT_COUNT := 6
const SAVES_DIR := "user://saves"
const CURRENT_VERSION := 1

# Active slot for this session. 0 = no active slot (auto-save is a no-op).
# In-memory only; never persisted as its own field.
var active_slot: int = 0

# Read each slot file, parse metadata (version/kind/scope_id/scope_title/
# saved_at/completed_count). Returns one Dictionary per slot 1..SLOT_COUNT.
# Empty/missing/corrupt/missing-pack slots are reported with a "status" field:
#   {"slot": N, "status": "empty"|"occupied"|"corrupt"|"missing_pack"|
#                        "unsupported_version", ...metadata}
# Does NOT touch GameManager state. Resolves pack validity via PackLoader.
func list_slots() -> Array[Dictionary]

# Load a slot into GameManager. Returns true on success.
# On any failure (corrupt, missing, unsupported, missing pack) returns false
# and leaves GameManager untouched. Sets active_slot on success.
func load_slot(slot: int) -> bool

# Persist GameManager.serialize() to the slot file. Atomic write + .bak rotate.
# Sets active_slot. Returns true on success, false on disk failure.
func save_slot(slot: int) -> bool

# Remove a slot file (and its .bak). Used by corrupt/missing-pack cleanup
# and by explicit user "clear slot" actions.
func delete_slot(slot: int) -> void

# Convenience wrapper: save to active_slot. No-op (returns true) if active_slot == 0.
func save_active() -> bool

# Clear active_slot (called when returning to main menu / starting a fresh
# session that has not yet chosen a slot).
func clear_active() -> void
```

### 4.2 Atomic write + backup

`save_slot` procedure:

1. Ensure `user://saves/` exists (`DirAccess.make_dir_recursive_absolute`).
2. Build the slot dictionary from `GameManager.serialize()` + cached metadata.
3. Serialize to JSON (`JSON.stringify(payload, "  ")`).
4. Write to `user://saves/slot_<N>.json.tmp` (`FileAccess.WRITE`).
5. If a previous `slot_<N>.json` exists, copy it to `slot_<N>.json.bak` (overwriting any prior `.bak`).
6. Rename `slot_<N>.json.tmp` → `slot_<N>.json` (`DirAccess.rename`).
7. On any step failure: `push_error`, remove the `.tmp`, return `false`. The previous good save (and `.bak`) remain intact.

`load_slot` falls back to `.bak` if the primary file fails JSON parsing or fails validation, logging a `push_warning`. If `.bak` also fails, the slot is reported corrupt.

### 4.3 Validation on load

`load_slot` rejects a file (returns `false`, slot marked corrupt/unsupported) when:

- JSON parse fails (and `.bak` fallback also fails).
- Root is not a Dictionary.
- `version` key missing, or `version > CURRENT_VERSION` (forward-incompatible — slot is "unsupported_version"), or `version < CURRENT_VERSION` (no migration path yet; for v1 this case cannot occur).
- `data` key missing or not a Dictionary.
- `GameManager.deserialize(data)` throws or `push_error`s — caught and treated as corrupt.

Missing-pack slots (`kind == "pack"` and `PackLoader.get_overworld(scope_id) == null`) are **not** offered for load; they surface in `list_slots` with status `"missing_pack"` and a delete affordance.

## 5. GameManager Changes

Minimal. The existing `serialize()`/`deserialize()` signatures and bodies are unchanged.

### 5.1 Auto-save hooks

One `SaveSystem.save_active()` call added to each state→OVERWORLD transition, after session state is updated:

| Method | Hook site |
|---|---|
| `complete_level()` | after `complete_level_no_scene_swap()` (which sets `state = OVERWORLD`) |
| `fail_level()` | after `fail_level_no_scene_swap()` |
| `teleport()` | after `teleport_no_scene_swap()` when the resolved destination `lvl.map_kind == OVERWORLD` |

The `_no_scene_swap` variants are **not** hooked — they are headless-test entry points and tests do not want disk I/O. The scene-swap variants are the real gameplay paths.

`save_active()` is a no-op when `active_slot == 0` (test mode, main menu, or a session that has not chosen a slot), so adding the calls is safe for existing tests.

### 5.2 Episode/pack title resolution

`SaveSystem` needs `scope_title` for the cached metadata. It resolves the title from the relevant source at save time:

- Episode: scan `GameManager.episodes` for `id == scope_id`, read `title`.
- Pack: `PackLoader.get_pack_title(pack_id)` (small accessor added to `PackLoader` if not present; falls back to `pack_id` if unknown).

The title is captured once at save and stored in the slot file; subsequent slot-select renders never re-resolve.

## 6. Active-Slot Lifecycle

| Event | `active_slot` |
|---|---|
| Game boot | `0` |
| New Game → episode/pack select → slot select → pick slot (overwrite confirmed) | `= N`, then immediate `save_slot(N)` |
| Continue → slot select → pick valid slot | `load_slot(N)` sets `= N` |
| Pause menu → Save Game | writes to current `active_slot` (disabled if `0`) |
| Auto-save fires (overworld transition) | writes to current `active_slot`; no-op if `0` |
| Quit to Main Menu | `clear_active()` → `0` |
| Test ▶ (editor) | never set; stays `0` so auto-save no-ops |
| Custom pack quick-start (if any) | per current `start_pack` semantics, packs may also opt into slot select; for v1 the **pack-select screen gains a slot-select step** mirroring the episode New Game flow |

## 7. UI

### 7.1 Pause menu — `src/ui/pause_menu.tscn`

- Triggered by `ui_cancel` (Esc) in OVERWORLD or LEVEL state. A small `_unhandled_input` check (on the pause overlay node or in `GameManager`) toggles `get_tree().paused = true` and shows the overlay.
- Buttons:
  - **Resume** — hides overlay, `paused = false`.
  - **Save Game** — calls `SaveSystem.save_slot(SaveSystem.active_slot)`. Disabled when `active_slot == 0` or `state != OVERWORLD`. Shows a brief "Saved." confirmation on success, "Save failed." on failure.
  - **Load Game** — opens `slot_select` (load mode) as a child overlay; on pick, calls `SaveSystem.load_slot(N)`, then rebuilds the runtime via `GameManager` (re-enter overworld).
  - **Quit to Main Menu** — calls `SaveSystem.save_active()` first (best-effort), then `clear_active()`, then changes scene to MainMenu.
- Esc inside the pause menu toggles back to Resume.

### 7.2 Slot-select screen — `src/ui/slot_select.tscn`

Reusable scene parameterized by `mode`:

| Mode | Behavior |
|---|---|
| `new_game` | All slots clickable. Empty → use directly. Occupied → confirm-overwrite dialog → use. Corrupt/missing_pack/unsupported → clickable only to delete (then becomes empty). |
| `continue` / `load` | Only `occupied` slots with valid scope are clickable. Others greyed with their status label. |

Grid of 6 slot cards. Each card renders:

- Slot number (1–6).
- Status-dependent content:
  - `occupied` — scope title (e.g. "Keen 1"), completed count ("3 levels cleared"), formatted timestamp.
  - `empty` — "Empty".
  - `corrupt` — "⚠ Corrupt — click to delete".
  - `missing_pack` — "⚠ Pack missing — click to delete".
  - `unsupported_version` — "⚠ Unsupported save (vN) — click to delete".

The screen reads metadata via `SaveSystem.list_slots()` once on open; no per-frame file I/O.

### 7.3 Main menu changes — `src/ui/main_menu.gd`

- **Play** (existing) — kept as a dev fast-path: starts `keen1` in the first empty slot (or creates one). Maintains quick-iteration ergonomics.
- **New Game** (new button) → episode/pack select → `slot_select` (`new_game` mode) → start.
- **Continue** (new button) → `slot_select` (`continue` mode). Disabled if `list_slots()` has zero occupied slots.
- **Load Game** — merged into Continue (identical flow).

## 8. Pack Save Handling

Custom packs are saveable on equal footing with bundled episodes. A slot file with `kind == "pack"` references the pack by id. The pack entry path splits into two cases:

- **New pack game** (player picks an empty slot): `clear_progress()` is still called, then the pack's overworld and levels are registered and a fresh save is written to the chosen slot. This matches today's behavior.
- **Load existing pack save** (player picks an occupied pack slot): `SaveSystem.load_slot(N)` applies `deserialize()` first (restoring `completed_levels`), then `start_pack_no_scene_swap` registers the pack's levels **without** calling `clear_progress()` — otherwise it would wipe the just-restored completion set. `register_level()` is idempotent (overwrites by `level_id`), so re-registration is harmless.

Concretely, `start_pack_no_scene_swap` drops its unconditional `clear_progress()` and instead trusts that the caller has either cleared (new-game path) or restored (load path) `completed_levels` beforehand. The public `start_pack` wrapper performs the clear for the new-game path so existing direct callers (and tests) that expect a fresh session still get one.

**Orphan handling is lazy.** When a pack is uninstalled (its directory removed from `user://levelpacks/`), its slot files are not eagerly deleted. Instead:

- `list_slots()` resolves pack validity via `PackLoader.get_overworld(scope_id)`. Null → status `"missing_pack"`.
- The slot-select UI shows the slot with a "⚠ Pack missing" label and a delete affordance.
- The player may delete the orphaned slot at their leisure.

No hook into `PackLoader`'s pack-removal path is added (keeping that subsystem untouched). If desired in future, an eager-cleanup pass can scan `user://saves/` on boot, but that is explicitly deferred.

## 9. Corruption, Versioning & Edge Cases

| Scenario | Behavior |
|---|---|
| Slot file missing | `list_slots` → `empty`. Normal. |
| JSON parse fails on `slot_N.json` | `load_slot` tries `slot_N.json.bak`; if `.bak` parses, loads it and `push_warning`. `list_slots` → `corrupt` if both fail. |
| Required key missing (`version`, `data`, etc.) | `corrupt`. |
| `version > CURRENT_VERSION` | `unsupported_version`. Refuse load; offer delete. No silent forward-read. |
| `version < CURRENT_VERSION` | Cannot occur in v1; future migration hook lives here. |
| `GameManager.deserialize` errors | Caught; slot marked `corrupt`. |
| Pack uninstalled between sessions | `missing_pack`; offer delete. |
| Disk write fails (permissions, full disk) | `save_slot` returns `false`, `push_error`. Pause-menu Save button shows "Save failed." Auto-save failure logs but does not interrupt gameplay. |
| Concurrent saves | Impossible: single-threaded, `save_slot` is synchronous. |
| Auto-save during scene transition | Fires after state is set to `OVERWORLD` and session fields are stable, before `change_scene_to_packed`. `serialize()` only reads stable fields, so the payload is consistent. |

## 10. Testing (GUT, headless)

Run via `./tests/run_all.sh` — must pass before commit.

| Area | Tests |
|---|---|
| `save_slot`/`load_slot` round-trip | Seed `GameManager.completed_levels` + `current_episode_id`, save, clear, load, assert equality. |
| Atomic write | Pre-existing good save; second save rotates `.bak` from the first; primary file always valid after the call. |
| Partial-write recovery | Manually truncate `slot_N.json` to invalid JSON; `load_slot` falls back to `.bak`. |
| Corrupt JSON | Both primary and `.bak` invalid → `load_slot` returns `false`, `GameManager` untouched, `list_slots` → `corrupt`. |
| Version mismatch | Hand-craft a `version: 999` file → refused (`unsupported_version`). |
| Missing required keys | Strip `data` key → `corrupt`. |
| Missing pack | Save a `kind:"pack"` slot, point `scope_id` at a non-existent pack, `list_slots` → `missing_pack`. |
| `delete_slot` | Removes `slot_N.json` and `slot_N.json.bak`. |
| Active-slot lifecycle | New-game path sets `active_slot`; `clear_active` resets to `0`; `save_active` no-op when `0`. |
| GameManager hooks | `complete_level`/`fail_level`/`teleport→overworld` invoke `save_active` exactly once each; test mode (`_no_scene_swap` variants) does **not** touch disk (assert no file written when `active_slot == 0`). |
| UI smoke (light) | `slot_select.gd` logic tested via an injected `SaveSystem` stub returning canned `list_slots` data; assert correct card labels per status. Full scene interaction is manual. |

UI scene wiring is verified manually (open pause menu, save, load, delete corrupt slot); the unit suite covers the data layer and the slot-card label logic.

## 11. Implementation Phasing

Each phase lands independently and is testable before the next begins. (Step detail belongs in the implementation plan, not here.)

1. **SaveSystem core** — autoload, schema v1, `save_slot`/`load_slot`/`list_slots`/`delete_slot`, atomic writes + `.bak`, validation, versioning. Fully unit-tested against a temp `user://` dir. No UI yet; no GameManager hooks yet.
2. **GameManager hooks** — add `save_active()` calls to the three overworld transitions; verify test suite still green (no-op when `active_slot == 0`).
3. **Slot-select UI** — `slot_select.tscn` + `slot_select.gd`; render all 5 statuses; wire into main menu (New Game / Continue).
4. **Pause menu** — `pause_menu.tscn` + `pause_menu.gd`; Esc toggle; Save / Load / Resume / Quit-to-menu.
5. **Pack save integration** — pack-select gains slot-select step; `start_pack` no longer hard-clears when a slot is loaded.
6. **End-to-end manual test** — full New Game → play → auto-save → quit → Continue cycle for an episode and for a pack; corrupt a save manually and confirm the UI handles it.

## 12. Open Questions (non-blocking)

- **Slot-select visual design:** card layout, theming. Deferred to implementation; will match existing main-menu theme.
- **Timestamp format in UI:** relative ("2 hours ago") vs absolute ("2026-07-13 14:32"). Implementation picks one; trivially swappable.
- **Quicksave keybind (F5/F9):** not in v1 (manual save is menu-only). Easy to add later as a keybind that calls `save_slot(active_slot)` / opens slot-select.
