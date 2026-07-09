# Plan 5 — Pack Loading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let players import a custom level-pack `.zip` and play its overworld+levels through the existing gameplay loop.

**Architecture:** `PackLoader` (autoload) scans `user://levelpacks/`, parses each `manifest.json` via the existing `LevelPack.from_json`, loads the `.tres` `LevelData`, and exposes lookups. `import_zip()` extracts a user-picked zip with path-traversal + file-type hardening, installs it under `user://levelpacks/<pack_id>/`, and re-scans. A new `pack_select` menu lists installed packs; double-clicking one calls a new `GameManager.start_pack(pack_id)`, which registers the pack's levels into the existing `_levels_by_id` seam and enters OVERWORLD state — reusing the unchanged enter/complete/fail loop.

**Tech Stack:** Godot 4.7 (stable), GDScript, GUT (Godot Unit Test), native `ZIPReader`/`ZIPPacker`, native `FileDialog`.

**Spec:** `docs/superpowers/specs/2026-07-09-plan5-pack-loading-design.md`

**Conventions:** GDScript uses **TAB indentation** — every code block below uses tabs. Tests extend `GutTest`. Run tests via `./tests/run_all.sh`. **Never commit unless a step says so.**

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `src/core/pack_loader.gd` | **Rewrite** (currently 2-line stub) | Scan `user://levelpacks/`, parse manifests, load `.tres`, cache; `import_zip()` extract+sanitize+install; lookups. |
| `src/core/game_manager.gd` | **Modify** | Add `start_pack(pack_id)` + `start_pack_no_scene_swap(...)`. |
| `src/ui/pack_select.gd` | **Create** | List installed packs; "Load .zip…" → FileDialog → `PackLoader.import_zip`; double-click row → `GameManager.start_pack`. |
| `src/ui/pack_select.tscn` | **Create** | Scene: Load button, ItemList, status Label, Back button. |
| `src/ui/main_menu.tscn` | **Modify** | Add `CustomPacksButton`. |
| `src/ui/main_menu.gd` | **Modify** | Wire `CustomPacksButton` → `change_scene_to_packed(pack_select)`. |
| `project.godot` | **Modify** | Reorder autoloads: `PackLoader` before `GameManager`. |
| `tests/unit/test_pack_loader.gd` | **Create** | Scan + query tests. |
| `tests/unit/test_pack_import.gd` | **Create** | Zip import + abuse-rejection tests. |
| `tests/unit/test_game_manager_loop.gd` | **Modify** | Add `start_pack` test. |
| `tests/unit/test_pack_select_ui.gd` | **Create** | UI smoke test. |

**Note on fixtures:** the spec mentioned a committed `tests/fixtures/sample_pack/`. This plan instead **generates all pack files at runtime** inside tests (manifests as strings, `LevelData` via `ResourceSaver`). This matches the existing test pattern (`test_game_manager_loop.gd::test_episode_load_overworld_from_path` saves `res://tests/tmp_overworld.tres`) and keeps assertions deterministic without committing fragile hand-written `.tres`. It is the sole intentional deviation from the spec.

---

## Task 1: PackLoader.scan + caches + queries

**Files:**
- Modify: `src/core/pack_loader.gd` (rewrite stub)
- Test: `tests/unit/test_pack_loader.gd`

- [ ] **Step 1: Write the failing scan test**

Create `tests/unit/test_pack_loader.gd`:

```gdscript
extends GutTest

const TMP_ROOT := "user://tmp_packtest/"

func before_each():
	PackLoader.root_dir = TMP_ROOT
	_clean(TMP_ROOT)

func after_each():
	_clean(TMP_ROOT)
	PackLoader.root_dir = "user://levelpacks/"

func _clean(path: String) -> void:
	PackLoader._remove_dir_recursive(path)

func _ow() -> LevelData:
	var ld := LevelData.new()
	ld.level_id = "ow"
	ld.level_name = "OW"
	ld.width = 2
	ld.height = 2
	ld.fill_blank()
	ld.map_kind = LevelData.MapKind.OVERWORLD
	return ld

func _lvl(id: String) -> LevelData:
	var ld := LevelData.new()
	ld.level_id = id
	ld.width = 2
	ld.height = 2
	ld.fill_blank()
	return ld

const MANIFEST_VALID := """{
	"pack_id": "p1", "name": "Pack One", "author": "qa", "version": "1.0", "episode": "keen1",
	"levels": [
		{"level_id": "ow", "file": "overworld.tres", "name": "OW", "order": 0},
		{"level_id": "l1", "file": "01.tres", "name": "One", "order": 1}
	]
}"""

func _install(pack_id: String, manifest_text: String, files: Dictionary) -> void:
	var d := TMP_ROOT + pack_id + "/"
	DirAccess.make_dir_recursive_absolute(d)
	var mf := FileAccess.open(d + "manifest.json", FileAccess.WRITE)
	mf.store_string(manifest_text)
	mf.close()
	for fname in files:
		var v = files[fname]
		if v is LevelData:
			ResourceSaver.save(v, d + fname)
		else:
			var f := FileAccess.open(d + fname, FileAccess.WRITE)
			f.store_string(String(v))
			f.close()

func test_scan_finds_pack_with_overworld_and_levels():
	_install("p1", MANIFEST_VALID, {"overworld.tres": _ow(), "01.tres": _lvl("l1")})
	PackLoader.scan()
	assert_true(PackLoader.is_installed("p1"))
	assert_eq(PackLoader.get_pack("p1").pack_name, "Pack One")
	var levels := PackLoader.get_levels("p1")
	assert_eq(levels.size(), 2)
	var ow := PackLoader.get_overworld("p1")
	assert_not_null(ow)
	assert_eq(ow.map_kind, LevelData.MapKind.OVERWORLD)
	assert_eq(PackLoader.get_level("p1", "l1").level_id, "l1")
	assert_eq(PackLoader.get_packs().size(), 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL / errors — `PackLoader.scan`, `_remove_dir_recursive` do not exist (stub has no methods).

- [ ] **Step 3: Implement PackLoader scan + queries**

Rewrite `src/core/pack_loader.gd` (replace the entire 2-line contents) with:

```gdscript
extends Node
## Scans user://levelpacks for custom level packs. Each pack is a directory
## containing a manifest.json (parsed via LevelPack.from_json) + .tres LevelData
## files. Exposes lookups and zip import. Pure data + IO — no UI.

var root_dir := "user://levelpacks/"
const TMP_IMPORT := "user://levelpacks/.tmp_import/"
const ALLOWED_EXTS := ["tres", "res"]

var _packs: Dictionary = {}       # pack_id -> LevelPack
var _levels: Dictionary = {}      # pack_id -> { level_id -> LevelData }
var _overworlds: Dictionary = {}  # pack_id -> LevelData (map_kind == OVERWORLD)


func _ready() -> void:
	scan()


## Clear caches and walk root_dir/*/manifest.json. Idempotent + safe when the
## directory does not exist yet (no packs installed).
func scan() -> void:
	_packs.clear()
	_levels.clear()
	_overworlds.clear()
	var root := DirAccess.open(root_dir)
	if root == null:
		return
	root.list_dir_begin()
	var subdir := root.get_next()
	while subdir != "":
		if not subdir.begins_with(".") and root.dir_exists(subdir):
			_scan_pack(root_dir + subdir + "/")
		subdir = root.get_next()
	root.list_dir_end()


func reload() -> void:
	scan()


func _scan_pack(pack_dir: String) -> void:
	var manifest_path := pack_dir + "manifest.json"
	if not FileAccess.file_exists(manifest_path):
		push_warning("PackLoader: no manifest.json in %s" % pack_dir)
		return
	var pack := LevelPack.from_json(FileAccess.get_file_as_string(manifest_path))
	if pack == null:
		push_warning("PackLoader: invalid manifest in %s" % pack_dir)
		return
	var lvl_map: Dictionary = {}
	var ow: LevelData = null
	for entry in pack.levels:
		var file: String = entry.get("file", "")
		var lid: String = entry.get("level_id", "")
		var res: Resource = load(pack_dir + file)
		if res == null or not (res is LevelData):
			push_warning("PackLoader: cannot load level '%s' in %s" % [file, pack_dir])
			continue
		var ld: LevelData = res
		lvl_map[lid] = ld
		if ld.map_kind == LevelData.MapKind.OVERWORLD:
			if ow == null:
				ow = ld
			else:
				push_warning("PackLoader: multiple overworlds in '%s'; using first" % pack.pack_id)
	if ow == null:
		push_warning("PackLoader: no overworld in pack '%s'" % pack.pack_id)
		return
	_packs[pack.pack_id] = pack
	_levels[pack.pack_id] = lvl_map
	_overworlds[pack.pack_id] = ow


# ---- queries ---------------------------------------------------------------

func get_packs() -> Array:
	return _packs.values()


func get_pack(pack_id: String) -> LevelPack:
	return _packs.get(pack_id)


func get_levels(pack_id: String) -> Array:
	var m: Dictionary = _levels.get(pack_id, {})
	return m.values()


func get_level(pack_id: String, level_id: String) -> LevelData:
	var m: Dictionary = _levels.get(pack_id, {})
	return m.get(level_id)


func get_overworld(pack_id: String) -> LevelData:
	return _overworlds.get(pack_id)


func is_installed(pack_id: String) -> bool:
	return _packs.has(pack_id)


# ---- filesystem helpers (static; reused by import + tests) -----------------

static func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			if dir.dir_exists(name):
				_remove_dir_recursive(path.path_join(name))
			else:
				dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_dir_absolute(path)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: `test_scan_finds_pack_with_overworld_and_levels` PASSES.

- [ ] **Step 5: Add scan edge-case tests**

Append to `tests/unit/test_pack_loader.gd`:

```gdscript
func test_scan_missing_manifest_skipped():
	# A subdir with no manifest.json must not crash scan.
	DirAccess.make_dir_recursive_absolute(TMP_ROOT + "empty/")
	PackLoader.scan()
	assert_false(PackLoader.is_installed("empty"))
	assert_eq(PackLoader.get_packs().size(), 0)

func test_scan_malformed_manifest_skipped():
	_install("bad", "{ not json", {"overworld.tres": _ow()})
	PackLoader.scan()
	assert_false(PackLoader.is_installed("bad"))

func test_scan_no_overworld_rejected():
	var no_ow := """{
		"pack_id": "noow", "name": "NoOW", "author": "qa", "version": "1.0",
		"levels": [{"level_id": "l1", "file": "01.tres", "name": "One", "order": 1}]
	}"""
	_install("noow", no_ow, {"01.tres": _lvl("l1")})
	PackLoader.scan()
	assert_false(PackLoader.is_installed("noow"))

func test_scan_multiple_overworlds_first_wins():
	var two_ow := """{
		"pack_id": "two", "name": "Two", "author": "qa", "version": "1.0",
		"levels": [
			{"level_id": "ow1", "file": "a.tres", "name": "A", "order": 0},
			{"level_id": "ow2", "file": "b.tres", "name": "B", "order": 1}
		]
	}"""
	var a := _ow()
	a.level_id = "ow1"
	var b := _ow()
	b.level_id = "ow2"
	_install("two", two_ow, {"a.tres": a, "b.tres": b})
	PackLoader.scan()
	assert_true(PackLoader.is_installed("two"))
	assert_eq(PackLoader.get_overworld("two").level_id, "ow1")

func test_scan_bad_level_file_skipped_but_pack_loads():
	var manifest := """{
		"pack_id": "p2", "name": "P2", "author": "qa", "version": "1.0",
		"levels": [
			{"level_id": "ow", "file": "overworld.tres", "name": "OW", "order": 0},
			{"level_id": "missing", "file": "ghost.tres", "name": "Ghost", "order": 1}
		]
	}"""
	_install("p2", manifest, {"overworld.tres": _ow()})
	PackLoader.scan()
	assert_true(PackLoader.is_installed("p2"))
	assert_eq(PackLoader.get_levels("p2").size(), 1, "missing level skipped")
	assert_null(PackLoader.get_level("p2", "missing"))
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: all `test_pack_loader.gd` tests PASS.

- [ ] **Step 7: Commit**

```bash
git add src/core/pack_loader.gd tests/unit/test_pack_loader.gd
git commit -m "feat(pack-loader): scan user levelpacks + manifest/overworld resolution"
```

---

## Task 2: PackLoader.import_zip (extract + harden + install)

**Files:**
- Modify: `src/core/pack_loader.gd` (add import + sanitize)
- Test: `tests/unit/test_pack_import.gd`

- [ ] **Step 1: Write the failing import test**

Create `tests/unit/test_pack_import.gd`:

```gdscript
extends GutTest

const TMP_ROOT := "user://tmp_importtest/"

func before_each():
	PackLoader.root_dir = TMP_ROOT
	PackLoader._remove_dir_recursive(TMP_ROOT)

func after_each():
	PackLoader._remove_dir_recursive(TMP_ROOT)
	PackLoader._remove_dir_recursive(PackLoader.TMP_IMPORT)
	PackLoader.root_dir = "user://levelpacks/"
	_clean_res_tmp()

func _clean_res_tmp() -> void:
	for f in ["tmp_zip_ow.tres", "tmp_zip_l1.tres"]:
		var p := "res://tests/" + f
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func _make_level(lid: String, is_ow: bool) -> LevelData:
	var ld := LevelData.new()
	ld.level_id = lid
	ld.width = 2
	ld.height = 2
	ld.fill_blank()
	if is_ow:
		ld.map_kind = LevelData.MapKind.OVERWORLD
	return ld

const MANIFEST := """{
	"pack_id": "ztest", "name": "Zip Test", "author": "qa", "version": "1.0", "episode": "keen1",
	"levels": [
		{"level_id": "ow", "file": "overworld.tres", "name": "OW", "order": 0},
		{"level_id": "l1", "file": "01.tres", "name": "One", "order": 1}
	]
}"""

## Build a zip at zip_path from { relpath: PackedByteArray }.
func _make_zip(zip_path: String, entries: Dictionary) -> void:
	var packer := ZIPPacker.new()
	assert_eq(packer.open(zip_path), OK)
	for path in entries:
		assert_eq(packer.start_file(path), OK)
		assert_eq(packer.write_file(entries[path]), OK)
		packer.close_file()
	packer.close()

func _valid_entries() -> Dictionary:
	var e: Dictionary = {}
	e["manifest.json"] = MANIFEST.to_utf8_buffer()
	var ow := _make_level("ow", true)
	ResourceSaver.save(ow, "res://tests/tmp_zip_ow.tres")
	e["overworld.tres"] = FileAccess.get_file_as_bytes("res://tests/tmp_zip_ow.tres")
	var l1 := _make_level("l1", false)
	ResourceSaver.save(l1, "res://tests/tmp_zip_l1.tres")
	e["01.tres"] = FileAccess.get_file_as_bytes("res://tests/tmp_zip_l1.tres")
	return e

func test_import_zip_valid_pack():
	var zip_path := "user://tmp_valid.zip"
	_make_zip(zip_path, _valid_entries())
	var r: Dictionary = PackLoader.import_zip(zip_path)
	assert_true(r.ok, "import should succeed: %s" % r.error)
	assert_eq(r.pack_id, "ztest")
	assert_true(PackLoader.is_installed("ztest"))
	var ow := PackLoader.get_overworld("ztest")
	assert_not_null(ow)
	assert_eq(ow.map_kind, LevelData.MapKind.OVERWORLD)
	assert_eq(PackLoader.get_levels("ztest").size(), 2)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `PackLoader.import_zip` does not exist.

- [ ] **Step 3: Implement import_zip + sanitize**

Append to `src/core/pack_loader.gd` (after `_remove_dir_recursive`):

```gdscript
## Import a level-pack zip. Extracts to TMP_IMPORT with path-traversal + file-
## type hardening, parses the manifest to learn pack_id, then moves to the
## canonical dir root_dir/<pack_id>/ and re-scans. Returns {ok, error, pack_id}.
func import_zip(zip_path: String) -> Dictionary:
	_reset_tmp()
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		reader.close()
		return _fail("cannot read zip")
	var entries := reader.get_files()
	# 1. validate every entry before writing anything to disk
	for entry in entries:
		if entry.ends_with("/"):
			continue  # directory entry; allowed, nothing to write
		if _safe_entry_path(entry) == "":
			reader.close()
			_reset_tmp()
			return _fail("unsafe/disallowed path: %s" % entry)
	# 2. extract to TMP_IMPORT
	DirAccess.make_dir_recursive_absolute(TMP_IMPORT)
	for entry in entries:
		if entry.ends_with("/"):
			continue
		var dest := TMP_IMPORT + _safe_entry_path(entry)
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var f := FileAccess.open(dest, FileAccess.WRITE)
		if f == null:
			reader.close()
			_reset_tmp()
			return _fail("cannot write extracted file: %s" % dest)
		f.store_buffer(reader.read_file(entry))
		f.close()
	reader.close()
	# 3. parse manifest to learn pack_id
	var manifest_path := TMP_IMPORT + "manifest.json"
	if not FileAccess.file_exists(manifest_path):
		_reset_tmp()
		return _fail("no manifest.json")
	var pack := LevelPack.from_json(FileAccess.get_file_as_string(manifest_path))
	if pack == null:
		_reset_tmp()
		return _fail("invalid manifest")
	# 4. move to canonical dir (overwrite if re-importing)
	var canon := root_dir + pack.pack_id + "/"
	_remove_dir_recursive(canon)
	DirAccess.make_dir_recursive_absolute(root_dir)
	var err := DirAccess.rename_absolute(TMP_IMPORT, canon)
	if err != OK:
		_reset_tmp()
		return _fail("cannot install pack dir (err=%d)" % err)
	scan()
	return {"ok": true, "error": "", "pack_id": pack.pack_id}


## Returns a safe relative path for a zip entry, or "" if it is absolute,
## traverses with "..", or has a disallowed extension. Allowlist:
## manifest.json, *.tres, *.res.
static func _safe_entry_path(raw: String) -> String:
	var p := raw.replace("\\", "/").strip_edges()
	if p.is_empty() or p.begins_with("/") or p.begins_with("res://") or p.begins_with("user://"):
		return ""
	if p.length() >= 2 and p[1] == ":":
		return ""  # Windows drive letter (e.g. C:)
	for seg in p.split("/"):
		if seg == "..":
			return ""
	var fname := p.get_file()
	if fname != "manifest.json" and not ALLOWED_EXTS.has(fname.get_extension().to_lower()):
		return ""
	return p


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "pack_id": ""}


func _reset_tmp() -> void:
	_remove_dir_recursive(TMP_IMPORT)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: `test_import_zip_valid_pack` PASSES.

- [ ] **Step 5: Add abuse-rejection tests**

Append to `tests/unit/test_pack_import.gd`:

```gdscript
func test_import_zip_rejects_traversal():
	var zip_path := "user://tmp_trav.zip"
	_make_zip(zip_path, {"../evil.tres": "x".to_utf8_buffer()})
	var r: Dictionary = PackLoader.import_zip(zip_path)
	assert_false(r.ok)
	assert_eq(PackLoader.get_packs().size(), 0, "nothing installed")

func test_import_zip_rejects_absolute_path():
	var zip_path := "user://tmp_abs.zip"
	_make_zip(zip_path, {"res://hack.tres": "x".to_utf8_buffer()})
	var r: Dictionary = PackLoader.import_zip(zip_path)
	assert_false(r.ok)

func test_import_zip_rejects_disallowed_type():
	var zip_path := "user://tmp_type.zip"
	_make_zip(zip_path, {"hack.gd": "extends Node".to_utf8_buffer()})
	var r: Dictionary = PackLoader.import_zip(zip_path)
	assert_false(r.ok)

func test_import_zip_rejects_no_manifest():
	var zip_path := "user://tmp_noman.zip"
	var e: Dictionary = {}
	# only a level, no manifest
	var ow := _make_level("ow", true)
	ResourceSaver.save(ow, "res://tests/tmp_zip_ow.tres")
	e["overworld.tres"] = FileAccess.get_file_as_bytes("res://tests/tmp_zip_ow.tres")
	_make_zip(zip_path, e)
	var r: Dictionary = PackLoader.import_zip(zip_path)
	assert_false(r.ok)
	assert_eq(r.error, "no manifest.json")

func test_import_zip_reimport_overwrites():
	var zip_path := "user://tmp_re.zip"
	_make_zip(zip_path, _valid_entries())
	assert_true(PackLoader.import_zip(zip_path).ok)
	# import again — must overwrite cleanly, still exactly one pack
	var r2: Dictionary = PackLoader.import_zip(zip_path)
	assert_true(r2.ok)
	assert_eq(r2.pack_id, "ztest")
	assert_eq(PackLoader.get_packs().size(), 1)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: all `test_pack_import.gd` tests PASS.

- [ ] **Step 7: Commit**

```bash
git add src/core/pack_loader.gd tests/unit/test_pack_import.gd
git commit -m "feat(pack-loader): hardened zip import (traversal + type allowlist)"
```

---

## Task 3: GameManager.start_pack

**Files:**
- Modify: `src/core/game_manager.gd` (add start_pack)
- Modify: `tests/unit/test_game_manager_loop.gd` (add test)

- [ ] **Step 1: Write the failing start_pack test**

Add this helper + test to the **end** of `tests/unit/test_game_manager_loop.gd`:

```gdscript
const PL_TMP := "user://tmp_gm_packtest/"

func _seed_pack_loader(pack_id: String, ow: LevelData, levels: Array) -> void:
	PackLoader.root_dir = PL_TMP
	PackLoader._remove_dir_recursive(PL_TMP)
	var d := PL_TMP + pack_id + "/"
	DirAccess.make_dir_recursive_absolute(d)
	ResourceSaver.save(ow, d + "overworld.tres")
	var parts := PackedStringArray()
	parts.append('{"level_id": "ow", "file": "overworld.tres", "name": "OW", "order": 0}')
	var i := 1
	for lvl in levels:
		var fn := "lvl_%d.tres" % i
		ResourceSaver.save(lvl, d + fn)
		parts.append('{"level_id": "%s", "file": "%s", "name": "L%d", "order": %d}' % [lvl.level_id, fn, i, i])
		i += 1
	var manifest := """{
		"pack_id": "%s", "name": "GM", "author": "qa", "version": "1.0",
		"levels": [%s]
	}""" % [pack_id, ", ".join(parts)]
	var mf := FileAccess.open(d + "manifest.json", FileAccess.WRITE)
	mf.store_string(manifest)
	mf.close()
	PackLoader.scan()


func test_start_pack_sets_overworld_state_and_registers_levels():
	GameManager.clear_progress()
	var ow := LevelData.new()
	ow.level_id = "ow"
	ow.width = 2
	ow.height = 2
	ow.fill_blank()
	ow.map_kind = LevelData.MapKind.OVERWORLD
	var lvl := LevelData.new()
	lvl.level_id = "k1_01"
	lvl.width = 2
	lvl.height = 2
	lvl.fill_blank()
	_seed_pack_loader("mypack", ow, [lvl])
	GameManager.start_pack_no_scene_swap("mypack", ow)
	assert_eq(GameManager.state, GameManager.State.OVERWORLD)
	assert_eq(GameManager.current_overworld, ow)
	assert_eq(GameManager.pending_level, ow)
	assert_eq(GameManager.current_episode_id, "mypack")
	# _levels_by_id populated via register_level (existing seam)
	assert_eq(GameManager.get_level_by_id("ow"), ow)
	assert_eq(GameManager.get_level_by_id("k1_01"), lvl)
	# fresh session: progress cleared on start_pack
	assert_false(GameManager.is_level_completed("k1_01"))
	PackLoader._remove_dir_recursive(PL_TMP)
	PackLoader.root_dir = "user://levelpacks/"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `GameManager.start_pack_no_scene_swap` does not exist.

- [ ] **Step 3: Implement start_pack**

In `src/core/game_manager.gd`, add these two methods immediately **after** the existing `start_episode_no_scene_swap` method (before `_resolve_overworld`):

```gdscript
## Boot a custom level pack: resolve its overworld, register every pack level,
## then swap to the runtime scene in OVERWORLD state. Reuses the existing
## enter/complete/fail loop. (Bundled episodes use start_episode instead.)
func start_pack(pack_id: String) -> void:
	var ow := PackLoader.get_overworld(pack_id)
	if ow == null:
		push_warning("GameManager: pack '%s' has no overworld" % pack_id)
		return
	start_pack_no_scene_swap(pack_id, ow)
	get_tree().change_scene_to_packed(RUNTIME_SCENE)


## Non-scene-swap variant for headless tests.
func start_pack_no_scene_swap(pack_id: String, ow: LevelData) -> void:
	clear_progress()
	current_episode_id = pack_id
	current_overworld = ow
	register_level(ow)
	for lvl in PackLoader.get_levels(pack_id):
		register_level(lvl)
	pending_level = ow
	pending_player_spawn = Vector2i(-1, -1)
	state = State.OVERWORLD
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: `test_start_pack_sets_overworld_state_and_registers_levels` PASSES; all pre-existing tests still PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/game_manager.gd tests/unit/test_game_manager_loop.gd
git commit -m "feat(game-manager): start_pack entry point for custom level packs"
```

---

## Task 4: pack_select menu + main_menu wiring

**Files:**
- Create: `src/ui/pack_select.gd`
- Create: `src/ui/pack_select.tscn`
- Modify: `src/ui/main_menu.tscn`
- Modify: `src/ui/main_menu.gd`
- Test: `tests/unit/test_pack_select_ui.gd`

- [ ] **Step 1: Create the pack_select script**

Create `src/ui/pack_select.gd`:

```gdscript
extends Control

const MAIN_MENU := preload("res://src/ui/main_menu.tscn")

@onready var list: ItemList = %PackList
@onready var status: Label = %StatusLabel
var dialog: FileDialog


func _ready() -> void:
	%LoadZipButton.pressed.connect(_open_dialog)
	%BackButton.pressed.connect(_back)
	list.item_activated.connect(_on_item_activated)
	_repopulate()


func _repopulate() -> void:
	list.clear()
	var packs := PackLoader.get_packs()
	if packs.is_empty():
		list.add_item("No packs installed. Click Load .zip…")
		return
	for p in packs:
		list.add_item("%s  —  %s  (%d)" % [p.pack_name, p.author, p.levels.size()])


func _open_dialog() -> void:
	if dialog == null:
		dialog = FileDialog.new()
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.filters = PackedStringArray(["*.zip ; Level Pack"])
		add_child(dialog)
		dialog.file_selected.connect(_on_zip_selected)
	dialog.popup_centered()


func _on_zip_selected(path: String) -> void:
	var r: Dictionary = PackLoader.import_zip(path)
	if r.ok:
		status.text = "Installed %s" % r.pack_id
		status.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	else:
		status.text = "Error: %s" % r.error
		status.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	_repopulate()


func _on_item_activated(idx: int) -> void:
	var packs := PackLoader.get_packs()
	if packs.is_empty() or idx < 0 or idx >= packs.size():
		return
	GameManager.start_pack(packs[idx].pack_id)


func _back() -> void:
	get_tree().change_scene_to_packed(MAIN_MENU)
```

- [ ] **Step 2: Create the pack_select scene**

Create `src/ui/pack_select.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/pack_select.gd" id="1_ps"]

[node name="PackSelect" type="Control"]
layout_mode = 3
script = ExtResource("1_ps")
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="BG" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0.05, 0.04, 0.08, 1)

[node name="Title" type="Label" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -320.0
offset_right = 320.0
offset_top = -200.0
offset_bottom = -160.0
grow_horizontal = 2
grow_vertical = 2
text = "Custom Packs"
horizontal_alignment = 1
vertical_alignment = 1

[node name="LoadZipButton" type="Button" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -110.0
offset_right = 110.0
offset_top = -140.0
offset_bottom = -100.0
grow_horizontal = 2
grow_vertical = 2
text = "Load .zip…"

[node name="PackList" type="ItemList" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -300.0
offset_right = 300.0
offset_top = -80.0
offset_bottom = 60.0
grow_horizontal = 2
grow_vertical = 2

[node name="StatusLabel" type="Label" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -300.0
offset_right = 300.0
offset_top = 70.0
offset_bottom = 100.0
grow_horizontal = 2
grow_vertical = 2
horizontal_alignment = 1
vertical_alignment = 1

[node name="BackButton" type="Button" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -60.0
offset_right = 60.0
offset_top = 120.0
offset_bottom = 160.0
grow_horizontal = 2
grow_vertical = 2
text = "Back"
```

- [ ] **Step 3: Add the Custom Packs button to main_menu**

In `src/ui/main_menu.tscn`, add a new node **before** the `EditorButton` node (insert after the `PlayButton` node block, i.e. after line 69 `text = "Play"`):

```
[node name="CustomPacksButton" type="Button" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -90.0
offset_right = 90.0
offset_top = 10.0
offset_bottom = 50.0
grow_horizontal = 2
grow_vertical = 2
text = "Custom Packs"
```

Then shift the existing `EditorButton` and `QuitButton` `offset_top`/`offset_bottom` down by 50 so they don't overlap:
- `EditorButton`: `offset_top` `10.0 → 60.0`, `offset_bottom` `50.0 → 100.0`.
- `QuitButton`: `offset_top` `60.0 → 110.0`, `offset_bottom` `100.0 → 150.0`.

(Use the Edit tool for these precise replacements.)

- [ ] **Step 4: Wire the button in main_menu.gd**

In `src/ui/main_menu.gd`, add the `PACK_SELECT` preload and wire the button. Change `_ready` and add the handler. Final file:

```gdscript
extends Control

const EDITOR_SCENE := preload("res://src/editor/level_editor.tscn")
const PACK_SELECT := preload("res://src/ui/pack_select.tscn")

func _ready() -> void:
	_ensure_play_button()
	%CustomPacksButton.pressed.connect(_open_pack_select)
	%EditorButton.pressed.connect(_open_editor)
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())

func _ensure_play_button() -> void:
	if has_node("%PlayButton"):
		(%PlayButton as Button).pressed.connect(_play)
		return
	var play := Button.new()
	play.name = "PlayButton"
	play.text = "Play"
	play.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(play)
	play.set("theme_type_variation", "Button")
	play.pressed.connect(_play)

func _play() -> void:
	GameManager.start_episode("keen1")

func _open_editor() -> void:
	get_tree().change_scene_to_packed(EDITOR_SCENE)

func _open_pack_select() -> void:
	get_tree().change_scene_to_packed(PACK_SELECT)
```

- [ ] **Step 5: Write the UI smoke test**

Create `tests/unit/test_pack_select_ui.gd`:

```gdscript
extends GutTest

const PACK_SELECT := preload("res://src/ui/pack_select.tscn")
const TMP_ROOT := "user://tmp_ps_ui/"

func before_each():
	PackLoader.root_dir = TMP_ROOT
	PackLoader._remove_dir_recursive(TMP_ROOT)
	PackLoader.scan()

func after_each():
	PackLoader._remove_dir_recursive(TMP_ROOT)
	PackLoader.root_dir = "user://levelpacks/"

func _ow() -> LevelData:
	var ld := LevelData.new()
	ld.level_id = "ow"
	ld.width = 2
	ld.height = 2
	ld.fill_blank()
	ld.map_kind = LevelData.MapKind.OVERWORLD
	return ld

func _install_pack(pack_id: String) -> void:
	var d := TMP_ROOT + pack_id + "/"
	DirAccess.make_dir_recursive_absolute(d)
	ResourceSaver.save(_ow(), d + "overworld.tres")
	var manifest := """{
		"pack_id": "%s", "name": "UI Pack", "author": "qa", "version": "1.0",
		"levels": [{"level_id": "ow", "file": "overworld.tres", "name": "OW", "order": 0}]
	}""" % pack_id
	var mf := FileAccess.open(d + "manifest.json", FileAccess.WRITE)
	mf.store_string(manifest)
	mf.close()

func test_empty_state_message():
	var ps := PACK_SELECT.instantiate()
	add_child(ps)
	assert_eq(ps.list.get_item_count(), 1)
	assert(ps.list.get_item_text(0).find("No packs") >= 0)
	ps.queue_free()

func test_repopulate_lists_installed_pack():
	_install_pack("uip1")
	PackLoader.scan()
	var ps := PACK_SELECT.instantiate()
	add_child(ps)
	assert_eq(ps.list.get_item_count(), 1)
	assert(ps.list.get_item_text(0).find("UI Pack") >= 0)
	ps.queue_free()
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: `test_pack_select_ui.gd` tests PASS; all other tests still PASS.

- [ ] **Step 7: Commit**

```bash
git add src/ui/pack_select.gd src/ui/pack_select.tscn src/ui/main_menu.gd src/ui/main_menu.tscn tests/unit/test_pack_select_ui.gd
git commit -m "feat(ui): pack-select menu + main-menu entry for custom packs"
```

---

## Task 5: Autoload ordering + full-suite verification

**Files:**
- Modify: `project.godot`

- [ ] **Step 1: Reorder autoloads**

In `project.godot`, in the `[autoload]` section, move `PackLoader` **above** `GameManager` so `PackLoader._ready()` (which calls `scan()`) runs before `GameManager._ready()`:

```
[autoload]

PackLoader="*res://src/core/pack_loader.gd"
GameManager="*res://src/core/game_manager.gd"
EntityRegistry="*res://src/core/entity_registry.gd"
TileSetRegistry="*res://src/core/tileset_registry.gd"
```

(Use the Edit tool to swap the `PackLoader` and `GameManager` lines.)

- [ ] **Step 2: Run the full test suite**

Run: `./tests/run_all.sh`
Expected: ALL tests PASS (new + pre-existing). If any pre-existing test breaks, investigate — most likely an autoload-ordering interaction; revert only if the failure is unrelated and blocking.

- [ ] **Step 3: Manual smoke (optional but recommended)**

Run: `make edit` → click **Custom Packs** → click **Load .zip…** → pick a test `.zip` (build one with the manifest from Task 2 + two `.tres`) → confirm it appears in the list → double-click → confirm the overworld loads.

Alternatively `make run-app` to launch the built app and repeat.

- [ ] **Step 4: Commit**

```bash
git add project.godot
git commit -m "chore(autoload): load PackLoader before GameManager"
```

---

## Done criteria

- [ ] `./tests/run_all.sh` is fully green.
- [ ] A custom pack `.zip` imports via the menu and its overworld is playable.
- [ ] Traversal / disallowed-type / no-manifest zips are rejected with no crash.
- [ ] No bundled keen1 path (`start_episode`) behavior changed.
