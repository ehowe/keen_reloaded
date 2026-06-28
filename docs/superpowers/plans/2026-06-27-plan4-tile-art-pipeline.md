# keen_reloaded — Plan 4: Tile-Art Import Pipeline

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire externally-authored tile art into the game through the existing `LevelData.tileset_ref` seam, with a procedural fallback — so an authored `TileSet` renders real art (and its authored collision) in both editor and runtime, and old/blank levels keep working.

**Architecture:** Author tiles in Aseprite → configure a `.tres` in Godot's TileSet editor → assign it via the inspector into `LevelData.tileset_ref`. A new `TileAtlas` helper owns the row-major tile-id ↔ atlas-coords convention, shared by `LevelRuntime` (renders + collides) and the editor canvas/palette. When `tileset_ref` is null, both fall back to the Plan 3 `ProceduralTileSet` colors.

**Tech Stack:** Godot 4.7, GDScript, GUT (Godot Unit Test).

**Godot binary:** `/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot`

**Design spec:** `docs/superpowers/specs/2026-06-27-plan4-tile-art-pipeline-design.md`

---

## Scope

- **In:** `TileAtlas` helper; `LevelRuntime.build` uses `tileset_ref` (else procedural); editor canvas + palette render real tiles when `tileset_ref` set; inspector TileSet picker; procedural fallback retained.
- **Out (later plans):** entity sprites, shoot, enemy AI, exit/special logic, level authoring, multi-source/animated tiles.

## API note (verified against Godot 4.7 stable, headless)

- `TileSetAtlasSource.margins` — **plural** (`margin` does not exist). Read & write.
- `TileSetAtlasSource.get_tiles_count()` — **plural** (`get_tile_count` does not exist).
- `TileSet.add_source(src)` returns the int source id (0 for the first source).
- `Control.draw_texture_rect_region(texture, dest_rect, src_rect, modulate=Color(1,1,1,1))`.
- `AtlasTexture.atlas` + `AtlasTexture.region` for palette thumbnails.
- Column count = `int((tex.get_width() - margins.x + separation.x) / (region.x + separation.x))`.

## File Structure (this plan)

| File | Responsibility |
|------|----------------|
| `src/core/tile_atlas.gd` | NEW. Maps `LevelData` integer tile ids ↔ TileSet atlas coords (row-major). Shared by runtime + editor. |
| `src/runtime/level_runtime.gd` | MODIFY `build()` + `_add_tile_layer`: use `level.tileset_ref` when present, else procedural. |
| `src/editor/canvas_editor.gd` | MODIFY `_layer_pass`: draw real tile textures when `tileset_ref` set, else colored cells. |
| `src/editor/palette_panel.gd` | MODIFY: rebuildable tile grid; real tile thumbnails when `tileset_ref` set, else color buttons. |
| `src/editor/inspector_panel.gd` | MODIFY: add TileSet picker (OptionButton scanning `assets/tilesets/*.tres`). |
| `tests/unit/test_tile_atlas.gd` | NEW. GUT for the helper. |
| `tests/unit/test_level_runtime.gd` | EXTEND. Assert `tileset_ref` path. |

**Testing stance (same as Plan 3):** GUT for deterministic logic (`TileAtlas`, runtime tileset wiring). Canvas/palette/inspector are draw/UI → manual via `make edit`. Movement + collision *feel* → manual via Test ▶.

---

## Task 1: `TileAtlas` helper (TDD)

**Files:**
- Create: `src/core/tile_atlas.gd`
- Create: `tests/unit/test_tile_atlas.gd`

- [ ] **Step 1: Write the failing test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_tile_atlas.gd`:

```gdscript
extends GutTest

## 4 cols x 2 rows, cell 16, margins (2,2), separation (1,1), 8 tiles.
## texture size = 4*16 + 2 + 3*1 = 69 wide, 2*16 + 2 + 1*1 = 35 tall.
func _fixture() -> TileSet:
	var img := Image.create(69, 35, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0, 1))
	var tex := ImageTexture.create_from_image(img)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(16, 16)
	src.margins = Vector2i(2, 2)
	src.separation = Vector2i(1, 1)
	ts.add_source(src)
	for i in range(8):
		src.create_tile(Vector2i(i % 4, i / 4))
	return ts


func test_columns_from_atlas_geometry():
	assert_eq(TileAtlas.columns(_fixture()), 4)


func test_rows_from_atlas_geometry():
	assert_eq(TileAtlas.rows(_fixture()), 2)


func test_tile_count_is_grid_size():
	assert_eq(TileAtlas.tile_count(_fixture()), 8)


func test_atlas_coords_row_major_with_wrap():
	var ts := _fixture()
	assert_eq(TileAtlas.atlas_coords_for_id(ts, 1), Vector2i(0, 0))
	assert_eq(TileAtlas.atlas_coords_for_id(ts, 4), Vector2i(3, 0), "end of row 1")
	assert_eq(TileAtlas.atlas_coords_for_id(ts, 5), Vector2i(0, 1), "wraps to row 2")
	assert_eq(TileAtlas.atlas_coords_for_id(ts, 8), Vector2i(3, 1))


func test_atlas_coords_invalid_ids():
	var ts := _fixture()
	assert_eq(TileAtlas.atlas_coords_for_id(ts, 0), Vector2i(-1, -1))
	assert_eq(TileAtlas.atlas_coords_for_id(ts, -3), Vector2i(-1, -1))
	assert_eq(TileAtlas.atlas_coords_for_id(null, 1), Vector2i(-1, -1))


func test_tile_region_accounts_for_margins_and_separation():
	var ts := _fixture()
	# id 5 -> idx 4 -> coords (0,1): x = 2 + 0*(16+1) = 2, y = 2 + 1*(16+1) = 19
	assert_eq(TileAtlas.tile_region(ts, 5), Rect2(2, 19, 16, 16))
	# id 4 -> idx 3 -> coords (3,0): x = 2 + 3*(16+1) = 53, y = 2
	assert_eq(TileAtlas.tile_region(ts, 4), Rect2(53, 2, 16, 16))


func test_tile_icon_is_atlas_texture_with_region():
	var ts := _fixture()
	var icon: AtlasTexture = TileAtlas.tile_icon(ts, 5)
	assert_not_null(icon)
	assert_eq(icon.region, Rect2(2, 19, 16, 16))
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `TileAtlas` class not found (script doesn't exist yet).

- [ ] **Step 3: Implement `TileAtlas`**

Create `/Users/eugene/git/keen_reloaded/src/core/tile_atlas.gd`:

```gdscript
class_name TileAtlas
extends RefCounted
## Maps LevelData integer tile ids to TileSet atlas coordinates. Row-major over
## the atlas source's grid (column count derived from the source geometry so
## multi-row sheets work). Shared by LevelRuntime + the editor so they never
## disagree on which cell a tile id points to.

## Atlas source id assumed for authored tilesets (and the procedural fallback).
const SOURCE_ID := 0


## Number of tile columns in the atlas source's grid.
static func columns(tileset: TileSet) -> int:
	if tileset == null or tileset.get_source_count() == 0:
		return 0
	var src: TileSetAtlasSource = tileset.get_source(SOURCE_ID)
	var region := src.texture_region_size
	var tex := src.texture
	if tex == null or region.x <= 0:
		return 0
	var sep := src.separation.x
	var margin := src.margins.x
	return int((tex.get_width() - margin + sep) / (region.x + sep))


## Number of tile rows in the atlas source's grid.
static func rows(tileset: TileSet) -> int:
	if tileset == null or tileset.get_source_count() == 0:
		return 0
	var src: TileSetAtlasSource = tileset.get_source(SOURCE_ID)
	var region := src.texture_region_size
	var tex := src.texture
	if tex == null or region.y <= 0:
		return 0
	var sep := src.separation.y
	var margin := src.margins.y
	return int((tex.get_height() - margin + sep) / (region.y + sep))


## Total grid cells (columns * rows) — the palette size for an authored TileSet.
static func tile_count(tileset: TileSet) -> int:
	return columns(tileset) * rows(tileset)


## Row-major atlas coords for tile id (1-based). id<=0 / no source -> Vector2i(-1,-1).
static func atlas_coords_for_id(tileset: TileSet, id: int) -> Vector2i:
	if id <= 0 or tileset == null or tileset.get_source_count() == 0:
		return Vector2i(-1, -1)
	var cols := columns(tileset)
	if cols <= 0:
		return Vector2i(-1, -1)
	var idx := id - 1
	return Vector2i(idx % cols, idx / cols)


## The tile's source rect in the atlas texture (for draw_texture_rect_region / AtlasTexture).
static func tile_region(tileset: TileSet, id: int) -> Rect2:
	var c := atlas_coords_for_id(tileset, id)
	if c.x < 0:
		return Rect2()
	var src: TileSetAtlasSource = tileset.get_source(SOURCE_ID)
	var region := src.texture_region_size
	var sep := src.separation
	var margin := src.margins
	return Rect2(
		margin.x + c.x * (region.x + sep.x),
		margin.y + c.y * (region.y + sep.y),
		region.x, region.y)


## An AtlasTexture for a tile (icon/thumbnail use). Returns null if no texture.
static func tile_icon(tileset: TileSet, id: int) -> AtlasTexture:
	if tileset == null or tileset.get_source_count() == 0:
		return null
	var src: TileSetAtlasSource = tileset.get_source(SOURCE_ID)
	var tex := src.texture
	if tex == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = tile_region(tileset, id)
	return at
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all `TileAtlas` tests green (and the existing suite stays green).

- [ ] **Step 5: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/core/tile_atlas.gd tests/unit/test_tile_atlas.gd
git commit -m "feat: add TileAtlas helper (row-major tile-id to atlas-coords mapping)"
```

---

## Task 2: `LevelRuntime.build` uses `tileset_ref` (TDD)

**Files:**
- Modify: `src/runtime/level_runtime.gd` (`build()` + `_add_tile_layer`)
- Extend: `tests/unit/test_level_runtime.gd`

- [ ] **Step 1: Add the failing tests**

Append to `/Users/eugene/git/keen_reloaded/tests/unit/test_level_runtime.gd` (new helper + 2 tests). The helper builds a small real TileSet (with a physics layer so it's collision-capable):

```gdscript
## A minimal real TileSet: 2 cols x 1 row, cell 16, one physics layer.
func _tileset_fixture() -> TileSet:
	var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.7, 0.3, 1))
	var tex := ImageTexture.create_from_image(img)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(16, 16)
	ts.add_source(src)
	src.create_tile(Vector2i(0, 0))
	src.create_tile(Vector2i(1, 0))
	ts.add_physics_layer()
	return ts


func test_build_uses_tileset_ref_when_assigned():
	GameManager.pending_level = null
	var ts := _tileset_fixture()
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.set_geometry_tile(0, 0, 2)  # tile id 2 -> atlas (1,0)
	ld.tileset_ref = ts
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	assert_eq(rt.layers[LevelData.LAYER_GEOMETRY].tile_set, ts, "geometry uses the real TileSet")
	assert_eq(rt.layers[LevelData.LAYER_FOREGROUND].tile_set, ts, "foreground uses the real TileSet")
	assert_eq(rt.layers[LevelData.LAYER_BACKGROUND].tile_set, ts, "background uses the real TileSet")
	var geo: TileMapLayer = rt.layers[LevelData.LAYER_GEOMETRY]
	assert_eq(geo.get_cell_atlas_coords(Vector2i(0, 0)), Vector2i(1, 0), "id 2 -> atlas (1,0) via TileAtlas")
	assert_eq(geo.get_cell_source_id(Vector2i(0, 0)), TileAtlas.SOURCE_ID, "source id 0")
	assert_true(ts.get_physics_layers_count() >= 1, "TileSet carries a physics (collision) layer")


func test_build_falls_back_to_procedural_when_tileset_ref_null():
	GameManager.pending_level = null
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.set_geometry_tile(0, 0, 1)
	assert_null(ld.tileset_ref)
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	# Procedural fallback: geometry TileSet is NOT the (null) tileset_ref; it's built.
	var geo: TileMapLayer = rt.layers[LevelData.LAYER_GEOMETRY]
	assert_not_null(geo.tile_set)
	assert_eq(geo.get_cell_atlas_coords(Vector2i(0, 0)), Vector2i(0, 0), "procedural id 1 -> (0,0)")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — geometry layer does not equal `ts` (runtime still builds `ProceduralTileSet` even when `tileset_ref` is set), and atlas coords won't match the multi-source mapping yet.

- [ ] **Step 3: Modify `build()` and `_add_tile_layer`**

In `/Users/eugene/git/keen_reloaded/src/runtime/level_runtime.gd`, replace the `build` function:

```gdscript
## Tear down any previous build and assemble the world from `level`.
func build(level: LevelData) -> void:
	_clear()
	scale = Vector2(RUNTIME_SCALE, RUNTIME_SCALE)
	var ts := level.tile_size
	var ts_geo: TileSet
	var ts_decor: TileSet
	if level.tileset_ref != null:
		ts_geo = level.tileset_ref
		ts_decor = level.tileset_ref
	else:
		var max_id := _max_tile_id(level)
		ts_geo = ProceduralTileSet.build(max_id, ts, true)
		ts_decor = ProceduralTileSet.build(max_id, ts, false)
	layers[LevelData.LAYER_BACKGROUND] = _add_tile_layer(level, LevelData.LAYER_BACKGROUND, ts_decor)
	layers[LevelData.LAYER_FOREGROUND] = _add_tile_layer(level, LevelData.LAYER_FOREGROUND, ts_decor)
	layers[LevelData.LAYER_GEOMETRY] = _add_tile_layer(level, LevelData.LAYER_GEOMETRY, ts_geo)
	_spawn_player(level, ts)
	_spawn_entities(level, ts)
```

And replace the `_add_tile_layer` function (route coords through `TileAtlas` instead of the hardcoded single-row `Vector2i(id - 1, 0)`):

```gdscript
func _add_tile_layer(level: LevelData, layer_name: String, tileset: TileSet) -> TileMapLayer:
	var tml := TileMapLayer.new()
	tml.name = "Tiles_" + layer_name
	tml.tile_set = tileset
	var src_id: int = TileAtlas.SOURCE_ID if tileset.get_source_count() > 0 else -1
	for y in range(level.height):
		for x in range(level.width):
			var id := level.get_tile(layer_name, x, y)
			if id > 0 and src_id >= 0:
				var coords := TileAtlas.atlas_coords_for_id(tileset, id)
				if coords.x >= 0:
					tml.set_cell(Vector2i(x, y), src_id, coords)
	add_child(tml)
	return tml
```

(Note: for the procedural fallback, `TileAtlas.atlas_coords_for_id` still yields `(id-1, 0)` because the procedural atlas is single-row — so existing behavior is preserved. The fallback test confirms this.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — both new tests green; the pre-existing `test_level_runtime.gd` tests (null `tileset_ref` path) still green.

- [ ] **Step 5: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/runtime/level_runtime.gd tests/unit/test_level_runtime.gd
git commit -m "feat: LevelRuntime renders+collides from level.tileset_ref (procedural fallback)"
```

---

## Task 3: Editor canvas renders real tile art

**Files:**
- Modify: `src/editor/canvas_editor.gd` (`_layer_pass`)

No GUT test here — `_draw()` is a draw call, not unit-testable. Verified manually (Task 6).

- [ ] **Step 1: Modify `_layer_pass`**

In `/Users/eugene/git/keen_reloaded/src/editor/canvas_editor.gd`, replace the `_layer_pass` function:

```gdscript
func _layer_pass(layer: String, cs: float, tint: Color) -> void:
	var ts: TileSet = _level().tileset_ref
	var has_art := ts != null and ts.get_source_count() > 0
	for y in range(_level().height):
		for x in range(_level().width):
			var id := _level().get_tile(layer, x, y)
			if id <= 0:
				continue
			if has_art:
				var region := TileAtlas.tile_region(ts, id)
				var tex := ts.get_source(TileAtlas.SOURCE_ID).texture
				draw_texture_rect_region(tex, Rect2(x * cs, y * cs, cs, cs), region, tint)
			else:
				draw_rect(Rect2(x * cs, y * cs, cs, cs), EditorColors.tile_color(id) * tint, true)
```

The layer `tint` still multiplies over real art so bg/fg/geo stay visually distinct in the editor.

- [ ] **Step 2: Verify import is clean**

Run:
```bash
cd /Users/eugene/git/keen_reloaded
"/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot" --headless --path . --import --quit 2>&1 | tail -3
./tests/run_all.sh
```
Expected: import clean (exit 0); full suite still green (no behavior change when `tileset_ref` is null).

- [ ] **Step 3: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/editor/canvas_editor.gd
git commit -m "feat: editor canvas renders real tile art when tileset_ref is set"
```

---

## Task 4: Editor palette shows real tile thumbnails

**Files:**
- Modify: `src/editor/palette_panel.gd`

No GUT test — UI. Verified manually (Task 6).

**Key constraint (see class docstring, lines 4-7):** `refresh()` must never rebuild the tile grid during a tile-button's `pressed` emission (it would free the emitting button → crash). The rebuild is gated on a `tileset_ref` *change*, which only happens via the inspector (Task 5) — never via a tile-button click — so it's safe.

- [ ] **Step 1: Make the tile grid rebuildable + change-aware**

In `/Users/eugene/git/keen_reloaded/src/editor/palette_panel.gd`:

(a) Add a `_tile_grid` reference and a `_last_tileset` tracker to the vars block (top of class):

```gdscript
var _tile_buttons: Array[Button] = []
var _tile_grid: GridContainer
var _last_tileset: TileSet = null
var _layer_buttons: Dictionary = {}  # layer -> Button
```

(b) Replace the tile-grid portion of `build()` (the block from `add_child(_section_label("Tiles"))` through `add_child(grid)`) so it delegates to a rebuildable method:

```gdscript
	add_child(_section_label("Tiles"))
	_tile_grid = GridContainer.new()
	_tile_grid.columns = 4
	add_child(_tile_grid)
```

(The entity/layer/tool sections below stay unchanged.)

(c) Add a `_rebuild_tile_grid(e)` method and call it from the end of `build()` (replace the existing `refresh(e)` call at the end of `build` with a rebuild + refresh):

```gdscript
func _rebuild_tile_grid(e: LevelEditor) -> void:
	for c in _tile_grid.get_children():
		c.queue_free()
	_tile_buttons.clear()
	_last_tileset = e.level.tileset_ref
	var ts: TileSet = _last_tileset
	var count := _tile_count(e)
	var tile_group := ButtonGroup.new()
	for id in range(1, count + 1):
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = tile_group
		b.custom_minimum_size = Vector2(40, 40)
		if ts != null and ts.get_source_count() > 0:
			b.icon = TileAtlas.tile_icon(ts, id)
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.expand_icon = true
			b.tooltip_text = "Tile %d" % id
		else:
			b.text = str(id)
			b.add_theme_color_override("font_color", EditorColors.tile_color(id))
			b.add_theme_color_override("font_hover_color", EditorColors.tile_color(id))
		var idv := id
		b.pressed.connect(func() -> void: e.set_selected_tile_id(idv))
		_tile_grid.add_child(b)
		_tile_buttons.append(b)


## Tile count for the palette: the atlas grid size when a TileSet is assigned,
## else the fixed Plan 2 default.
func _tile_count(e: LevelEditor) -> int:
	var ts: TileSet = e.level.tileset_ref
	if ts != null and ts.get_source_count() > 0:
		return TileAtlas.tile_count(ts)
	return LevelEditor.PALETTE_TILE_COUNT
```

(d) Update `refresh()` to rebuild the grid ONLY when the tileset changed (safe — a tile-button click does not change `tileset_ref`). Replace the existing `refresh` function:

```gdscript
## Lightweight: toggle states only. Rebuilds the tile grid exclusively when the
## level's TileSet changed (which happens via the inspector, never a tile click),
## so it never frees a button during its own pressed emission.
func refresh(e: LevelEditor) -> void:
	if e.level.tileset_ref != _last_tileset:
		_rebuild_tile_grid(e)
	for i in range(_tile_buttons.size()):
		_tile_buttons[i].set_pressed_no_signal((i + 1) == e.selected_tile_id)
	for layer in _layer_buttons:
		_layer_buttons[layer].set_pressed_no_signal(layer == e.active_layer)
	for tool in _tool_buttons:
		_tool_buttons[tool].set_pressed_no_signal(tool == e.active_tool)
	_entity_list.deselect_all()
	for i in range(_entity_ids.size()):
		if _entity_ids[i] == e.selected_entity_type:
			_entity_list.select(i)
			break
```

(e) At the end of `build()`, replace the existing `refresh(e)` call with `_rebuild_tile_grid(e)` followed by `refresh(e)`:

```gdscript
	_rebuild_tile_grid(e)
	refresh(e)
```

- [ ] **Step 2: Verify import is clean + suite green**

Run:
```bash
cd /Users/eugene/git/keen_reloaded
"/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot" --headless --path . --import --quit 2>&1 | tail -3
./tests/run_all.sh
```
Expected: import clean; suite green.

- [ ] **Step 3: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/editor/palette_panel.gd
git commit -m "feat: editor palette shows real tile thumbnails when tileset_ref is set"
```

---

## Task 5: Inspector TileSet picker

**Files:**
- Modify: `src/editor/inspector_panel.gd`
- Create dir: `assets/tilesets/` (the picker scans here)

No GUT test — UI. Verified manually (Task 6).

- [ ] **Step 1: Create the tilesets directory**

Create the directory the picker scans, tracked by git via a `.gitkeep` (an empty dir is otherwise untracked; `DirAccess` handles a missing dir either way):

```bash
cd /Users/eugene/git/keen_reloaded
mkdir -p assets/tilesets
touch assets/tilesets/.gitkeep
```

- [ ] **Step 2: Add the picker to the inspector**

In `/Users/eugene/git/keen_reloaded/src/editor/inspector_panel.gd`:

(a) Add a `_tileset_picker: OptionButton` var alongside the other widget vars (near line 14):

```gdscript
var _entity_box: VBoxContainer
var _tileset_picker: OptionButton
```

(b) In `build(e)`, after the Player Spawn section (after `add_child(_labeled("Spawn Y", _spawn_y))`), add a TileSet section:

```gdscript
	add_child(_section_label("TileSet"))
	_tileset_picker = OptionButton.new()
	_populate_tileset_picker()
	_tileset_picker.item_selected.connect(_on_tileset_selected)
	add_child(_labeled("Art", _tileset_picker))
```

(c) In `refresh(e)`, after the spawn spin boxes are synced (after `_spawn_y.set_value_no_signal(...)`), sync the picker to the current `tileset_ref`:

```gdscript
	_sync_tileset_picker(e.level.tileset_ref)
```

(d) Add the picker logic methods (place them in the handlers/helpers area, e.g. after `_on_spawn_changed`):

```gdscript
func _populate_tileset_picker() -> void:
	_tileset_picker.clear()
	_tileset_picker.add_item("None (procedural)", 0)
	_tileset_picker.set_item_metadata(0, "")
	var dir := DirAccess.open("res://assets/tilesets")
	if dir == null:
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".tres"):
			_tileset_picker.add_item(fn)
			_tileset_picker.set_item_metadata(_tileset_picker.item_count - 1, "res://assets/tilesets/%s" % fn)
		fn = dir.get_next()


func _sync_tileset_picker(ts: TileSet) -> void:
	var want := ""
	if ts != null and ts.resource_path != null and ts.resource_path != "":
		want = ts.resource_path
	for i in range(_tileset_picker.item_count):
		if String(_tileset_picker.get_item_metadata(i)) == want:
			_tileset_picker.select(i)
			return
	_tileset_picker.select(0)


func _on_tileset_selected(index: int) -> void:
	var path := String(_tileset_picker.get_item_metadata(index))
	if path == "":
		_e.level.tileset_ref = null
	else:
		_e.level.tileset_ref = load(path)
	_e._broadcast()
```

- [ ] **Step 3: Verify import is clean + suite green**

Run:
```bash
cd /Users/eugene/git/keen_reloaded
"/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot" --headless --path . --import --quit 2>&1 | tail -3
./tests/run_all.sh
```
Expected: import clean; suite green.

- [ ] **Step 4: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/editor/inspector_panel.gd assets/tilesets
git commit -m "feat: inspector TileSet picker (assigns level.tileset_ref)"
```

---

## Task 6: Manual verification — author a sample + Test ▶

**Files:** none (manual). The user authors one small tileset externally.

This task verifies the whole pipeline end-to-end. It cannot be automated.

- [ ] **Step 1: Author a small sample sheet**

In Aseprite/LibreSprite (or any image editor): create a PNG that is a **clean uniform grid** of 16×16 cells, e.g. 4 columns × 2 rows (8 tiles). Fill a few cells with distinct simple art (a solid block, a slope-ish shape, a decorative dot). Save to `/Users/eugene/git/keen_reloaded/assets/tilesets/sample.png`.

- [ ] **Step 2: Build the TileSet in Godot's editor**

Run `make edit`. In the editor:
1. Create a new TileSet resource (`FileSystem` dock → right-click `assets/tilesets` → New → TileSet → save as `assets/tilesets/sample.tres`).
2. Add `sample.png` as an atlas source (drag into the TileSet panel). Set cell size to 16×16. Godot auto-creates tiles for the grid.
3. Open the TileSet's physics layers, add one physics layer, and paint a collision polygon (full-cell rectangle) on the tile(s) you'll use as solid ground.
4. Save the TileSet.

- [ ] **Step 3: Verify in the editor**

In the level editor:
1. New level (small, e.g. 16×12).
2. Inspector → **TileSet → Art**: pick `sample.tres`. Confirm:
   - The **palette** now shows real tile thumbnails (not color buttons).
   - The **canvas** paints the real tile art (with layer tints) when you paint.
3. Paint a floor of solid tiles on the bottom row; place a candy entity; set player spawn.
4. Switch the picker back to "None (procedural)" — confirm canvas + palette revert to colored cells.

- [ ] **Step 4: Verify in the runtime (Test ▶)**

Click **Test ▶**. Confirm:
- The floor renders with real art at ×3 scale.
- The player stands on the floor (real authored collision works).
- Run (A/D), jump (Space), pogo (P) behave.
- Press **Esc** → returns to the editor with the level + the `tileset_ref` assignment intact.

- [ ] **Step 5: Commit the authored sample**

```bash
cd /Users/eugene/git/keen_reloaded
git add assets/tilesets/sample.png assets/tilesets/sample.tres
git commit -m "assets: sample tileset (proves the Plan 4 art pipeline)"
```

---

## Plan 4 Complete Criteria

- [ ] `TileAtlas` maps ids ↔ atlas coords correctly (row-major, multi-row wrap, invalid → `(-1,-1)`) — GUT.
- [ ] `LevelRuntime.build` renders from an assigned `tileset_ref` (real TileSet + its physics layer); falls back to procedural when null — GUT (both paths).
- [ ] Editor canvas renders real tile art when `tileset_ref` set, colors when null — manual.
- [ ] Editor palette shows real thumbnails when `tileset_ref` set, rebuilds safely on tileset change, color buttons when null — manual.
- [ ] Inspector TileSet picker lists `assets/tilesets/*.tres`, assigns `level.tileset_ref`, live-refreshes canvas/palette, "None" reverts to procedural — manual.
- [ ] One sample authored tileset demonstrates the full pipeline (author → configure → assign → render + collide via Test ▶) — manual.
- [ ] No regression: existing/blank levels still use procedural colors; `./tests/run_all.sh` green; `godot --headless --import --quit` clean; all work committed to `main`.
