extends GutTest

class FakePlayer extends Node:
	var score: int = 0
	var ammo: int = 0
	var max_ammo: int = 5
	func _ready() -> void:
		add_to_group("player")
	func add_score(a: int) -> void:
		score += a
	func add_ammo(a: int) -> void:
		ammo = clampi(ammo + a, 0, max_ammo)


func test_lollipop_awards_score():
	var c: Lollipop = add_child_autofree(load("res://src/runtime/entities/lollipop.tscn").instantiate())
	assert_eq(c.score_value, 100)
	var p := FakePlayer.new()
	add_child_autofree(p)
	c._on_body_entered(p)
	assert_eq(p.score, 100)
	assert_true(c.is_queued_for_deletion())


## Each score pickup awards its declared value on contact.
func test_score_pickups_award_expected_values():
	var cases := [
		["keen1.soda", 200],
		["keen1.pizza", 500],
		["keen1.book", 1000],
		["keen1.teddy", 5000],
	]
	for entry: Variant in EntityRegistry.get_palette_entries():
		var tid: String = entry["type_id"]
		var idx := cases.find_custom(func(c) -> bool: return c[0] == tid)
		if idx < 0:
			continue
		var expected: int = cases[idx][1]
		var node := add_child_autofree(EntityRegistry.instantiate(tid, Vector2.ZERO)) as Collectible
		assert_not_null(node, "%s instantiates" % tid)
		assert_eq(node.score_value, expected, "%s score_value" % tid)
		var p := FakePlayer.new()
		add_child_autofree(p)
		node._on_body_entered(p)
		assert_eq(p.score, expected, "%s awards %d" % [tid, expected])
		assert_true(node.is_queued_for_deletion(), "%s frees after use" % tid)


func test_raygun_grants_ammo():
	var r: AmmoPickup = add_child_autofree(load("res://src/runtime/entities/ammo_pickup.tscn").instantiate())
	assert_eq(r.ammo_value, 5)
	var p := FakePlayer.new()
	p.ammo = 1
	add_child_autofree(p)
	r._on_body_entered(p)
	assert_eq(p.ammo, 5, "ammo granted and clamped to max")
	assert_true(r.is_queued_for_deletion(), "pickup frees after use")


func after_each():
	GameManager.register_episodes()
