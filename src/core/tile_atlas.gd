class_name TileAtlas
extends RefCounted
## Maps LevelData integer tile ids to TileSet atlas coordinates across MULTIPLE
## atlas sources. A tile id packs a source index + a row-major cell index:
##
##     id = source_index * SOURCE_STRIDE + (y * columns + x) + 1
##
## `source_index` is the 0-based position in TileSet.get_source_id(order) order
## (NOT the raw Godot source id, which may be non-contiguous after deletes).
## SOURCE_STRIDE reserves a fixed id range per source so source 0 ids stay
## 1..SOURCE_STRIDE-1 — every previously authored level keeps resolving
## identically. Shared by LevelRuntime + the editor so they never disagree on
## which cell a tile id points to.

const INVALID_COORDS := Vector2i(-1, -1)

## Cells reserved per source in the packed id space. Must exceed the largest
## atlas grid (columns*rows) any single source ever uses. 65536 fits any
## practical texture and keeps source 0 ids 1..65535 (all existing levels).
const SOURCE_STRIDE := 65536


## Number of atlas sources in the tileset.
static func source_count(tileset: TileSet) -> int:
	if tileset == null:
		return 0
	return tileset.get_source_count()


## Godot source id for the source at `order` (0-based). -1 if missing.
static func source_id_at(tileset: TileSet, order: int) -> int:
	if tileset == null or order < 0 or order >= tileset.get_source_count():
		return -1
	return tileset.get_source_id(order)


## Godot source id of the primary (order 0) atlas. -1 if none.
static func source_id(tileset: TileSet) -> int:
	return source_id_at(tileset, 0)


## The 0-based source order encoded in `id`. -1 for id<=0. Pure (no tileset).
static func source_index_for_id(id: int) -> int:
	if id <= 0:
		return -1
	return (id - 1) / SOURCE_STRIDE


## Godot source id that `id` refers to, or -1 if that source is missing.
static func source_id_for_id(tileset: TileSet, id: int) -> int:
	var order := source_index_for_id(id)
	if order < 0:
		return -1
	return source_id_at(tileset, order)


## TileSetAtlasSource at `order`, or null.
static func _source_at(tileset: TileSet, order: int) -> TileSetAtlasSource:
	var sid := source_id_at(tileset, order)
	if sid < 0:
		return null
	return tileset.get_source(sid)


## Primary atlas source (order 0). null if none.
static func _atlas_source(tileset: TileSet) -> TileSetAtlasSource:
	return _source_at(tileset, 0)


## Encodes (source order, x, y) into a packed tile id. cols is the column count
## of that source. y/x must be >= 0, cols > 0.
static func id_for_coords(source_order: int, x: int, y: int, cols: int) -> int:
	return source_order * SOURCE_STRIDE + (y * cols + x) + 1


static func _columns_of(src: TileSetAtlasSource) -> int:
	if src == null:
		return 0
	var region := src.texture_region_size
	var tex := src.texture
	if tex == null or region.x <= 0:
		return 0
	var sep := src.separation.x
	var margin := src.margins.x
	return int((tex.get_width() - margin + sep) / (region.x + sep))


static func _rows_of(src: TileSetAtlasSource) -> int:
	if src == null:
		return 0
	var region := src.texture_region_size
	var tex := src.texture
	if tex == null or region.y <= 0:
		return 0
	var sep := src.separation.y
	var margin := src.margins.y
	return int((tex.get_height() - margin + sep) / (region.y + sep))


## Columns of the source at `order`.
static func columns_at(tileset: TileSet, order: int) -> int:
	return _columns_of(_source_at(tileset, order))


## Rows of the source at `order`.
static func rows_at(tileset: TileSet, order: int) -> int:
	return _rows_of(_source_at(tileset, order))


## Columns of the primary atlas source.
static func columns(tileset: TileSet) -> int:
	return columns_at(tileset, 0)


## Rows of the primary atlas source.
static func rows(tileset: TileSet) -> int:
	return rows_at(tileset, 0)


## Grid cells of the primary atlas source.
static func tile_count(tileset: TileSet) -> int:
	return columns(tileset) * rows(tileset)


## Total tile count across ALL sources (palette enumeration).
static func tile_count_total(tileset: TileSet) -> int:
	if tileset == null:
		return 0
	var total := 0
	for i in range(tileset.get_source_count()):
		total += _columns_of(_source_at(tileset, i)) * _rows_of(_source_at(tileset, i))
	return total


## Every valid tile id across all sources, in (source order, row-major) order.
## Empty if the tileset has no usable sources.
static func all_tile_ids(tileset: TileSet) -> Array[int]:
	var out: Array[int] = []
	if tileset == null:
		return out
	for i in range(tileset.get_source_count()):
		var src := _source_at(tileset, i)
		var cols := _columns_of(src)
		var rows := _rows_of(src)
		if cols <= 0 or rows <= 0:
			continue
		var base := i * SOURCE_STRIDE
		for cell in range(cols * rows):
			out.append(base + cell + 1)
	return out


## Tile ids for a single source (row-major), or empty if the source is missing
## or has no usable texture.
static func tile_ids_for_source(tileset: TileSet, order: int) -> Array[int]:
	var out: Array[int] = []
	var src := _source_at(tileset, order)
	var cols := _columns_of(src)
	var rows := _rows_of(src)
	if cols <= 0 or rows <= 0:
		return out
	var base := order * SOURCE_STRIDE
	for cell in range(cols * rows):
		out.append(base + cell + 1)
	return out


## Display name for the source at `order`: the source's resource_name (set via
## the TileSet editor's rename) when non-empty, else "Source N". "" if missing.
static func source_name(tileset: TileSet, order: int) -> String:
	var src := _source_at(tileset, order)
	if src == null:
		return ""
	var n: String = src.resource_name
	if n.length() > 0:
		return n
	return "Source %d" % order


## Row-major atlas coords for `id` within its source. id<=0/missing -> (-1,-1).
static func atlas_coords_for_id(tileset: TileSet, id: int) -> Vector2i:
	if id <= 0 or tileset == null or tileset.get_source_count() == 0:
		return INVALID_COORDS
	var src := _source_at(tileset, source_index_for_id(id))
	if src == null:
		return INVALID_COORDS
	var cols := _columns_of(src)
	if cols <= 0:
		return INVALID_COORDS
	var cell := (id - 1) % SOURCE_STRIDE
	return Vector2i(cell % cols, cell / cols)


## The tile's source rect in its atlas texture (for draw_texture_rect_region).
static func tile_region(tileset: TileSet, id: int) -> Rect2:
	var c := atlas_coords_for_id(tileset, id)
	if c.x < 0:
		return Rect2()
	var src := _source_at(tileset, source_index_for_id(id))
	if src == null:
		return Rect2()
	var region := src.texture_region_size
	var sep := src.separation
	var margin := src.margins
	return Rect2(
		margin.x + c.x * (region.x + sep.x),
		margin.y + c.y * (region.y + sep.y),
		region.x, region.y)


## An AtlasTexture for a tile (icon/thumbnail use). null if no texture.
static func tile_icon(tileset: TileSet, id: int) -> AtlasTexture:
	var src := _source_at(tileset, source_index_for_id(id))
	if src == null:
		return null
	var tex := src.texture
	if tex == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = tile_region(tileset, id)
	return at


## Base texture of the primary atlas (order 0). null if none.
static func atlas_texture(tileset: TileSet) -> Texture2D:
	var src := _atlas_source(tileset)
	if src == null:
		return null
	return src.texture
