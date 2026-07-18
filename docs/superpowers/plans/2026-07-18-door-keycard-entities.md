# Door + Keycard Entities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a color-locked Door entity (4 variants) gated by per-level Keycard pickups (4 variants), with keycard state isolated to the current level via the Player instance.

**Architecture:** Keycards live on `Player.keycards: Dictionary` (auto-cleared because `LevelRuntime` frees and rebuilds the Player each level). `Door` extends `Entity`, sits on the tiles collision bit (so its `CollisionPolygon2D` blocks the player), and on matching-keycard contact plays the existing `Retract` animation then disables both `CollisionPolygon2D` and its contact Area2D. `Keycard` extends `Entity`, grants one count of its `variant` color to the player, frees itself. Both use the existing `EntityVariant` helper for enum-driven sprite selection.

**Tech Stack:** Godot 4.7, GDScript, GUT (Godot Unit Test) for testing.

**Spec:** `docs/superpowers/specs/2026-07-18-door-keycard-entities-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `src/runtime/player/player.gd` | Modify | Add `keycards` Dictionary + `add_keycard`/`has_keycard`/`consume_keycard` methods |
| `src/runtime/entities/entity.gd` | Modify | Refactor `_build_contact` to extract `_build_contact_area()` helper (enables Door to skip the ColorRect visual fallback) |
| `src/runtime/entities/keycard.gd` | Create | `Keycard` script: pickup that grants color count to player |
| `src/runtime/entities/Keycard.tscn` | Create | Scene with 4 variant Sprite2D children (Red/Blue/Yellow/Green) from `Doors and Keycards.png` row 128–191 |
| `src/runtime/entities/door.gd` | Create | `Door` script: solid until matching keycard, plays Retract, disables collision after anim |
| `src/runtime/entities/Door.tscn` | Modify | Attach `door.gd` at the root `CharacterBody2D` |
| `src/episodes/keen1/episode.gd` | Modify | Register `keen1.door` (special) and `keen1.keycard` (item) with `variant` enum schema |
| `tests/unit/test_player_keycards.gd` | Create | Tests for `add_keycard`/`has_keycard`/`consume_keycard` |
| `tests/unit/test_keycard_pickup.gd` | Create | Tests for Keycard contact → player.add_keycard + queue_free |
| `tests/unit/test_door.gd` | Create | Tests for Door lock/open/consume/lifecycle |

---

## Conventions

- **Tabs** for GDScript indentation (matches existing code).
- **Run all tests:** `./tests/run_all.sh` (must pass before commit).
- **Run a single test file:** `GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot "$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit -gdisable_colors -gselect=<test_filename_without_ext>`
- **GDScript convention:** instance/class variables use `snake_case`, classes use `PascalCase`, constants use `SCREAMING_SNAKE_CASE`.

---

## Task 1: Player keycard state (TDD)

Add per-level keycard storage to `Player`. No serialization — `Player` is rebuilt per level so the Dictionary naturally resets.

**Files:**
- Create: `tests/unit/test_player_keycards.gd`
- Modify: `src/runtime/player/player.gd`

- [ ] **Step 1.1: Write failing tests**

Create `tests/unit/test_player_keycards.gd`:

```gdscript
extends GutTest


func _new_player() -> Player:
	return add_child_autofree(load("res://src/runtime/player/player.tscn").instantiate())


func test_keycards_empty_by_default():
	var p := _new_player()
	assert_eq(p.keycards, {}, "fresh Player starts with no keycards")


func test_has_keycard_false_before_add():
	var p := _new_player()
	assert_false(p.has_keycard("red"), "no red keycard before add")


func test_add_keycard_grants_color():
	var p := _new_player()
	p.add_keycard("red")
	assert_true(p.has_keycard("red"), "red keycard granted")


func test_add_keycard_accumulates_count():
	var p := _new_player()
	p.add_keycard("blue")
	p.add_keycard("blue")
	p.add_keycard("blue")
	# has_keycard only tells us count > 0; consume to verify count.
	assert_true(p.consume_keycard("blue"), "first consume ok")
	assert_true(p.consume_keycard("blue"), "second consume ok")
	assert_true(p.consume_keycard("blue"), "third consume ok")
	assert_false(p.consume_keycard("blue"), "fourth consume fails (empty)")


func test_consume_returns_false_when_empty():
	var p := _new_player()
	assert_false(p.consume_keycard("yellow"), "consume on empty returns false")


func test_consume_decrements_count():
	var p := _new_player()
	p.add_keycard("green")
	p.add_keycard("green")
	assert_true(p.consume_keycard("green"), "consume when count=2")
	assert_true(p.has_keycard("green"), "still has one green after first consume")
	assert_true(p.consume_keycard("green"), "consume when count=1")
	assert_false(p.has_keycard("green"), "no green left after second consume")
	assert_false(p.consume_keycard("green"), "third consume fails")


func test_colors_are_independent():
	var p := _new_player()
	p.add_keycard("red")
	p.add_keycard("blue")
	assert_true(p.has_keycard("red"), "red present")
	assert_true(p.has_keycard("blue"), "blue present")
	assert_false(p.has_keycard("yellow"), "yellow absent")
	p.consume_keycard("red")
	assert_false(p.has_keycard("red"), "red drained")
	assert_true(p.has_keycard("blue"), "blue unaffected by red consume")


func test_each_player_instance_starts_empty():
	# Per-level isolation: two fresh Player instances must NOT share keycard state.
	var p1 := _new_player()
	p1.add_keycard("red")
	var p2 := _new_player()
	assert_false(p2.has_keycard("red"), "second Player instance is isolated")
```

- [ ] **Step 1.2: Run tests to verify they fail**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_player_keycards
```

Expected: **FAIL** — errors like `Invalid call. Nonexistent function 'add_keycard' on base 'Player'` and `Invalid get index 'keycards'`.

- [ ] **Step 1.3: Add `keycards` Dictionary to Player**

In `src/runtime/player/player.gd`, locate the existing instance-variable block (lines 55–75):

```gdscript
var score: int = 0
var health: int = 3
var ammo: int = 0
```

Add `keycards` immediately after `ammo`:

```gdscript
var score: int = 0
var health: int = 3
var ammo: int = 0
## Per-level keycard counts. color (String) -> count (int). Auto-cleared: the
## Player node is freed + rebuilt on every level swap, so this Dictionary never
## crosses levels and never reaches save/load.
var keycards: Dictionary = {}
```

- [ ] **Step 1.4: Add keycard API methods**

In `src/runtime/player/player.gd`, find the `add_ammo` method (around line 295):

```gdscript
func add_ammo(amount: int) -> void:
	_set_ammo(clampi(ammo + amount, 0, max_ammo))
```

Insert immediately AFTER `add_ammo`:

```gdscript
## Apply a horizontal bounce impulse (e.g. from a yorp bump). Overrides Keen's
## horizontal input while active, decaying to 0 so he slides back smoothly.
func apply_bounce(vx: float) -> void:
	_bounce_vx = vx
```

Wait — locate `apply_bounce` first. The new keycard methods go after `add_ammo` and before `apply_bounce`. Insert this block:

```gdscript
## True if the player holds at least one keycard of `color`.
func has_keycard(color: String) -> bool:
	return int(keycards.get(color, 0)) > 0


## Grant one keycard of `color`. Adds to the existing count if any.
func add_keycard(color: String) -> void:
	keycards[color] = int(keycards.get(color, 0)) + 1


## Decrement the `color` count by 1 (floors at 0). Returns true if a keycard
## was actually consumed (player had at least one); false if the player had none.
func consume_keycard(color: String) -> bool:
	if not has_keycard(color):
		return false
	keycards[color] = int(keycards[color]) - 1
	return true
```

- [ ] **Step 1.5: Run tests to verify they pass**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_player_keycards
```

Expected: **PASS** — all 8 tests green.

- [ ] **Step 1.6: Verify existing player tests still pass**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_player
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_player_shoot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_player_overworld
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_player_find
```

Expected: **PASS** — no regressions.

- [ ] **Step 1.7: Commit**

```bash
git add src/runtime/player/player.gd tests/unit/test_player_keycards.gd
git commit -m "feat(player): add per-level keycard state

Adds keycards Dictionary + add_keycard/has_keycard/consume_keycard API.
Auto-cleared across levels: Player node is freed + rebuilt per level."
```

---

## Task 2: Keycard entity (TDD)

Build the `Keycard` pickup. Pattern mirrors `PogoStick` (contact → grant → free) but writes to `Player.keycards` instead of the global `Inventory`.

**Files:**
- Create: `tests/unit/test_keycard_pickup.gd`
- Create: `src/runtime/entities/keycard.gd`
- Create: `src/runtime/entities/Keycard.tscn`
- Modify: `src/episodes/keen1/episode.gd`

- [ ] **Step 2.1: Write failing tests**

Create `tests/unit/test_keycard_pickup.gd`:

```gdscript
extends GutTest


class FakePlayer extends Node:
	var granted: Dictionary = {}  # color -> count
	func _ready() -> void:
		add_to_group("player")
	func add_keycard(color: String) -> void:
		granted[color] = int(granted.get(color, 0)) + 1
	func has_keycard(color: String) -> bool:
		return int(granted.get(color, 0)) > 0
	func consume_keycard(color: String) -> bool:
		if not has_keycard(color):
			return false
		granted[color] = int(granted[color]) - 1
		return true


func after_each():
	# Re-register the autoload's default roster so a clear() inside a test
	# doesn't leak an empty registry into later test scripts.
	GameManager.register_episodes()


func test_keycard_grants_matching_color():
	var kc: Keycard = add_child_autofree(load("res://src/runtime/entities/Keycard.tscn").instantiate())
	kc.variant = "blue"
	var p := FakePlayer.new()
	add_child_autofree(p)
	kc._on_body_entered(p)
	assert_true(p.has_keycard("blue"), "blue keycard granted")
	assert_false(p.has_keycard("red"), "only blue granted")


func test_keycard_pickup_frees_after_contact():
	var kc: Keycard = add_child_autofree(load("res://src/runtime/entities/Keycard.tscn").instantiate())
	kc.variant = "red"
	var p := FakePlayer.new()
	add_child_autofree(p)
	kc._on_body_entered(p)
	assert_true(kc.is_queued_for_deletion(), "keycard queue_frees after pickup")


func test_keycard_registered_as_level_item():
	var entry: Dictionary = EntityRegistry.get_entry("keen1.keycard")
	assert_eq(entry.get("category", ""), "item")
	var kinds: Array = entry.get("map_kinds", [])
	assert_true(kinds.has(LevelData.MapKind.LEVEL), "available on LEVEL maps")
	assert_false(kinds.has(LevelData.MapKind.OVERWORLD), "not available on OVERWORLD")


func test_keycar_variant_schema_has_four_colors():
	var schema := EntityRegistry.get_properties_schema("keen1.keycard")
	assert_eq(schema.size(), 1, "one property (variant)")
	assert_eq(String(schema[0].get("name")), "variant")
	assert_eq(String(schema[0].get("type")), "enum")
	assert_eq(String(schema[0].get("default")), "red")
	assert_eq(schema[0].get("options"), ["red", "blue", "yellow", "green"])


func test_keycard_instantiates_as_entity():
	var node := add_child_autofree(EntityRegistry.instantiate("keen1.keycard", Vector2.ZERO)) as Node2D
	assert_not_null(node)
	assert_true(node is Keycard)
	assert_eq(node.type_id, "keen1.keycard")
	assert_true(node.is_in_group("entity"))


func test_keycard_variant_property_propagates_from_props():
	var node := add_child_autofree(EntityRegistry.instantiate("keen1.keycard", Vector2.ZERO, {"variant": "yellow"})) as Keycard
	assert_eq(node.variant, "yellow", "variant property bound from props")


func test_keycard_variant_selects_matching_sprite():
	# Default variant = red; the Red sprite should be the only visible one
	# among the four color siblings under Visual.
	var kc: Keycard = add_child_autofree(EntityRegistry.instantiate("keen1.keycard", Vector2.ZERO)) as Keycard
	assert_true(kc.get_node("Visual/Red").visible, "Red visible for default variant")
	assert_false(kc.get_node("Visual/Blue").visible, "Blue hidden")
	assert_false(kc.get_node("Visual/Yellow").visible, "Yellow hidden")
	assert_false(kc.get_node("Visual/Green").visible, "Green hidden")
```

- [ ] **Step 2.2: Run tests to verify they fail**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_keycard_pickup
```

Expected: **FAIL** — `Keycard.tscn` does not exist; `keen1.keycard` not registered; class `Keycard` unknown.

- [ ] **Step 2.3: Create the Keycard script**

Create `src/runtime/entities/keycard.gd`:

```gdscript
class_name Keycard
extends Entity
## Color keycard pickup. Grants one count of its `variant` color to the player
## on contact, plays the pickup SFX, then frees itself. Variant sprite is
## selected via EntityVariant (mirrors the Door's variant system).


var variant: String = "red"


func setup(p_type_id: String, p_props: Dictionary) -> void:
	super(p_type_id, p_props)
	EntityVariant.apply(type_id, properties, self)


func _handle_player(player: Node) -> void:
	if player.has_method("add_keycard"):
		player.add_keycard(variant)
	AudioManager.play_sfx("pickup_score")
	queue_free()
```

- [ ] **Step 2.4: Create the Keycard scene**

Create `src/runtime/entities/Keycard.tscn`:

```
[gd_scene load_steps=6 format=3 uid="uid://bk2ycard00000"]

[ext_resource type="Script" path="res://src/runtime/entities/keycard.gd" id="1_keycard"]
[ext_resource type="Texture2D" uid="uid://dwytk2047oo55" path="res://assets/tilesets/Doors and Keycards.png" id="2_atlas"]

[sub_resource type="AtlasTexture" id="AtlasTexture_red"]
atlas = ExtResource("2_atlas")
region = Rect2(0, 128, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_blue"]
atlas = ExtResource("2_atlas")
region = Rect2(64, 128, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_yellow"]
atlas = ExtResource("2_atlas")
region = Rect2(128, 128, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_green"]
atlas = ExtResource("2_atlas")
region = Rect2(192, 128, 64, 64)

[node name="Keycard" type="CharacterBody2D"]
script = ExtResource("1_keycard")

[node name="Visual" type="Node2D" parent="."]

[node name="Red" type="Sprite2D" parent="Visual"]
texture = SubResource("AtlasTexture_red")

[node name="Blue" type="Sprite2D" parent="Visual"]
visible = false
texture = SubResource("AtlasTexture_blue")

[node name="Yellow" type="Sprite2D" parent="Visual"]
visible = false
texture = SubResource("AtlasTexture_yellow")

[node name="Green" type="Sprite2D" parent="Visual"]
visible = false
texture = SubResource("AtlasTexture_green")
```

**Note on the uid:** `uid="uid://bk2ycard00000"` is a placeholder string. After saving the file, run `make import` (or `godot --headless --import --quit`) once to let Godot assign a real uid; the placeholder string is valid syntactically and Godot will replace it on import.

**Note on atlas regions:** `Doors and Keycards.png` is 256×192. Doors occupy y=0–127 (64×128 cells); keycards occupy y=128–191 (64×64 cells). The four keycard cells are at x=0, 64, 128, 192 along the row y=128. If a manual visual check in the editor shows the regions are off (e.g. wrong color shown), open `assets/tilesets/Doors and Keycards.aseprite` to confirm cell layout and adjust the Rect2 values accordingly.

- [ ] **Step 2.5: Register the Keycard in the episode**

In `src/episodes/keen1/episode.gd`, locate the existing preload block (around line 28, where `fire` is preloaded):

```gdscript
	var fire := preload("res://src/runtime/entities/fire.tscn")
```

Add a new preload immediately after the existing preloads (after the `message` preload near the end of the preload block, around line 27):

```gdscript
	var keycard := preload("res://src/runtime/entities/Keycard.tscn")
```

Then locate the `message` registration block at the end of `register_entities()`:

```gdscript
	var message := preload("res://src/runtime/entities/message.tscn")
	registry.register("keen1.message", registry.CATEGORY_SPECIAL, "Message Sign",
		[
			{name = "target_level_id", default = "", type = "level_id"},
			{name = "repeat", default = false, type = "bool"},
		],
		message)
```

Append after it:

```gdscript
	var keycard := preload("res://src/runtime/entities/Keycard.tscn")
	registry.register("keen1.keycard", registry.CATEGORY_ITEM, "Keycard",
		[{name = "variant", default = "red", type = "enum",
			options = ["red", "blue", "yellow", "green"]}],
		keycard)
```

(Move the `var keycard := preload(...)` line up to the preload block if you prefer them grouped; either works since GDScript allows local var declarations anywhere in a function before use.)

- [ ] **Step 2.6: Import the new scene so Godot sees it**

```bash
make import
```

Expected: completes without errors. The Keycard.tscn uid is assigned/normalized.

- [ ] **Step 2.7: Run the keycard tests to verify they pass**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_keycard_pickup
```

Expected: **PASS** — all 7 tests green.

- [ ] **Step 2.8: Verify no regression in related suites**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_episode
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_entity_registry_instantiate
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_entity_variant
```

Expected: **PASS** — no regressions.

- [ ] **Step 2.9: Commit**

```bash
git add src/runtime/entities/keycard.gd src/runtime/entities/Keycard.tscn \
        src/runtime/entities/Keycard.tscn.uid \
        src/episodes/keen1/episode.gd tests/unit/test_keycard_pickup.gd
git commit -m "feat(entities): add Keycard pickup entity

Color-variant keycard (red/blue/yellow/green) grants one count of its
variant to Player.keycards on contact, then frees. Registered as
keen1.keycard under CATEGORY_ITEM, LEVEL-only."
```

---

## Task 3: Refactor `Entity._build_contact` (prep for Door)

The Door scene has no direct `"Visual"` child (its sprites live at `DoorMask/Visual`), so `Entity._build_contact`'s ColorRect fallback would draw a stray rectangle over the door. Extract the Area2D construction into a reusable `_build_contact_area()` helper so Door can skip the fallback without duplicating code.

**Files:**
- Modify: `src/runtime/entities/entity.gd`

- [ ] **Step 3.1: Read the current `_build_contact` for reference**

`src/runtime/entities/entity.gd:38-58` currently:

```gdscript
func _build_contact() -> void:
	_area = Area2D.new()
	_area.name = "Area2D"
	_area.monitoring = true
	_area.collision_layer = 0
	_area.collision_mask = 1  # player bit
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	shape.shape = rect
	_area.add_child(shape)
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)

	if not has_node("Visual"):
		var vis := ColorRect.new()
		vis.name = "Visual"
		vis.size = Vector2(TILE, TILE)
		vis.position = Vector2(-TILE / 2.0, -TILE / 2.0)
		vis.color = _color()
		add_child(vis)
```

- [ ] **Step 3.2: Replace `_build_contact` with the refactored version**

In `src/runtime/entities/entity.gd`, replace the entire `_build_contact` function (lines 38–58) with:

```gdscript
func _build_contact() -> void:
	_area = _build_contact_area()
	add_child(_area)
	if not has_node("Visual"):
		var vis := ColorRect.new()
		vis.name = "Visual"
		vis.size = Vector2(TILE, TILE)
		vis.position = Vector2(-TILE / 2.0, -TILE / 2.0)
		vis.color = _color()
		add_child(vis)


## Build the player-contact Area2D (mask = player bit, 1-tile rectangle shape,
## wired to _on_body_entered). Factored out so subclasses with their own visual
## tree (e.g. Door, whose sprites live at DoorMask/Visual) can build the sensor
## without triggering the ColorRect fallback in _build_contact.
func _build_contact_area() -> Area2D:
	var area := Area2D.new()
	area.name = "Area2D"
	area.monitoring = true
	area.collision_layer = 0
	area.collision_mask = 1  # player bit
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	shape.shape = rect
	area.add_child(shape)
	area.body_entered.connect(_on_body_entered)
	return area
```

- [ ] **Step 3.3: Verify refactor is behavior-preserving**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_entity_registry_instantiate
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_hazard
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_pogo_pickup
```

Expected: **PASS** — refactor preserves existing behavior (the public `_build_contact` does exactly what it did before).

- [ ] **Step 3.4: Commit**

```bash
git add src/runtime/entities/entity.gd
git commit -m "refactor(entity): extract _build_contact_area helper

No behavior change. Enables entities with nested visual trees
(upcoming Door) to build the contact sensor without the ColorRect
visual fallback."
```

---

## Task 4: Door entity (TDD)

Build the `Door` script, attach it to the existing `Door.tscn`, register it. Door is solid (tiles bit), plays `Retract` on matching-keycard contact, disables collision after anim.

**Files:**
- Create: `tests/unit/test_door.gd`
- Create: `src/runtime/entities/door.gd`
- Modify: `src/runtime/entities/Door.tscn`
- Modify: `src/episodes/keen1/episode.gd`

- [ ] **Step 4.1: Write failing tests**

Create `tests/unit/test_door.gd`:

```gdscript
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


func test_door_collision_disables_after_retract_animation():
	var d := _new_door({"variant": "red"})
	var p := _new_player_with(["red"])
	d._handle_player(p)
	# Simulate AnimationPlayer.animation_finished firing for "Retract".
	d._on_retract_finished("Retract")
	assert_true(d.get_node("CollisionPolygon2D").disabled, "CollisionPolygon2D disabled after anim")
	# Contact Area2D also disabled so re-entry cannot refire.
	var area := d.get_node_or_null("Area2D") as Area2D
	assert_not_null(area, "contact Area2D present")
	assert_false(area.monitoring, "Area2D monitoring off after open")


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
```

- [ ] **Step 4.2: Run tests to verify they fail**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_door
```

Expected: **FAIL** — `Door.tscn` has no script attached; `keen1.door` not registered; `class Door` unknown; `_handle_player`/`_on_retract_finished`/`_opened` do not exist.

- [ ] **Step 4.3: Create the Door script**

Create `src/runtime/entities/door.gd`:

```gdscript
class_name Door
extends Entity
## Color-locked door. Solid (collision on the tiles bit) until the player
## carries a matching keycard; on contact the door consumes one keycard of its
## variant color, plays the "Retract" animation, then disables both its
## CollisionPolygon2D and contact Area2D so the door stays open and cannot
## refire. Variant sprite is selected via EntityVariant (Red/Blue/Yellow/Green).


var variant: String = "red"
var _opened: bool = false


func setup(p_type_id: String, p_props: Dictionary) -> void:
	super(p_type_id, p_props)
	EntityVariant.apply(type_id, properties, self)


func _ready() -> void:
	# Build only the contact Area2D — skip Entity's ColorRect visual fallback
	# (the door's sprites live at DoorMask/Visual, not as a direct child).
	_area = _build_contact_area()
	add_child(_area)
	# Door sits on the tiles layer (bit 3 = value 4) so its CollisionPolygon2D
	# actually blocks the player (player.collision_mask = 4). Default items bit
	# (8) would let the player walk through.
	collision_layer = 4
	collision_mask = 0


func _handle_player(player: Node) -> void:
	if _opened:
		return
	if not player.has_method("has_keycard") or not player.has_keycard(variant):
		return  # Locked — door stays solid, player bumped.
	_opened = true
	player.consume_keycard(variant)
	AudioManager.play_sfx("door_open")  # warns gracefully until asset exists
	var anim := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim == null:
		_disable_collision()
		return
	if not anim.has_animation("Retract"):
		_disable_collision()
		return
	anim.animation_finished.connect(_on_retract_finished)
	anim.play("Retract")


func _on_retract_finished(_anim_name: String) -> void:
	_disable_collision()


func _disable_collision() -> void:
	var poly := get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if poly != null:
		poly.disabled = true
	if _area != null:
		_area.monitoring = false
```

- [ ] **Step 4.4: Attach the script to the existing Door scene**

`src/runtime/entities/Door.tscn` line 1–3 currently:

```
[gd_scene format=3 uid="uid://c41lgnol20jpr"]

[ext_resource type="Texture2D" uid="uid://dwytk2047oo55" path="res://assets/tilesets/Doors and Keycards.png" id="1_jitga"]
```

Add `load_steps=3` to the gd_scene header (1 step for the texture, 1 for the script, plus the implicit base) and add a new ext_resource for the script. Update the root node to reference the script.

Replace lines 1–3 with:

```
[gd_scene load_steps=3 format=3 uid="uid://c41lgnol20jpr"]

[ext_resource type="Texture2D" uid="uid://dwytk2047oo55" path="res://assets/tilesets/Doors and Keycards.png" id="1_jitga"]
[ext_resource type="Script" path="res://src/runtime/entities/door.gd" id="2_door"]
```

Then find the root node definition (line 89):

```
[node name="Door" type="CharacterBody2D" unique_id=405096024]
```

Add the `script` assignment:

```
[node name="Door" type="CharacterBody2D" unique_id=405096024]
script = ExtResource("2_door")
```

- [ ] **Step 4.5: Register the Door in the episode**

In `src/episodes/keen1/episode.gd`, find the keycard registration added in Task 2:

```gdscript
	var keycard := preload("res://src/runtime/entities/Keycard.tscn")
	registry.register("keen1.keycard", registry.CATEGORY_ITEM, "Keycard",
		[{name = "variant", default = "red", type = "enum",
			options = ["red", "blue", "yellow", "green"]}],
		keycard)
```

Append immediately after:

```gdscript
	var door := preload("res://src/runtime/entities/Door.tscn")
	registry.register("keen1.door", registry.CATEGORY_SPECIAL, "Door",
		[{name = "variant", default = "red", type = "enum",
			options = ["red", "blue", "yellow", "green"]}],
		door)
```

- [ ] **Step 4.6: Re-import so Godot picks up the script attachment**

```bash
make import
```

Expected: completes without errors. The Door.tscn now references door.gd.

- [ ] **Step 4.7: Run door tests to verify they pass**

```bash
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_door
```

Expected: **PASS** — all 10 tests green.

If `test_door_variant_selects_matching_sprite` fails with "Yellow hidden", the sprite visibility check needs the `DoorMask/Visual/` prefix to exactly match what `EntityVariant` walks — confirm the sprite names (`Red`/`Blue`/`Yellow`/`Green`) match the case-insensitive substring match `EntityVariant._select` performs (it lowercases both sides, so case is not an issue, but the option `"yellow"` must be a substring of the node name `"Yellow"` lowercased = `"yellow"`, which it is).

- [ ] **Step 4.8: Commit**

```bash
git add src/runtime/entities/door.gd src/runtime/entities/Door.tscn \
        src/runtime/entities/Door.tscn.uid \
        src/episodes/keen1/episode.gd tests/unit/test_door.gd
git commit -m "feat(entities): add color-locked Door entity

Door (red/blue/yellow/green) is solid on tiles bit, plays Retract anim
on matching-keycard contact, disables CollisionPolygon2D + contact
Area2D on anim finish. One keycard per door. Registered as keen1.door
under CATEGORY_SPECIAL, LEVEL-only."
```

---

## Task 5: Full suite verification

Run the entire GUT suite to confirm no regressions across the project.

**Files:** None (verification only).

- [ ] **Step 5.1: Run the full test suite**

```bash
./tests/run_all.sh
```

Expected: **ALL TESTS PASS**. Note the final summary line; capture the pass/fail counts and confirm 0 failures.

- [ ] **Step 5.2: Confirm `keen_reloaded` still imports cleanly**

```bash
make import
```

Expected: exits 0, no errors, no new warnings beyond the expected `AudioManager: unknown sfx 'door_open'` warning (graceful).

- [ ] **Step 5.3: Manual editor check (optional but recommended)**

```bash
make edit
```

In the editor:
1. Open a test level (e.g. `assets/levels/keen1/level1.tres`).
2. Place a red Door + red Keycard from the palette.
3. Place a blue Door (no blue keycard) to verify it stays locked.
4. Run the scene (▶).
5. Confirm: red door blocks Keen; picking up the red keycard lets Keen walk into the red door, triggering the retract animation; after the animation, Keen can pass through; the blue door stays solid.
6. Exit + re-enter the level: all doors reset to locked, the keycard respawns.

If everything looks correct, no further action — implementation is complete.

---

## Self-Review

**1. Spec coverage:**

| Spec section | Task |
|---|---|
| §4 Player keycard state (Dictionary + add/has/consume) | Task 1 |
| §5.1 Door script (extends Entity, variant, _opened, _ready layer=4, _handle_player, _on_retract_finished, _disable_collision) | Task 4 |
| §5.2 Door scene script attach + skip ColorRect fallback | Task 3 (refactor) + Task 4 (attach) |
| §5.3 Idempotency (`_opened` guard) | Task 4 (test_door_handle_player_is_idempotent_after_open) |
| §5.4 Edge case: missing keycard method | Task 4 (`has_method` guard in _handle_player) |
| §6.1 Keycard script | Task 2 |
| §6.2 Keycard scene (4 variant sprites, keycard atlas row) | Task 2 |
| §6.3 Keycard pickup contract (extends Entity, play_sfx pickup_score) | Task 2 |
| §7 Episode registration (keen1.door special, keen1.keycard item, variant enum) | Task 2 + Task 4 |
| §8 Editor integration (no editor code changes; palette picks up registration) | Implicit — verified by test_keycard_registered / test_door_registered |
| §9 Tests (test_player_keycards, test_keycard_pickup, test_door) | Tasks 1, 2, 4 |
| §11 Open Q: door_open.wav not present, play_sfx warns gracefully | Task 4 ( AudioManager.play_sfx("door_open") — warning is graceful per AudioManager line 32) |

No gaps.

**2. Placeholder scan:** Searched plan for "TBD", "TODO", "implement later", "fill in", "similar to". None present. The `uid="uid://bk2ycard00000"` placeholder in `Keycard.tscn` is called out with a note that Godot replaces it on import (`make import` step normalizes it). No "add appropriate error handling" / "write tests for the above" / etc.

**3. Type / name consistency:**
- `keycards: Dictionary` — Player field name consistent in Task 1 (player.gd), Task 2 (FakePlayer test stub uses local `_cards` for clarity; the real Player field is `keycards`), Task 4 (FakePlayer test stub uses local `_cards`).
- `add_keycard(color: String)`, `has_keycard(color: String) -> bool`, `consume_keycard(color: String) -> bool` — signatures identical in player.gd, test_player_keycards.gd, test_keycard_pickup.gd FakePlayer, test_door.gd FakePlayer, keycard.gd call site, door.gd call site.
- `variant: String` — name consistent in keycard.gd, door.gd, both schemas, both test suites.
- `_opened: bool` — name consistent in door.gd and test_door.gd (accessed via `d.get("_opened")`).
- `_on_retract_finished(_anim_name: String)` — door.gd defines it, test_door.gd calls `d._on_retract_finished("Retract")` directly. Signatures match.
- `_disable_collision()` — internal to door.gd; tests verify its effects (CollisionPolygon2D.disabled, Area2D.monitoring) rather than calling it.
- `_build_contact_area() -> Area2D` — entity.gd new helper, door.gd calls it in `_ready`. Name matches.
- Entity registry type_ids: `keen1.door` (CATEGORY_SPECIAL) and `keen1.keycard` (CATEGORY_ITEM) — consistent across episode.gd, test_door.gd, test_keycard_pickup.gd.
- Schema options order `["red", "blue", "yellow", "green"]` — consistent everywhere.

No type/name drift.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-18-door-keycard-entities.md`.
