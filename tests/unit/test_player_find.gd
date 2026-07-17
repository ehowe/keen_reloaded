extends GutTest

## Unit tests for Player.find (consolidates the scattered
## get_first_node_in_group("player") + null-tree-guard boilerplate).


func test_find_returns_null_for_null_tree():
	assert_eq(Player.find(null), null, "null tree -> null")


func test_find_returns_null_when_no_player_in_tree():
	# Sweep any leaked player nodes so the assertion is deterministic.
	for n in get_tree().get_nodes_in_group("player"):
		n.remove_from_group("player")
	assert_eq(Player.find(get_tree()), null, "no player group member -> null")


func test_find_returns_the_player_group_node():
	var p := CharacterBody2D.new()
	p.add_to_group("player")
	add_child_autofree(p)
	var found := Player.find(get_tree())
	assert_not_null(found, "find returns the group member")
	assert_true(found.is_in_group("player"), "found node is in the player group")
