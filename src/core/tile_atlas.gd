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
