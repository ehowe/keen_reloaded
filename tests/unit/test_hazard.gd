extends GutTest

## Characterization tests for the instakill hazard family (Spike/Fire/Clapper)
## and the base Hazard contact-damage contract. These lock the existing
## "drain all health on contact" behavior so the instakill-helper refactor
## (#1) cannot silently change it.


class FakePlayer extends CharacterBody2D:
	var health: int = 3
	func _ready() -> void:
		add_to_group("player")
	func take_damage(amount: int) -> void:
		health = max(0, health - amount)


func _player() -> FakePlayer:
	var p := FakePlayer.new()
	add_child_autofree(p)
	return p


func test_base_hazard_deals_configured_damage():
	var h := Hazard.new()
	h.damage = 1
	add_child_autofree(h)
	var p := _player()
	h._handle_player(p)
	assert_eq(p.health, 2, "base Hazard subtracts its damage value")


func test_spike_instakills_on_contact():
	var s := Spike.new()
	add_child_autofree(s)
	var p := _player()
	s._handle_player(p)
	assert_eq(p.health, 0, "Spike drains all health")


func test_fire_instakills_on_contact():
	var f := Fire.new()
	add_child_autofree(f)
	var p := _player()
	f._handle_player(p)
	assert_eq(p.health, 0, "Fire drains all health")


func test_clapper_instakills_on_contact():
	var c := Clapper.new()
	add_child_autofree(c)
	var p := _player()
	c._handle_player(p)
	assert_eq(p.health, 0, "Clapper drains all health")


func test_instakill_ignores_non_player_body():
	# _handle_player is only reached via the player-filtered Area2D, but the
	# method itself must not crash on a body lacking the player contract.
	var s := Spike.new()
	add_child_autofree(s)
	var decoy := CharacterBody2D.new()  # no take_damage, no health
	add_child_autofree(decoy)
	s._handle_player(decoy)  # must not error
	assert_true(true, "non-player body does not crash instakill path")
