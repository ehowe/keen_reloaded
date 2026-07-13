# Plan 6c — Persistence (Save/Load) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add disk-based save/load with 6 named slots, auto-save at overworld transitions, and manual save via a pause menu — wiring the existing `GameManager.serialize()`/`deserialize()` seams to `user://saves/`.

**Architecture:** A new `SaveSystem` autoload owns all slot file I/O and the active-slot concept; `GameManager` keeps its session-state role and gains minimal hooks (`SaveSystem.save_active()` at each state→OVERWORLD transition). Both bundled episodes and custom packs are saveable. Atomic writes (temp + rename) with `.bak` rollback. Slot-select screen + pause menu are the two new UI scenes.

**Tech Stack:** Godot 4.7, GDScript, GUT (headless tests), JSON for slot files.

**Spec:** `docs/superpowers/specs/2026-07-13-plan6c-persistence-design.md`

---

## File Structure

**Create:**
- `src/core/save_system.gd` — `SaveSystem` autoload; slot file I/O, active-slot tracking, validation, versioning.
- `src/ui/slot_select.gd` + `src/ui/slot_select.tscn` — reusable slot-select screen (modes: new_game, continue).
- `src/ui/pause_menu.gd` + `src/ui/pause_menu.tscn` — Esc pause overlay (Resume / Save / Load / Quit).
- `tests/unit/test_save_system.gd` — GUT suite for SaveSystem.
- `tests/unit/test_slot_select_ui.gd` — GUT suite for slot-select logic.

**Modify:**
- `src/core/game_manager.gd` — add `current_scope_kind`; extend `serialize()`/`deserialize()`; add `resume_overworld()`; refactor `start_pack` clear; add auto-save hooks in `complete_level`/`fail_level`/`teleport`.
- `src/ui/main_menu.gd` + `src/ui/main_menu.tscn` — add Continue + New Game buttons.
- `src/ui/pack_select.gd` — route pack start through slot-select.
- `project.godot` — register `SaveSystem` autoload.

**Conventions (from existing code):**
- Tabs for GDScript indentation.
- Tests: `extends GutTest`, `before_each`/`after_each`, `assert_eq`/`assert_true`/`assert_false`/`assert_null`/`assert_not_null`.
- Filesystem tests override a `*_dir` instance var to a temp path, clean in `before_each`/`after_each` (mirrors `PackLoader.root_dir` pattern).
- Autoloads referenced by global name (`GameManager`, `PackLoader`, `SaveSystem`).
- Scene nodes use `unique_name_in_owner = true` for `%NodeName` access.
- Run tests: `./tests/run_all.sh` (headless Godot).

---

## Task 1: GameManager — `current_scope_kind` + serialize/deserialize

Adds a `current_scope_kind` field so `SaveSystem` can tag saves as episode vs pack, and extends the serialize seam to carry it. No behavior change yet — field is set in Task 5.

**Files:**
- Modify: `src/core/game_manager.gd`
- Test: `tests/unit/test_game_manager_loop.gd`

- [ ] **Step 1: Write the failing test**

Add to `tests/unit/test_game_manager_loop.gd` (append a new test function; do not modify existing tests):

```gdscript
func test_current_scope_kind_defaults_episode():
	assert_eq(GameManager.current_scope_kind, "episode")


func test_serialize_carries_scope_kind_and_round_trips():
	GameManager.current_scope_kind = "pack"
	GameManager.current_episode_id = "mypack"
	GameManager.mark_completed("lvl1")
	var data := GameManager.serialize()
	assert_eq(data.get("current_scope_kind", ""), "pack")
	GameManager.clear_progress()
	assert_eq(GameManager.current_scope_kind, "episode")
	GameManager.deserialize(data)
	assert_eq(GameManager.current_scope_kind, "pack")
	assert_eq(GameManager.current_episode_id, "mypack")
	assert_true(GameManager.is_level_completed("lvl1"))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh 2>&1 | grep -E "test_current_scope_kind|test_serialize_carries"`
Expected: FAIL — `current_scope_kind` property not found / serialize missing key.

- [ ] **Step 3: Add the field + reset**

In `src/core/game_manager.gd`, after the `current_episode_id` declaration (line 21), add:

```gdscript
# "episode" or "pack". Set by start_episode/start_pack so SaveSystem can tag
# saves and resume_overworld can pick the right overworld resolver.
var current_scope_kind: String = "episode"
```

In `clear_progress()` (around line 31), add `current_scope_kind = "episode"` inside the body, e.g. after `current_episode_id = ""`.

- [ ] **Step 4: Extend serialize/deserialize**

Replace the `serialize()` and `deserialize()` methods (lines 252–265) with:

```gdscript
## Save-ready hooks. SaveSystem wraps this payload with slot metadata.
func serialize() -> Dictionary:
	return {
		"completed_levels": completed_levels.duplicate(),
		"current_episode_id": current_episode_id,
		"current_scope_kind": current_scope_kind,
	}


func deserialize(data: Dictionary) -> void:
	completed_levels.clear()
	var loaded: Array = data.get("completed_levels", [])
	for id in loaded:
		completed_levels.append(String(id))
	current_episode_id = String(data.get("current_episode_id", ""))
	# Older saves (pre-Plan-6c) lack this key; default to "episode".
	current_scope_kind = String(data.get("current_scope_kind", "episode"))
```

- [ ] **Step 5: Run full test suite to verify pass + no regressions**

Run: `./tests/run_all.sh`
Expected: all tests PASS (existing `test_serialize_deserialize_round_trip` still passes since it ignores the new key).

- [ ] **Step 6: Commit**

```bash
git add src/core/game_manager.gd tests/unit/test_game_manager_loop.gd
git commit -m "feat(game): add current_scope_kind + extend serialize/deserialize"
```

---

## Task 2: SaveSystem autoload — `save_slot` + `save_active` + `clear_active`

Creates the autoload, registers it, and implements the save path (happy + atomic write + `.bak` rotate). Load/list/delete come in Tasks 3–4.

**Files:**
- Create: `src/core/save_system.gd`
- Modify: `project.godot` (add autoload)
- Test: `tests/unit/test_save_system.gd` (new)

- [ ] **Step 1: Create the test file with failing save tests**

Create `tests/unit/test_save_system.gd`:

```gdscript
extends GutTest

const TMP := "user://tmp_savetest/"

func before_each():
	SaveSystem.saves_dir = TMP
	SaveSystem.active_slot = 0
	_clean(TMP)
	GameManager.clear_progress()

func after_each():
	_clean(TMP)
	SaveSystem.saves_dir = SaveSystem.DEFAULT_SAVES_DIR
	SaveSystem.active_slot = 0
	GameManager.clear_progress()

func _clean(path: String) -> void:
	DirAccess.remove_absolute(path + "slot_1.json")
	DirAccess.remove_absolute(path + "slot_1.json.bak")
	DirAccess.remove_absolute(path + "slot_1.json.tmp")
	DirAccess.remove_absolute(path + "slot_2.json")
	DirAccess.remove_absolute(path + "slot_2.json.bak")
	DirAccess.remove_absolute(path + "slot_3.json")
	DirAccess.remove_absolute(path + "slot_6.json")
	DirAccess.remove_absolute(TMP)

func _seed_game(kind: String = "episode", scope_id: String = "keen1") -> void:
	GameManager.current_scope_kind = kind
	GameManager.current_episode_id = scope_id
	GameManager.mark_completed("lvl_a")
	GameManager.mark_completed("lvl_b")

func test_save_slot_writes_valid_json_file():
	_seed_game()
	var ok := SaveSystem.save_slot(1)
	assert_true(ok)
	assert_true(FileAccess.file_exists(TMP + "slot_1.json"))

func test_save_slot_round_trips_payload_fields():
	_seed_game("episode", "keen1")
	assert_true(SaveSystem.save_slot(1))
	var text := FileAccess.get_file_as_string(TMP + "slot_1.json")
	var parser := JSON.new()
	assert_eq(parser.parse(text), OK)
	var d: Dictionary = parser.data
	assert_eq(d["version"], SaveSystem.CURRENT_VERSION)
	assert_eq(d["kind"], "episode")
	assert_eq(d["scope_id"], "keen1")
	assert_eq(d["completed_count"], 2)
	assert_eq(d["data"]["current_episode_id"], "keen1")
	assert_eq(d["data"]["current_scope_kind"], "episode")
	assert_eq((d["data"]["completed_levels"] as Array).size(), 2)

func test_save_slot_sets_active_slot():
	_seed_game()
	assert_eq(SaveSystem.active_slot, 0)
	assert_true(SaveSystem.save_slot(3))
	assert_eq(SaveSystem.active_slot, 3)

func test_save_slot_rejects_out_of_range():
	_seed_game()
	assert_false(SaveSystem.save_slot(0))
	assert_false(SaveSystem.save_slot(7))

func test_save_slot_rotates_bak_from_previous():
	_seed_game()
	assert_true(SaveSystem.save_slot(1))
	var first := FileAccess.get_file_as_string(TMP + "slot_1.json")
	# Change state and save again — previous content should land in .bak.
	GameManager.mark_completed("lvl_c")
	assert_true(SaveSystem.save_slot(1))
	assert_true(FileAccess.file_exists(TMP + "slot_1.json.bak"))
	assert_eq(FileAccess.get_file_as_string(TMP + "slot_1.json.bak"), first)

func test_save_active_noop_when_no_active_slot():
	_seed_game()
	SaveSystem.active_slot = 0
	assert_true(SaveSystem.save_active())  # no-op, returns true
	assert_false(FileAccess.file_exists(TMP + "slot_1.json"))

func test_save_active_writes_to_active_slot():
	_seed_game()
	SaveSystem.active_slot = 2
	assert_true(SaveSystem.save_active())
	assert_true(FileAccess.file_exists(TMP + "slot_2.json"))

func test_clear_active_resets_to_zero():
	SaveSystem.active_slot = 5
	SaveSystem.clear_active()
	assert_eq(SaveSystem.active_slot, 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh 2>&1 | grep -E "SaveSystem|test_save"`
Expected: FAIL — `SaveSystem` identifier not found (autoload not registered yet).

- [ ] **Step 3: Create `src/core/save_system.gd`**

```gdscript
extends Node
## Disk persistence for GameManager session state. Owns slot file I/O and the
## active-slot concept. Calls GameManager.serialize()/deserialize() — does not
## own session state itself.
##
## Slot files live at <saves_dir>/slot_<N>.json (N = 1..SLOT_COUNT). Writes are
## atomic: payload is written to .tmp, the previous good save is copied to .bak,
## then .tmp is renamed over the slot file. load_slot falls back to .bak if the
## primary file fails validation.

const SLOT_COUNT := 6
const CURRENT_VERSION := 1
const DEFAULT_SAVES_DIR := "user://saves/"

# Overridable in tests (mirrors PackLoader.root_dir pattern).
var saves_dir: String = DEFAULT_SAVES_DIR

# Active slot for this session. 0 = none (save_active is a no-op). In-memory
# only; never persisted as its own field.
var active_slot: int = 0


## Persist GameManager.serialize() to the slot file. Atomic write + .bak rotate.
## Sets active_slot. Returns true on success, false on disk/arg failure.
func save_slot(slot: int) -> bool:
	if slot < 1 or slot > SLOT_COUNT:
		push_error("SaveSystem: invalid slot %d" % slot)
		return false
	var data := GameManager.serialize()
	var kind: String = data.get("current_scope_kind", "episode")
	var scope_id: String = data.get("current_episode_id", "")
	var completed: Array = data.get("completed_levels", [])
	var payload := {
		"version": CURRENT_VERSION,
		"kind": kind,
		"scope_id": scope_id,
		"scope_title": _resolve_scope_title(kind, scope_id),
		"saved_at": int(Time.get_unix_time_from_system()),
		"completed_count": completed.size(),
		"data": data,
	}
	_ensure_dir()
	var base := saves_dir + "slot_%d.json" % slot
	var tmp := base + ".tmp"
	var bak := base + ".bak"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: cannot open %s for write" % tmp)
		return false
	f.store_string(JSON.stringify(payload, "  "))
	f.close()
	# Rotate backup from the previous good save (if any). Best-effort.
	if FileAccess.file_exists(base):
		if DirAccess.copy_absolute(base, bak) != OK:
			push_warning("SaveSystem: could not rotate .bak for slot %d" % slot)
	if DirAccess.rename_absolute(tmp, base) != OK:
		push_error("SaveSystem: cannot rename tmp to %s" % base)
		DirAccess.remove_absolute(tmp)
		return false
	active_slot = slot
	return true


## Save to the active slot. No-op (returns true) when active_slot == 0.
func save_active() -> bool:
	if active_slot == 0:
		return true
	return save_slot(active_slot)


func clear_active() -> void:
	active_slot = 0


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(saves_dir):
		DirAccess.make_dir_recursive_absolute(saves_dir)


## Resolve a human-readable scope title for the cached slot metadata. Falls
## back to scope_id when the source is unavailable (e.g. pack uninstalled).
func _resolve_scope_title(kind: String, scope_id: String) -> String:
	if kind == "pack":
		var p := PackLoader.get_pack(scope_id)
		if p != null:
			return p.pack_name
		return scope_id
	for ep in GameManager.episodes:
		if String(ep.get("id", "")) == scope_id:
			return String(ep.get("title", scope_id))
	return scope_id
```

- [ ] **Step 4: Register the autoload in `project.godot`**

In `project.godot`, find the `[autoload]` section (currently ends with `AudioManager`). Add `SaveSystem` as the last entry so all other autoloads are ready before it runs:

```
[autoload]
PackLoader="*res://src/core/pack_loader.gd"
GameManager="*res://src/core/game_manager.gd"
EntityRegistry="*res://src/core/entity_registry.gd"

AudioManager="*res://src/core/audio_manager.gd"
SaveSystem="*res://src/core/save_system.gd"
```

(Only the new `SaveSystem=...` line is added; preserve the existing section formatting and any blank lines/comments exactly.)

- [ ] **Step 5: Run tests to verify pass**

Run: `./tests/run_all.sh`
Expected: all `test_save_*` tests PASS; no regressions.

- [ ] **Step 6: Commit**

```bash
git add src/core/save_system.gd project.godot tests/unit/test_save_system.gd
git commit -m "feat(save): SaveSystem autoload with atomic save_slot + .bak rotate"
```

---

## Task 3: SaveSystem — `load_slot` + validation + `.bak` fallback

Implements the load path: read, validate (version + required keys), apply via `deserialize`, `.bak` fallback on corrupt primary.

**Files:**
- Modify: `src/core/save_system.gd` (add `load_slot` + `_read_and_validate`)
- Test: `tests/unit/test_save_system.gd` (add tests)

- [ ] **Step 1: Add failing load tests**

Append to `tests/unit/test_save_system.gd`:

```gdscript
func test_load_slot_round_trips_into_game_manager():
	_seed_game("episode", "keen1")
	assert_true(SaveSystem.save_slot(1))
	GameManager.clear_progress()
	assert_false(GameManager.is_level_completed("lvl_a"))
	assert_true(SaveSystem.load_slot(1))
	assert_true(GameManager.is_level_completed("lvl_a"))
	assert_true(GameManager.is_level_completed("lvl_b"))
	assert_eq(GameManager.current_episode_id, "keen1")
	assert_eq(GameManager.current_scope_kind, "episode")
	assert_eq(SaveSystem.active_slot, 1)

func test_load_slot_missing_file_returns_false():
	GameManager.clear_progress()
	assert_false(SaveSystem.load_slot(2))
	assert_eq(SaveSystem.active_slot, 0)

func test_load_slot_corrupt_json_returns_false():
	_seed_game()
	assert_true(SaveSystem.save_slot(1))
	# Corrupt the primary file. No .bak yet (only one save) → load fails.
	var f := FileAccess.open(TMP + "slot_1.json", FileAccess.WRITE)
	f.store_string("{ not valid json")
	f.close()
	assert_false(SaveSystem.load_slot(1))

func test_load_slot_falls_back_to_bak_when_primary_corrupt():
	_seed_game()
	assert_true(SaveSystem.save_slot(1))   # creates base
	_seed_game()
	GameManager.mark_completed("lvl_c")
	assert_true(SaveSystem.save_slot(1))   # rotates base → .bak
	# Now corrupt the primary; .bak holds the previous good save.
	var f := FileAccess.open(TMP + "slot_1.json", FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	GameManager.clear_progress()
	assert_true(SaveSystem.load_slot(1))   # recovers from .bak
	# .bak was the first save (2 completions: lvl_a, lvl_b).
	assert_true(GameManager.is_level_completed("lvl_a"))
	assert_false(GameManager.is_level_completed("lvl_c"))

func test_load_slot_rejects_future_version():
	_seed_game()
	assert_true(SaveSystem.save_slot(1))
	var text := FileAccess.get_file_as_string(TMP + "slot_1.json")
	text = text.replace('"version": 1', '"version": 999')
	var f := FileAccess.open(TMP + "slot_1.json", FileAccess.WRITE)
	f.store_string(text)
	f.close()
	assert_false(SaveSystem.load_slot(1))

func test_load_slot_rejects_missing_data_key():
	_seed_game()
	assert_true(SaveSystem.save_slot(1))
	# Hand-write a file that lacks the "data" key.
	var f := FileAccess.open(TMP + "slot_1.json", FileAccess.WRITE)
	f.store_string('{"version": 1, "kind": "episode", "scope_id": "keen1"}')
	f.close()
	assert_false(SaveSystem.load_slot(1))

func test_load_slot_rejects_out_of_range():
	assert_false(SaveSystem.load_slot(0))
	assert_false(SaveSystem.load_slot(7))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh 2>&1 | grep -E "test_load"`
Expected: FAIL — `load_slot` not defined.

- [ ] **Step 3: Implement `load_slot` + `_read_and_validate`**

Add to `src/core/save_system.gd` (after `save_slot`):

```gdscript
## Read a slot, validate, apply to GameManager via deserialize(), set active_slot.
## Falls back to <slot>.bak if the primary file fails validation. Returns true
## on success; on any failure GameManager is left untouched and active_slot
## is unchanged.
func load_slot(slot: int) -> bool:
	if slot < 1 or slot > SLOT_COUNT:
		push_error("SaveSystem: invalid slot %d" % slot)
		return false
	var base := saves_dir + "slot_%d.json" % slot
	var payload := _read_and_validate(base)
	if payload == null:
		var bak := base + ".bak"
		if FileAccess.file_exists(bak):
			payload = _read_and_validate(bak)
			if payload == null:
				return false
			push_warning("SaveSystem: slot %d primary corrupt, loaded .bak" % slot)
		else:
			return false
	GameManager.deserialize(payload["data"])
	active_slot = slot
	return true


## Read + JSON-parse + validate a slot file. Returns the validated Dictionary
## (the full envelope including "data"), or null on any failure.
func _read_and_validate(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = parsed
	if not d.has("version") or not d.has("data"):
		return null
	var ver: int = int(d["version"])
	if ver != CURRENT_VERSION:
		return null  # forward-incompatible or pre-migration; no converters yet
	if typeof(d["data"]) != TYPE_DICTIONARY:
		return null
	return d
```

- [ ] **Step 4: Run tests to verify pass**

Run: `./tests/run_all.sh`
Expected: all `test_load_*` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/save_system.gd tests/unit/test_save_system.gd
git commit -m "feat(save): load_slot with validation + .bak fallback"
```

---

## Task 4: SaveSystem — `list_slots` + `delete_slot`

Implements slot metadata listing (for the slot-select grid) with granular status (`empty`/`occupied`/`corrupt`/`missing_pack`/`unsupported_version`), and slot deletion.

**Files:**
- Modify: `src/core/save_system.gd`
- Test: `tests/unit/test_save_system.gd`

- [ ] **Step 1: Add failing list/delete tests**

Append to `tests/unit/test_save_system.gd`:

```gdscript
func test_list_slots_all_empty_by_default():
	var slots := SaveSystem.list_slots()
	assert_eq(slots.size(), SaveSystem.SLOT_COUNT)
	for s in slots:
		assert_eq(s["status"], "empty")

func test_list_slots_marks_occupied_after_save():
	_seed_game("episode", "keen1")
	assert_true(SaveSystem.save_slot(2))
	var slots := SaveSystem.list_slots()
	assert_eq(slots[1]["status"], "occupied")
	assert_eq(slots[1]["slot"], 2)
	assert_eq(slots[1]["kind"], "episode")
	assert_eq(slots[1]["scope_id"], "keen1")
	assert_eq(slots[1]["scope_title"], "keen1")
	assert_eq(slots[1]["completed_count"], 2)
	assert_true(int(slots[1]["saved_at"]) > 0)
	# Other slots still empty.
	assert_eq(slots[0]["status"], "empty")
	assert_eq(slots[3]["status"], "empty")

func test_list_slots_corrupt_json():
	var f := FileAccess.open(TMP + "slot_3.json", FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	var slots := SaveSystem.list_slots()
	assert_eq(slots[2]["status"], "corrupt")

func test_list_slots_unsupported_version():
	var f := FileAccess.open(TMP + "slot_4.json", FileAccess.WRITE)
	f.store_string('{"version": 999, "data": {}}')
	f.close()
	var slots := SaveSystem.list_slots()
	assert_eq(slots[3]["status"], "unsupported_version")

func test_list_slots_missing_pack():
	# Save a pack slot for a pack that is not installed.
	_seed_game("pack", "ghost_pack")
	# Force the file to exist even though PackLoader has no such pack: save
	# writes scope_title fallback = scope_id.
	assert_true(SaveSystem.save_slot(5))
	# PackLoader.get_overworld("ghost_pack") is null → missing_pack.
	var slots := SaveSystem.list_slots()
	assert_eq(slots[4]["status"], "missing_pack")
	assert_eq(slots[4]["kind"], "pack")

func test_list_slots_pack_present_marks_occupied():
	# Install a real pack and seed a save against it.
	const PK := "user://tmp_savetest_pack/"
	PackLoader.root_dir = PK
	DirAccess.make_dir_recursive_absolute(PK + "realpack/")
	ResourceSaver.save(_real_overworld(), PK + "realpack/overworld.tres")
	var mf := FileAccess.open(PK + "realpack/manifest.json", FileAccess.WRITE)
	mf.store_string('{"pack_id": "realpack", "name": "Real", "author": "qa", "version": "1.0", "levels": [{"level_id": "ow", "file": "overworld.tres", "name": "OW", "order": 0}]}')
	mf.close()
	PackLoader.scan()
	_seed_game("pack", "realpack")
	assert_true(SaveSystem.save_slot(6))
	var slots := SaveSystem.list_slots()
	assert_eq(slots[5]["status"], "occupied")
	assert_eq(slots[5]["scope_title"], "Real")
	# cleanup
	PackLoader._remove_dir_recursive(PK)
	PackLoader.root_dir = "user://levelpacks/"

func _real_overworld() -> LevelData:
	var ld := LevelData.new()
	ld.level_id = "ow"
	ld.width = 2
	ld.height = 2
	ld.fill_blank()
	ld.map_kind = LevelData.MapKind.OVERWORLD
	return ld

func test_delete_slot_removes_file_and_bak():
	_seed_game()
	assert_true(SaveSystem.save_slot(1))
	GameManager.mark_completed("lvl_c")
	assert_true(SaveSystem.save_slot(1))   # creates .bak
	assert_true(FileAccess.file_exists(TMP + "slot_1.json"))
	assert_true(FileAccess.file_exists(TMP + "slot_1.json.bak"))
	SaveSystem.delete_slot(1)
	assert_false(FileAccess.file_exists(TMP + "slot_1.json"))
	assert_false(FileAccess.file_exists(TMP + "slot_1.json.bak"))

func test_delete_slot_clears_active_if_match():
	SaveSystem.active_slot = 3
	SaveSystem.delete_slot(3)
	assert_eq(SaveSystem.active_slot, 0)

func test_delete_slot_out_of_range_noop():
	SaveSystem.delete_slot(0)  # no crash
	SaveSystem.delete_slot(9)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh 2>&1 | grep -E "test_list_slots|test_delete"`
Expected: FAIL — `list_slots`/`delete_slot` not defined.

- [ ] **Step 3: Implement `list_slots` + `_slot_status` + `delete_slot`**

Add to `src/core/save_system.gd`:

```gdscript
## Read metadata for every slot 1..SLOT_COUNT. Each entry is a Dictionary:
##   {"slot": N, "status": "empty"|"occupied"|"corrupt"|"missing_pack"|
##                       "unsupported_version", ...metadata}
## Does NOT touch GameManager. Resolves pack validity via PackLoader.
func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in range(1, SLOT_COUNT + 1):
		out.append(_slot_status(slot))
	return out


func _slot_status(slot: int) -> Dictionary:
	var base := saves_dir + "slot_%d.json" % slot
	var entry := {"slot": slot}
	if not FileAccess.file_exists(base):
		entry["status"] = "empty"
		return entry
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(base)) != OK:
		entry["status"] = "corrupt"
		return entry
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		entry["status"] = "corrupt"
		return entry
	var d: Dictionary = parsed
	if not d.has("version") or not d.has("data") or not d.has("kind") or not d.has("scope_id"):
		entry["status"] = "corrupt"
		return entry
	var ver: int = int(d["version"])
	if ver != CURRENT_VERSION:
		entry["status"] = "unsupported_version"
		entry["version"] = ver
		return entry
	var kind: String = String(d["kind"])
	var scope_id: String = String(d["scope_id"])
	if kind == "pack" and PackLoader.get_overworld(scope_id) == null:
		entry["status"] = "missing_pack"
	else:
		entry["status"] = "occupied"
	entry["kind"] = kind
	entry["scope_id"] = scope_id
	entry["scope_title"] = String(d.get("scope_title", scope_id))
	entry["saved_at"] = int(d.get("saved_at", 0))
	entry["completed_count"] = int(d.get("completed_count", 0))
	return entry


## Remove a slot file and its .bak. Used by corrupt/missing-pack cleanup and
## explicit user "clear slot" actions.
func delete_slot(slot: int) -> void:
	if slot < 1 or slot > SLOT_COUNT:
		return
	var base := saves_dir + "slot_%d.json" % slot
	if FileAccess.file_exists(base):
		DirAccess.remove_absolute(base)
	var bak := base + ".bak"
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(bak)
	if active_slot == slot:
		active_slot = 0
```

- [ ] **Step 4: Run tests to verify pass**

Run: `./tests/run_all.sh`
Expected: all `test_list_slots_*` and `test_delete_slot_*` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/save_system.gd tests/unit/test_save_system.gd
git commit -m "feat(save): list_slots with status classification + delete_slot"
```

---

## Task 5: GameManager — `resume_overworld` + `start_pack` refactor + auto-save hooks

Wires the load path into GameManager and adds the auto-save hooks at every state→OVERWORLD transition.

**Files:**
- Modify: `src/core/game_manager.gd`
- Test: `tests/unit/test_game_manager_loop.gd`

- [ ] **Step 1: Extend the existing before_each/after_each to reset SaveSystem**

The file already has `before_each` (calls `GameManager.clear_progress()`) and `after_each` (clears progress + `PackLoader._remove_dir_recursive(PL_TMP)` + resets `PackLoader.root_dir`). Add SaveSystem reset to both so every test in the file starts and ends clean. Add this const + helper near the existing `PL_TMP` const (line ~151), then modify the two lifecycle methods:

Add the const + helper (near `PL_TMP`):
```gdscript
const SAVES_TMP := "user://tmp_gm_saves/"

func _restore_save_dir():
	PackLoader._remove_dir_recursive(SAVES_TMP)
	SaveSystem.saves_dir = SaveSystem.DEFAULT_SAVES_DIR
	SaveSystem.active_slot = 0
```

Modify `before_each` to:
```gdscript
func before_each():
	GameManager.clear_progress()
	SaveSystem.saves_dir = SAVES_TMP
	SaveSystem.active_slot = 0
	PackLoader._remove_dir_recursive(SAVES_TMP)
```

Modify `after_each` to (append one line):
```gdscript
func after_each():
	GameManager.clear_progress()
	PackLoader._remove_dir_recursive(PL_TMP)
	PackLoader.root_dir = "user://levelpacks/"
	_restore_save_dir()
```

Now append the new test functions (they rely on the above cleanup, so no per-test teardown needed):

```gdscript
func test_resume_overworld_episode_registers_levels_without_clearing():
	# Seed completion state as if loaded from a save.
	GameManager.current_scope_kind = "episode"
	GameManager.current_episode_id = "keen1"
	GameManager.mark_completed("keen1_01")
	var ep := GameManager._find_episode("keen1")
	assert_not_null(ep)
	var ow := ep.load_overworld()
	assert_not_null(ow)
	# resume_overworld_no_scene_swap must register the overworld + episode
	# levels without wiping the just-restored completion set.
	var ok := GameManager.resume_overworld_no_scene_swap()
	assert_true(ok)
	assert_eq(GameManager.state, GameManager.State.OVERWORLD)
	assert_eq(GameManager.current_overworld, ow)
	assert_not_null(GameManager.get_level_by_id("keen1_01"))
	assert_true(GameManager.is_level_completed("keen1_01"), "completion preserved")


func test_resume_overworld_missing_episode_returns_false():
	GameManager.current_scope_kind = "episode"
	GameManager.current_episode_id = "no_such_episode"
	assert_false(GameManager.resume_overworld_no_scene_swap())


func test_start_pack_no_scene_swap_does_not_clear_progress():
	# Per Plan 6c: start_pack_no_scene_swap no longer hard-clears; the public
	# start_pack wrapper clears for the new-game path, and the load path uses
	# resume_overworld_no_scene_swap instead.
	GameManager.mark_completed("pre_existing")
	var ow := LevelData.new()
	ow.level_id = "ow"
	ow.width = 2
	ow.height = 2
	ow.fill_blank()
	ow.map_kind = LevelData.MapKind.OVERWORLD
	_seed_pack_loader("clrpack", ow, [])
	GameManager.start_pack_no_scene_swap("clrpack", ow)
	assert_true(GameManager.is_level_completed("pre_existing"), "progress must survive _no_scene_swap")
	assert_eq(GameManager.current_scope_kind, "pack")


func test_save_active_noop_without_active_slot():
	# save_active must be a no-op (no file/dir created) when active_slot == 0.
	SaveSystem.active_slot = 0
	assert_true(SaveSystem.save_active())
	assert_false(DirAccess.dir_exists_absolute(SAVES_TMP))


func test_serialize_carries_scope_kind_post_resume():
	# After resume sets scope_kind, serialize must round-trip it.
	GameManager.current_scope_kind = "pack"
	var data := GameManager.serialize()
	assert_eq(data["current_scope_kind"], "pack")
	GameManager.clear_progress()
	GameManager.deserialize(data)
	assert_eq(GameManager.current_scope_kind, "pack")
```
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh 2>&1 | grep -E "test_resume_overworld|test_start_pack_no_scene_swap_does_not"`
Expected: FAIL — `resume_overworld_no_scene_swap` not defined; start_pack_no_scene_swap still clears.

- [ ] **Step 3: Refactor `start_pack_no_scene_swap` (drop unconditional clear)**

In `src/core/game_manager.gd`, replace the body of `start_pack_no_scene_swap` (lines ~204–217). The caller now owns the clear-or-restore decision:

```gdscript
## Non-scene-swap variant for headless tests. Does NOT call clear_progress():
## the public start_pack wrapper clears for the new-game path, and the load
## path (resume_overworld_no_scene_swap) restores progress via deserialize
## before calling this. Here we only register levels + set state.
func start_pack_no_scene_swap(pack_id: String, ow: LevelData) -> void:
	current_episode_id = pack_id
	current_scope_kind = "pack"
	current_overworld = ow
	# Explicit overworld register mirrors start_episode; the loop below re-registers
	# it (same cached instance) — idempotent and harmless.
	register_level(ow)
	for lvl in PackLoader.get_levels(pack_id):
		register_level(lvl)
	pending_level = ow
	pending_player_spawn = Vector2i(-1, -1)
	state = State.OVERWORLD
```

Then update the public `start_pack` wrapper (lines ~195–201) so the new-game path still clears:

```gdscript
## Boot a custom level pack: resolve its overworld, register every pack level,
## then swap to the runtime scene in OVERWORLD state. Reuses the existing
## enter/complete/fail loop. (Bundled episodes use start_episode instead.)
## New-game path: clears progress for a fresh session.
func start_pack(pack_id: String) -> void:
	var ow := PackLoader.get_overworld(pack_id)
	if ow == null:
		push_warning("GameManager: pack '%s' has no overworld" % pack_id)
		return
	clear_progress()
	start_pack_no_scene_swap(pack_id, ow)
	get_tree().change_scene_to_packed(RUNTIME_SCENE)
```

Also set `current_scope_kind = "episode"` inside `start_episode_no_scene_swap` (after `current_episode_id = ep_id`):

```gdscript
func start_episode_no_scene_swap(ep_id: String, ow: LevelData) -> void:
	current_episode_id = ep_id
	current_scope_kind = "episode"
	current_overworld = ow
	register_level(ow)
	# Register every LEVEL-kind map in the episode so level entrances resolve.
	var ep := _find_episode(ep_id)
	if ep != null:
		for lvl in ep.load_levels():
			register_level(lvl)
	pending_level = ow
	pending_player_spawn = Vector2i(-1, -1)
	state = State.OVERWORLD
```

- [ ] **Step 4: Add `resume_overworld` (load-path entry)**

Add these two methods to `src/core/game_manager.gd` (after `start_pack_no_scene_swap`):

```gdscript
## Resume the overworld for the current scope (episode or pack) after a save
## load. Registers levels WITHOUT clearing progress (deserialize already
## restored completed_levels). Returns false if the overworld is gone.
func resume_overworld_no_scene_swap() -> bool:
	var ow: LevelData = null
	if current_scope_kind == "pack":
		ow = PackLoader.get_overworld(current_episode_id)
		if ow == null:
			push_warning("GameManager: cannot resume — pack '%s' overworld gone" % current_episode_id)
			return false
		for lvl in PackLoader.get_levels(current_episode_id):
			register_level(lvl)
	else:
		ow = _resolve_overworld(current_episode_id)
		if ow == null:
			push_warning("GameManager: cannot resume — episode '%s' overworld gone" % current_episode_id)
			return false
		var ep := _find_episode(current_episode_id)
		if ep != null:
			for lvl in ep.load_levels():
				register_level(lvl)
	current_overworld = ow
	register_level(ow)
	pending_level = ow
	pending_player_spawn = Vector2i(-1, -1)
	pending_teleport_arrival_id = ""
	current_level = null
	state = State.OVERWORLD
	return true


## Scene-swap wrapper for the load path. Called by the slot-select UI after
## SaveSystem.load_slot has restored session state.
func resume_overworld() -> void:
	if not resume_overworld_no_scene_swap():
		return
	get_tree().change_scene_to_packed(RUNTIME_SCENE)
```

- [ ] **Step 5: Add auto-save hooks in scene-swap transitions**

In `src/core/game_manager.gd`:

Replace `complete_level()` (lines ~87–89):
```gdscript
func complete_level() -> void:
	complete_level_no_scene_swap()
	SaveSystem.save_active()
	get_tree().change_scene_to_packed(RUNTIME_SCENE)
```

Replace `fail_level()` (lines ~104–106):
```gdscript
func fail_level() -> void:
	fail_level_no_scene_swap()
	SaveSystem.save_active()
	get_tree().change_scene_to_packed(RUNTIME_SCENE)
```

Replace `teleport()` (lines ~122–126) to save only when the destination is the overworld:
```gdscript
func teleport(destination_level_id: String, destination_teleporter_id: String) -> bool:
	if not teleport_no_scene_swap(destination_level_id, destination_teleporter_id):
		return false
	# Auto-save only when the teleport lands us back on an overworld.
	if state == State.OVERWORLD:
		SaveSystem.save_active()
	get_tree().change_scene_to_packed(RUNTIME_SCENE)
	return true
```

The `_no_scene_swap` variants are deliberately NOT hooked — they are headless-test entry points and must not touch disk.

- [ ] **Step 6: Run full test suite**

Run: `./tests/run_all.sh`
Expected: ALL tests PASS. Existing tests that use `_no_scene_swap` variants are unaffected (no hook, and `active_slot == 0` makes `save_active` a no-op anyway).

- [ ] **Step 7: Commit**

```bash
git add src/core/game_manager.gd tests/unit/test_game_manager_loop.gd
git commit -m "feat(game): resume_overworld + start_pack clear refactor + auto-save hooks"
```

---

## Task 6: Slot-select UI (scene + script + test)

Reusable screen parameterized by mode (`new_game` or `continue`). Renders 6 slot cards with status-specific labels. Tested headlessly by injecting canned `list_slots` data.

**Files:**
- Create: `src/ui/slot_select.gd`
- Create: `src/ui/slot_select.tscn`
- Test: `tests/unit/test_slot_select_ui.gd`

- [ ] **Step 1: Create the failing UI logic test**

Create `tests/unit/test_slot_select_ui.gd`:

```gdscript
extends GutTest

const SLOT_SELECT := preload("res://src/ui/slot_select.tscn")

func before_each():
	SaveSystem.saves_dir = "user://tmp_slot_ui/"
	PackLoader._remove_dir_recursive("user://tmp_slot_ui/")

func after_each():
	PackLoader._remove_dir_recursive("user://tmp_slot_ui/")
	SaveSystem.saves_dir = SaveSystem.DEFAULT_SAVES_DIR
	GameManager.clear_progress()

func test_card_text_empty():
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)
	assert(ss._card_text({"slot": 1, "status": "empty"}).find("Empty") >= 0)
	ss.queue_free()

func test_card_text_occupied():
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)
	var t := ss._card_text({"slot": 2, "status": "occupied", "scope_title": "Keen 1",
		"completed_count": 3, "saved_at": 1700000000, "kind": "episode", "scope_id": "keen1"})
	assert(t.find("Keen 1") >= 0)
	assert(t.find("3") >= 0)
	ss.queue_free()

func test_card_text_corrupt():
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)
	assert(ss._card_text({"slot": 3, "status": "corrupt"}).find("Corrupt") >= 0)
	ss.queue_free()

func test_card_text_missing_pack():
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)
	assert(ss._card_text({"slot": 1, "status": "missing_pack"}).find("missing") >= 0)
	ss.queue_free()

func test_card_text_unsupported_version():
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)
	assert(ss._card_text({"slot": 1, "status": "unsupported_version", "version": 999}).find("Unsupported") >= 0)
	ss.queue_free()

func test_repopulate_shows_all_six_slots():
	# add_child triggers _ready → _repopulate against the empty temp saves_dir,
	# producing one button per slot (all "empty").
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)
	assert_eq(ss.grid.get_child_count(), 6)
	ss.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh 2>&1 | grep -E "test_card_text|test_repopulate_shows"`
Expected: FAIL — `res://src/ui/slot_select.tscn` not found.

- [ ] **Step 3: Create `src/ui/slot_select.gd`**

```gdscript
extends Control
## Reusable slot-select screen. Modes:
##   "new_game" — all slots clickable; occupied → confirm overwrite; corrupt /
##               missing_pack / unsupported_version → delete-only.
##   "continue" — only valid occupied slots are clickable; rest greyed.
##
## On a successful pick, emits signal "slot_chosen(slot: int, mode: String)".
## The parent scene wires the consequence (start episode, load + resume, etc.).
## Back just removes this overlay so the parent underneath reappears.

signal slot_chosen(slot: int, mode: String)

@onready var grid: VBoxContainer = %SlotGrid
@onready var title: Label = %TitleLabel
@onready var back: Button = %BackButton

var mode: String = "new_game"


func _ready() -> void:
	%BackButton.pressed.connect(_on_back)
	_wire_ui_sfx()
	_repopulate()


func set_mode(m: String) -> void:
	mode = m
	if is_inside_tree():
		_repopulate()


## Pure function: build the human-readable label for one slot status entry.
## Unit-tested directly.
func _card_text(entry: Dictionary) -> String:
	var n := int(entry.get("slot", 0))
	var status: String = String(entry.get("status", "empty"))
	match status:
		"empty":
			return "Slot %d — Empty" % n
		"occupied":
			return "Slot %d — %s (%d cleared)" % [n, String(entry.get("scope_title", "?")), int(entry.get("completed_count", 0))]
		"corrupt":
			return "Slot %d — ⚠ Corrupt (click to delete)" % n
		"missing_pack":
			return "Slot %d — ⚠ Pack missing (click to delete)" % n
		"unsupported_version":
			return "Slot %d — ⚠ Unsupported save v%s (click to delete)" % [n, String(entry.get("version", "?"))]
	return "Slot %d — %s" % [n, status]


func _repopulate() -> void:
	for c in grid.get_children():
		c.queue_free()
	var slots := SaveSystem.list_slots()
	for entry in slots:
		var btn := Button.new()
		btn.text = _card_text(entry)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var status: String = entry["status"]
		var clickable := _is_clickable(status)
		btn.disabled = not clickable
		if clickable:
			btn.pressed.connect(_on_slot_pressed.bind(entry))
		grid.add_child(btn)


func _is_clickable(status: String) -> bool:
	if mode == "new_game":
		return true  # empty (use), occupied (overwrite), corrupt/missing/unsupported (delete)
	# continue: only valid occupied slots
	return status == "occupied"


func _on_slot_pressed(entry: Dictionary) -> void:
	var status: String = entry["status"]
	var slot_num := int(entry["slot"])
	if status == "occupied" and mode == "new_game":
		# Confirm overwrite.
		var dlg := ConfirmationDialog.new()
		dlg.title = "Overwrite slot %d?" % slot_num
		dlg.dialog_text = "This slot already contains a save. Overwrite?"
		add_child(dlg)
		dlg.confirmed.connect(func() -> void:
			slot_chosen.emit(slot_num, mode)
			dlg.queue_free())
		dlg.canceled.connect(func() -> void: dlg.queue_free())
		dlg.popup_centered()
		return
	if status in ["corrupt", "missing_pack", "unsupported_version"]:
		SaveSystem.delete_slot(slot_num)
		_repopulate()
		return
	# empty (new_game) or occupied (continue)
	slot_chosen.emit(slot_num, mode)


## Remove this overlay; the parent scene underneath reappears (main menu, pause
## menu, or pack select). Works in every context because the parent decides what
## is behind this screen.
func _on_back() -> void:
	queue_free()


func _wire_ui_sfx() -> void:
	for b in find_children("*", "Button", true, false):
		(b as Button).focus_entered.connect(_on_button_focus)
		(b as Button).pressed.connect(_on_button_select)


func _on_button_focus() -> void:
	AudioManager.play_sfx("menu_move")


func _on_button_select() -> void:
	AudioManager.play_sfx("menu_select")
```

- [ ] **Step 4: Create `src/ui/slot_select.tscn`**

```gdscene
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/slot_select.gd" id="1_ss"]

[node name="SlotSelect" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_ss")

[node name="BG" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0.05, 0.04, 0.08, 1)

[node name="TitleLabel" type="Label" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -320.0
offset_top = -240.0
offset_right = 320.0
offset_bottom = -200.0
grow_horizontal = 2
grow_vertical = 2
text = "Select Slot"
horizontal_alignment = 1
vertical_alignment = 1

[node name="Scroll" type="ScrollContainer" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -240.0
offset_top = -180.0
offset_right = 240.0
offset_bottom = 120.0
grow_horizontal = 2
grow_vertical = 2

[node name="SlotGrid" type="VBoxContainer" parent="Scroll"]
unique_name_in_owner = true
layout_mode = 2
size_flags_horizontal = 3

[node name="BackButton" type="Button" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -60.0
offset_top = 130.0
offset_right = 60.0
offset_bottom = 170.0
grow_horizontal = 2
grow_vertical = 2
text = "Back"
```

- [ ] **Step 5: Run tests to verify pass**

Run: `./tests/run_all.sh`
Expected: all `test_card_text_*` and `test_repopulate_shows_all_six_slots` PASS. (`test_repopulate_shows_all_six_slots` relies on `_ready` calling `_repopulate` exactly once against the clean temp `saves_dir`.)

- [ ] **Step 6: Commit**

```bash
git add src/ui/slot_select.gd src/ui/slot_select.tscn tests/unit/test_slot_select_ui.gd
git commit -m "feat(ui): slot-select screen with status-aware card labels"
```

---

## Task 7: Main menu — New Game + Continue buttons

Adds the two entry points. New Game → slot-select (new_game mode) → start keen1 in chosen slot. Continue → slot-select (continue mode) → load + resume. Play button stays as a dev fast-path.

**Files:**
- Modify: `src/ui/main_menu.tscn` (add buttons)
- Modify: `src/ui/main_menu.gd` (wire new buttons)

- [ ] **Step 1: Rewrite `src/ui/main_menu.tscn` with the two new buttons**

Replace the entire contents of `src/ui/main_menu.tscn` with:

```
[gd_scene format=3 uid="uid://dj54t8muj1ckb"]

[ext_resource type="Script" uid="uid://c8jo7jac6y0v1" path="res://src/ui/main_menu.gd" id="1_menu"]

[node name="MainMenu" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_menu")

[node name="ColorRect" type="ColorRect"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0.05, 0.04, 0.08, 1)

[node name="Title" type="Label"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -320.0
offset_top = -170.0
offset_right = 320.0
offset_bottom = -110.0
grow_horizontal = 2
grow_vertical = 2
text = "Commander Keen Reloaded"
horizontal_alignment = 1
vertical_alignment = 1

[node name="Subtitle" type="Label"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -320.0
offset_top = -110.0
offset_right = 320.0
offset_bottom = -80.0
grow_horizontal = 2
grow_vertical = 2
text = "Click Play to Demo"
horizontal_alignment = 1
vertical_alignment = 1

[node name="ContinueButton" type="Button"]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -90.0
offset_top = -60.0
offset_right = 90.0
offset_bottom = -20.0
grow_horizontal = 2
grow_vertical = 2
text = "Continue"

[node name="NewGameButton" type="Button"]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -90.0
offset_top = -10.0
offset_right = 90.0
offset_bottom = 30.0
grow_horizontal = 2
grow_vertical = 2
text = "New Game"

[node name="PlayButton" type="Button"]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -90.0
offset_top = 40.0
offset_right = 90.0
offset_bottom = 80.0
grow_horizontal = 2
grow_vertical = 2
text = "Play (dev)"

[node name="CustomPacksButton" type="Button"]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -90.0
offset_top = 90.0
offset_right = 90.0
offset_bottom = 130.0
grow_horizontal = 2
grow_vertical = 2
text = "Custom Packs"

[node name="EditorButton" type="Button"]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -90.0
offset_top = 140.0
offset_right = 90.0
offset_bottom = 180.0
grow_horizontal = 2
grow_vertical = 2
text = "Open Level Editor"

[node name="QuitButton" type="Button"]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -90.0
offset_top = 190.0
offset_right = 90.0
offset_bottom = 230.0
grow_horizontal = 2
grow_vertical = 2
text = "Quit"
```

The `ext_resource` line preserves the existing script UID. If Godot rewrites UIDs on import, re-open once via `make edit` and save — functionally identical.

- [ ] **Step 2: Wire the buttons in `src/ui/main_menu.gd`**

Replace the full contents of `src/ui/main_menu.gd` with:

```gdscript
extends Control

const EDITOR_SCENE := preload("res://src/editor/level_editor.tscn")
const PACK_SELECT := preload("res://src/ui/pack_select.tscn")
const SLOT_SELECT := preload("res://src/ui/slot_select.tscn")

func _ready() -> void:
	AudioManager.play_music(AudioManager.MUSIC_THEME)
	_ensure_play_button()
	_wire_button(%ContinueButton, _continue)
	_wire_button(%NewGameButton, _new_game)
	%CustomPacksButton.pressed.connect(_open_pack_select)
	%EditorButton.pressed.connect(_open_editor)
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())
	_wire_ui_sfx()
	_update_continue_enabled()


func _wire_ui_sfx() -> void:
	for b in find_children("*", "Button", true, false):
		(b as Button).focus_entered.connect(_on_button_focus)
		(b as Button).pressed.connect(_on_button_select)


func _wire_button(btn: Button, fn: Callable) -> void:
	if btn != null:
		btn.pressed.connect(fn)


func _on_button_focus() -> void:
	AudioManager.play_sfx("menu_move")


func _on_button_select() -> void:
	AudioManager.play_sfx("menu_select")


## Continue is only meaningful if at least one slot holds a valid save.
func _update_continue_enabled() -> void:
	if has_node("%ContinueButton"):
		var has_occupied := false
		for s in SaveSystem.list_slots():
			if s["status"] == "occupied":
				has_occupied = true
				break
		(%ContinueButton as Button).disabled = not has_occupied


func _ensure_play_button() -> void:
	if has_node("%PlayButton"):
		(%PlayButton as Button).pressed.connect(_play)
		return
	var play := Button.new()
	play.name = "PlayButton"
	play.text = "Play (dev)"
	play.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(play)
	play.set("theme_type_variation", "Button")
	play.pressed.connect(_play)


## Dev fast-path: start keen1 in the first empty slot (or slot 1).
func _play() -> void:
	_start_new_game_in_first_empty_slot("keen1")


func _start_new_game_in_first_empty_slot(scope_id: String) -> void:
	var slot := _first_empty_slot()
	if slot == 0:
		slot = 1
	SaveSystem.active_slot = slot
	GameManager.clear_progress()
	GameManager.current_scope_kind = "episode"
	GameManager.start_episode(scope_id)
	SaveSystem.save_active()


func _first_empty_slot() -> int:
	for s in SaveSystem.list_slots():
		if s["status"] == "empty":
			return int(s["slot"])
	return 0


func _new_game() -> void:
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)  # @onready vars (title, grid) resolve here
	ss.set_mode("new_game")
	ss.title.text = "New Game — Choose Slot"
	ss.slot_chosen.connect(_on_new_game_slot_chosen)


func _on_new_game_slot_chosen(slot: int, _mode: String) -> void:
	SaveSystem.active_slot = slot
	# For v1 New Game defaults to the only bundled episode (keen1). When a
	# second episode ships, insert an episode-select step here.
	GameManager.clear_progress()
	GameManager.current_scope_kind = "episode"
	GameManager.start_episode("keen1")
	SaveSystem.save_active()


func _continue() -> void:
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)
	ss.set_mode("continue")
	ss.title.text = "Continue — Choose Slot"
	ss.slot_chosen.connect(_on_continue_slot_chosen)


func _on_continue_slot_chosen(slot: int, _mode: String) -> void:
	if not SaveSystem.load_slot(slot):
		push_warning("MainMenu: failed to load slot %d" % slot)
		return
	GameManager.resume_overworld()


func _open_editor() -> void:
	get_tree().change_scene_to_packed(EDITOR_SCENE)


func _open_pack_select() -> void:
	get_tree().change_scene_to_packed(PACK_SELECT)
```

- [ ] **Step 3: Run full test suite (smoke check for autoload/scene health)**

Run: `./tests/run_all.sh`
Expected: all tests PASS. (Main menu UI is not unit-tested for layout; logic is covered by SaveSystem + slot-select tests. The `has_node("%ContinueButton")` guards keep tests that don't load this scene safe.)

- [ ] **Step 4: Commit**

```bash
git add src/ui/main_menu.tscn src/ui/main_menu.gd
git commit -m "feat(menu): New Game + Continue buttons wired to slot-select"
```

---

## Task 8: Pause menu (Esc) — Resume / Save / Load / Quit

In-game overlay. Esc toggles. Save writes to active slot (overworld-only). Quit auto-saves first.

**Files:**
- Create: `src/ui/pause_menu.gd`
- Create: `src/ui/pause_menu.tscn`
- Modify: `src/core/game_manager.gd` (Esc detection — minimal `_unhandled_input`)

- [ ] **Step 1: Create `src/ui/pause_menu.gd`**

```gdscript
extends CanvasLayer
## Pause overlay. Toggled by Esc (ui_cancel) via GameManager._unhandled_input.
## Save Game is gated to overworld + active slot. Load reopens slot-select.
## Quit to Menu auto-saves first (best-effort).

const MAIN_MENU := preload("res://src/ui/main_menu.tscn")
const SLOT_SELECT := preload("res://src/ui/slot_select.tscn")

@onready var save_btn: Button = %SaveButton
@onready var status: Label = %StatusLabel


func _ready() -> void:
	layer = 100
	# PROCESS_MODE_ALWAYS so the overlay (and any slot-select child) still
	# receive input while get_tree().paused is true.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	%ResumeButton.pressed.connect(_on_resume)
	%SaveButton.pressed.connect(_on_save)
	%LoadButton.pressed.connect(_on_load)
	%QuitButton.pressed.connect(_on_quit)
	_wire_ui_sfx()


func _unhandled_input(event: InputEvent) -> void:
	# Esc closes the menu. (GameManager opens it; it can't run while paused, so
	# the close path lives here on the ALWAYS overlay.)
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_refresh_save_button()
	status.text = ""
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


func _refresh_save_button() -> void:
	# Save is only allowed on the overworld with an active slot chosen.
	var allowed := GameManager.state == GameManager.State.OVERWORLD and SaveSystem.active_slot != 0
	save_btn.disabled = not allowed


func _on_resume() -> void:
	close()


func _on_save() -> void:
	if SaveSystem.active_slot == 0:
		status.text = "No active slot."
		return
	if SaveSystem.save_slot(SaveSystem.active_slot):
		status.text = "Saved to slot %d." % SaveSystem.active_slot
	else:
		status.text = "Save failed."


func _on_load() -> void:
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)  # @onready vars resolve here
	ss.set_mode("continue")
	ss.title.text = "Load — Choose Slot"
	ss.slot_chosen.connect(_on_load_slot_chosen)


func _on_load_slot_chosen(slot: int, _mode: String) -> void:
	if not SaveSystem.load_slot(slot):
		status.text = "Load failed."
		return
	close()
	GameManager.resume_overworld()


func _on_quit() -> void:
	# Best-effort auto-save before leaving.
	SaveSystem.save_active()
	SaveSystem.clear_active()
	get_tree().paused = false
	get_tree().change_scene_to_packed(MAIN_MENU)


func _wire_ui_sfx() -> void:
	for b in find_children("*", "Button", true, false):
		(b as Button).focus_entered.connect(_on_button_focus)
		(b as Button).pressed.connect(_on_button_select)


func _on_button_focus() -> void:
	AudioManager.play_sfx("menu_move")


func _on_button_select() -> void:
	AudioManager.play_sfx("menu_select")
```

- [ ] **Step 2: Create `src/ui/pause_menu.tscn`**

```gdscene
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/pause_menu.gd" id="1_pm"]

[node name="PauseMenu" type="CanvasLayer"]
process_mode = 3
script = ExtResource("1_pm")

[node name="Dim" type="ColorRect" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0, 0, 0, 0.6)

[node name="Panel" type="Panel" parent="."]
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -150.0
offset_top = -160.0
offset_right = 150.0
offset_bottom = 160.0
grow_horizontal = 2
grow_vertical = 2

[node name="VBox" type="VBoxContainer" parent="Panel"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 20.0
offset_top = 20.0
offset_right = -20.0
offset_bottom = -20.0
theme_override_constants_separation = 10

[node name="ResumeButton" type="Button" parent="Panel/VBox"]
unique_name_in_owner = true
layout_mode = 2
text = "Resume"

[node name="SaveButton" type="Button" parent="Panel/VBox"]
unique_name_in_owner = true
layout_mode = 2
text = "Save Game"

[node name="LoadButton" type="Button" parent="Panel/VBox"]
unique_name_in_owner = true
layout_mode = 2
text = "Load Game"

[node name="QuitButton" type="Button" parent="Panel/VBox"]
unique_name_in_owner = true
layout_mode = 2
text = "Quit to Main Menu"

[node name="StatusLabel" type="Label" parent="Panel/VBox"]
unique_name_in_owner = true
layout_mode = 2
horizontal_alignment = 1
```

- [ ] **Step 3: Add Esc toggle in GameManager**

Add to `src/core/game_manager.gd`, inside the class (e.g. after `_ready`):

```gdscript
const PAUSE_MENU := preload("res://src/ui/pause_menu.tscn")

var _pause_menu: CanvasLayer = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	# No pause in menu or test mode.
	if state == State.MENU or state == State.TEST:
		return
	if _pause_menu == null:
		_pause_menu = PAUSE_MENU.instantiate()
		get_tree().root.add_child(_pause_menu)
	if _pause_menu.visible:
		_pause_menu.close()
	else:
		_pause_menu.open()
```

- [ ] **Step 4: Run full test suite**

Run: `./tests/run_all.sh`
Expected: all tests PASS. (`_unhandled_input` is not exercised headlessly; Esc behavior is verified in the manual E2E test, Task 10.)

- [ ] **Step 5: Commit**

```bash
git add src/ui/pause_menu.gd src/ui/pause_menu.tscn src/core/game_manager.gd
git commit -m "feat(ui): pause menu (Esc) with save/load/quit"
```

---

## Task 9: Pack save integration — route pack start through slot-select

Currently `pack_select.gd` calls `GameManager.start_pack(pack_id)` directly. Change it to open slot-select (new_game mode) first; on slot chosen, clear + start pack + save. Pack load (continue) goes through the main-menu Continue flow already (it lists pack slots too).

**Files:**
- Modify: `src/ui/pack_select.gd`

- [ ] **Step 1: Modify `_on_item_activated` in `src/ui/pack_select.gd`**

Replace `_on_item_activated` (lines ~68–72) and add a slot-chosen handler + the slot-select preload. Update the top of the file:

Add to the const block near the top:
```gdscript
const SLOT_SELECT := preload("res://src/ui/slot_select.tscn")
```

Replace the `_on_item_activated` function with:

```gdscript
func _on_item_activated(idx: int) -> void:
	var packs := PackLoader.get_packs()
	if packs.is_empty() or idx < 0 or idx >= packs.size():
		return
	var pack_id: String = packs[idx].pack_id
	# Route through slot-select so the pack run is saveable.
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)  # @onready vars resolve here
	ss.set_mode("new_game")
	ss.title.text = "New Pack Game — Choose Slot"
	ss.slot_chosen.connect(func(slot: int, _mode: String) -> void:
		_on_pack_slot_chosen(pack_id, slot))


func _on_pack_slot_chosen(pack_id: String, slot: int) -> void:
	SaveSystem.active_slot = slot
	GameManager.clear_progress()
	GameManager.start_pack(pack_id)
	SaveSystem.save_active()
```

- [ ] **Step 2: Run full test suite**

Run: `./tests/run_all.sh`
Expected: all tests PASS. (`test_pack_select_ui.gd` calls `_repopulate` and checks list contents — does not trigger `_on_item_activated`, so it remains green. The pack-start path is exercised in the manual E2E test.)

- [ ] **Step 3: Commit**

```bash
git add src/ui/pack_select.gd
git commit -m "feat(packs): route custom pack start through slot-select"
```

---

## Task 10: Docs update + end-to-end manual test

Mark Plan 6c done in the build-phases doc and the spec status, then run a full manual E2E.

**Files:**
- Modify: `docs/superpowers/specs/2026-07-13-plan6c-persistence-design.md` (Status: Draft → Implemented)
- Modify: any build-phases tracker that references Plan 6c status.

- [ ] **Step 1: Update spec status**

In `docs/superpowers/specs/2026-07-13-plan6c-persistence-design.md`, change line 3:
```
**Status:** Implemented
```

- [ ] **Step 2: Update build-phases tracker**

Search for references to "6c — Persistence" status. The earlier audit found these files list it as `later`:
- `docs/superpowers/specs/2026-07-09-plan6a-audio-design.md:18`
- `docs/superpowers/specs/2026-07-09-plan6b-feel-feedback-design.md:18`

In each, change the row for "6c — Persistence" from `later` to `done`. (Use `grep -rn "6c" docs/superpowers/specs/` to find every occurrence and update consistently.)

- [ ] **Step 3: Run the full automated suite one more time**

Run: `./tests/run_all.sh`
Expected: all tests PASS.

- [ ] **Step 4: Manual E2E — episode save/load**

Build + launch: `make run-app`

1. Main Menu → **New Game** → pick slot 1 → game starts on Keen 1 overworld.
2. Enter a level, complete it (reach exit) → returns to overworld (auto-save fires).
3. Enter another level, die (fail) → returns to overworld (auto-save fires).
4. Press **Esc** → pause menu → **Save Game** → "Saved to slot 1."
5. **Quit to Main Menu**.
6. Main Menu → **Continue** → slot 1 shows "Keen 1 (N cleared)" → pick → resumes on overworld with completed levels still cleared (gates open).

- [ ] **Step 5: Manual E2E — pack save/load**

1. Main Menu → **Custom Packs** → install/select a pack → slot-select → pick slot 2 → pack starts.
2. Complete a level (auto-save).
3. **Esc → Quit to Main Menu**.
4. **Continue** → slot 2 shows pack name → pick → resumes pack overworld.

- [ ] **Step 6: Manual E2E — corruption + missing pack**

1. Quit the app. Open `user://saves/slot_1.json` in a text editor, scramble a few characters, save.
2. Launch → **Continue** → slot 1 shows "⚠ Corrupt (click to delete)" → click → slot becomes Empty.
3. Repeat with a pack save, then delete the pack's directory under `user://levelpacks/` → slot shows "⚠ Pack missing" → delete.

- [ ] **Step 7: Commit**

```bash
git add docs/superpowers/specs/2026-07-13-plan6c-persistence-design.md docs/superpowers/specs/2026-07-09-plan6a-audio-design.md docs/superpowers/specs/2026-07-09-plan6b-feel-feedback-design.md
git commit -m "docs: mark Plan 6c (persistence) done"
```

---

## Verification Checklist (run after all tasks)

- [ ] `./tests/run_all.sh` is green.
- [ ] No save file is written when `SaveSystem.active_slot == 0` (test mode is clean).
- [ ] `user://saves/` is created lazily (not at boot).
- [ ] Slot files survive a rename of the saves_dir only if renamed back (paths are absolute under `saves_dir`).
- [ ] Atomic write: killing the app between `.tmp` write and rename never corrupts the previous good save (the `.bak` + untouched original cover this).
- [ ] Pause menu Esc toggle works in OVERWORLD and LEVEL; Save button disabled mid-level.
- [ ] Continue button is disabled on the main menu when no slot is occupied.
