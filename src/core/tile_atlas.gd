class_name TileAtlas
extends RefCounted
## Maps LevelData integer tile ids to TileSet atlas coordinates. Row-major over
## the atlas source's grid (column count derived from the source geometry so
## multi-row sheets work). Shared by LevelRuntime + the editor so they never
## disagree on which cell a tile id points to.
##
## The primary atlas source is resolved by INDEX (get_source_id(0)), not a
## hardcoded id, so authored TileSets whose first source landed at id != 0
## (e.g. after deleting + re-adding a source in the editor) still work.

const INVALID_COORDS := Vector2i(-1, -1)


## Actual source id of the primary atlas (resolved by index). -1 if none.
static func source_id(tileset: TileSet) -> int:
	if tileset == null or tileset.get_source_count() == 0:
		return -1
	return tileset.get_source_id(0)


## Resolves the primary atlas source robustly. Returns null if none.
static func _atlas_source(tileset: TileSet) -> TileSetAtlasSource:
	if tileset == null or tileset.get_source_count() == 0:
		return null
	return tileset.get_source(tileset.get_source_id(0))


## Base texture of the atlas (for draw_texture_rect_region). null if none.
static func atlas_texture(tileset: TileSet) -> Texture2D:
	var src := _atlas_source(tileset)
	if src == null:
		return null
	return src.texture


## Number of tile columns in the atlas source's grid.
static func columns(tileset: TileSet) -> int:
	var src := _atlas_source(tileset)
	if src == null:
		return 0
	var region := src.texture_region_size
	var tex := src.texture
	if tex == null or region.x <= 0:
		return 0
	var sep := src.separation.x
	var margin := src.margins.x
	return int((tex.get_width() - margin + sep) / (region.x + sep))


## Number of tile rows in the atlas source's grid.
static func rows(tileset: TileSet) -> int:
	var src := _atlas_source(tileset)
	if src == null:
		return 0
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


## Row-major atlas coords for tile id (1-based). id<=0 / no source -> (-1,-1).
static func atlas_coords_for_id(tileset: TileSet, id: int) -> Vector2i:
	if id <= 0 or tileset == null or tileset.get_source_count() == 0:
		return INVALID_COORDS
	var cols := columns(tileset)
	if cols <= 0:
		return INVALID_COORDS
	var idx := id - 1
	return Vector2i(idx % cols, idx / cols)


## The tile's source rect in the atlas texture (for draw_texture_rect_region / AtlasTexture).
static func tile_region(tileset: TileSet, id: int) -> Rect2:
	var c := atlas_coords_for_id(tileset, id)
	if c.x < 0:
		return Rect2()
	var src := _atlas_source(tileset)
	var region := src.texture_region_size
	var sep := src.separation
	var margin := src.margins
	return Rect2(
		margin.x + c.x * (region.x + sep.x),
		margin.y + c.y * (region.y + sep.y),
		region.x, region.y)


## An AtlasTexture for a tile (icon/thumbnail use). Returns null if no texture.
static func tile_icon(tileset: TileSet, id: int) -> AtlasTexture:
	var src := _atlas_source(tileset)
	if src == null:
		return null
	var tex := src.texture
	if tex == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = tile_region(tileset, id)
	return at
