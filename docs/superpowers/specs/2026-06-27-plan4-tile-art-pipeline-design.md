# keen_reloaded — Plan 4: Tile-Art Import Pipeline (Design Spec)

**Brainstormed:** 2026-06-27
**Scope owner:** runtime + editor toolchain
**Predecessors:** Plans 1–3 (`LevelData` model, level editor MVP, runtime core with procedural no-art tiles).

## 1. Goal

Replace the no-art procedural tiles with **real, externally-authored tile art** using a clean, no-importer-code pipeline. The existing-but-dead `LevelData.tileset_ref: TileSet` field becomes the live seam: when a level references an authored `TileSet`, the editor and runtime render its real art (and its authored collision); otherwise they fall back to the Plan 3 `ProceduralTileSet` colors. No regression for existing/blank levels.

## 2. Scope

### In scope
- **`TileAtlas` helper** owning the tile-id ↔ atlas-coords convention (shared by runtime + editor).
- **`LevelRuntime.build`** uses `level.tileset_ref` when present (real art + authored collision), else the procedural fallback.
- **Editor canvas** (`CanvasEditor`) draws real tile textures when `tileset_ref` is set, else colored cells.
- **Editor palette** (`PalettePanel`) shows real tile thumbnails when `tileset_ref` is set, else color buttons.
- **Inspector** (`InspectorPanel`) gains a TileSet picker to assign `tileset_ref`.
- Procedural fallback retained (zero regression).
- End-to-end pipeline proven with one sample authored tileset.

### Out of scope (deferred to later plans)
- **Entity sprites** — entities stay placeholder procedural shapes (this plan is tiles only).
- **Shoot** ability (moved to its own phase).
- **Enemy AI** (vorticon/yorp behaviors), exit/special completion logic, first level authoring.
- **Multi-source / animated tiles** — one static atlas source id `0` only, this phase.
- The abandoned Commander Keen sprite rips (already removed in `c326ccb`).

## 3. Key decisions (resolved during brainstorm)

| Decision | Choice | Why |
|----------|--------|-----|
| Art source | **Author externally** (Aseprite/LibreSprite), not rips | Original Keen sprite sets aren't cleanly available; rips are unusable (irregular 652×873 / 845×425 sheets). Authoring original tiles is the clean path. |
| Import mechanism | **Godot's built-in TileSet editor** configures the `.tres` | Zero importer code; mature tool handles atlas cell-size + collision painting in one place; the `.tres` is committed (reproducible). |
| Seam | `LevelData.tileset_ref` (already declared, unused) | No data-model change; the hook was anticipated in Plan 1. |
| Fallback | `ProceduralTileSet` retained | Existing levels / blank levels keep working; existing tests stay green. |
| id ↔ atlas mapping | **Row-major** over the atlas grid; column count derived from atlas source geometry | Supports multi-row sheets; `LevelData` keeps plain integer tile ids. |
| Layers | One `TileSet` serves all 3 layers (geo/fg/bg) | `LevelData` already has 3 tile arrays + one `tileset_ref`; collision is authored per-tile so decorative tiles simply have no polygons. |
| Shoot | Deferred | Focus the plan; shoot is orthogonal to the art pipeline. |

## 4. Architecture

### Pipeline (no new importer code)

1. **Author** tiles in Aseprite/LibreSprite → export a **clean uniform-grid** PNG (16×16 cells; gutters OK — Godot's atlas handles margin/separation).
2. **Configure once** in Godot's TileSet editor: add the PNG as atlas source `0`, set cell size, paint collision polygons per tile → save `assets/tilesets/<name>.tres`.
3. **Assign** the `.tres` to a level via the inspector TileSet picker → stored in `LevelData.tileset_ref`.

### Render rule (one rule, two consumers)

> **If `level.tileset_ref != null` → render tiles from it (real art + authored collision). Else → `ProceduralTileSet` color fallback.**

Both `LevelRuntime` and the editor (`CanvasEditor`, `PalettePanel`) apply this identical rule.

### Components

#### 4.1 NEW `src/core/tile_atlas.gd` — `TileAtlas` (RefCounted, static)

Owns the id ↔ atlas convention so runtime + editor never disagree. Pure logic, fully GUT-testable.

```gdscript
class_name TileAtlas
extends RefCounted
## Maps LevelData integer tile ids to TileSet atlas coordinates. Row-major over
## the atlas source's grid (column count derived from the source geometry so
## multi-row sheets work). Shared by LevelRuntime + the editor.

## Atlas source id assumed for authored tilesets.
const SOURCE_ID := 0

## Number of tile columns in the atlas source's grid (from texture/region/margin/separation).
static func columns(tileset: TileSet) -> int:
    if tileset == null or tileset.get_source_count() == 0:
        return 0
    var src: TileSetAtlasSource = tileset.get_source(SOURCE_ID)
    var region := src.texture_region_size
    var tex := src.texture
    if tex == null or region.x <= 0:
        return 0
    var sep := src.separation.x
    var margin := src.margins.x  # NOTE: Godot 4.7 uses `margins` (plural)
    return int((tex.get_width() - margin + sep) / (region.x + sep))

## Row-major coords for tile id (1-based). id<=0 or out-of-range -> Vector2i(-1,-1).
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
    var margin := src.margins  # NOTE: Godot 4.7 uses `margins` (plural)
    return Rect2(
        margin.x + c.x * (region.x + sep.x),
        margin.y + c.y * (region.y + sep.y),
        region.x, region.y)

## AtlasTexture for a tile (icon/thumbnail use). Caller frees if needed.
static func tile_icon(tileset: TileSet, id: int) -> AtlasTexture:
    var src: TileSetAtlasSource = tileset.get_source(SOURCE_ID)
    var tex := src.texture
    if tex == null:
        return null
    var at := AtlasTexture.new()
    at.atlas = tex
    at.region = tile_region(tileset, id)
    return at
```

#### 4.2 `src/runtime/level_runtime.gd` — `build()` TileSet selection

Minimal change: pick the TileSet, then `_add_tile_layer` routes coords through `TileAtlas`. The procedural fallback keeps its solid/decor split (all-solid geometry, no-collision decor); the real path uses **one** TileSet for all layers (collision authored per-tile).

```gdscript
func build(level: LevelData) -> void:
    _clear()
    scale = Vector2(RUNTIME_SCALE, RUNTIME_SCALE)
    var ts := level.tile_size
    var max_id := _max_tile_id(level)
    var ts_geo: TileSet
    var ts_decor: TileSet
    if level.tileset_ref != null:
        ts_geo = level.tileset_ref
        ts_decor = level.tileset_ref
    else:
        ts_geo = ProceduralTileSet.build(max_id, ts, true)
        ts_decor = ProceduralTileSet.build(max_id, ts, false)
    layers[LevelData.LAYER_BACKGROUND] = _add_tile_layer(level, LevelData.LAYER_BACKGROUND, ts_decor)
    layers[LevelData.LAYER_FOREGROUND] = _add_tile_layer(level, LevelData.LAYER_FOREGROUND, ts_decor)
    layers[LevelData.LAYER_GEOMETRY] = _add_tile_layer(level, LevelData.LAYER_GEOMETRY, ts_geo)
    _spawn_player(level, ts)
    _spawn_entities(level, ts)
```

`_add_tile_layer` switches its `set_cell` atlas arg from the hardcoded `Vector2i(id - 1, 0)` to `TileAtlas.atlas_coords_for_id(tileset, id)`, and its source id from `tileset.get_source_id(0)` to `TileAtlas.SOURCE_ID`. (For the procedural fallback this still yields `(id-1, 0)` since procedural is a single-row atlas, so existing behavior is preserved.)

#### 4.3 `src/editor/canvas_editor.gd` — `_layer_pass()` real-art path

```gdscript
func _layer_pass(layer: String, cs: float, tint: Color) -> void:
    var ts: TileSet = _level().tileset_ref
    for y in range(_level().height):
        for x in range(_level().width):
            var id := _level().get_tile(layer, x, y)
            if id <= 0:
                continue
            if ts != null and ts.get_source_count() > 0:
                var region := TileAtlas.tile_region(ts, id)
                var tex := ts.get_source(TileAtlas.SOURCE_ID).texture
                draw_texture_rect_region(tex, Rect2(x * cs, y * cs, cs, cs), region, tint)
            else:
                draw_rect(Rect2(x * cs, y * cs, cs, cs), EditorColors.tile_color(id) * tint, true)
```

Layer tints (`tint`) still multiply so bg/fg/geo stay visually distinct over real art.

#### 4.4 `src/editor/palette_panel.gd` — real thumbnails

When `level.tileset_ref != null`: enumerate tiles `1..N` (where `N` = atlas tile count = `cols * rows`), build each as a `Button` whose `icon` = `TileAtlas.tile_icon(ts, id)` (an `AtlasTexture`). Clicking sets `selected_tile_id` as today. Else: today's color buttons. The panel rebuilds on `level_changed` (already does via `refresh`).

#### 4.5 `src/editor/inspector_panel.gd` — TileSet picker

A dropdown (`OptionButton`) populated by scanning `assets/tilesets/*.tres` via `DirAccess`, plus a leading **"None (procedural)"** item (value `null`). Selecting an item assigns `level.tileset_ref` (loads via `load("res://assets/tilesets/<name>.tres")`) and triggers `_broadcast()` so canvas + palette refresh. Refreshed on panel `build`/`refresh`.

### Constraints (documented in code + this spec)

- Authored TileSet **must use atlas source id `0`** (`TileAtlas.SOURCE_ID`).
- `LevelData.tile_size` **must equal** the TileSet's `tile_size` (mismatch = misaligned cells).
- The sheet must be a **complete grid** (no holes before the highest used tile id) so row-major mapping is contiguous.
- Only static tiles this phase (no `TileSetScenesCollectionSource`, no animation).

### API note (verified against Godot 4.7 stable, headless)

- `TileSetAtlasSource.margins` — **plural** (`margin` does not exist). Same for reading.
- `TileSetAtlasSource.get_tiles_count()` — **plural** (`get_tile_count` does not exist).
- `TileSet.add_source(src)` returns the int source id (0 for the first).
- `Control.draw_texture_rect_region(texture, dest_rect, src_rect, modulate=Color(1,1,1,1))` — draws a sub-region of a texture (used by the editor canvas).
- `AtlasTexture.atlas` + `AtlasTexture.region` — for palette thumbnails.

## 5. Data flow

```
Aseprite (author) -> clean grid PNG
Godot TileSet editor (configure: cell size + collision) -> assets/tilesets/foo.tres  [committed]
Inspector picker -> LevelData.tileset_ref = load(".../foo.tres")  -> saved in level .tres
                                          |
              +---------------------------+---------------------------+
              v                                                       v
   LevelRuntime.build (runtime)                           CanvasEditor + PalettePanel (editor)
   tileset_ref != null ? real TileSet                    tileset_ref != null ? real art
                     else ProceduralTileSet                                 else EditorColors
   (TileAtlas maps id -> atlas coords in both)           (TileAtlas maps id -> region/icon)
```

## 6. Testing

### GUT (deterministic)
- **`test_tile_atlas.gd`** — build a **multi-row** `TileSet` fixture in-test (≥2 rows); assert `columns()`, `atlas_coords_for_id()` row-major (incl. wrap to 2nd row, and `id<=0` → `(-1,-1)`), `tile_region()` accounts for margin/separation.
- **`test_level_runtime.gd`** (extend) — assign a programmatic `TileSet` fixture to `level.tileset_ref`, `build()`, assert: 3 layers reference that exact TileSet; a painted cell's atlas coords == `TileAtlas.atlas_coords_for_id(fixture, id)`; the TileSet's physics layer is in effect (collision present). Fixtures are built in-test (no asset files) — a single-row `ProceduralTileSet.build` works for a basic case; build a custom multi-row `TileSet` to exercise wrap.
- Fallback path (null `tileset_ref`) already covered by today's tests → stays green.

### Manual via `make edit`
- Canvas renders authored tiles (with layer tints).
- Palette shows real thumbnails; selecting paints the right tile.
- Inspector picker lists `assets/tilesets/*.tres`; choosing one swaps art live; "None" reverts to colors.
- Test ▶: real tiles render in the runtime with working collision.

## 7. Defaults / conventions

- Tileset artifacts live under `assets/tilesets/` (dir created as needed; empty dir → picker shows only "None").
- `TileAtlas.SOURCE_ID = 0`.
- Sample tileset: authored by the user (out of code scope); tests use programmatic fixtures so they are asset-independent and run headless.

## 8. Complete-criteria for the plan

- [ ] `TileAtlas` maps ids ↔ atlas coords correctly (row-major, multi-row) — GUT.
- [ ] `LevelRuntime.build` renders + collides from an assigned `tileset_ref`; falls back to procedural when null — GUT (both paths).
- [ ] Editor canvas + palette render real tile art when `tileset_ref` set, colors when null — manual.
- [ ] Inspector TileSet picker assigns `tileset_ref` and live-refreshes canvas/palette — manual.
- [ ] One sample authored tileset demonstrates the full pipeline (author → configure → assign → render + collide) — manual via Test ▶.
- [ ] `./tests/run_all.sh` green; `godot --headless --import --quit` clean; all work committed to `main`.
- [ ] No regression: existing levels/blank levels still use procedural colors.
