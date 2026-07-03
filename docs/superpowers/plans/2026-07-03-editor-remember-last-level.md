# Editor: Remember Last Opened Level — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the level editor auto-reopen the `.tres` file the user last saved or loaded on every fresh editor open, falling back safely to a blank level when the file is gone/unreadable.

**Architecture:** All change is localized to `src/editor/level_editor.gd`. A Godot `ConfigFile` at `user://editor.cfg` stores the last path. The existing load body is extracted into `_load_from_path(path) -> bool`, reused by both the Load dialog callback and a new `_try_reopen_last()` that `_restore_or_new()` calls when there is no in-session `GameManager.pending_level`.

**Tech Stack:** Godot 4.7, GDScript, GUT (vendored in `addons/gut/`).

**Spec:** `docs/superpowers/specs/2026-07-03-editor-remember-last-level-design.md`

**Commands:**
- Full test suite: `make test` (or `./tests/run_all.sh`)
- Single test file:
  `GODOT="/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gselect=res://tests/unit/test_editor_workflow.gd -gexit -gdisable_colors`
- Godot binary: `/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot`

**Key invariants (critical):**
- `_load_from_path` must NOT call `_remember_path` and must NOT set status — only the Load-dialog caller remembers (on success) and each caller sets its own status message.
- `New` (`_new_level`) must NOT clear the on-disk memory; it only resets the in-session `_last_path`.
- The Test ▶ branch (`GameManager.pending_level != null`) stays first in `_restore_or_new` and is unchanged.

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `src/editor/level_editor.gd` | Modify | Add persistence constants + `_remember_path`/`_recall_path`; extract `_load_from_path`; remember on save/load; auto-reopen via `_try_reopen_last` in `_restore_or_new` |
| `tests/unit/test_editor_workflow.gd` | Modify | Add `before_each` cfg cleanup + GUT cases for the new helpers |

No new files, no autoload/scene changes.

---

## Reference: final changed regions of `src/editor/level_editor.gd`

> Target state after Tasks 1–3. Each task below shows the exact code it adds. The three regions touched are: the constants block, `_restore_or_new`, and the save/load section.

**Constants block (after `DEFAULT_HEIGHT`):**
```gdscript
const DEFAULT_WIDTH := 32
const DEFAULT_HEIGHT := 24
const SETTINGS_PATH := "user://editor.cfg"
const SETTINGS_SECTION := "editor"
const SETTINGS_KEY := "last_level_path"
```

**`_restore_or_new` (only the tail changes — `else: _new_level()` → `elif not _try_reopen_last(): _new_level()`):**
```gdscript
func _restore_or_new() -> void:
	if GameManager != null and GameManager.pending_level != null:
		level = GameManager.pending_level
		undo_stack.clear()
		selected_entity_index = -1
		_last_path = ""
		# Consume the stash so a later non-Test editor open starts fresh.
		GameManager.pending_level = null
		GameManager.return_scene = null
	elif not _try_reopen_last():
		_new_level()
```

**Save/load + persistence section (replaces current `_on_save_path`/`_on_load_path` and adds new helpers):**
```gdscript
func _on_save_path(path: String) -> void:
	_last_path = path
	var err := ResourceSaver.save(level, path)
	if err == OK:
		_remember_path(path)
		_set_status("Saved: %s" % path)
	else:
		_set_status("Save FAILED (error %d): %s" % [err, path])


func _on_load_path(path: String) -> void:
	if _load_from_path(path):
		_remember_path(path)
		_set_status("Loaded: %s" % path)
	else:
		_set_status("Load FAILED (not a LevelData): %s" % path)


## Loads a .tres into the editor without touching the dialog. Returns true on
## success. Does not set status (callers choose their own message) and does not
## touch disk memory (the dialog caller remembers on success; auto-reopen does
## not, since the path is unchanged).
func _load_from_path(path: String) -> bool:
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	if loaded == null:
		return false
	level = loaded
	undo_stack.clear()
	selected_entity_index = -1
	_last_path = path
	_broadcast()
	return true


# ------------------------------------------------------------------ persistence

## Best-effort: remember the last file path so the next fresh editor open can
## reopen it. Never raises — memory is a convenience, not a requirement.
func _remember_path(path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY, path)
	cfg.save(SETTINGS_PATH)


## Returns the last remembered file path, or "" if none/unreadable.
func _recall_path() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return ""
	return cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY, "") as String


## On a fresh open (no Test ▶ round-trip), reopen the last remembered file if it
## still exists and loads cleanly. Returns true when a level was loaded, false
## when the editor should fall back to a blank level.
func _try_reopen_last() -> bool:
	var path := _recall_path()
	if path.is_empty():
		return false
	if not ResourceLoader.exists(path):
		_set_status("Last level not found, started blank: %s" % path)
		return false
	if _load_from_path(path):
		_set_status("Reopened: %s" % path)
		return true
	_set_status("Last level not loadable, started blank: %s" % path)
	return false
```

---

### Task 1: Persistence helpers (`_remember_path` / `_recall_path`)

**Files:**
- Modify: `src/editor/level_editor.gd` (constants block ~line 21; new helpers appended in the save/load section after `_on_load_path` ~line 382)
- Test: `tests/unit/test_editor_workflow.gd`

- [ ] **Step 1: Add test isolation + failing tests**

Add a `before_each` to `tests/unit/test_editor_workflow.gd` (the file currently has only `after_each`). Place it directly above the existing `func after_each():`:

```gdscript
func before_each():
	# Each editor-memory test must start with no leftover cfg on disk.
	DirAccess.remove_absolute("user://editor.cfg")
```

Then append these two tests at the end of the file:

```gdscript
func test_remember_then_recall_path_round_trips():
	var ed := LevelEditor.new()
	ed._remember_path("user://tests/some_level.tres")
	assert_eq(ed._recall_path(), "user://tests/some_level.tres")


func test_recall_with_no_config_returns_empty():
	var ed := LevelEditor.new()
	assert_eq(ed._recall_path(), "")
```

- [ ] **Step 2: Run tests to verify they fail**

Run the single-file test command (see **Commands** above).
Expected: FAIL — `_remember_path` / `_recall_path` not defined on `LevelEditor`.

- [ ] **Step 3: Add the constants**

In `src/editor/level_editor.gd`, find:
```gdscript
const DEFAULT_WIDTH := 32
const DEFAULT_HEIGHT := 24
```
Add immediately after:
```gdscript
const SETTINGS_PATH := "user://editor.cfg"
const SETTINGS_SECTION := "editor"
const SETTINGS_KEY := "last_level_path"
```

- [ ] **Step 4: Add the helper methods**

In `src/editor/level_editor.gd`, find the end of `_on_load_path` (the `_set_status("Loaded: %s" % path)` line, ~line 382). Insert this block directly after it (before the `# ----- refresh` section comment):

```gdscript


# ------------------------------------------------------------------ persistence

## Best-effort: remember the last file path so the next fresh editor open can
## reopen it. Never raises — memory is a convenience, not a requirement.
func _remember_path(path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY, path)
	cfg.save(SETTINGS_PATH)


## Returns the last remembered file path, or "" if none/unreadable.
func _recall_path() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return ""
	return cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY, "") as String
```

- [ ] **Step 5: Run tests to verify they pass**

Run the single-file test command.
Expected: PASS for both new tests.

- [ ] **Step 6: Commit**

```bash
git add src/editor/level_editor.gd tests/unit/test_editor_workflow.gd
git commit -m "feat(editor): persist last level path to user config"
```

---

### Task 2: Extract `_load_from_path` + remember on save/load

**Files:**
- Modify: `src/editor/level_editor.gd` (`_on_save_path` ~line 363, `_on_load_path` ~line 372)
- Test: `tests/unit/test_editor_workflow.gd`

- [ ] **Step 1: Add failing tests**

Append at the end of `tests/unit/test_editor_workflow.gd`:

```gdscript
func test_load_from_path_loads_valid_level_and_sets_last_path():
	var ld := _level()
	var path := "user://tests/test_remember_load.tres"
	DirAccess.make_dir_recursive_absolute("user://tests/")
	assert_eq(ResourceSaver.save(ld, path), OK)
	var ed := LevelEditor.new()
	ed.undo_stack = UndoStack.new()
	assert_true(ed._load_from_path(path))
	assert_not_null(ed.level)
	assert_eq(ed._last_path, path)


func test_load_from_path_returns_false_for_missing_file():
	var ed := LevelEditor.new()
	ed.undo_stack = UndoStack.new()
	assert_false(ed._load_from_path("user://tests/does_not_exist_12345.tres"))
	assert_null(ed.level)


func test_load_from_path_returns_false_for_non_leveldata():
	var path := "user://tests/test_remember_notlevel.tres"
	DirAccess.make_dir_recursive_absolute("user://tests/")
	var r := Resource.new()
	assert_eq(ResourceSaver.save(r, path), OK)
	var ed := LevelEditor.new()
	ed.undo_stack = UndoStack.new()
	assert_false(ed._load_from_path(path))
```

- [ ] **Step 2: Run tests to verify they fail**

Run the single-file test command.
Expected: FAIL — `_load_from_path` not defined on `LevelEditor`.

- [ ] **Step 3: Extract `_load_from_path` and rewire the dialog callbacks**

In `src/editor/level_editor.gd`, replace the entire current `_on_load_path` function:

```gdscript
func _on_load_path(path: String) -> void:
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	if loaded == null:
		_set_status("Load FAILED (not a LevelData): %s" % path)
		return
	level = loaded
	undo_stack.clear()
	selected_entity_index = -1
	_last_path = path
	_broadcast()
	_set_status("Loaded: %s" % path)
```

with:

```gdscript
func _on_load_path(path: String) -> void:
	if _load_from_path(path):
		_remember_path(path)
		_set_status("Loaded: %s" % path)
	else:
		_set_status("Load FAILED (not a LevelData): %s" % path)


## Loads a .tres into the editor without touching the dialog. Returns true on
## success. Does not set status (callers choose their own message) and does not
## touch disk memory (the dialog caller remembers on success; auto-reopen does
## not, since the path is unchanged).
func _load_from_path(path: String) -> bool:
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	if loaded == null:
		return false
	level = loaded
	undo_stack.clear()
	selected_entity_index = -1
	_last_path = path
	_broadcast()
	return true
```

- [ ] **Step 4: Remember path on save**

In `src/editor/level_editor.gd`, replace the current `_on_save_path`:

```gdscript
func _on_save_path(path: String) -> void:
	_last_path = path
	var err := ResourceSaver.save(level, path)
	if err == OK:
		_set_status("Saved: %s" % path)
	else:
		_set_status("Save FAILED (error %d): %s" % [err, path])
```

with:

```gdscript
func _on_save_path(path: String) -> void:
	_last_path = path
	var err := ResourceSaver.save(level, path)
	if err == OK:
		_remember_path(path)
		_set_status("Saved: %s" % path)
	else:
		_set_status("Save FAILED (error %d): %s" % [err, path])
```

- [ ] **Step 5: Run tests to verify they pass**

Run the single-file test command.
Expected: PASS for all editor-workflow tests (new + existing).

- [ ] **Step 6: Commit**

```bash
git add src/editor/level_editor.gd tests/unit/test_editor_workflow.gd
git commit -m "refactor(editor): extract _load_from_path, remember on save/load"
```

---

### Task 3: Auto-reopen via `_try_reopen_last` in `_restore_or_new`

**Files:**
- Modify: `src/editor/level_editor.gd` (`_restore_or_new` ~line 50; add `_try_reopen_last` in the persistence section)
- Test: `tests/unit/test_editor_workflow.gd`

- [ ] **Step 1: Add failing tests**

Append at the end of `tests/unit/test_editor_workflow.gd`:

```gdscript
func test_try_reopen_last_returns_false_with_no_memory():
	var ed := LevelEditor.new()
	ed.undo_stack = UndoStack.new()
	assert_false(ed._try_reopen_last())
	assert_null(ed.level)


func test_try_reopen_last_opens_remembered_valid_file():
	var ld := _level()
	var path := "user://tests/test_remember_reopen.tres"
	DirAccess.make_dir_recursive_absolute("user://tests/")
	assert_eq(ResourceSaver.save(ld, path), OK)
	var ed := LevelEditor.new()
	ed.undo_stack = UndoStack.new()
	ed._remember_path(path)
	assert_true(ed._try_reopen_last())
	assert_not_null(ed.level)
	assert_eq(ed._last_path, path)


func test_try_reopen_last_falls_back_when_file_missing():
	var ed := LevelEditor.new()
	ed.undo_stack = UndoStack.new()
	ed._remember_path("user://tests/gone_12345.tres")
	assert_false(ed._try_reopen_last())
	assert_null(ed.level)
```

- [ ] **Step 2: Run tests to verify they fail**

Run the single-file test command.
Expected: FAIL — `_try_reopen_last` not defined on `LevelEditor`.

- [ ] **Step 3: Add `_try_reopen_last`**

In `src/editor/level_editor.gd`, find the `_recall_path` method added in Task 1. Insert this method directly after the end of `_recall_path` (still inside the `# ----- persistence` section):

```gdscript


## On a fresh open (no Test ▶ round-trip), reopen the last remembered file if it
## still exists and loads cleanly. Returns true when a level was loaded, false
## when the editor should fall back to a blank level.
func _try_reopen_last() -> bool:
	var path := _recall_path()
	if path.is_empty():
		return false
	if not ResourceLoader.exists(path):
		_set_status("Last level not found, started blank: %s" % path)
		return false
	if _load_from_path(path):
		_set_status("Reopened: %s" % path)
		return true
	_set_status("Last level not loadable, started blank: %s" % path)
	return false
```

- [ ] **Step 4: Wire it into `_restore_or_new`**

In `src/editor/level_editor.gd`, replace the tail of `_restore_or_new`. Change:

```gdscript
	else:
		_new_level()
```

(the final two lines of `_restore_or_new`) to:

```gdscript
	elif not _try_reopen_last():
		_new_level()
```

- [ ] **Step 5: Run the full test suite**

Run: `make test`
Expected: PASS — all tests green (new editor-memory tests + every existing test).

- [ ] **Step 6: Commit**

```bash
git add src/editor/level_editor.gd tests/unit/test_editor_workflow.gd
git commit -m "feat(editor): auto-reopen last level on fresh editor open"
```

---

### Task 4: Manual end-to-end verification

**Files:** none (manual run).

- [ ] **Step 1: Clean slate**

Delete any stale memory so the first run shows the blank-fallback:
```bash
rm -f "$(godot --headless --path . --quit 2>/dev/null; echo)" 2>/dev/null
```
If the above is awkward on your host, instead just launch the editor once, hit **New**, then quit — no path is remembered yet.

- [ ] **Step 2: Build + launch**

```bash
make run-app
```

- [ ] **Step 3: Happy path — reopen**

1. Main menu → **Editor** (should start blank — no memory yet).
2. Paint a few tiles, place an entity.
3. **Save** → pick `~/keen_levels/verify_reopen.tres` (create the folder if needed). Status reads `Saved: ...`.
4. Quit the app completely.

- [ ] **Step 4: Confirm reopen**

1. `make run-app` again.
2. Main menu → **Editor**.
3. **Expected:** the saved level loads automatically; status bar reads `Reopened: .../verify_reopen.tres`; the painted tiles + entity are present.

- [ ] **Step 5: Missing-file fallback**

1. Quit, then delete or rename `verify_reopen.tres` on disk.
2. `make run-app` → Main menu → **Editor**.
3. **Expected:** blank `Untitled` level; status reads `Last level not found, started blank: ...`.

- [ ] **Step 6: New does not erase memory**

1. Re-save `verify_reopen.tres` (so memory points at it again), quit, relaunch, confirm it reopens.
2. In the editor hit **New** → blank level. Quit.
3. Relaunch → **Editor**. **Expected:** `verify_reopen.tres` reopens again (memory survived the New).

If all six steps behave as described, the feature is complete.

---

## Self-Review notes

- **Spec coverage:** decisions 1–5 and every edge-case row map to a task/step. `_load_from_path` non-LevelData case (spec edge: "corrupt / not a LevelData") → Task 2 test `test_load_from_path_returns_false_for_non_leveldata` and `_try_reopen_last`'s final `_load_from_path` failure branch. "res:// path works" → covered by `ResourceLoader.exists`/load (no special-casing needed). "New does not erase memory" → Task 4 Step 6 manual check.
- **Type consistency:** method names (`_remember_path`, `_recall_path`, `_load_from_path`, `_try_reopen_last`) and constants (`SETTINGS_PATH/SECTION/KEY`) are identical across all tasks and the reference block.
- **No placeholders.** Every code step contains full, copy-pasteable GDScript.
