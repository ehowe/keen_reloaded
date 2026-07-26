# Ice Cannon Hazard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Ice Cannon hazard that periodically fires a straight-line icicle projectile from one of eight directional muzzles; the cannon body is solid-but-harmless, the projectile instakills Keen on contact and despawns on the first solid tile.

**Architecture:** Cannon is a `CharacterBody2D` extending `Hazard` (reuses `_instakill` contract) but overrides `_ready()` to skip the default contact Area2D — the body must not kill. It builds a solid 128×128 body shape + a looping `Timer`. On each timeout it reads the active facing sprite's `projectile_start_position` / `projectile_vector` metadata, instantiates a dedicated `IceCannonProjectile` scene (Area2D + AnimatedSprite2D spin), and launches it. The projectile moves linearly, reuses the static `Projectile.is_solid_tile_at()` helper for solid-tile despawn (no duplication), and instakills the player on `body_entered`.

**Tech Stack:** Godot 4.7, GDScript, GUT test framework. Tests run via `./tests/run_all.sh` (headless). All GDScript uses TAB indentation (project convention — do not substitute spaces).

**Spec:** `docs/superpowers/specs/2026-07-26-ice-cannon-hazard-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `src/runtime/entities/ice_cannon_projectile.gd` | Create | Area2D projectile: linear motion, solid-tile despawn, player instakill |
| `src/runtime/entities/ice_cannon_projectile.tscn` | Create | Scene: Area2D root (script) + `Spin` AnimatedSprite2D with relocated 8-frame SpriteFrames |
| `src/runtime/entities/ice_cannon.gd` | Create | Hazard: solid body, Timer, facing selection, fire logic |
| `src/runtime/entities/ice_cannon.tscn` | Rewrite | Root `Node2D`→`CharacterBody2D` (script), keep 8 sprites+metadata, drop embedded Projectile |
| `src/episodes/keen1/episode.gd` | Modify | Register `keen1.ice_cannon` hazard with `facing` enum schema |
| `tests/unit/test_ice_cannon_projectile.gd` | Create | Projectile unit tests |
| `tests/unit/test_ice_cannon.gd` | Create | Cannon unit tests |
| `tests/unit/test_episode.gd` | Modify | Add registration assertion |

---

## Conventions for all tasks

- **Indentation:** TAB characters in every `.gd` file (match `entity.gd`, `green_dangly_stuff.gd`). Never spaces.
- **Run tests:** `./tests/run_all.sh` from repo root. Headless Godot, runs all of `tests/unit/`.
- **Import after new scenes:** `make import` regenerates `.uid` files and validates `.tscn` resources. Always run after creating/editing `.tscn`.
- **Commit message style:** Conventional Commits (`feat:`, `test:`, `refactor:`), subject ≤50 chars. Match `git log --oneline -5`.

---

## Task 1: Ice Cannon Projectile (scene + script + tests)

The projectile is the leaf unit — it has no dependency on the cannon, so build and test it first.

**Files:**
- Create: `src/runtime/entities/ice_cannon_projectile.gd`
- Create: `src/runtime/entities/ice_cannon_projectile.tscn`
- Test: `tests/unit/test_ice_cannon_projectile.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_ice_cannon_projectile.gd` with TAB indentation:

```gdscript
extends GutTest

## Tests for the IceCannon projectile: linear motion, solid-tile despawn
## (via the shared Projectile.is_solid_tile_at helper), one-way pass-through,
## and instakill on player contact. Mirrors test_projectile.gd's approach of
## testing is_solid_tile_at directly (the _physics_process overlap path
## needs a live physics tick which GUT does not drive per-step).


class FakePlayer extends CharacterBody2D:
	var health: int = 3
	func _ready() -> void:
		add_to_group("player")
	func take_damage(amount: int) -> void:
		health = max(0, health - amount)


func _new_proj() -> IceCannonProjectile:
	return add_child_autofree(load("res://src/runtime/entities/ice_cannon_projectile.tscn").instantiate())


## Minimal TileMapLayer fixture: cell (0,0) = one-way, cell (1,0) = solid.
## Mirrors test_projectile.gd._tilemap_with_one_way_and_solid.
func _tilemap_with_one_way_and_solid() -> TileMapLayer:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(16, 16)
	ts.add_source(src)
	src.create_tile(Vector2i(0, 0))  # one-way
	src.create_tile(Vector2i(1, 0))  # solid
	ts.add_physics_layer()
	var rect := PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)])
	var td_ow: TileData = src.get_tile_data(Vector2i(0, 0), 0)
	td_ow.add_collision_polygon(0)
	td_ow.set_collision_polygon_points(0, 0, rect)
	td_ow.set_collision_polygon_one_way(0, 0, true)
	var td_solid: TileData = src.get_tile_data(Vector2i(1, 0), 0)
	td_solid.add_collision_polygon(0)
	td_solid.set_collision_polygon_points(0, 0, rect)
	var tml := TileMapLayer.new()
	tml.tile_set = ts
	tml.set_cell(Vector2i(0, 0), 0, Vector2i(0, 0))  # one-way at cell (0,0)
	tml.set_cell(Vector2i(1, 0), 0, Vector2i(1, 0))  # solid at cell (1,0)
	add_child_autofree(tml)
	return tml


func test_launch_sets_velocity():
	var p := _new_proj()
	p.launch(Vector2(100, 0))
	assert_eq(p.velocity, Vector2(100, 0), "launch stores velocity verbatim")


func test_moves_in_straight_line():
	var p := _new_proj()
	p.launch(Vector2(200, 0))
	var start := p.global_position
	p._physics_process(0.5)
	# velocity*dt = 100 px on x; y untouched (straight line).
	assert_almost_eq(p.global_position.x, start.x + 100.0, 0.001, "x advances by velocity*dt")
	assert_almost_eq(p.global_position.y, start.y, 0.001, "y unchanged")


func test_solid_tile_detected_as_blocking():
	var tml := _tilemap_with_one_way_and_solid()
	# Cell (1,0) center is at (24, 8) for 16px tiles.
	assert_true(Projectile.is_solid_tile_at(tml, Vector2(24, 8)), "solid tile blocks projectile")


func test_one_way_tile_not_blocking():
	var tml := _tilemap_with_one_way_and_solid()
	# Cell (0,0) center is at (8, 8).
	assert_false(Projectile.is_solid_tile_at(tml, Vector2(8, 8)), "one-way platform passed through")


func test_instakills_player_on_contact():
	var p := _new_proj()
	var player := FakePlayer.new()
	add_child_autofree(player)
	p._on_body_entered(player)
	assert_eq(player.health, 0, "contact drains all health")


func test_ignores_non_player_body():
	# A body without the player contract must not crash the instakill path.
	var p := _new_proj()
	var decoy := CharacterBody2D.new()
	add_child_autofree(decoy)
	p._on_body_entered(decoy)  # must not error
	assert_false(p.is_queued_for_deletion(), "non-player body does not free the projectile")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_all.sh`
Expected: FAIL — `IceCannonProjectile` class not found (ParseScript error / identifier not declared), tests skipped or erroring.

- [ ] **Step 3: Create the projectile script**

Create `src/runtime/entities/ice_cannon_projectile.gd` (TABS):

```gdscript
class_name IceCannonProjectile
extends Area2D
## Icicle fired by IceCannon. Straight-line motion at constant velocity;
## despawns instantly on touching a solid (non-one-way) tile, or instakills
## Keen on contact. Reuses Projectile.is_solid_tile_at() for the tile probe
## so one-way platforms (jump-through floors) remain passable — no logic
## duplication with the raygun bolt.
##
## The collision shape is built at _ready (codebase pattern: scenes carry
## visuals, scripts build physics). mask = player bit only: the projectile
## senses the player for the kill trigger but does not physically collide
## with anything, so it never blocks or is blocked.

const _HITBOX_SIZE := 32.0  # half of the 64px frame; tight hitbox, dodge room

var velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1  # player bit -> body_entered fires only for Keen
	_add_hitbox()
	if body_entered.is_connected(_on_body_entered) == false:
		body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	# Per-frame solid-tile probe: body_entered fires once per TileMapLayer,
	# so a fast projectile could tunnel past the entry frame into a solid
	# cell. Mirrors the player Projectile's defense; honors one-way skip.
	for body in get_overlapping_bodies():
		if body is TileMapLayer and Projectile.is_solid_tile_at(body, global_position):
			queue_free()
			return


func launch(p_velocity: Vector2) -> void:
	velocity = p_velocity


func _on_body_entered(body: Node) -> void:
	# Only the player is on the mask, but guard for the contract anyway.
	# Drain all health — mirrors Hazard._instakill verbatim. Cannot call
	# _instakill directly because this node extends Area2D, not Hazard.
	if body != null and body.is_in_group("player") \
			and body.has_method("take_damage") and "health" in body:
		body.take_damage(body.health)


func _add_hitbox() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(_HITBOX_SIZE, _HITBOX_SIZE)
	shape.shape = rect
	add_child(shape)
```

- [ ] **Step 4: Create the projectile scene**

Create `src/runtime/entities/ice_cannon_projectile.tscn`. This relocates the 8 `AtlasTexture` frames + `SpriteFrames` that currently live inline in `ice_cannon.tscn` (they will be removed from the cannon scene in Task 2). No header `uid` — `make import` assigns one. Uses TAB indentation inside string values.

```
[gd_scene load_steps=11 format=3]

[ext_resource type="Texture2D" uid="uid://chitt08kubjlc" path="res://assets/sprites/Ice Cannon Projectile.png" id="1_proj"]
[ext_resource type="Script" path="res://src/runtime/entities/ice_cannon_projectile.gd" id="2_script"]

[sub_resource type="AtlasTexture" id="AtlasTexture_f0"]
atlas = ExtResource("1_proj")
region = Rect2(0, 0, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_f1"]
atlas = ExtResource("1_proj")
region = Rect2(64, 0, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_f2"]
atlas = ExtResource("1_proj")
region = Rect2(128, 0, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_f3"]
atlas = ExtResource("1_proj")
region = Rect2(192, 0, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_f4"]
atlas = ExtResource("1_proj")
region = Rect2(256, 0, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_f5"]
atlas = ExtResource("1_proj")
region = Rect2(320, 0, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_f6"]
atlas = ExtResource("1_proj")
region = Rect2(384, 0, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_f7"]
atlas = ExtResource("1_proj")
region = Rect2(448, 0, 64, 64)

[sub_resource type="SpriteFrames" id="SpriteFrames_spin"]
animations = [{
"frames": [{
"duration": 1.0,
"texture": SubResource("AtlasTexture_f0")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_f1")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_f2")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_f3")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_f4")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_f5")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_f6")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_f7")
}],
"loop": 1,
"name": &"default",
"speed": 10.0
}]

[node name="IceCannonProjectile" type="Area2D"]
collision_layer = 0
collision_mask = 1
script = ExtResource("2_script")

[node name="Spin" type="AnimatedSprite2D" parent="."]
sprite_frames = SubResource("SpriteFrames_spin")
autoplay = "default"
```

- [ ] **Step 5: Import so Godot resolves the new resources**

Run: `make import`
Expected: exits 0, generates `ice_cannon_projectile.gd.uid` and assigns a scene header uid. No parse errors.

- [ ] **Step 6: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all 6 `test_ice_cannon_projectile_*` tests green, no regressions in the rest of the suite.

- [ ] **Step 7: Commit**

```bash
git add src/runtime/entities/ice_cannon_projectile.gd \
        src/runtime/entities/ice_cannon_projectile.gd.uid \
        src/runtime/entities/ice_cannon_projectile.tscn \
        tests/unit/test_ice_cannon_projectile.gd \
        tests/unit/test_ice_cannon_projectile.gd.uid
git commit -m "feat: add ice cannon projectile scene + script"
```

---

## Task 2: Ice Cannon (scene rewrite + script + tests)

Depends on Task 1 (the projectile scene must exist for `_fire()` to instantiate).

**Files:**
- Create: `src/runtime/entities/ice_cannon.gd`
- Rewrite: `src/runtime/entities/ice_cannon.tscn`
- Test: `tests/unit/test_ice_cannon.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_ice_cannon.gd` (TABS):

```gdscript
extends GutTest

## Tests for the IceCannon hazard: facing selection, direction-vector math
## for all eight sprites, solid-body/no-contact-area construction, timer
## wiring, and fire-spawns-projectile-at-muzzle.


func _new_cannon(facing: String = "UpRight") -> IceCannon:
	var c: IceCannon = load("res://src/runtime/entities/ice_cannon.tscn").instantiate()
	c.setup("keen1.ice_cannon", {"facing": facing})
	add_child_autofree(c)
	return c


## Table of expected normalized direction vectors per sprite, derived from
## the projectile_vector metadata (degrees, 0=up, CCW visually):
##   dir = Vector2(-sin(rad), -cos(rad))
const _DIRECTIONS := {
	"Up": [0.0, -1.0],
	"Left": [-1.0, 0.0],
	"Down": [0.0, 1.0],
	"Right": [1.0, 0.0],
	"UpRight": [0.7071067811865476, -0.7071067811865476],
	"UpLeft": [-0.7071067811865476, -0.7071067811865476],
	"DownRight": [0.7071067811865476, 0.7071067811865476],
	"DownLeft": [-0.7071067811865476, 0.7071067811865476],
}


func test_facing_selects_exactly_one_matching_sprite():
	for facing in _DIRECTIONS.keys():
		var c := _new_cannon(facing)
		var visible_names: Array[String] = []
		for child in c.get_children():
			if child is Sprite2D and child.visible:
				visible_names.append(String(child.name))
		assert_eq(visible_names.size(), 1, "%s: exactly one sprite visible" % facing)
		assert_eq(visible_names[0].to_lower(), facing.to_lower(),
			"%s: visible sprite name matches facing" % facing)


func test_direction_vector_for_each_facing_sprite():
	# Read each sprite's metadata and verify _read_direction produces the
	# expected normalized vector. Covers all eight directions.
	var c := _new_cannon()
	for child in c.get_children():
		if not (child is Sprite2D):
			continue
		var name := String(child.name)
		if not _DIRECTIONS.has(name):
			continue
		var expected: Array = _DIRECTIONS[name]
		var got := c._read_direction(child)
		assert_almost_eq(got.x, expected[0], 0.0001, "%s direction.x" % name)
		assert_almost_eq(got.y, expected[1], 0.0001, "%s direction.y" % name)


func test_read_start_offset_reads_metadata():
	var c := _new_cannon()
	# UpRight sprite carries PackedInt32Array(32, 32).
	var up_right := c.get_node("UpRight") as Sprite2D
	var off := c._read_start_offset(up_right)
	assert_eq(off, Vector2(32, 32), "UpRight muzzle offset read from metadata")


func test_body_is_solid_and_has_no_contact_area():
	var c := _new_cannon()
	assert_eq(c.collision_layer, 4, "body on tiles bit so Keen collides with it")
	assert_eq(c.collision_mask, 0, "body mask zero (static)")
	var body_col: CollisionShape2D = null
	var has_contact_area := false
	for child in c.get_children():
		if body_col == null and child is CollisionShape2D:
			body_col = child
		if child is Area2D:
			has_contact_area = true
	assert_not_null(body_col, "body has a direct CollisionShape2D child")
	assert_true(body_col.shape is RectangleShape2D, "body shape is RectangleShape2D")
	assert_eq((body_col.shape as RectangleShape2D).size, Vector2(128, 128),
		"body shape covers the 128px cannon footprint")
	assert_false(has_contact_area,
		"no contact Area2D — cannon body does not kill Keen (only the projectile does)")


func test_timer_configured_for_period():
	var c := _new_cannon()
	var timer: Timer = null
	for child in c.get_children():
		if child is Timer:
			timer = child
			break
	assert_not_null(timer, "Timer child built by _ready")
	assert_almost_eq(timer.wait_time, 1.0, 0.001, "default period is 1.0s")
	assert_true(timer.autostart, "timer autostarts on ready")
	assert_false(timer.one_shot, "timer loops (periodic firing)")


func test_period_export_overrides_wait_time():
	var c := _new_cannon()
	c.period = 2.5
	c._ready()  # rebuild timer with new period
	var timer: Timer = null
	for child in c.get_children():
		if child is Timer:
			timer = child
			break
	assert_almost_eq(timer.wait_time, 2.5, 0.001, "period @export drives Timer.wait_time")


func test_fire_spawns_projectile_at_muzzle_with_velocity():
	var c := _new_cannon("UpRight")
	c.global_position = Vector2(100, 100)
	var parent := c.get_parent()
	var before := parent.get_child_count()
	c._fire()
	assert_eq(parent.get_child_count(), before + 1, "_fire spawns one sibling")
	var proj := parent.get_child(parent.get_child_count() - 1)
	assert_true(proj is IceCannonProjectile, "sibling is IceCannonProjectile")
	# UpRight muzzle offset (32,32) + cannon pos (100,100) = (132,132).
	assert_eq(proj.global_position, Vector2(132, 132), "projectile spawned at muzzle offset")
	# UpRight direction (315 deg) * speed (300) = (212.13, -212.13).
	var expected_speed := c.projectile_speed
	assert_almost_eq(proj.velocity.x, 0.7071067811865476 * expected_speed, 0.01, "velocity.x")
	assert_almost_eq(proj.velocity.y, -0.7071067811865476 * expected_speed, 0.01, "velocity.y")


func test_handle_player_is_noop():
	# The cannon builds no contact Area2D, so _handle_player is never
	# invoked at runtime; verify the guard doesn't crash and does nothing.
	var c := _new_cannon()
	var player := CharacterBody2D.new()
	player.set("health", 3)  # dynamic; just ensures no mutation path runs
	add_child_autofree(player)
	c._handle_player(player)
	assert_eq(player.get("health"), 3, "cannon contact does not damage player")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_all.sh`
Expected: FAIL — `IceCannon` class not found, and/or `ice_cannon.tscn` root is still `Node2D` (instantiation type error).

- [ ] **Step 3: Create the cannon script**

Create `src/runtime/entities/ice_cannon.gd` (TABS):

```gdscript
class_name IceCannon
extends Hazard
## Directional cannon. Solid body — Keen can stand on it or bump into it
## without damage. Periodically fires a straight-line icicle projectile
## from the active facing sprite's muzzle; the projectile instakills on
## contact and despawns on the first solid tile.
##
## Eight Sprite2D children encode per-direction firing solutions as node
## metadata: projectile_start_position (PackedInt32Array x,y offset from
## cannon center) and projectile_vector (degrees, 0=up, CCW visually).
## Selection is by exact-name match against the `facing` enum — NOT
## EntityVariant, because the sprite names substring-collide
## (Up is a substring of UpRight/UpLeft) which breaks EntityVariant's
## first-substring-wins rule.

const _BODY_SIZE := 128.0  # cannon sprite footprint, px
const _PROJECTILE_SCENE := preload("res://src/runtime/entities/ice_cannon_projectile.tscn")

@export var period: float = 1.0       # seconds between shots
@export var projectile_speed: float = 300.0


func setup(p_type_id: String, p_props: Dictionary) -> void:
	super(p_type_id, p_props)
	_apply_facing()


func _ready() -> void:
	# Deliberately do NOT call super._ready(): the base builds a player-
	# contact Area2D, but the cannon body must not kill. Build only the
	# solid body + the firing timer.
	collision_layer = 4  # tiles bit -> Keen collides with / lands on body
	collision_mask = 0
	_add_body_shape()
	_add_timer()


func _handle_player(_player: Node) -> void:
	# No contact Area2D is built, so this is never invoked at runtime.
	# Kept as a no-op guard to satisfy the Hazard override contract.
	pass


func _apply_facing() -> void:
	# Exact-name match (case-insensitive). Only one of the eight sprites is
	# visible at a time; the visible one's metadata drives _fire().
	var facing := String(properties.get("facing", "UpRight"))
	var want := facing.to_lower()
	for c in get_children():
		if c is Sprite2D:
			c.visible = (String(c.name).to_lower() == want)


func _add_body_shape() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(_BODY_SIZE, _BODY_SIZE)
	shape.shape = rect
	add_child(shape)


func _add_timer() -> void:
	var timer := Timer.new()
	timer.wait_time = period
	timer.autostart = true
	timer.one_shot = false
	timer.timeout.connect(_fire)
	add_child(timer)


func _fire() -> void:
	var muzzle := _active_facing_sprite()
	if muzzle == null:
		return
	var start_offset := _read_start_offset(muzzle)
	var direction := _read_direction(muzzle)
	var proj: IceCannonProjectile = _PROJECTILE_SCENE.instantiate()
	get_parent().add_child(proj)
	proj.global_position = global_position + start_offset
	proj.launch(direction * projectile_speed)


func _active_facing_sprite() -> Sprite2D:
	for c in get_children():
		if c is Sprite2D and c.visible:
			return c
	return null


func _read_start_offset(sprite: Sprite2D) -> Vector2:
	var arr: PackedInt32Array = sprite.get_meta("projectile_start_position", PackedInt32Array())
	if arr.size() >= 2:
		return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO


func _read_direction(sprite: Sprite2D) -> Vector2:
	# projectile_vector is degrees, 0 = straight up, counter-clockwise
	# visually on screen (Y-down). Verified against all eight sprites:
	#   Up=0 -> (0,-1), Left=90 -> (-1,0), Down=180 -> (0,1),
	#   Right=270 -> (1,0), UpRight=315 -> (0.707,-0.707), etc.
	var deg := float(sprite.get_meta("projectile_vector", 0.0))
	var rad := deg_to_rad(deg)
	return Vector2(-sin(rad), -cos(rad))
```

- [ ] **Step 4: Rewrite the cannon scene**

Replace the entire contents of `src/runtime/entities/ice_cannon.tscn` with the version below. Changes from the placeholder:
1. Root `Node2D` → `CharacterBody2D`, script attached.
2. Removed `Projectile` `AnimatedSprite2D` + its 8 `AtlasTexture` sub-resources + `SpriteFrames` sub-resource (relocated to `ice_cannon_projectile.tscn` in Task 1).
3. Removed the now-unused `Ice Cannon Projectile.png` ext_resource.
4. The 8 directional `Sprite2D` children are unchanged (same textures, rotations, visibility defaults, metadata).
5. Renamed the body-texture ext_resource id to `1_body` for clarity; updated the three atlas sub_resource references to match.

```
[gd_scene load_steps=6 format=3 uid="uid://b0n0s1tybh84e"]

[ext_resource type="Texture2D" uid="uid://c6e2rh8ihc1fm" path="res://assets/tilesets/Ice Cannon.png" id="1_body"]
[ext_resource type="Script" path="res://src/runtime/entities/ice_cannon.gd" id="2_script"]

[sub_resource type="AtlasTexture" id="AtlasTexture_x4u6v"]
atlas = ExtResource("1_body")
region = Rect2(0, 0, 128, 128)

[sub_resource type="AtlasTexture" id="AtlasTexture_qccdw"]
atlas = ExtResource("1_body")
region = Rect2(256, 0, 128, 128)

[sub_resource type="AtlasTexture" id="AtlasTexture_07erc"]
atlas = ExtResource("1_body")
region = Rect2(128, 0, 128, 128)

[node name="IceCannon" type="CharacterBody2D"]
script = ExtResource("2_script")

[node name="UpRight" type="Sprite2D" parent="."]
texture = SubResource("AtlasTexture_x4u6v")
metadata/projectile_start_position = PackedInt32Array(32, 32)
metadata/projectile_vector = 315

[node name="DownLeft" type="Sprite2D" parent="."]
visible = false
rotation = 3.1415927
texture = SubResource("AtlasTexture_x4u6v")
metadata/projectile_start_position = PackedInt32Array(-32, -32)
metadata/projectile_vector = 135

[node name="UpLeft" type="Sprite2D" parent="."]
visible = false
texture = SubResource("AtlasTexture_qccdw")
metadata/projectile_start_position = PackedInt32Array(-32, 32)
metadata/projectile_vector = 45

[node name="DownRight" type="Sprite2D" parent="."]
visible = false
rotation = 3.1415927
texture = SubResource("AtlasTexture_qccdw")
metadata/projectile_start_position = PackedInt32Array(32, -32)
metadata/projectile_vector = 225

[node name="Up" type="Sprite2D" parent="."]
visible = false
texture = SubResource("AtlasTexture_07erc")
metadata/projectile_start_position = PackedInt32Array(0, 64)
metadata/projectile_vector = 0

[node name="Left" type="Sprite2D" parent="."]
visible = false
rotation = -1.5707964
texture = SubResource("AtlasTexture_07erc")
metadata/projectile_start_position = PackedInt32Array(-64, 0)
metadata/projectile_vector = 90

[node name="Down" type="Sprite2D" parent="."]
visible = false
rotation = 3.1415927
texture = SubResource("AtlasTexture_07erc")
metadata/projectile_start_position = PackedInt32Array(0, -64)
metadata/projectile_vector = 180

[node name="Right" type="Sprite2D" parent="."]
visible = false
rotation = 1.5707964
texture = SubResource("AtlasTexture_07erc")
metadata/projectile_start_position = PackedInt32Array(64, 0)
metadata/projectile_vector = 270
```

- [ ] **Step 5: Import so Godot resolves the rewritten scene**

Run: `make import`
Expected: exits 0, generates `ice_cannon.gd.uid`, no parse errors. The scene uid is preserved (`uid://b0n0s1tybh84e`) so existing references remain valid.

- [ ] **Step 6: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all 8 `test_ice_cannon_*` tests green (facing selection ×8, direction math ×8, body solid, no contact area, timer wiring, period override, fire spawn + velocity, handle_player noop). No regressions.

- [ ] **Step 7: Commit**

```bash
git add src/runtime/entities/ice_cannon.gd \
        src/runtime/entities/ice_cannon.gd.uid \
        src/runtime/entities/ice_cannon.tscn \
        tests/unit/test_ice_cannon.gd \
        tests/unit/test_ice_cannon.gd.uid
git commit -m "feat: add ice cannon hazard (solid body + timer-fired projectile)"
```

---

## Task 3: Register the entity in the keen1 episode

Depends on Task 2 (the cannon scene must exist for the preload).

**Files:**
- Modify: `src/episodes/keen1/episode.gd` (add preload + register call)
- Test: `tests/unit/test_episode.gd` (add registration assertion)

- [ ] **Step 1: Write the failing test**

Open `tests/unit/test_episode.gd` and append this test method (TABS, before the `after_each` method at the bottom):

```gdscript
func test_ice_cannon_registered_as_hazard_with_facing_schema():
	EntityRegistry.clear()
	Keen1Episode.new().register_entities(EntityRegistry)
	assert_true(EntityRegistry.has("keen1.ice_cannon"), "keen1.ice_cannon registered")
	var e: Dictionary = EntityRegistry.get_entry("keen1.ice_cannon")
	assert_eq(e["category"], EntityRegistry.CATEGORY_HAZARD, "category is HAZARD")
	assert_true(e.get("scene", null) is PackedScene, "binds a runtime PackedScene")
	var kinds: Array = e.get("map_kinds", [])
	assert_true(kinds.has(LevelData.MapKind.LEVEL), "LEVEL kind allowed")
	assert_false(kinds.has(LevelData.MapKind.OVERWORLD), "OVERWORLD excluded")
	var schema := EntityRegistry.get_properties_schema("keen1.ice_cannon")
	assert_eq(schema.size(), 1, "exactly one schema property")
	assert_eq(String(schema[0].get("name")), "facing", "schema property name is facing")
	assert_eq(String(schema[0].get("type")), "enum", "schema property type is enum")
	assert_eq(String(schema[0].get("default")), "UpRight", "default facing is UpRight")
	assert_eq(schema[0].get("options"),
		["Up", "UpRight", "Right", "DownRight", "Down", "DownLeft", "Left", "UpLeft"],
		"eight directional options")
```

- [ ] **Step 2: Run tests to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `keen1.ice_cannon` not registered (`assert_true(EntityRegistry.has(...))` fails).

- [ ] **Step 3: Add the registration**

In `src/episodes/keen1/episode.gd`, add the preload alongside the other hazard preloads (after the `green_dangly` line, around line 34) and add the register call alongside the other hazard registrations (after the `green_dangly_stuff` register block, around line 45).

Add preload (match the surrounding `var <name> := preload(...)` style):

```gdscript
	var ice_cannon := preload("res://src/runtime/entities/ice_cannon.tscn")
```

Add register call (after the `green_dangly_stuff` registration):

```gdscript
	registry.register("keen1.ice_cannon", registry.CATEGORY_HAZARD, "Ice Cannon",
		[{name = "facing", default = "UpRight", type = "enum",
			options = ["Up", "UpRight", "Right", "DownRight", "Down",
				"DownLeft", "Left", "UpLeft"]}],
		ice_cannon)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — `test_ice_cannon_registered_as_hazard_with_facing_schema` green, no regressions across the full suite.

- [ ] **Step 5: Commit**

```bash
git add src/episodes/keen1/episode.gd tests/unit/test_episode.gd
git commit -m "feat: register keen1.ice_cannon hazard with facing enum"
```

---

## Task 4: Full-suite verification + cleanup

**Files:** none modified unless `make import` produced new `.uid` files.

- [ ] **Step 1: Re-import to settle all .uid files**

Run: `make import`
Expected: exits 0. If new `.uid` files appear (e.g. for the new test files), note them for the commit.

- [ ] **Step 2: Run the full test suite**

Run: `./tests/run_all.sh`
Expected: all tests pass (existing suite + the new projectile, cannon, and episode tests). Zero failures.

- [ ] **Step 3: Sanity-check the scene loads in the editor (optional, manual)**

Run: `make edit` and open both `ice_cannon.tscn` and `ice_cannon_projectile.tscn`. Verify:
- `IceCannon` root is `CharacterBody2D` with `ice_cannon.gd` attached.
- All 8 directional `Sprite2D` children retain their metadata (visible in the Node → Metadata panel).
- `IceCannonProjectile` root is `Area2D` with the script; `Spin` child shows the 8-frame animation preview.
- No error spam in the editor console.

- [ ] **Step 4: Commit any .uid additions**

```bash
git status
# If new .uid files or the .godot/imported changes are present and relevant:
git add -A
git commit -m "chore: regenerate import uids for ice cannon assets"
```
If `git status` is clean, skip the commit — Task 1–3 already committed everything.

---

## Self-Review (run after writing this plan)

**Spec coverage:** Each requirement in the spec §1 maps to a task:
- R1 (8 sprites carry collision, body solid, no kill) → Task 2 `test_body_is_solid_and_has_no_contact_area`.
- R2 (projectile collision follows it, instakills) → Task 1 `test_instakills_player_on_contact` + `_add_hitbox` in script.
- R3 (straight-line motion) → Task 1 `test_moves_in_straight_line`.
- R4 (despawn on solid tile) → Task 1 `test_solid_tile_detected_as_blocking` + `_physics_process` solid probe.
- R5 (facing enum, default UpRight) → Task 2 `test_facing_selects_exactly_one_matching_sprite` + Task 3 schema test.
- R6 (periodic timer, 1.0s default) → Task 2 `test_timer_configured_for_period`.
- R7 (registry, palette) → Task 3 `test_ice_cannon_registered_as_hazard_with_facing_schema`.
- R8 (existing tests pass + new tests) → Task 4 full-suite run.

**Placeholder scan:** No TBD/TODO/"add appropriate" — all code blocks contain the exact content.

**Type/name consistency:** `IceCannon`, `IceCannonProjectile`, `_fire`, `_read_direction`, `_read_start_offset`, `_active_facing_sprite`, `_apply_facing`, `_add_body_shape`, `_add_timer`, `launch(velocity)`, `velocity`, `period`, `projectile_speed` — same names across tests and implementation. `_DIRECTIONS` table values match the `Vector2(-sin(rad), -cos(rad))` formula.
