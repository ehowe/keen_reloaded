# keen_reloaded — Plan 1: Project Foundation + Data Model

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Initialize the Godot 4.7 project, set up GUT testing, and implement the `LevelData` / `EntityDef` / `LevelPack` data model with serialization — fully unit-tested.

**Architecture:** Approach C hybrid (see spec `docs/superpowers/specs/2026-06-25-keen-reloaded-design.md`). Levels are custom Godot `Resource` classes serialized to `.tres`. This plan builds the data layer only — no UI, no gameplay. Every class is tested for construction and `.tres` round-trip serialization.

**Tech Stack:** Godot 4.7, GDScript, GUT (Godot Unit Test) addon.

**Godot binary:** `/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot`
(All `godot` commands below use this path. Set a shell alias if convenient: `alias godot="/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot"`)

---

## File Structure (this plan)

| File | Responsibility |
|------|----------------|
| `project.godot` | Godot project config, autoloads, GUT plugin enabled |
| `.gitignore` | Ignore `.godot/`, `.superpowers/`, `*.import`, editor files |
| `addons/gut/` | GUT test framework (vendored) |
| `src/data/level_data.gd` | `LevelData` resource — one level's full data |
| `src/data/entity_def.gd` | `EntityDef` resource — one placed entity |
| `src/data/level_pack.gd` | `LevelPack` manifest parser (JSON → data class) |
| `tests/unit/test_level_data.gd` | `LevelData` construction + round-trip tests |
| `tests/unit/test_entity_def.gd` | `EntityDef` tests |
| `tests/unit/test_level_pack.gd` | `LevelPack` manifest parse tests |
| `tests/run_all.sh` | Headless test runner wrapper |

---

## Task 1: Git init + Godot project + directory scaffold

**Files:**
- Create: `.gitignore`
- Create: `project.godot`
- Create dirs: `src/data`, `src/core`, `src/runtime`, `src/editor`, `src/ui`, `src/episodes`, `levels`, `assets/tilesets`, `assets/sprites`, `assets/audio`, `assets/backgrounds`, `tests/unit`

- [ ] **Step 1: Initialize git repo**

```bash
cd /Users/eugene/git/keen_reloaded
git init
git branch -M main
```

- [ ] **Step 2: Write `.gitignore`**

Create `/Users/eugene/git/keen_reloaded/.gitignore`:

```gitignore
# Godot
.godot/
*.import
export_presets.cfg

# OS
.DS_Store
Thumbs.db

# Superpowers brainstorm artifacts
.superpowers/

# Editor temp
*.tmp
```

- [ ] **Step 3: Write `project.godot`**

Create `/Users/eugene/git/keen_reloaded/project.godot`:

```ini
config_version=5

[application]

config/name="keen_reloaded"
config/description="Commander Keen remaster — modular, episodic, with level editor"
run/main_scene="res://src/ui/main_menu.tscn"
config/features=PackedStringArray("4.7", "Forward Plus")

[autoload]

GameManager="*res://src/core/game_manager.gd"
PackLoader="*res://src/core/pack_loader.gd"
EntityRegistry="*res://src/core/entity_registry.gd"

[display]

window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"

[layer_names]

2d_physics/layer_1="player"
2d_physics/layer_2="enemies"
2d_physics/layer_3="tiles"
2d_physics/layer_4="items"

[rendering]

textures/canvas_textures/default_texture_filter=0
```

Note: `default_texture_filter=0` sets NEAREST filtering globally — required for crisp pixel-art rendering. The autoload scripts referenced don't exist yet; we create stubs in Task 3.

- [ ] **Step 4: Create the directory tree**

```bash
cd /Users/eugene/git/keen_reloaded
mkdir -p src/data src/core src/runtime src/editor src/ui src/episodes
mkdir -p levels assets/tilesets assets/sprites assets/audio assets/backgrounds
mkdir -p tests/unit
```

- [ ] **Step 5: Create placeholder autoload stubs (so project imports cleanly)**

Create `/Users/eugene/git/keen_reloaded/src/core/game_manager.gd`:

```gdscript
extends Node
## Top-level game state singleton (autoload). Expanded in later plans.
```

Create `/Users/eugene/git/keen_reloaded/src/core/pack_loader.gd`:

```gdscript
extends Node
## Scans res://levels + user://levelpacks for level packs. Implemented in Plan 4.
```

Create `/Users/eugene/git/keen_reloaded/src/core/entity_registry.gd`:

```gdscript
extends Node
## Extensible entity catalog (autoload). Implemented in Plan 3.
```

- [ ] **Step 6: Verify the project imports without errors**

```bash
cd /Users/eugene/git/keen_reloaded
"/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot" --headless --import --quit 2>&1 | tail -5
```

Expected: exits cleanly (no parse errors). A `.godot/` folder is generated (it's gitignored).

- [ ] **Step 7: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add -A
git commit -m "chore: init godot 4.7 project scaffold"
```

---

## Task 2: Install + configure GUT

**Files:**
- Create: `addons/gut/` (vendored from GUT repo)
- Create: `tests/unit/test_gut_smoke.gd` (smoke test)
- Create: `tests/run_all.sh`

- [ ] **Step 1: Clone GUT and vendor the addon**

```bash
cd /Users/eugene/git/keen_reloaded
git clone --depth 1 https://github.com/bitwes/Gut.git /tmp/gut_install
rm -rf addons/gut
cp -r /tmp/gut_install/addons/gut addons/gut
rm -rf /tmp/gut_install
```

This copies only the `addons/gut` folder from the GUT repo (its main branch supports Godot 4).

- [ ] **Step 2: Enable the GUT plugin in `project.godot`**

Append this section to `/Users/eugene/git/keen_reloaded/project.godot` (add at end of file):

```ini

[editor_plugins]

enabled=PackedStringArray("res://addons/gut/plugin.cfg")
```

- [ ] **Step 3: Write a GUT smoke test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_gut_smoke.gd`:

```gdscript
extends GutTest

func test_gut_is_running():
	assert_true(true, "GUT is wired up correctly")

func test_basic_math():
	assert_eq(2 + 2, 4, "sanity check")
```

- [ ] **Step 4: Write the headless test runner**

Create `/Users/eugene/git/keen_reloaded/tests/run_all.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
GODOT="/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gcompact
```

Then make it executable:

```bash
chmod +x tests/run_all.sh
```

- [ ] **Step 5: Re-import and run the smoke test**

```bash
cd /Users/eugene/git/keen_reloaded
"/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot" --headless --import --quit 2>&1 | tail -3
./tests/run_all.sh
```

Expected: GUT runs, reports `2` passing tests, `0` failures, then exits.

- [ ] **Step 6: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add -A
git commit -m "test: add GUT framework + smoke test"
```

---

## Task 3: `EntityDef` resource

**Files:**
- Create: `src/data/entity_def.gd`
- Create: `tests/unit/test_entity_def.gd`

`EntityDef` is built first because `LevelData` references it (`Array[EntityDef]`). `class_name` must exist before `LevelData` can reference the type.

- [ ] **Step 1: Write the failing test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_entity_def.gd`:

```gdscript
extends GutTest

func test_default_construction():
	var e := EntityDef.new()
	assert_eq(e.type, "", "default type is empty")
	assert_eq(e.x, 0, "default x is 0")
	assert_eq(e.y, 0, "default y is 0")
	assert_eq(e.properties, {}, "default properties is empty dict")

func test_parameterized_construction():
	var e := EntityDef.new("vorticon", 12, 7, {"speed": 30})
	assert_eq(e.type, "vorticon")
	assert_eq(e.x, 12)
	assert_eq(e.y, 7)
	assert_eq(e.properties.get("speed"), 30)

func test_serialization_round_trip():
	var e := EntityDef.new("yorp", 3, 4, {"hp": 2})
	var path := "user://tests/test_entity_def.tres"
	DirAccess.make_dir_recursive_absolute("user://tests/")
	var err := ResourceSaver.save(e, path)
	assert_eq(err, OK, "save should return OK")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as EntityDef
	assert_not_null(loaded, "loaded resource should not be null")
	assert_eq(loaded.type, "yorp")
	assert_eq(loaded.x, 3)
	assert_eq(loaded.y, 4)
	assert_eq(loaded.properties.get("hp"), 2)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `EntityDef` class not found / parse error.

- [ ] **Step 3: Implement `EntityDef`**

Create `/Users/eugene/git/keen_reloaded/src/data/entity_def.gd`:

```gdscript
class_name EntityDef
extends Resource
## A single placed entity inside a LevelData. Type ID is resolved at runtime
## by EntityRegistry. Extensible: episodes add types without changing this class.

@export var type: String = ""
@export var x: int = 0
@export var y: int = 0
@export var properties: Dictionary = {}

func _init(p_type := "", p_x := 0, p_y := 0, p_props: Dictionary = {}) -> void:
	type = p_type
	x = p_x
	y = p_y
	properties = p_props
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all entity_def tests green (plus the smoke tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/data/entity_def.gd tests/unit/test_entity_def.gd
git commit -m "feat: add EntityDef resource with serialization"
```

---

## Task 4: `LevelData` resource — metadata + dimensions + tiles

**Files:**
- Create: `src/data/level_data.gd`
- Create: `tests/unit/test_level_data.gd`

Note: the spec described nested `metadata.*` / `dimensions.*` groups. For a Godot `Resource`, flat `@export` properties serialize more cleanly and are idiomatic. This plan flattens them with clear names.

- [ ] **Step 1: Write the failing test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_level_data.gd`:

```gdscript
extends GutTest

const TILE_EMPTY := 0
const TILE_SOLID := 1

func _make_level() -> LevelData:
	var ld := LevelData.new()
	ld.level_id = "keen1_01"
	ld.level_name = "Border Village"
	ld.episode = "keen1"
	ld.order = 1
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	return ld

func test_default_construction():
	var ld := LevelData.new()
	assert_eq(ld.level_id, "")
	assert_eq(ld.width, 0)
	assert_eq(ld.height, 0)
	assert_eq(ld.tile_size, 16)
	assert_eq(ld.geometry_tiles.size(), 0)
	assert_eq(ld.entities.size(), 0)
	assert_eq(ld.player_spawn, Vector2i.ZERO)

func test_tile_index_helpers():
	var ld := _make_level()
	# tile_at for (0,0) = index 0; (3,2) = index 3 + 2*4 = 11
	assert_eq(ld.tile_index_at(0, 0), 0)
	assert_eq(ld.tile_index_at(3, 2), 11)
	# out of bounds returns -1
	assert_eq(ld.tile_index_at(4, 0), -1)
	assert_eq(ld.tile_index_at(0, 3), -1)

func test_fill_blank_tiles():
	var ld := _make_level()
	ld.fill_blank()
	assert_eq(ld.geometry_tiles.size(), 12, "4x3 = 12 tiles")
	assert_eq(ld.geometry_tiles[0], TILE_EMPTY)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `LevelData` class not found.

- [ ] **Step 3: Implement `LevelData` (metadata, dimensions, tiles, helpers)**

Create `/Users/eugene/git/keen_reloaded/src/data/level_data.gd`:

```gdscript
class_name LevelData
extends Resource
## Full data for a single level. Serialized to .tres. The single source of
## truth: the editor writes it, the runtime reads it.

@export_group("Metadata")
@export var level_id: String = ""
@export var level_name: String = ""
@export var episode: String = ""
@export var order: int = 0

@export_group("Dimensions")
@export var width: int = 0
@export var height: int = 0
@export var tile_size: int = 16

@export_group("Tile Layers")
@export var geometry_tiles: PackedInt32Array = []
@export var foreground_tiles: PackedInt32Array = []
@export var background_tiles: PackedInt32Array = []

@export_group("Entities")
@export var entities: Array[EntityDef] = []

@export_group("Spawn / Exit")
@export var player_spawn: Vector2i = Vector2i.ZERO
@export var exit_type: String = ""
@export var exit_position: Vector2i = Vector2i.ZERO
@export var exit_target_level_id: String = ""

@export_group("Assets")
@export var tileset_ref: TileSet = null
@export var music: Resource = null
@export var background_ref: Resource = null


## Returns the flat array index for tile (x, y), or -1 if out of bounds.
func tile_index_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	return x + y * width


## Initializes every tile layer to size width*height filled with 0 (empty).
func fill_blank() -> void:
	var count := width * height
	geometry_tiles.resize(count)
	geometry_tiles.fill(0)
	foreground_tiles.resize(count)
	foreground_tiles.fill(0)
	background_tiles.resize(count)
	background_tiles.fill(0)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — construction, index helpers, and fill_blank all green.

- [ ] **Step 5: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/data/level_data.gd tests/unit/test_level_data.gd
git commit -m "feat: add LevelData resource with metadata, dimensions, tile helpers"
```

---

## Task 5: `LevelData` — tile get/set + serialization round-trip

**Files:**
- Modify: `src/data/level_data.gd` (add tile getters/setters)
- Modify: `tests/unit/test_level_data.gd` (add tile + round-trip tests)

- [ ] **Step 1: Add failing tests for tile get/set and serialization**

Append to `/Users/eugene/git/keen_reloaded/tests/unit/test_level_data.gd`:

```gdscript
func test_set_get_geometry_tile():
	var ld := _make_level()
	ld.fill_blank()
	ld.set_geometry_tile(2, 1, 1)
	assert_eq(ld.get_geometry_tile(2, 1), 1)
	assert_eq(ld.get_geometry_tile(0, 0), 0)

func test_set_tile_out_of_bounds_is_ignored():
	var ld := _make_level()
	ld.fill_blank()
	ld.set_geometry_tile(99, 99, 1)
	assert_eq(ld.get_geometry_tile(99, 99), 0, "out-of-bounds get returns 0")

func test_serialization_round_trip():
	var ld := _make_level()
	ld.fill_blank()
	ld.set_geometry_tile(1, 0, 1)
	ld.set_geometry_tile(0, 2, 1)
	ld.player_spawn = Vector2i(1, 1)
	ld.exit_type = "door"
	ld.exit_position = Vector2i(3, 2)
	ld.exit_target_level_id = "keen1_02"
	ld.entities.append(EntityDef.new("vorticon", 2, 1, {"speed": 25}))

	var path := "user://tests/test_level_data.tres"
	DirAccess.make_dir_recursive_absolute("user://tests/")
	var err := ResourceSaver.save(ld, path)
	assert_eq(err, OK, "save should return OK")

	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	assert_not_null(loaded, "loaded should not be null")
	assert_eq(loaded.level_id, "keen1_01")
	assert_eq(loaded.width, 4)
	assert_eq(loaded.height, 3)
	assert_eq(loaded.get_geometry_tile(1, 0), 1)
	assert_eq(loaded.get_geometry_tile(0, 2), 1)
	assert_eq(loaded.player_spawn, Vector2i(1, 1))
	assert_eq(loaded.exit_target_level_id, "keen1_02")
	assert_eq(loaded.entities.size(), 1)
	assert_eq(loaded.entities[0].type, "vorticon")
	assert_eq(loaded.entities[0].properties.get("speed"), 25)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_all.sh`
Expected: FAIL — `set_geometry_tile` / `get_geometry_tile` methods don't exist yet.

- [ ] **Step 3: Add tile get/set methods to `LevelData`**

In `/Users/eugene/git/keen_reloaded/src/data/level_data.gd`, add these methods at the end of the class (after `fill_blank`):

```gdscript


## Returns the geometry tile id at (x, y). 0 if out of bounds.
func get_geometry_tile(x: int, y: int) -> int:
	var idx := tile_index_at(x, y)
	if idx < 0:
		return 0
	return geometry_tiles[idx]


## Sets the geometry tile id at (x, y). Ignored if out of bounds.
func set_geometry_tile(x: int, y: int, tile_id: int) -> void:
	var idx := tile_index_at(x, y)
	if idx < 0:
		return
	geometry_tiles[idx] = tile_id


## Returns the foreground tile id at (x, y). 0 if out of bounds.
func get_foreground_tile(x: int, y: int) -> int:
	var idx := tile_index_at(x, y)
	if idx < 0:
		return 0
	return foreground_tiles[idx]


## Sets the foreground tile id at (x, y). Ignored if out of bounds.
func set_foreground_tile(x: int, y: int, tile_id: int) -> void:
	var idx := tile_index_at(x, y)
	if idx < 0:
		return
	foreground_tiles[idx] = tile_id


## Returns the background tile id at (x, y). 0 if out of bounds.
func get_background_tile(x: int, y: int) -> int:
	var idx := tile_index_at(x, y)
	if idx < 0:
		return 0
	return background_tiles[idx]


## Sets the background tile id at (x, y). Ignored if out of bounds.
func set_background_tile(x: int, y: int, tile_id: int) -> void:
	var idx := tile_index_at(x, y)
	if idx < 0:
		return
	background_tiles[idx] = tile_id
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all tile get/set and serialization round-trip tests green.

- [ ] **Step 5: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/data/level_data.gd tests/unit/test_level_data.gd
git commit -m "feat: add LevelData tile accessors + serialization round-trip"
```

---

## Task 6: `LevelPack` manifest parser

**Files:**
- Create: `src/data/level_pack.gd`
- Create: `tests/unit/test_level_pack.gd`

`LevelPack` is a plain data class (RefCounted, not Resource) that parses a pack's `manifest.json`. It does not load the `.tres` files themselves (that's PackLoader's job in Plan 4) — it just validates and exposes the manifest structure.

- [ ] **Step 1: Write the failing test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_level_pack.gd`:

```gdscript
extends GutTest

const VALID_MANIFEST := """{
	"pack_id": "keen1",
	"name": "Keen 1: Marooned on Mars",
	"author": "keen_reloaded",
	"version": "1.0.0",
	"episode": "keen1",
	"levels": [
		{"level_id": "keen1_01", "file": "01.tres", "name": "Border Village", "order": 1},
		{"level_id": "keen1_02", "file": "02.tres", "name": "Ice Shrine", "order": 2}
	]
}"""

func test_parse_valid_manifest():
	var pack := LevelPack.from_json(VALID_MANIFEST)
	assert_not_null(pack, "from_json should return a pack for valid JSON")
	assert_eq(pack.pack_id, "keen1")
	assert_eq(pack.pack_name, "Keen 1: Marooned on Mars")
	assert_eq(pack.author, "keen_reloaded")
	assert_eq(pack.version, "1.0.0")
	assert_eq(pack.episode, "keen1")
	assert_eq(pack.levels.size(), 2)
	assert_eq(pack.levels[0]["level_id"], "keen1_01")
	assert_eq(pack.levels[0]["file"], "01.tres")
	assert_eq(pack.levels[1]["order"], 2)

func test_parse_invalid_json_returns_null():
	var pack := LevelPack.from_json("{ this is not valid json")
	assert_null(pack, "invalid JSON should return null")

func test_manifest_missing_required_field():
	var bad := """{"pack_id": "x", "name": "No levels key here"}"""
	var pack := LevelPack.from_json(bad)
	assert_null(pack, "missing 'levels' should return null")

func test_levels_sorted_by_order():
	var unordered := """{
		"pack_id": "p", "name": "n", "author": "a", "version": "1",
		"levels": [
			{"level_id": "c", "file": "c.tres", "name": "C", "order": 3},
			{"level_id": "a", "file": "a.tres", "name": "A", "order": 1},
			{"level_id": "b", "file": "b.tres", "name": "B", "order": 2}
		]
	}"""
	var pack := LevelPack.from_json(unordered)
	assert_eq(pack.levels[0]["level_id"], "a")
	assert_eq(pack.levels[1]["level_id"], "b")
	assert_eq(pack.levels[2]["level_id"], "c")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `LevelPack` class not found.

- [ ] **Step 3: Implement `LevelPack`**

Create `/Users/eugene/git/keen_reloaded/src/data/level_pack.gd`:

```gdscript
class_name LevelPack
extends RefCounted
## Parsed representation of a level pack's manifest.json. Pure data — does
## not load the .tres level files (that's PackLoader's job).

var pack_id: String = ""
var pack_name: String = ""
var author: String = ""
var version: String = ""
var episode: String = ""
var levels: Array[Dictionary] = []  # each: {level_id, file, name, order}


## Parses manifest JSON text. Returns null if invalid or missing required fields.
static func from_json(json_text: String) -> LevelPack:
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = parsed
	for key in ["pack_id", "name", "author", "version", "levels"]:
		if not d.has(key):
			return null
	var raw_levels: Variant = d["levels"]
	if typeof(raw_levels) != TYPE_ARRAY:
		return null

	var pack := LevelPack.new()
	pack.pack_id = d["pack_id"]
	pack.pack_name = d["name"]
	pack.author = d["author"]
	pack.version = d["version"]
	pack.episode = d.get("episode", "")

	for entry: Variant in raw_levels:
		if typeof(entry) == TYPE_DICTIONARY:
			pack.levels.append(entry)

	pack.levels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("order", 0)) < int(b.get("order", 0)))
	return pack
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all level_pack tests green (valid parse, invalid JSON null, missing field null, sorting).

- [ ] **Step 5: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/data/level_pack.gd tests/unit/test_level_pack.gd
git commit -m "feat: add LevelPack manifest parser with validation + sorting"
```

---

## Task 7: Integration test — full `LevelData` ↔ `LevelPack` flow

**Files:**
- Create: `tests/unit/test_integration_data_flow.gd`

This is a sanity check that the data model classes compose correctly: build a level, save it, parse a manifest pointing at it, and confirm the pieces fit.

- [ ] **Step 1: Write the integration test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_integration_data_flow.gd`:

```gdscript
extends GutTest

func test_level_matches_manifest_entry():
	# Build and save a level as a pack would expect.
	var ld := LevelData.new()
	ld.level_id = "keen1_01"
	ld.level_name = "Border Village"
	ld.episode = "keen1"
	ld.order = 1
	ld.width = 8
	ld.height = 4
	ld.fill_blank()
	ld.set_geometry_tile(0, 3, 1)
	ld.player_spawn = Vector2i(1, 2)
	ld.entities.append(EntityDef.new("vorticon", 5, 1))

	var dir := "user://tests/integration/"
	DirAccess.make_dir_recursive_absolute(dir)
	var level_path := dir + "keen1_01.tres"
	assert_eq(ResourceSaver.save(ld, level_path), OK)

	# A manifest that references it.
	var manifest_text := """{
		"pack_id": "keen1", "name": "Keen 1", "author": "me", "version": "1.0",
		"levels": [{"level_id": "keen1_01", "file": "keen1_01.tres", "name": "Border Village", "order": 1}]
	}"""
	var pack := LevelPack.from_json(manifest_text)
	assert_not_null(pack)
	assert_eq(pack.levels.size(), 1)

	# Load the level the manifest points to and confirm id matches.
	var entry: Dictionary = pack.levels[0]
	var loaded := ResourceLoader.load(level_path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	assert_not_null(loaded)
	assert_eq(loaded.level_id, entry["level_id"])
	assert_eq(loaded.entities.size(), 1)
```

- [ ] **Step 2: Run the full test suite**

Run: `./tests/run_all.sh`
Expected: ALL tests PASS across all files (smoke, entity_def, level_data, level_pack, integration).

- [ ] **Step 3: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add tests/unit/test_integration_data_flow.gd
git commit -m "test: add data model integration test"
```

---

## Task 8: Add an `AGENTS.md` with build/test commands

**Files:**
- Create: `AGENTS.md`

This records the project-specific commands so future sessions know how to test.

- [ ] **Step 1: Write `AGENTS.md`**

Create `/Users/eugene/git/keen_reloaded/AGENTS.md`:

```markdown
# keen_reloaded — Agent Notes

## Project
Godot 4.7 game (Commander Keen remaster). GDScript. Desktop-only.

## Godot binary
`/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot`

## Commands
- **Run tests (headless):** `./tests/run_all.sh`
- **Import project:** `godot --headless --import --quit`
- **Open editor:** `godot -e` (or open `project.godot` in Godot app)

## Testing
GUT (Godot Unit Test) framework, vendored in `addons/gut/`.
Tests live in `tests/unit/` and extend `GutTest`.
Always run `./tests/run_all.sh` after changes — it must pass before commit.

## Architecture
See `docs/superpowers/specs/2026-06-25-keen-reloaded-design.md`.
Levels = `LevelData` Resource (.tres). Editor writes, runtime reads.
Entities are data-driven via EntityRegistry (per-episode registration).
```

- [ ] **Step 2: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add AGENTS.md
git commit -m "docs: add AGENTS.md with build/test commands"
```

---

## Plan 1 Complete Criteria

- [ ] Godot 4.7 project imports cleanly (`--headless --import --quit` exits 0, no errors)
- [ ] GUT installed and smoke tests pass
- [ ] `EntityDef` resource: construct + serialize round-trip
- [ ] `LevelData` resource: metadata, dimensions, tile get/set, full serialize round-trip (incl. nested `EntityDef`)
- [ ] `LevelPack` manifest parser: valid parse, invalid/missing rejection, order sorting
- [ ] Integration test: level saved + loaded matches manifest entry
- [ ] `./tests/run_all.sh` is green
- [ ] All work committed to `main`

## Next Plans (out of scope here)

- **Plan 2:** Level editor MVP (3-panel UI, tile painting, entity placement, save/load, Test ▶)
- **Plan 3:** Runtime core (LevelRuntime, Player CharacterBody2D, base entity classes, Keen 1 entities)
- **Plan 4:** Pack loading (PackLoader scans res:// + user://, level-select menu, GameManager progression)
