extends GutTest


class FakePlayer extends Node:
	var _cards: Dictionary = {}
	func _ready() -> void:
		add_to_group("player")
	func add_keycard(color: String) -> void:
		_cards[color] = int(_cards.get(color, 0)) + 1
	func has_keycard(color: String) -> bool:
		return int(_cards.get(color, 0)) > 0
	func consume_keycard(color: String) -> bool:
		if not has_keycard(color):
			return false
		_cards[color] = int(_cards[color]) - 1
		return true


func after_each():
	GameManager.register_episodes()


func _new_door(props: Dictionary = {}) -> Door:
	var d: Door = add_child_autofree(load("res://src/runtime/entities/Door.tscn").instantiate())
	d.setup("keen1.door", props)
	return d


func _new_player_with(colors: Array) -> FakePlayer:
	var p := FakePlayer.new()
	add_child_autofree(p)
	for c in colors:
		p.add_keycard(c)
	return p


func test_door_registered_as_special():
	var entry: Dictionary = EntityRegistry.get_entry("keen1.door")
	assert_eq(entry.get("category", ""), "special")
	var kinds: Array = entry.get("map_kinds", [])
	assert_true(kinds.has(LevelData.MapKind.LEVEL), "LEVEL-only")
	assert_false(kinds.has(LevelData.MapKind.OVERWORLD), "not on OVERWORLD")


func test_door_variant_schema_has_four_colors():
	var schema := EntityRegistry.get_properties_schema("keen1.door")
	assert_eq(schema.size(), 1)
	assert_eq(String(schema[0].get("name")), "variant")
	assert_eq(String(schema[0].get("type")), "enum")
	assert_eq(String(schema[0].get("default")), "red")
	assert_eq(schema[0].get("options"), ["red", "blue", "yellow", "green"])


func test_door_collision_layer_is_tiles_bit():
	# Player.collision_mask = 4 (tiles bit) — Door must be on layer 4 so its
	# CollisionPolygon2D actually blocks the player. Default items bit (8) would
	# let the player walk through.
	var d := _new_door()
	assert_eq(d.collision_layer, 4, "Door on tiles layer so it blocks the player")


func test_door_locked_when_player_has_no_keycard():
	var d := _new_door({"variant": "red"})
	var p := _new_player_with([])
	d._handle_player(p)
	assert_false(d.get("_opened"), "door stays closed without keycard")
	# CollisionPolygon2D still active.
	assert_false(d.get_node("CollisionPolygon2D").disabled, "collision still solid")
	# Player keeps 0 keycards (no consume attempted).
	assert_false(p.has_keycard("red"), "no keycard consumed")


func test_door_opens_with_matching_keycard():
	var d := _new_door({"variant": "red"})
	var p := _new_player_with(["red"])
	d._handle_player(p)
	assert_true(d.get("_opened"), "_opened flag set")
	assert_false(p.has_keycard("red"), "the one red keycard was consumed")


func test_door_non_matching_color_stays_locked():
	var d := _new_door({"variant": "red"})
	var p := _new_player_with(["blue"])
	d._handle_player(p)
	assert_false(d.get("_opened"), "blue keycard does not open red door")
	assert_true(p.has_keycard("blue"), "blue keycard not consumed")
	assert_false(d.get_node("CollisionPolygon2D").disabled, "collision still solid")


func test_door_collision_disables_when_animation_starts():
	# Player must be able to walk through the door WHILE the Retract animation
	# is playing, not after it finishes. So _handle_player must disable the
	# solid CollisionPolygon2D + contact Area2D immediately when the animation
	# starts — without waiting for animation_finished.
	# Uses set_deferred because body_entered is a physics-signal callback;
	# the deferred call applies at end of frame, so we await one frame before
	# asserting.
	var d := _new_door({"variant": "red"})
	var p := _new_player_with(["red"])
	d._handle_player(p)
	await get_tree().process_frame
	assert_true(d.get_node("CollisionPolygon2D").disabled,
		"CollisionPolygon2D disabled immediately on contact (not deferred to anim end)")
	var area := d.get_node_or_null("Area2D") as Area2D
	assert_not_null(area, "contact Area2D present")
	assert_false(area.monitoring, "Area2D monitoring off immediately on contact")


func test_door_handle_player_is_idempotent_after_open():
	var d := _new_door({"variant": "red"})
	# Give the player two reds so the second call COULD consume if it weren't
	# guarded by _opened.
	var p := _new_player_with(["red", "red"])
	d._handle_player(p)
	assert_eq(int(p._cards.get("red", 0)), 1, "first contact consumed one")
	# Second contact must be a no-op (door already opened).
	d._handle_player(p)
	assert_eq(int(p._cards.get("red", 0)), 1, "second contact did not consume")
	assert_true(d.get("_opened"), "still opened")


func test_door_variant_property_bound_from_schema_default():
	var d := _new_door()  # no props → schema default "red"
	assert_eq(d.variant, "red", "default variant applied via setup()")


func test_door_variant_property_bound_from_props():
	var d := _new_door({"variant": "green"})
	assert_eq(d.variant, "green")


func test_door_variant_selects_matching_sprite():
	var d := _new_door({"variant": "yellow"}) as Door
	# Door sprites live at DoorMask/Visual/{Red,Blue,Yellow,Green}.
	assert_true(d.get_node("DoorMask/Visual/Yellow").visible, "Yellow visible")
	assert_false(d.get_node("DoorMask/Visual/Red").visible, "Red hidden")
	assert_false(d.get_node("DoorMask/Visual/Blue").visible, "Blue hidden")
	assert_false(d.get_node("DoorMask/Visual/Green").visible, "Green hidden")


func test_door_contact_area_extends_beyond_solid_collision():
	# Bug repro: the door's CollisionPolygon2D is solid and ~1 tile wide. The
	# contact Area2D sits at the door origin. If the Area2D's shape matches the
	# door's collision width, the player gets stopped at the tile boundary and
	# their body NEVER enters the Area2D's region — body_entered never fires,
	# the door never opens. The Area2D shape must extend BEYOND the solid
	# collision horizontally so the player enters the detection zone first.
	var d := _new_door()
	var area := d.get_node_or_null("Area2D") as Area2D
	assert_not_null(area, "contact Area2D present")
	var col := area.get_child(0) as CollisionShape2D
	assert_not_null(col, "Area2D has a CollisionShape2D")
	var rect := col.shape as RectangleShape2D
	assert_not_null(rect, "Area2D shape is RectangleShape2D")
	# Door's collision polygon is ~TILE wide (64px). Contact shape must be
	# STRICTLY WIDER so the player can enter the detection zone before being
	# blocked by the solid collision.
	assert_gt(rect.size.x, Constants.TILE,
		"contact Area2D shape wider than 1 tile (got %f)" % rect.size.x)
