# Green Dangly Stuff Hazard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `GreenDanglyStuff` ceiling hazard: one-way walkable on top, instakill on the bottom 48 px, with three sprite variants (Left Edge / Normal / Right Edge) selectable via the existing `EntityVariant` mechanism.

**Architecture:** New `GreenDanglyStuff extends Hazard` overrides `_ready()` to (a) keep the body's `CollisionShape2D` full-tile but flip on `one_way_collision`, layer=4 (tiles); (b) shrink the inherited contact `Area2D` shape to the bottom 48 px of the tile. `_handle_player()` delegates to `Hazard._instakill()`. The placeholder `green_dangly_stuff.tscn` becomes a real scene with three `AnimatedSprite2D` children (one per sprite-sheet row), and `episode.gd` registers `keen1.green_dangly_stuff` with a 3-option `variant` enum schema.

**Tech Stack:** Godot 4.7, GDScript, GUT (Godot Unit Test) for testing.

**Spec:** `docs/superpowers/specs/2026-07-21-green-dangly-stuff-hazard-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `src/runtime/entities/green_dangly_stuff.gd` | Create | `GreenDanglyStuff extends Hazard`: one-way body + bottom-half kill Area2D + instakill on contact |
| `src/runtime/entities/green_dangly_stuff.tscn` | Replace | Root `CharacterBody2D` + `Visual` Node2D with 3 `AnimatedSprite2D` variant children (Left Edge / Normal / Right Edge), each a 4-frame loop from the matching sprite-sheet row |
| `src/episodes/keen1/episode.gd` | Modify | Register `keen1.green_dangly_stuff` as `CATEGORY_HAZARD` with a `variant` enum schema |
| `tests/unit/test_hazard.gd` | Modify | Add 3 tests: instakill on contact, Area2D shape is 64×48 + centered low, body's `CollisionShape2D.one_way_collision=true` and `collision_layer=4` |
| `tests/unit/test_episode.gd` | Modify | Add `test_green_dangly_stuff_registered_as_hazard_with_variant_schema` |

---

## Conventions

- **Tabs** for GDScript indentation (matches existing code).
- **Run all tests:** `./tests/run_all.sh` (must pass before commit).
- **Run a single test file:**
  ```
  GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
  "$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
    -gdir=res://tests/unit -gexit -gdisable_colors -gselect=<test_filename_without_ext>
  ```
- **GDScript naming:** instance vars `snake_case`, classes `PascalCase`, constants `SCREAMING_SNAKE_CASE`.
- **Importing the project** (required after creating/editing `.tscn` so Godot regenerates `.uid` files): `make import` (or `"$GODOT" --headless --path . --import --quit`).

---

## Task 1: Failing tests + GreenDanglyStuff script

Add the `GreenDanglyStuff` class with the one-way body, bottom-half kill zone, and instakill behavior. Drive it from three new characterization tests in `test_hazard.gd`.

**Files:**
- Modify: `tests/unit/test_hazard.gd`
- Create: `src/runtime/entities/green_dangly_stuff.gd`

- [ ] **Step 1.1: Write failing tests**

Append to `tests/unit/test_hazard.gd` (after `test_instakill_ignores_non_player_body`):

```gdscript
func test_green_dangly_stuff_instakills_on_contact():
	var g := GreenDanglyStuff.new()
	add_child_autofree(g)
	var p := _player()
	g._handle_player(p)
	assert_eq(p.health, 0, "GreenDanglyStuff drains all health on bottom contact")


func test_green_dangly_stuff_contact_area_is_bottom_half():
	var g := GreenDanglyStuff.new()
	add_child_autofree(g)  # _ready() builds the contact Area2D + body shape
	var area := g.get_node_or_null("Area2D") as Area2D
	assert_not_null(area, "contact Area2D exists")
	var col := area.get_child(0) as CollisionShape2D
	assert_not_null(col, "Area2D has a CollisionShape2D")
	assert_true(col.shape is RectangleShape2D, "Area2D shape is RectangleShape2D")
	var rect := col.shape as RectangleShape2D
	assert_eq(rect.size, Vector2(64, 48), "kill zone is 64 wide × 48 tall (bottom half)")
	# Shape position centers the rect in the LOWER half of the tile.
	# Tile center is (0,0); bottom 48 occupies y in [16-24, 16+24] = [-8, 40]… actually:
	# the bottom 48 strip has its center at y = (TILE - kill_height) / 2 = (64-48)/2 = 8 below center.
	assert_eq(col.position, Vector2(0, 8), "kill zone offset 8 px down so it spans the bottom 48 px")


func test_green_dangly_stuff_body_is_one_way_platform():
	var g := GreenDanglyStuff.new()
	add_child_autofree(g)
	assert_eq(g.collision_layer, 4, "body on tiles bit so player lands on it")
	assert_eq(g.collision_mask, 0, "body mask is zero (static)")
	# Find the body's direct-child CollisionShape2D (not the Area2D's shape).
	var body_col: CollisionShape2D = null
	for c in g.get_children():
		if c is CollisionShape2D:
			body_col = c
			break
	assert_not_null(body_col, "body has a direct CollisionShape2D child")
	assert_true(body_col.one_way_collision, "body shape is one-way (land from top, pass through from below)")
	assert_true(body_col.shape is RectangleShape2D, "body shape is RectangleShape2D")
	var rect := body_col.shape as RectangleShape2D
	assert_eq(rect.size, Vector2(64, 64), "body shape covers the full tile")
```

- [ ] **Step 1.2: Run tests to verify they fail**

```
GODOT=/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_hazard
```

Expected: **FAIL** — `GreenDanglyStuff` class does not exist yet (`Identifier "GreenDanglyStuff" not declared` or similar parse error in the test file). The test file will not even compile.

- [ ] **Step 1.3: Create the script**

Create `src/runtime/entities/green_dangly_stuff.gd`:

```gdscript
class_name GreenDanglyStuff
extends Hazard
## Ceiling hazard: one-way platform on top, instakill dangly mass below.
## Three visual variants (Left Edge / Normal / Right Edge) map to the three
## sprite-sheet rows and are selected via the `variant` schema enum, applied
## by EntityVariant in setup().

const _KILL_HEIGHT := 48.0  # px of the bottom of the tile that kills
const _TOP_SOLID := 16.0    # px of the top of the tile that is non-deadly


func setup(p_type_id: String, p_props: Dictionary) -> void:
	super(p_type_id, p_props)
	EntityVariant.apply(type_id, properties, self)


func _ready() -> void:
	# Build the player-contact Area2D via the base, then shrink its shape to
	# the bottom _KILL_HEIGHT px of the tile so only the dangly mass kills.
	# Player standing on top (feet above the kill zone) is safe.
	_build_contact()
	_shrink_contact_to_bottom()
	# Body is a one-way platform: layer=tiles so the player lands on it,
	# one_way_collision=true so the player can rise through from below.
	collision_layer = 4  # tiles bit
	collision_mask = 0
	_add_one_way_body_shape()


func _handle_player(player: Node) -> void:
	_instakill(player)


func _shrink_contact_to_bottom() -> void:
	var col := _area.get_child(0) as CollisionShape2D
	if col != null and col.shape is RectangleShape2D:
		var rect := col.shape as RectangleShape2D
		rect.size = Vector2(TILE, _KILL_HEIGHT)
		# Center of the bottom _KILL_HEIGHT strip is (TILE - _KILL_HEIGHT) / 2
		# below the tile's center (which is the body origin).
		col.position = Vector2(0, (TILE - _KILL_HEIGHT) / 2.0)


func _add_one_way_body_shape() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	shape.shape = rect
	shape.one_way_collision = true
	add_child(shape)
```

- [ ] **Step 1.4: Import the project so Godot registers the new class**

```
make import
```

Expected: exits 0 with no errors. The `class_name GreenDanglyStuff` is now globally available to the test file.

- [ ] **Step 1.5: Run tests to verify they pass**

```
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_hazard
```

Expected: **PASS** — all existing tests plus the 3 new ones.

If a test fails with the body shape being added underneath the existing `Area2D` shape, double-check `_add_one_way_body_shape()` calls `add_child(shape)` on `self` (the body root), not on `_area`.

- [ ] **Step 1.6: Commit**

```bash
git add src/runtime/entities/green_dangly_stuff.gd tests/unit/test_hazard.gd
git commit -m "feat: add GreenDanglyStuff hazard script + tests

One-way body (top walkable), bottom 48px Area2D instakill zone.
Reuses Hazard._instakill() helper. Variant sprites wired in next task."
```

---

## Task 2: Real scene with three variant sprites

Replace the empty placeholder `green_dangly_stuff.tscn` with a real scene: root `CharacterBody2D` scripted as `GreenDanglyStuff`, with a `Visual` `Node2D` holding three `AnimatedSprite2D` children — `Left Edge`, `Normal`, `Right Edge` — each a 4-frame loop from the matching sprite-sheet row. Mirrors the layout of `assets/sprites/Spike.tscn` but inlined into the runtime scene (matches the `clapper.tscn` inline-SpriteFrames pattern).

**Files:**
- Replace: `src/runtime/entities/green_dangly_stuff.tscn`

- [ ] **Step 2.1: Write the new scene file**

Overwrite `src/runtime/entities/green_dangly_stuff.tscn` with:

```
[gd_scene load_steps=18 format=3 uid="uid://c6ymsifd05n7s"]

[ext_resource type="Script" path="res://src/runtime/entities/green_dangly_stuff.gd" id="1_gds"]
[ext_resource type="Texture2D" path="res://assets/sprites/Green Dangly Stuff.png" id="2_tex"]

[sub_resource type="AtlasTexture" id="AtlasTexture_le_0"]
atlas = ExtResource("2_tex")
region = Rect2(0, 0, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_le_1"]
atlas = ExtResource("2_tex")
region = Rect2(64, 0, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_le_2"]
atlas = ExtResource("2_tex")
region = Rect2(128, 0, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_le_3"]
atlas = ExtResource("2_tex")
region = Rect2(192, 0, 64, 64)

[sub_resource type="SpriteFrames" id="SpriteFrames_le"]
animations = [{
"frames": [{
"duration": 1.0,
"texture": SubResource("AtlasTexture_le_0")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_le_1")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_le_2")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_le_3")
}],
"loop": 1,
"name": &"default",
"speed": 5.0
}]

[sub_resource type="AtlasTexture" id="AtlasTexture_nm_0"]
atlas = ExtResource("2_tex")
region = Rect2(0, 64, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_nm_1"]
atlas = ExtResource("2_tex")
region = Rect2(64, 64, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_nm_2"]
atlas = ExtResource("2_tex")
region = Rect2(128, 64, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_nm_3"]
atlas = ExtResource("2_tex")
region = Rect2(192, 64, 64, 64)

[sub_resource type="SpriteFrames" id="SpriteFrames_nm"]
animations = [{
"frames": [{
"duration": 1.0,
"texture": SubResource("AtlasTexture_nm_0")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_nm_1")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_nm_2")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_nm_3")
}],
"loop": 1,
"name": &"default",
"speed": 5.0
}]

[sub_resource type="AtlasTexture" id="AtlasTexture_re_0"]
atlas = ExtResource("2_tex")
region = Rect2(0, 128, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_re_1"]
atlas = ExtResource("2_tex")
region = Rect2(64, 128, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_re_2"]
atlas = ExtResource("2_tex")
region = Rect2(128, 128, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_re_3"]
atlas = ExtResource("2_tex")
region = Rect2(192, 128, 64, 64)

[sub_resource type="SpriteFrames" id="SpriteFrames_re"]
animations = [{
"frames": [{
"duration": 1.0,
"texture": SubResource("AtlasTexture_re_0")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_re_1")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_re_2")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_re_3")
}],
"loop": 1,
"name": &"default",
"speed": 5.0
}]

[node name="GreenDanglyStuff" type="CharacterBody2D"]
script = ExtResource("1_gds")

[node name="Visual" type="Node2D" parent="."]

[node name="Left Edge" type="AnimatedSprite2D" parent="Visual"]
visible = false
sprite_frames = SubResource("SpriteFrames_le")
autoplay = "default"

[node name="Normal" type="AnimatedSprite2D" parent="Visual"]
sprite_frames = SubResource("SpriteFrames_nm")
autoplay = "default"

[node name="Right Edge" type="AnimatedSprite2D" parent="Visual"]
visible = false
sprite_frames = SubResource("SpriteFrames_re")
autoplay = "default"
```

The `uid="uid://c6ymsifd05n7s"` is preserved from the existing placeholder so any forward references keep resolving. Each variant's `AnimatedSprite2D` name **exactly matches** an enum option so `EntityVariant`'s substring matching is unambiguous (`"left edge"` ⊆ `"left edge"`, etc.). The `Visual` Node2D is required: `Entity._build_contact()` skips its `ColorRect` fallback when a child named `Visual` exists.

- [ ] **Step 2.2: Import the project**

```
make import
```

Expected: exits 0 with no errors.

- [ ] **Step 2.3: Re-run the hazard tests (regression — the script now runs against the real scene tree)**

The Task 1 tests used `GreenDanglyStuff.new()` (raw script, no scene). Now we also want to verify the **scene instantiation** path picks up the script and the Visual node. Append this test to `tests/unit/test_hazard.gd`:

```gdscript
func test_green_dangly_stuff_scene_instantiates_with_three_variants():
	var packed := load("res://src/runtime/entities/green_dangly_stuff.tscn") as PackedScene
	assert_not_null(packed, "scene loads")
	var g := add_child_autofree(packed.instantiate()) as GreenDanglyStuff
	assert_not_null(g, "scene root is GreenDanglyStuff")
	var vis := g.get_node_or_null("Visual")
	assert_not_null(vis, "Visual wrapper exists")
	# All three variant AnimatedSprite2D children are present by exact name.
	assert_not_null(vis.get_node_or_null("Left Edge"), "Left Edge variant present")
	assert_not_null(vis.get_node_or_null("Normal"), "Normal variant present")
	assert_not_null(vis.get_node_or_null("Right Edge"), "Right Edge variant present")
```

- [ ] **Step 2.4: Run hazard tests**

```
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_hazard
```

Expected: **PASS** — 5 green-dangly tests + the original 5 hazard tests.

- [ ] **Step 2.5: Commit**

```bash
git add src/runtime/entities/green_dangly_stuff.tscn tests/unit/test_hazard.gd
git commit -m "feat: replace green dangly placeholder with real scene

Three AnimatedSprite2D variant children (Left Edge/Normal/Right Edge)
mapping to the three sprite-sheet rows. Visible-by-default = Normal."
```

---

## Task 3: Register in keen1 episode + registration test

Wire `keen1.green_dangly_stuff` into the registry as a hazard with the 3-option `variant` enum, then lock the registration with a test.

**Files:**
- Modify: `src/episodes/keen1/episode.gd`
- Modify: `tests/unit/test_episode.gd`

- [ ] **Step 3.1: Write the failing registration test**

Append to `tests/unit/test_episode.gd` (after `test_spike_registered_as_hazard_with_facing_schema`):

```gdscript
func test_green_dangly_stuff_registered_as_hazard_with_variant_schema():
	EntityRegistry.clear()
	Keen1Episode.new().register_entities(EntityRegistry)
	assert_true(EntityRegistry.has("keen1.green_dangly_stuff"), "keen1.green_dangly_stuff registered")
	var e: Dictionary = EntityRegistry.get_entry("keen1.green_dangly_stuff")
	assert_eq(e["category"], EntityRegistry.CATEGORY_HAZARD)
	assert_true(e.get("scene", null) is PackedScene, "binds a runtime PackedScene")
	var kinds: Array = e.get("map_kinds", [])
	assert_true(kinds.has(LevelData.MapKind.LEVEL), "LEVEL kind allowed")
	assert_false(kinds.has(LevelData.MapKind.OVERWORLD), "OVERWorld excluded")
	var schema := EntityRegistry.get_properties_schema("keen1.green_dangly_stuff")
	assert_eq(schema.size(), 1)
	assert_eq(String(schema[0].get("name")), "variant")
	assert_eq(String(schema[0].get("type")), "enum")
	assert_eq(String(schema[0].get("default")), "Normal")
	assert_eq(schema[0].get("options"), ["Left Edge", "Normal", "Right Edge"])
```

- [ ] **Step 3.2: Run the test to verify it fails**

```
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_episode
```

Expected: **FAIL** — `keen1.green_dangly_stuff` is not registered.

- [ ] **Step 3.3: Register the entity**

In `src/episodes/keen1/episode.gd`, locate the existing hazard preload block (lines ~31–33, near `var fire := preload(...)`). After the `var fire :=` line, add:

```gdscript
	var green_dangly := preload("res://src/runtime/entities/green_dangly_stuff.tscn")
```

Then after the existing `registry.register("keen1.fire", ...)` call (around line 40), add:

```gdscript
	registry.register("keen1.green_dangly_stuff", registry.CATEGORY_HAZARD, "Green Dangly Stuff",
		[{name = "variant", default = "Normal", type = "enum",
			options = ["Left Edge", "Normal", "Right Edge"]}],
		green_dangly)
```

Map kind defaults to `LEVEL` only — matches Clapper/Spike/Fire which are also hazards that never appear on the overworld.

- [ ] **Step 3.4: Import + run the registration test**

```
make import
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -gexit -gdisable_colors -gselect=test_episode
```

Expected: **PASS** — the new test passes alongside the existing episode tests.

- [ ] **Step 3.5: Commit**

```bash
git add src/episodes/keen1/episode.gd tests/unit/test_episode.gd
git commit -m "feat: register keen1.green_dangly_stuff hazard

Three variant enum (Left Edge/Normal/Right Edge), LEVEL-only map kind."
```

---

## Task 4: Full suite + editor verification

Run the whole test suite to catch regressions, then manually confirm the entity appears in the editor palette with working variant switching.

**Files:** none (verification only).

- [ ] **Step 4.1: Run the full GUT suite**

```
./tests/run_all.sh
```

Expected: all tests pass (the count grows by 6: 4 new in `test_hazard.gd`, 1 new in `test_episode.gd`, plus the scene-instantiation test added in Task 2).

If any pre-existing test fails, **stop** — investigate before continuing. Likely culprits: `test_runtime_entities.gd` (entity count changed) or `test_editor_workflow.gd` (palette count changed). If so, update the affected test's hardcoded count to match.

- [ ] **Step 4.2: Open the editor and verify the palette entry**

```
make edit
```

In the editor:

1. Open any keen1 level (`assets/levels/keen1/level1.tres` or similar).
2. Open the entity palette — confirm **Green Dangly Stuff** appears under the **Hazard** category.
3. Place an instance on the canvas.
4. With the instance selected, confirm the inspector shows a **Variant** dropdown with options **Left Edge**, **Normal**, **Right Edge** and default value **Normal**.
5. Switch the variant — confirm the visible sprite changes (only the matching row should render).
6. Save and quit the editor.

If the variant dropdown is empty or the sprite doesn't switch, the AnimatedSprite2D node names don't exactly match the enum options — re-check Step 2.1.

- [ ] **Step 4.3: Manual runtime verification (optional but recommended)**

Place a Green Dangly Stuff in a test level (or temporarily edit `level1.tres`):

1. Build + run: `make run-app`.
2. Walk Keen onto the top of the dangly stuff → confirm he stands on it (does not fall through).
3. Jump into it from below → confirm Keen dies (health drains to 0, death sequence triggers).
4. Walk into it from the side at ground level → confirm Keen dies.

If Keen falls through the top, the body's `one_way_collision` is not engaging — verify the body's `CollisionShape2D.one_way_collision = true` is actually set (Task 1 test guards this, but runtime physics can differ from class inspection).

- [ ] **Step 4.4: Final commit (if any test counts were updated in 4.1)**

If Step 4.1 required updating any pre-existing tests' hardcoded counts:

```bash
git add tests/
git commit -m "test: update entity/palette counts for green dangly stuff"
```

Otherwise, no commit — Task 3's commit is the last code change.

---

## Self-Review Checklist

After all tasks complete, verify:

- [ ] `./tests/run_all.sh` is green.
- [ ] `green_dangly_stuff.gd` has `class_name GreenDanglyStuff extends Hazard`.
- [ ] `green_dangly_stuff.tscn` root is `CharacterBody2D` with the script attached and a `Visual` Node2D containing `Left Edge`, `Normal`, `Right Edge` `AnimatedSprite2D` children.
- [ ] `episode.gd` registers `keen1.green_dangly_stuff` as `CATEGORY_HAZARD` with the 3-option `variant` enum.
- [ ] No new SFX, no projectile/stomp interaction (invincible like Clapper), no overworld placement.
- [ ] The spec's requirements table (§1.1) is fully covered: walk-on-top (Task 1), bottom instakill (Task 1), variant selection (Task 2 + Task 3), palette spawn (Task 3 + Task 4.2), tests (Tasks 1, 2, 3, 4.1).
