class_name EditorColors
extends RefCounted
## Maps tile ids to display colors for the editor canvas/palette. No art assets
## required — real TileSets arrive in a later plan.

const EMPTY := Color(0, 0, 0, 0)

static func tile_color(tile_id: int) -> Color:
	if tile_id <= 0:
		return EMPTY
	# golden-ratio hue stride => stable, well-spread distinct hues
	var h := fmod(float(tile_id) * 0.61803398875, 1.0)
	return Color.from_hsv(h, 0.55, 0.85, 1.0)

static func layer_tint(layer: String) -> Color:
	match layer:
		LevelData.LAYER_GEOMETRY:
			return Color(1, 1, 1, 1)
		LevelData.LAYER_FOREGROUND:
			return Color(1, 1, 1, 0.9)
		LevelData.LAYER_BACKGROUND:
			return Color(1, 1, 1, 0.6)
		LevelData.LAYER_FRONT:
			return Color(1, 0.6, 0.8, 0.95)
	return Color(1, 1, 1, 1)
