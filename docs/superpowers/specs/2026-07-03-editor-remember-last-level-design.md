# Editor: Remember Last Opened Level

**Date:** 2026-07-03
**Status:** Approved (design)
**Scope:** Level editor only. No runtime/data-model changes.

## Problem

Every time the editor is opened fresh (app restart, or main menu → Editor with no
`GameManager.pending_level`), it starts on a blank `Untitled` level. The file the
user was last editing is gone from context: they must hit Load and re-navigate to
the same `.tres` every session. For iterative level work this is friction.

## Goal

On a fresh editor open, automatically reopen the `.tres` file the user last saved
or loaded, so they resume exactly where they left off. Fail silently and safely to
a blank level when the remembered file is gone or unreadable.

## Decisions (confirmed with user)

1. **Behavior:** auto-reopen. A fresh editor open silently loads the remembered
   file into the canvas (no prompt, no extra click).
2. **What counts as "last":** the path of the file last **saved** *or* **loaded**
   — the file actively being worked on.
3. **`New` does not erase memory.** Starting a blank level must not make the user
   lose track of the real file; memory is updated only by a successful save/load.
4. **Persistence:** a Godot `ConfigFile` at `user://editor.cfg`, section
   `editor`, key `last_level_path`. Idiomatic, ~15 lines, crash-safe (written on
   every save/load), survives reinstalls.
5. **Test ▶ unchanged:** the in-session `GameManager.pending_level` round-trip
   still takes priority over disk recall.

## Architecture

No new classes, autoloads, or scenes. The change is localized to
`src/editor/level_editor.gd` following its existing patterns
(`_restore_or_new`, `_on_load_path`, `_on_save_path`).

### Data flow — write (memory)

```
_on_save_path(path)        _on_load_path(path)
        │                          │
        ▼                          ▼
   [save ok]            _load_from_path(path) ──► existing load body (factored out)
        │                          │
        └──────────┬───────────────┘
                   ▼
          _remember_path(path)        ← NEW
             ├─ cfg = ConfigFile.new()
             ├─ cfg.set_value("editor", "last_level_path", path)
             └─ cfg.save("user://editor.cfg")
```

### Data flow — read (auto-reopen)

```
_ready()
   └─ _restore_or_new()
         ├─ GameManager.pending_level != null ──► restore (Test ▶ round-trip)   [unchanged]
         ├─ elif recalled path non-empty AND ResourceLoader.exists(path):
         │       ok = _load_from_path(path)
         │       ok  ──► level loaded, status "Reopened: <path>"
         │       !ok ──► _new_level(), status "Last level not found, started blank"
         └─ else: _new_level()                                                   [unchanged]
```

`_load_from_path` is the single load seam, reused by the dialog callback and the
auto-reopen path, so both behave identically.

## Components

### `src/editor/level_editor.gd`

- New constants near the top (after line 21):
  - `const SETTINGS_PATH := "user://editor.cfg"`
  - `const SETTINGS_SECTION := "editor"`
  - `const SETTINGS_KEY := "last_level_path"`
- **New `_load_from_path(path: String) -> bool`** — extracted from the current
  `_on_load_path` body (lines 372–382): load with `CACHE_MODE_IGNORE`, null/type
  check, on success set `level`, `undo_stack.clear()`,
  `selected_entity_index = -1`, `_last_path = path`, `_broadcast()`, return
  `true`. On failure return `false` (caller sets status). Does **not** set status
  itself — the dialog caller and the auto-reopen caller want different messages.
- **`_on_load_path(path)`** becomes:

  ```gdscript
  if _load_from_path(path):
      _remember_path(path)
      _set_status("Loaded: %s" % path)
  else:
      _set_status("Load FAILED (not a LevelData): %s" % path)
  ```

  Remembering lives in the dialog success branch, **not** in `_load_from_path`, so
  the auto-reopen path (which reuses `_load_from_path`) doesn't redundantly
  rewrite the unchanged path.
- **`_on_save_path(path)`** (lines 363–369): after a successful `ResourceSaver`,
  call `_remember_path(path)`. (`_last_path = path` already set on line 364.)
- **New `_remember_path(path: String) -> void`** — open `SETTINGS_PATH` via
  `ConfigFile`, `set_value(SETTINGS_SECTION, SETTINGS_KEY, path)`, save. Errors
  from `cfg.save` are ignored (memory is best-effort; never block editing).
- **New `_recall_path() -> String`** — load `SETTINGS_PATH`; on any load error
  return `""`; else return `cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY, "")`
  as String.
- **`_restore_or_new()`** (lines 50–60): insert a new `elif` branch between the
  `pending_level` branch and the `else`:

  ```gdscript
  elif not _try_reopen_last():
      _new_level()
  ```

  where **`_try_reopen_last() -> bool`** reads `_recall_path()`; if empty → return
  `false`; if not `ResourceLoader.exists(path)` → status hint + return `false`;
  else call `_load_from_path(path)`: on success status `"Reopened: %s"` + return
  `true`; on failure status hint + return `false`.

No changes to `_new_level` (it already resets `_last_path = ""` for the session;
memory on disk is untouched, per decision 3).

## Edge cases & behavior

| Case | Behavior |
|------|----------|
| No cfg / first run | `_recall_path` → `""`; blank level. No file created until first save/load. |
| Remembered file moved/deleted | `ResourceLoader.exists` false → status `Last level not found, started blank`; blank level. Memory **not** cleared (a temporarily-moved file isn't forgotten). |
| Remembered file corrupt / not a LevelData | `_load_from_path` returns false → same status hint; blank level. Memory not cleared. |
| `res://` path (shipped level) | Works — `ResourceLoader.exists` and load cover both `res://` and `user://`. |
| User hits New after a reopen | Blank level for the session; memory on disk unchanged, so next open still reopens the real file. |
| Test ▶ then quit app mid-runtime | `pending_level` is gone next session, but the persisted path (set when the level was saved/loaded before Test) still reopens it. |
| ConfigFile save fails (read-only user dir) | Ignored; editing continues; reopen just won't work next session. No crash. |

## Testing

GUT, run via `./tests/run_all.sh` (must pass before commit). Unit-testable seams
are the pure helpers; extend `tests/unit/test_editor_workflow.gd`:

- `_remember_path(p)` then `_recall_path()` returns `p` (round-trip).
- `_recall_path()` with no/partial cfg returns `""` (delete the cfg in
  `before_each`/`after_each` to isolate tests).
- `_load_from_path` on a valid saved `.tres` (reuse the existing
  `test_full_editor_workflow_then_serialize` fixture) returns true and sets
  `level` + `_last_path`.
- `_load_from_path` on a non-existent path returns false and leaves `level`
  unchanged.
- `_load_from_path` on a file that is not a LevelData returns false.

`_try_reopen_last` end-to-end (cfg → load → status) is verified by a manual
editor run: save a level, quit, reopen editor, confirm it reopens and the status
reads `Reopened: ...`; then point the cfg at a bogus path, reopen, confirm the
blank-level fallback and status hint.

## Out of scope

- Remembering more than the path (e.g. scroll position, active tool/layer,
  selection). Path only for now.
- A UI toggle to disable auto-reopen. YAGNI; `New` is the escape hatch.
- Multiple recent files / a recent-files list. Single last file only.
- Remembering unsaved in-memory edits (no path → nothing to remember).
