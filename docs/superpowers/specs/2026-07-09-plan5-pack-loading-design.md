# Plan 5 — Pack Loading — Design Spec

**Date:** 2026-07-09
**Status:** Draft
**Parent spec:** `docs/superpowers/specs/2026-06-25-keen-reloaded-design.md`
**Engine:** Godot 4.7 (stable), GDScript

## 1. Overview

Plan 5 delivers the **custom level-pack** loading path. Players who want content
beyond the bundled Keen 1 set can obtain a **level pack** (a `.zip`), import it
through the menu, and play its complete experience — its own **overworld** plus
one or more **levels**.

The bundled Keen 1 content is **out of scope** for PackLoader: it is wired up
separately via Godot scenes and the existing `Episode`-script discovery
(`GameManager.start_episode`). PackLoader only handles user-supplied packs
dropped into `user://levelpacks/`.

```
MainMenu → [Custom Packs] → pack_select → [Load .zip…] → import → select pack
  → GameManager.start_pack(pack_id) → Overworld → (existing enter/complete/fail loop)
```

### Why now

`GameManager` already owns the full overworld→level→overworld state machine and a
level-resolution seam (`register_level` / `get_level_by_id` /
`_levels_by_id`), introduced by the Map Kind & Overworld Loop spec
(2026-07-05). That seam is currently populated by tests via ad-hoc
`register_level` calls — there is no production path that fills it.
`PackLoader` is already declared an autoload (`project.godot:21`) but is a
2-line stub. `LevelPack` (`src/data/level_pack.gd`) already parses
`manifest.json` and is fully tested. This spec is the wiring that makes all three
production-ready for custom content.

### Goals

| # | Goal |
|---|------|
| 1 | `PackLoader` scans `user://levelpacks/`, parses each pack's `manifest.json`, loads its `.tres` `LevelData`, and exposes lookups. |
| 2 | Users import a pack by selecting a `.zip` in a native file dialog; the zip is extracted, validated, and registered for play. |
| 3 | Imported packs appear in a `pack_select` submenu; selecting one launches its overworld via `GameManager.start_pack`. |
| 4 | The existing enter/complete/fail overworld loop works unchanged for custom packs. |
| 5 | Zip import is hardened against path-traversal and disallowed file types (user-supplied input). |
| 6 | GUT tests cover scanning, import, traversal/abuse rejection, and `start_pack` integration — all deterministic and headless. |

### Out of scope

- **Bundled Keen 1 content wiring** — handled by scenes + `Episode` scripts; not via PackLoader.
- **Custom art/sprites/tilesets in packs** — packs contain only `manifest.json` + `.tres` files and reuse shipped art + registered entity types (the plan4 "reuse only" decision).
- **Pack deletion UI** — remove by deleting files under `user://levelpacks/` manually (YAGNI for now).
- **Online catalog / server / auto-download** — long-term, separate.
- **Disk-based save/progression** — Plan 6 (`serialize/deserialize` hooks already exist).
- **Pack-local entity type registration** — custom packs reuse the global registered catalog only (plan4 decision; "Plan 5 may revisit" left as-is — no change this spec).

## 2. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Where import/menu/state live | **PackLoader owns scan+import; menu owns UI only; GameManager owns state** (Approach A) | Clean single-responsibility; PackLoader is pure data + IO, headlessly testable; GameManager stays focused on game state; UI isolated to the menu scene. |
| Scan location | `user://levelpacks/` only | Bundled content uses scenes (out of scope). `res://levels/` scanning would be dead code. Devs test packs by dropping them in `user://levelpacks/`. |
| Import mechanism | Native `FileDialog` → `ZIPReader` extract | Godot 4 has built-in zip reading; no dependency. One-click UX. |
| Pack contents | `manifest.json` + `.tres` only | Reuse shipped art/tilesets + registered entity types. Deterministic, fast, smallest attack surface. |
| Overworld designation | Detected from `LevelData.map_kind == OVERWORLD` | `map_kind` already exists (2026-07-05 spec). No manifest schema change — `.tres` files are self-describing. |
| Canonical extract dir | `user://levelpacks/<pack_id>/` (pack_id from parsed manifest) | Re-importing a pack overwrites its own dir; pack_id is the stable identity, independent of zip filename. |
| Duplicate pack_id on re-import | Overwrite + log warning, `{ok:true}` | Idempotent re-install; matches "last wins" scan semantics. |
| Progress on pack start | `clear_progress()` first | Each custom pack gets a fresh session; no cross-pack completion bleed. Save is Plan 6. |

## 3. Architecture

### 3.1 Components & responsibilities

| Component | File | Role |
|---|---|---|
| `PackLoader` (autoload, exists as stub) | `src/core/pack_loader.gd` | Scan `user://levelpacks/*/manifest.json`; parse via `LevelPack.from_json`; load `.tres` `LevelData`; cache. `import_zip()` extracts + sanitizes + reloads. Exposes lookups. Pure data + IO — no UI. |
| `main_menu` (exists) | `src/ui/main_menu.gd` | Keeps Play (bundled) / Editor / Quit; adds **"Custom Packs"** button → `change_scene_to_packed(pack_select)`. |
| `pack_select` (**new**) | `src/ui/pack_select.gd` + `.tscn` | Lists `PackLoader.get_packs()` (name, author, level count); **"Load .zip…"** → `FileDialog`; double-click row → `GameManager.start_pack(pack_id)`; **Back**. |
| `GameManager` (autoload, exists) | `src/core/game_manager.gd` | New `start_pack(pack_id)` + `start_pack_no_scene_swap(...)`: resolve pack overworld, register pack levels into `_levels_by_id`, set state OVERWORLD, scene-swap. Reuses existing enter/complete/fail loop unchanged. |
| `LevelPack` (data, exists) | `src/data/level_pack.gd` | Unchanged — `from_json` already parses the manifest. |

No new entity registration for custom packs (reuse-only). No `State` enum change.

### 3.2 Data flow

**Import (one-time, user-driven):**

```
main_menu → "Custom Packs" → pack_select → "Load .zip…"
  → FileDialog (*.zip) → user picks path
  → PackLoader.import_zip(path)
       1. ZIPReader.open(path); for each entry:
          - sanitize: reject absolute paths and ".." traversal
          - enforce allowlist: manifest.json / *.tres / *.res only
       2. extract to temp dir user://levelpacks/.tmp_import/
       3. locate manifest.json at extracted root
       4. LevelPack.from_json() → validate; abort+cleanup if null
       5. move temp dir → user://levelpacks/<pack_id>/ (canonical)
       6. scan() (re-scan all packs)
  → returns {ok:bool, error:String, pack_id:String}
  → pack_select shows status, repopulates list
```

**Play (existing loop, new entry):**

```
pack_select row double-click → GameManager.start_pack(pack_id)
  1. pack = PackLoader.get_pack(pack_id)
  2. ow   = PackLoader.get_overworld(pack_id)    # the map_kind==OVERWORLD .tres
  3. clear_progress()
  4. current_episode_id = pack_id
  5. register overworld + every pack level into _levels_by_id
  6. state = OVERWORLD, pending_level = ow, scene-swap to RUNTIME
  ... existing enter_level / complete_level / fail_level loop unchanged
```

**Bundled keen1** is untouched: `main_menu._play()` still calls
`start_episode("keen1")` via Episode-script discovery.

## 4. PackLoader API

```gdscript
extends Node

# caches (rebuilt by scan)
var _packs: Dictionary       # pack_id -> LevelPack
var _levels: Dictionary      # pack_id -> { level_id -> LevelData }
var _overworlds: Dictionary  # pack_id -> LevelData (map_kind==OVERWORLD)

const ROOT := "user://levelpacks/"
const TMP_IMPORT := "user://levelpacks/.tmp_import/"

# lifecycle
func _ready() -> void          # scan() once at boot
func scan() -> void            # clear caches; walk ROOT/*/manifest.json
func reload() -> void          # alias scan()
func import_zip(zip_path: String) -> Dictionary  # {ok:bool, error:String, pack_id:String}

# queries
func get_packs() -> Array[LevelPack]
func get_pack(pack_id: String) -> LevelPack
func get_levels(pack_id: String) -> Array[LevelData]
func get_level(pack_id: String, level_id: String) -> LevelData
func get_overworld(pack_id: String) -> LevelData
func is_installed(pack_id: String) -> bool
```

### 4.1 Scan rules (per `user://levelpacks/<pack_id>/`)

- `manifest.json` required at root — skip pack + `push_warning` if missing.
- `LevelPack.from_json` returns null → skip + warn (malformed).
- Each manifest level `{level_id, file, name, order}`:
  `load("<pack_dir>/<file>")` cast to `LevelData`; skip + warn if load fails or
  wrong type.
- Duplicate `pack_id` across installed packs → last-wins + warn.
- **Overworld**: exactly one level with `map_kind == OVERWORLD`. Zero → pack
  invalid (skip + warn). More than one → first wins + warn.
- Hidden dirs (`.tmp_import`) are skipped during scan.

### 4.2 manifest.json (unchanged schema)

No new fields — overworld is detected from `map_kind`:

```json
{
  "pack_id": "keen1_fanremix",
  "name": "Keen Fan Remix",
  "author": "modder",
  "version": "1.0",
  "episode": "keen1",
  "levels": [
    {"level_id": "ow",     "file": "overworld.tres", "name": "Overworld", "order": 0},
    {"level_id": "lvl_01", "file": "01.tres",        "name": "Border",    "order": 1}
  ]
}
```

(`overworld.tres` has `map_kind = MapKind.OVERWORLD` baked in at authoring time.)

### 4.3 import_zip detail

Canonical extracted dir = `user://levelpacks/<pack_id>/` where `pack_id` is taken
from the **parsed manifest** (not the zip filename), so re-importing overwrites
the pack's own dir. Flow extracts to `TMP_IMPORT` first, parses the manifest to
learn `pack_id`, then moves `TMP_IMPORT` → `<pack_id>/`. If the manifest is
unparseable (pack_id unknown) the temp dir is deleted and the import is rejected.

## 5. GameManager.start_pack

New method; reuses the existing state machine + level-resolution seam:

```gdscript
func start_pack(pack_id: String) -> void:
	var ow := PackLoader.get_overworld(pack_id)
	if ow == null:
		push_warning("GameManager: pack '%s' has no overworld" % pack_id)
		return
	start_pack_no_scene_swap(pack_id, ow)
	get_tree().change_scene_to_packed(RUNTIME_SCENE)

func start_pack_no_scene_swap(pack_id: String, ow: LevelData) -> void:
	clear_progress()                  # fresh session per custom pack
	current_episode_id = pack_id      # custom pack identified by pack_id
	current_overworld = ow
	register_level(ow)                # existing seam
	for lvl in PackLoader.get_levels(pack_id):
		register_level(lvl)           # populates _levels_by_id
	pending_level = ow
	pending_player_spawn = Vector2i(-1, -1)
	state = State.OVERWORLD
```

Notes:
- `clear_progress()` first → no cross-pack completion bleed.
- `current_episode_id = pack_id` lets `serialize/deserialize` and any UI treat a
  custom pack uniformly. The Episode-script path (`start_episode` /
  `_resolve_overworld`) stays for bundled keen1 only — untouched.
- No `State` enum change (uses existing `OVERWORLD`). No change to
  enter/complete/fail loops.

**Autoload order:** list `PackLoader` before `GameManager` in `project.godot`
autoloads so its `_ready()` `scan()` completes first. `start_pack` runs only on
user action (post-boot) so there is no race either way, but the order is safer.

## 6. Menu / UI

`main_menu` (existing) — add one button:

```
Play          → start_episode("keen1")    [bundled, unchanged]
Custom Packs  → change_scene_to_packed(pack_select)   [NEW]
Editor        → [unchanged]
Quit          → [unchanged]
```

`pack_select` (**new** scene `src/ui/pack_select.tscn` + `.gd`):

```
┌─ Custom Packs ──────────────────────────┐
│  [Load .zip…]                            │  → FileDialog (native, *.zip)
│ ─────────────────────────────────────── │
│  <pack name>           — <author> (N)    │  ← ItemList row per pack
│  Keen Fan Remix        — modder   (2)    │
│ ─────────────────────────────────────── │
│  status label (last import result)       │
│  [Back]                                  │  → change_scene_to_packed(main_menu)
└──────────────────────────────────────────┘
```

Behavior:
- `_ready()`: native `FileDialog`, `file_mode = OPEN`, filter `*.zip`. Populate
  `ItemList` from `PackLoader.get_packs()` (columns: name, author,
  `levels.size()`).
- **"Load .zip…"**: on file picked → `var r := PackLoader.import_zip(path)`;
  set status label (`ok`: "Installed <pack_id>" / fail: red error text);
  repopulate list.
- **Launch**: double-click a row → `GameManager.start_pack(pack_id)`. (Single
  select just highlights; avoids accidental launches.)
- **Empty state**: if no packs, list shows "No packs installed. Click Load .zip…".
- **Back**: `change_scene_to_packed(main_menu)`.
- No pack deletion UI this plan (YAGNI).

## 7. Security & error handling

### 7.1 Zip path-traversal guard (critical — zips are user-supplied)

- Reject any entry whose path is absolute (`/`, `res://`, `user://`, drive
  letters) or contains `..` after normalization.
- Reject any path that escapes the target pack dir post-join.
- File-type allowlist: extract **only** `manifest.json`, `*.tres`, `*.res`.
  Reject anything else (no `.png`, `.gd`, `.import`, executables). Matches the
  "manifest + .tres only" decision and prevents dropping scripts.
- On any rejected entry → abort the whole import, delete the partial extraction
  dir, return `{ok:false, error:"unsafe/disallowed path in zip: <entry>"}`.

### 7.2 Import error matrix (all return `{ok:false, error:<msg>}`, no crash)

| Case | Result |
|---|---|
| zip unreadable / not a zip | `ok:false, "cannot read zip"` |
| no manifest.json in zip | `ok:false, "no manifest.json"` |
| manifest malformed / missing required fields | `ok:false, "invalid manifest"` |
| unsafe or disallowed entry | `ok:false, "unsafe/disallowed path: <x>"` + cleanup |
| duplicate pack_id already installed | overwrite (re-import), warn in log, `{ok:true}` |
| a level `.tres` fails to load at scan time | pack still registers; that level skipped + warned; scan continues |

### 7.3 Runtime lookups

`get_overworld` / `get_level` return `null` on miss; callers already null-check
(`GameManager.start_pack` warns + bails). Invalid pack selected from the menu →
status label error, no scene swap.

## 8. Testing (GUT)

All headless and deterministic. The native `FileDialog` is **not** driven; UI
tests are smoke-level only.

**`tests/fixtures/sample_pack/`** — one real fixture (committed), reused by
loader + import tests:
- `manifest.json` (the schema example above)
- `overworld.tres` — tiny `LevelData`, `map_kind = OVERWORLD`, 2×2
- `01.tres` — tiny `LevelData`, `map_kind = LEVEL`, 2×2

`test_pack_loader.gd` (**new**):
- `scan()` over a temp `user://levelpacks/test_pack/` (copy fixture in) →
  `get_pack`, `get_levels`, `get_overworld`, `is_installed` correct.
- missing manifest / malformed JSON / non-`LevelData` file → skipped, no crash.
- zero overworlds → pack rejected; two overworlds → first wins.
- duplicate `pack_id` → last wins.
- `before_each`/`after_each` clean `user://levelpacks/` so tests are isolated.

`test_pack_import.gd` (**new**):
- build a real zip at runtime via `ZIPPacker` from the fixture → `import_zip` →
  asserts files at `user://levelpacks/<pack_id>/`, `get_pack` resolves, returns
  `{ok:true}`.
- traversal zip (entry `../evil.tres`) → `{ok:false}`, nothing extracted.
- disallowed-type zip (entry `hack.gd`) → `{ok:false}`.
- no-manifest zip → `{ok:false}`.
- re-import same pack → overwrites canonical dir, `{ok:true}`.

`test_game_manager_loop.gd` (**extend** existing):
- seed `PackLoader` (or its caches) with a fake pack →
  `start_pack_no_scene_swap` → state `OVERWORLD`, `_levels_by_id` populated with
  overworld + levels, `current_episode_id == pack_id`, progress cleared.

`test_pack_select_ui.gd` (**new**, light smoke):
- instantiate `pack_select.tscn`; with a stubbed/seeded `PackLoader` assert the
  `ItemList` populates; assert empty-state text when no packs.

### 8.1 Test hygiene

Tests must not pollute the real `user://levelpacks/`. Each importing/loader test
backs up any existing packs dir, runs against a clean temp, and restores in
`after_each`. (The fixture-copy approach keeps assertions deterministic.)

## 9. Plan / phasing (for writing-plans)

Suggested task order (full breakdown deferred to the implementation plan):

1. `PackLoader.scan()` + caches + queries + scan rules (no import yet); unit tests.
2. `import_zip()` extraction + sanitization + allowlist + temp-dir move; import tests.
3. `GameManager.start_pack` / `start_pack_no_scene_swap`; extend loop test.
4. `pack_select` scene + `main_menu` wiring; UI smoke test.
5. Autoload ordering + fixture authoring.
6. Full `./tests/run_all.sh` green; manual smoke via `make edit` / `make run-app`.
