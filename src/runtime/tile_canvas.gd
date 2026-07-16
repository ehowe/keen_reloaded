class_name TileCanvas
extends Node2D
## Draws LevelData tiles via _draw() at a specified cell size. Used where
## TileSet.tile_size differs from LevelData.tile_size (e.g. message overlays
## with 32px font tiles in a 64px TileSet), since TileMapLayer always renders
## at the TileSet's native tile_size, producing gaps.

var level: LevelData
var cell_size: float = 32.0
var _tex_cache: Dictionary = {}  # source_order -> Texture2D


func set_data(p_level: LevelData, p_cell_size: float) -> void:
	level = p_level
	cell_size = p_cell_size
	_tex_cache.clear()
	if level != null and level.tileset_ref != null:
		var ts: TileSet = level.tileset_ref
		for i in range(ts.get_source_count()):
			var src := ts.get_source(ts.get_source_id(i))
			if src is TileSetAtlasSource and src.texture != null:
				_tex_cache[i] = src.texture
	queue_redraw()


func _draw() -> void:
	if level == null:
		return
	var cs := cell_size
	var ts: TileSet = level.tileset_ref
	var has_art := ts != null and ts.get_source_count() > 0
	for layer in [LevelData.LAYER_BACKGROUND, LevelData.LAYER_FOREGROUND, LevelData.LAYER_GEOMETRY]:
		for y in range(level.height):
			for x in range(level.width):
				var id := level.get_tile(layer, x, y)
				if id <= 0:
					continue
				var rect := Rect2(x * cs, y * cs, cs, cs)
				if has_art:
					var region := TileAtlas.tile_region(ts, id)
					var tex: Texture2D = _tex_cache.get(TileAtlas.source_index_for_id(id))
					if tex != null:
						draw_texture_rect_region(tex, rect, region)
				else:
					draw_rect(rect, EditorColors.tile_color(id), true)
