class_name ProceduralTileSet
extends RefCounted
## Builds a TileSet procedurally with NO art files. Each tile id 1..max_id maps
## to a solid-color cell (reusing the Plan 2 EditorColors palette) and, when
## with_collision is true, a full-cell collision rectangle. Used by LevelRuntime
## to render + collide the geometry layer (solid) and the fg/bg layers (decor).
##
## NOTE (Godot 4.7): set_collision_polygon_points() uses a hardcoded polygon
## index 0. Do NOT call get_collision_polygon_count() — it hangs the headless
## engine in 4.7.

# Collision bit values mirror project.godot [layer_names]:
# layer_1 "player" = bit 1, layer_3 "tiles" = bit 4.
const COLLISION_LAYER_TILES := 4
const COLLISION_MASK_PLAYER := 1

## Build a TileSet with `max_id` colored tiles (ids 1..max_id).
static func build(max_id: int, tile_size: int, with_collision: bool) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)
	if max_id <= 0:
		return ts

	# Atlas image: one row of `max_id` colored cells.
	var img := Image.create(max_id * tile_size, tile_size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for id in range(1, max_id + 1):
		_paint_cell(img, id, tile_size, EditorColors.tile_color(id))

	var tex := ImageTexture.create_from_image(img)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(tile_size, tile_size)
	ts.add_source(src)
	for id in range(1, max_id + 1):
		src.create_tile(Vector2i(id - 1, 0))

	if with_collision:
		ts.add_physics_layer()
		var layer: int = ts.get_physics_layers_count() - 1
		ts.set_physics_layer_collision_layer(layer, COLLISION_LAYER_TILES)
		ts.set_physics_layer_collision_mask(layer, COLLISION_MASK_PLAYER)
		var poly := PackedVector2Array([
			Vector2(0, 0),
			Vector2(tile_size, 0),
			Vector2(tile_size, tile_size),
			Vector2(0, tile_size),
		])
		for id in range(1, max_id + 1):
			var td: TileData = src.get_tile_data(Vector2i(id - 1, 0), 0)
			td.add_collision_polygon(layer)
			td.set_collision_polygon_points(layer, 0, poly)
	return ts


static func _paint_cell(img: Image, id: int, tile_size: int, color: Color) -> void:
	var origin_x := (id - 1) * tile_size
	for px in range(tile_size):
		for py in range(tile_size):
			img.set_pixel(origin_x + px, py, color)
