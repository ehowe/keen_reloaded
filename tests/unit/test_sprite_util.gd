extends GutTest

## Unit tests for SpriteUtil (extracted from byte-identical _frame_height
## statics in player.gd and enemy.gd).


func _make_anim() -> AnimatedSprite2D:
	# SpriteFrames ships with an empty "default" animation; reuse it.
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = SpriteFrames.new()
	return spr


func test_frame_height_null_frames_returns_zero():
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = null
	assert_eq(SpriteUtil.frame_height(spr), 0.0, "no SpriteFrames -> 0")


func test_frame_height_no_animations_returns_zero():
	var spr := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")  # truly empty
	spr.sprite_frames = frames
	assert_eq(SpriteUtil.frame_height(spr), 0.0, "no animations -> 0")


func test_frame_height_animation_with_no_frames_returns_zero():
	var spr := _make_anim()  # "default" exists but has zero frames
	assert_eq(SpriteUtil.frame_height(spr), 0.0, "null frame texture -> 0")


func test_frame_height_uses_atlas_region_for_atlas_texture():
	var spr := _make_anim()
	var at := AtlasTexture.new()
	at.region = Rect2(0.0, 0.0, 48.0, 64.0)
	spr.sprite_frames.add_frame(&"default", at)
	assert_eq(SpriteUtil.frame_height(spr), 64.0, "AtlasTexture height = region.size.y")


func test_frame_height_uses_texture_height_for_plain_texture():
	var spr := _make_anim()
	var img := Image.create(10, 24, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	spr.sprite_frames.add_frame(&"default", tex)
	assert_eq(SpriteUtil.frame_height(spr), 24.0, "plain texture height = get_height()")
