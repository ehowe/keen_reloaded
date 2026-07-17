class_name SpriteUtil
extends RefCounted
## Shared sprite helpers extracted from duplicated statics in player.gd and
## enemy.gd. Pure functions over AnimatedSprite2D / SpriteFrames.


## Frame height of an AnimatedSprite2D's first animation, first frame. Prefers
## the AtlasTexture region (the in-game art packing) and falls back to the raw
## texture height. Returns 0.0 when the sprite has no frames or animations.
static func frame_height(spr: AnimatedSprite2D) -> float:
	if spr.sprite_frames == null:
		return 0.0
	var anims := spr.sprite_frames.get_animation_names()
	if anims.is_empty():
		return 0.0
	var tex := spr.sprite_frames.get_frame_texture(anims[0], 0)
	if tex == null:
		return 0.0
	if tex is AtlasTexture:
		return (tex as AtlasTexture).region.size.y
	return float(tex.get_height())


## Vertical offset that lifts a sprite of `frame_h` so its bottom edge sits on
## the foot line (`foot_y` below origin). Shared by player & enemy feet
## alignment so the offset formula lives in one place.
static func foot_offset_y(frame_h: float, foot_y: float) -> float:
	if frame_h <= 0.0:
		return 0.0
	return -(frame_h * 0.5 - foot_y)
