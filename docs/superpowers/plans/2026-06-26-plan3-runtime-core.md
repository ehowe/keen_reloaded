# keen_reloaded — Plan 3: Runtime Core

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the gameplay runtime that turns a `LevelData` into a playable scene — procedural no-art `TileSet`+`TileMapLayer` world with collision, a `CharacterBody2D` player (run/jump/pogo), the base entity-class hierarchy, `EntityRegistry.instantiate`, and a live editor **Test ▶**.

**Architecture:** Approach C hybrid (spec §6). `LevelRuntime(Node2D).build(level)` constructs 3 `TileMapLayer`s from the level's tile arrays using two procedurally-built `TileSet`s (solid=with collision, decor=without), spawns a `Player` at `player_spawn`, and spawns each `EntityDef` via `EntityRegistry.instantiate`. The editor's Test ▶ stashes the level in `GameManager.pending_level`, swaps to the runtime scene; Esc swaps back and the editor restores the level. No art files — tiles reuse the Plan 2 `EditorColors` palette; entities/player are placeholder shapes.

**Tech Stack:** Godot 4.7, GDScript, GUT (Godot Unit Test).

**Godot binary:** `/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot`
(Set a shell alias if convenient: `alias godot="/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot"`)

**Design spec:** `docs/superpowers/specs/2026-06-26-plan3-runtime-core-design.md`

---

## Scope

- **In scope:** `ProceduralTileSet`, `LevelRuntime`, `Player` (run/jump/pogo), base entities (`Entity`/`Enemy`/`Collectible`/`Hazard`/`Special`), `EntityRegistry.instantiate`, `GameManager.pending_level`/`return_scene` + input actions, live Test ▶ + restore.
- **Out of scope (Plan 4):** real art/tileset assets, concrete Keen 1 entity scenes, `shoot`, exit/special completion logic.
- **Testing:** GUT for all deterministic logic (scene assembly, entity contact, registry, tileset building). Player movement *feel* = manual via Test ▶.

## API note (verified against Godot 4.7 stable)

The following were probed headless and are correct for 4.7:
- `ImageTexture.create_from_image(img)` → `ImageTexture` (there is **no** `ImageTexture2D` class in 4.7).
- `TileSet.add_source(src)` returns the int source id; `TileSetAtlasSource.create_tile(atlas_coords)` returns **void**.
- `TileSet.add_physics_layer()` returns **void** — the new layer index is `get_physics_layers_count() - 1`.
- `TileData.add_collision_polygon(layer)` then `TileData.set_collision_polygon_points(layer, 0, poly)` (hardcode polygon index 0). **Do NOT call `TileData.get_collision_polygon_count()`** — it hangs the headless engine in 4.7 (engine bug). To verify collision, read points back with `get_collision_polygon_points(layer, 0)`.

---

## File Structure (this plan)

| File | Responsibility |
|------|----------------|
| `src/runtime/procedural_tileset.gd` | Builds a no-art `TileSet` (colored cells from `EditorColors`); optional per-tile collision |
| `src/runtime/entities/entity.gd` | `Entity(Node2D)` base: contact Area2D + placeholder visual + dispatch hook |
| `src/runtime/entities/collectible.gd` | Awards score on contact, frees self |
| `src/runtime/entities/hazard.gd` | Damages player on contact |
| `src/runtime/entities/enemy.gd` | Health + contact damage + `take_damage()` |
| `src/runtime/entities/special.gd` | No-op hook (exits/triggers = Plan 4) |
| `src/runtime/player/player.gd` | `CharacterBody2D`: run/jump/pogo, gravity, score/health API, group `"player"` |
| `src/runtime/player/player.tscn` | Player scene (body + CollisionShape2D + ColorRect + Camera2D) |
| `src/core/entity_registry.gd` | Extend: `scene` param + `instantiate(type_id, pos, props)` |
| `src/core/game_manager.gd` | `pending_level`/`return_scene` + register input actions in code |
| `src/runtime/level_runtime.gd` | `LevelRuntime(Node2D).build(level)` — assembles the scene |
| `src/runtime/level_runtime.tscn` | Bare `Node2D` + script |
| `src/editor/level_editor.gd` | Wire live Test ▶ + restore level on return |
| `tests/unit/test_procedural_tileset.gd` | TileSet build + collision tests |
| `tests/unit/test_runtime_entities.gd` | Base entity contact-dispatch tests |
| `tests/unit/test_entity_registry_instantiate.gd` | `instantiate` tests |
| `tests/unit/test_player.gd` | Player score/health/group tests |
| `tests/unit/test_game_manager.gd` | pending_level round-trip + input action presence |
| `tests/unit/test_level_runtime.gd` | `LevelRuntime.build` scene-assembly tests |
| `tests/unit/test_runtime_integration.gd` | Spawn every registered entity type |

---

## Task 1: `ProceduralTileSet`

**Files:**
- Create: `src/runtime/procedural_tileset.gd`
- Create: `tests/unit/test_procedural_tileset.gd`

- [ ] **Step 1: Write the failing test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_procedural_tileset.gd`:

```gdscript
extends GutTest

func test_solid_tileset_has_tiles_and_collision():
	var ts: TileSet = ProceduralTileSet.build(4, 16, true)
	assert_eq(ts.tile_size, Vector2i(16, 16))
	assert_eq(ts.get_source_count(), 1, "one atlas source")
	var src: TileSetAtlasSource = ts.get_source(0) as TileSetAtlasSource
	assert_eq(src.get_tiles_count(), 4, "4 tiles for ids 1..4")
	assert_eq(ts.get_physics_layers_count(), 1, "solid has 1 physics layer")
	var td: TileData = src.get_tile_data(Vector2i(0, 0), 0)
	assert_eq(td.get_collision_polygon_points(0, 0).size(), 4, "tile 1 has a 4-pt collision rect")

func test_decor_tileset_has_no_collision():
	var ts: TileSet = ProceduralTileSet.build(3, 16, false)
	var src: TileSetAtlasSource = ts.get_source(0) as TileSetAtlasSource
	assert_eq(src.get_tiles_count(), 3)
	assert_eq(ts.get_physics_layers_count(), 0, "decor has no physics layer")

func test_max_id_zero_returns_empty_tileset():
	var ts: TileSet = ProceduralTileSet.build(0, 16, true)
	assert_eq(ts.get_source_count(), 0)
	assert_eq(ts.get_physics_layers_count(), 0)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `ProceduralTileSet` class not found.

- [ ] **Step 3: Implement `ProceduralTileSet`**

Create `/Users/eugene/git/keen_reloaded/src/runtime/procedural_tileset.gd`:

```gdscript
class_name ProceduralTileSet
extends RefCounted
## Builds a TileSet procedurally with NO art files. Each tile id 1..max_id maps
## to a solid-color cell (reusing the Plan 2 EditorColors palette) and, when
## with_collision is true, a full-cell collision rectangle. Used by LevelRuntime
## to render + collide the geometry layer (solid) and the fg/bg layers (decor).
##
## NOTE (Godot 4.7): set_collision_polygon_points() uses a hardcoded polygon
## index 0. Do NOT call get_collision_polygon_count() — it hangs the headless
## engine in 4.7.

## Build a TileSet with `max_id` colored tiles (ids 1..max_id).
static func build(max_id: int, tile_size: int, with_collision: bool) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)
	if max_id <= 0:
		return ts

	# Atlas image: one row of `max_id` colored cells.
	var img := Image.create(max_id * tile_size, tile_size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for id in range(1, max_id + 1):
		_paint_cell(img, id, tile_size, EditorColors.tile_color(id))

	var tex := ImageTexture.create_from_image(img)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(tile_size, tile_size)
	ts.add_source(src)
	for id in range(1, max_id + 1):
		src.create_tile(Vector2i(id - 1, 0))

	if with_collision:
		ts.add_physics_layer()
		var layer: int = ts.get_physics_layers_count() - 1
		# layer bit 4 = "tiles" (project layer_3), mask bit 1 = "player" (layer_1)
		ts.set_physics_layer_collision_layer(layer, 4)
		ts.set_physics_layer_collision_mask(layer, 1)
		var poly := PackedVector2Array([
			Vector2(0, 0),
			Vector2(tile_size, 0),
			Vector2(tile_size, tile_size),
			Vector2(0, tile_size),
		])
		for id in range(1, max_id + 1):
			var td: TileData = src.get_tile_data(Vector2i(id - 1, 0), 0)
			td.add_collision_polygon(layer)
			td.set_collision_polygon_points(layer, 0, poly)
	return ts


static func _paint_cell(img: Image, id: int, tile_size: int, color: Color) -> void:
	var origin_x := (id - 1) * tile_size
	for px in range(tile_size):
		for py in range(tile_size):
			img.set_pixel(origin_x + px, py, color)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all ProceduralTileSet tests green (plus existing tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/runtime/procedural_tileset.gd tests/unit/test_procedural_tileset.gd
git commit -m "feat: add ProceduralTileSet builder (no-art render + collision)"
```

---

## Task 2: Base entity classes

**Files:**
- Create: `src/runtime/entities/entity.gd`
- Create: `src/runtime/entities/collectible.gd`
- Create: `src/runtime/entities/hazard.gd`
- Create: `src/runtime/entities/enemy.gd`
- Create: `src/runtime/entities/special.gd`
- Create: `tests/unit/test_runtime_entities.gd`

`Entity` builds a contact `Area2D` (mask = player bit) + placeholder `ColorRect` in `_ready()`, and dispatches `body_entered` to an overridable `_handle_player(player)`. Tests call `_on_body_entered(body)` directly with a fake player node, so they don't depend on physics stepping.

- [ ] **Step 1: Write the failing test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_runtime_entities.gd`:

```gdscript
extends GutTest

class FakePlayer extends Node:
	var score: int = 0
	var health: int = 3
	func _ready() -> void:
		add_to_group("player")
	func add_score(amount: int) -> void:
		score += amount
	func take_damage(amount: int) -> void:
		health -= amount


func _fake_player() -> FakePlayer:
	var p := FakePlayer.new()
	add_child(p)
	return p


func test_collectible_awards_score_and_frees():
	var c := Collectible.new()
	c.score_value = 250
	add_child(c)
	var p := _fake_player()
	c._on_body_entered(p)
	assert_eq(p.score, 250, "score awarded")
	assert_true(c.is_queued_for_deletion(), "collectible frees on pickup")


func test_hazard_damages_player():
	var h := Hazard.new()
	h.damage = 2
	add_child(h)
	var p := _fake_player()
	h._on_body_entered(p)
	assert_eq(p.health, 1, "took 2 damage from 3")


func test_enemy_contact_damages_player():
	var e := Enemy.new()
	e.contact_damage = 1
	add_child(e)
	var p := _fake_player()
	e._on_body_entered(p)
	assert_eq(p.health, 2)


func test_enemy_take_damage_reduces_health_and_frees_at_zero():
	var e := Enemy.new()
	e.health = 2
	add_child(e)
	e.take_damage(1)
	assert_eq(e.health, 1)
	assert_false(e.is_queued_for_deletion())
	e.take_damage(1)
	assert_eq(e.health, 0)
	assert_true(e.is_queued_for_deletion(), "enemy frees at 0 health")


func test_entity_ignores_non_player_body():
	var c := Collectible.new()
	add_child(c)
	var decoy := Node.new()
	add_child(decoy)
	c._on_body_entered(decoy)  # must not error and must not free
	assert_false(c.is_queued_for_deletion())
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `Entity` / `Collectible` / `Hazard` / `Enemy` classes not found.

- [ ] **Step 3: Implement `Entity` base**

Create `/Users/eugene/git/keen_reloaded/src/runtime/entities/entity.gd`:

```gdscript
class_name Entity
extends Node2D
## Base class for all runtime entities. Builds a contact Area2D (collision_mask =
## player bit) + a placeholder ColorRect visual in _ready(). Subclasses override
## _handle_player(player) to react when the player touches them.

signal player_touched(player: Node)

const TILE := 16

var type_id: String = ""
var properties: Dictionary = {}

var _area: Area2D


## Called by EntityRegistry.instantiate after constructing the node.
func setup(p_type_id: String, p_props: Dictionary) -> void:
	type_id = p_type_id
	properties = p_props


func _ready() -> void:
	_build_contact()


func _build_contact() -> void:
	_area = Area2D.new()
	_area.monitoring = true
	_area.collision_layer = 0
	_area.collision_mask = 1  # player bit (project layer_1)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	shape.shape = rect
	_area.add_child(shape)
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)

	var vis := ColorRect.new()
	vis.size = Vector2(TILE, TILE)
	vis.position = Vector2(-TILE / 2.0, -TILE / 2.0)
	vis.color = _color()
	add_child(vis)


func _color() -> Color:
	return Color(0.8, 0.8, 0.8, 1)


func _on_body_entered(body: Node) -> void:
	var p := _as_player(body)
	if p == null:
		return
	player_touched.emit(p)
	_handle_player(p)


func _as_player(body: Node) -> Node:
	if body != null and body.is_in_group("player"):
		return body
	return null


## Override in subclasses to react to the player touching this entity.
func _handle_player(_player: Node) -> void:
	pass
```

- [ ] **Step 4: Implement `Collectible`**

Create `/Users/eugene/git/keen_reloaded/src/runtime/entities/collectible.gd`:

```gdscript
class_name Collectible
extends Entity
## A pickup that awards score on contact, then frees itself.

var score_value: int = 100


func _color() -> Color:
	return Color(1.0, 0.85, 0.2, 1)


func _handle_player(player: Node) -> void:
	if player.has_method("add_score"):
		player.add_score(score_value)
	queue_free()
```

- [ ] **Step 5: Implement `Hazard`**

Create `/Users/eugene/git/keen_reloaded/src/runtime/entities/hazard.gd`:

```gdscript
class_name Hazard
extends Entity
## Damages the player on contact (spikes, fire, etc.).

var damage: int = 1


func _color() -> Color:
	return Color(1.0, 0.2, 0.2, 1)


func _handle_player(player: Node) -> void:
	if player.has_method("take_damage"):
		player.take_damage(damage)
```

- [ ] **Step 6: Implement `Enemy`**

Create `/Users/eugene/git/keen_reloaded/src/runtime/entities/enemy.gd`:

```gdscript
class_name Enemy
extends Entity
## An enemy with health and contact damage. take_damage() reduces health and
## frees the enemy at 0. (No AI movement in Plan 3 — Plan 4 adds it.)

var health: int = 1
var contact_damage: int = 1


func _color() -> Color:
	return Color(0.9, 0.4, 0.6, 1)


func _handle_player(player: Node) -> void:
	if player.has_method("take_damage"):
		player.take_damage(contact_damage)


func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		queue_free()
```

- [ ] **Step 7: Implement `Special`**

Create `/Users/eugene/git/keen_reloaded/src/runtime/entities/special.gd`:

```gdscript
class_name Special
extends Entity
## Base for exits / triggers / doors. Concrete behavior is Plan 4 content; this
## class is a visible no-op placeholder so registered special types spawn safely.


func _color() -> Color:
	return Color(0.4, 0.9, 1.0, 1)
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all base-entity contact tests green.

- [ ] **Step 9: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/runtime/entities tests/unit/test_runtime_entities.gd
git commit -m "feat: add base entity classes (Entity/Collectible/Hazard/Enemy/Special)"
```

---

## Task 3: `EntityRegistry.instantiate`

**Files:**
- Modify: `src/core/entity_registry.gd` (add `scene` param + `instantiate`)
- Create: `tests/unit/test_entity_registry_instantiate.gd`

`register` gains an optional `scene: PackedScene`. `instantiate(type_id, pos, props)` instances the scene if one is set, otherwise builds a default base-class node by category. Unknown types return `null`.

- [ ] **Step 1: Write the failing test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_entity_registry_instantiate.gd`:

```gdscript
extends GutTest

func test_default_node_per_category():
	EntityRegistry.clear()
	EntityRegistry.register("candy", EntityRegistry.CATEGORY_ITEM, "Candy")
	EntityRegistry.register("spike", EntityRegistry.CATEGORY_HAZARD, "Spike")
	EntityRegistry.register("vort", EntityRegistry.CATEGORY_ENEMY, "Vort")
	EntityRegistry.register("door", EntityRegistry.CATEGORY_SPECIAL, "Door")

	var candy := EntityRegistry.instantiate("candy", Vector2(16, 0))
	assert_not_null(candy)
	assert_true(candy is Collectible)
	assert_eq(candy.position, Vector2(16, 0))
	assert_eq(candy.type_id, "candy")
	assert_true(candy.is_in_group("entity"))

	assert_true(EntityRegistry.instantiate("spike", Vector2.ZERO) is Hazard)
	assert_true(EntityRegistry.instantiate("vort", Vector2.ZERO) is Enemy)
	assert_true(EntityRegistry.instantiate("door", Vector2.ZERO) is Special)


func test_props_applied_via_setup():
	EntityRegistry.clear()
	EntityRegistry.register("candy", EntityRegistry.CATEGORY_ITEM, "Candy")
	var c: Collectible = EntityRegistry.instantiate("candy", Vector2.ZERO, {"score_value": 77})
	assert_eq(c.properties.get("score_value"), 77)


func test_unknown_type_returns_null():
	EntityRegistry.clear()
	assert_null(EntityRegistry.instantiate("does_not_exist", Vector2.ZERO))


func test_default_roster_instantiates_without_scenes():
	# autoload _ready registered the defaults; each must spawn a base-class node.
	for entry in EntityRegistry.get_palette_entries():
		var tid: String = entry["type_id"]
		var node := EntityRegistry.instantiate(tid, Vector2.ZERO)
		assert_not_null(node, "%s should instantiate" % tid)
		assert_true(node is Entity, "%s should be an Entity" % tid)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `instantiate` not found on `EntityRegistry`.

- [ ] **Step 3: Add `scene` binding + `instantiate` to `EntityRegistry`**

In `/Users/eugene/git/keen_reloaded/src/core/entity_registry.gd`, replace the `register` function with:

```gdscript
func register(type_id: String, category: String, label: String, properties: Array = [], scene: PackedScene = null) -> void:
	_entries[type_id] = {
		"type_id": type_id,
		"category": category,
		"label": label,
		"properties": properties,
		"scene": scene,
	}
```

Then append at the end of the file (after `clear`):

```gdscript


## Instantiate a node for `type_id` at `pos` with `props`. Uses the registered
## PackedScene if present, else a default base-class node by category. Adds the
## node to group "entity". Returns null for unknown types.
func instantiate(type_id: String, pos: Vector2, props: Dictionary = {}) -> Node2D:
	if not _entries.has(type_id):
		push_warning("EntityRegistry: unknown entity type '%s'" % type_id)
		return null
	var entry: Dictionary = _entries[type_id]
	var node: Node2D = null
	var scene: Variant = entry.get("scene", null)
	if scene != null and scene is PackedScene:
		node = (scene as PackedScene).instantiate()
	else:
		node = _default_node_for_category(String(entry.get("category", "")))
	if node == null:
		return null
	if node.has_method("setup"):
		node.setup(type_id, props)
	else:
		node.set("type_id", type_id)
		node.set("properties", props)
	node.position = pos
	node.add_to_group("entity")
	return node


func _default_node_for_category(category: String) -> Node2D:
	match category:
		CATEGORY_ENEMY:
			return Enemy.new()
		CATEGORY_ITEM:
			return Collectible.new()
		CATEGORY_HAZARD:
			return Hazard.new()
		CATEGORY_SPECIAL:
			return Special.new()
	return Entity.new()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all instantiate tests green (the pre-existing `test_entity_registry_data.gd` still passes — the new optional param is backward compatible).

- [ ] **Step 5: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/core/entity_registry.gd tests/unit/test_entity_registry_instantiate.gd
git commit -m "feat: add EntityRegistry.instantiate + scene binding"
```

---

## Task 4: `Player` (run / jump / pogo)

**Files:**
- Create: `src/runtime/player/player.gd`
- Create: `src/runtime/player/player.tscn`
- Create: `tests/unit/test_player.gd`

`CharacterBody2D` with gravity, run, jump (coyote + buffer), and a toggleable pogo (auto-bounce on landing). Exposes `add_score()` / `take_damage()` and joins group `"player"`. Movement *feel* is manual; this task GUT-tests only the score/health/group API.

- [ ] **Step 1: Write the failing test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_player.gd`:

```gdscript
extends GutTest

func test_score_accumulates():
	var p := Player.new()
	add_child(p)
	p.add_score(100)
	p.add_score(25)
	assert_eq(p.score, 125)

func test_take_damage_reduces_health():
	var p := Player.new()
	add_child(p)
	p.take_damage(1)
	assert_eq(p.health, 2)

func test_player_in_player_group():
	var p := Player.new()
	add_child(p)
	assert_true(p.is_in_group("player"))
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `Player` class not found.

- [ ] **Step 3: Implement `Player`**

Create `/Users/eugene/git/keen_reloaded/src/runtime/player/player.gd`:

```gdscript
class_name Player
extends CharacterBody2D
## Player avatar. Run, jump (with coyote time + jump buffer), and a toggle pogo
## stick (auto-bounce on landing while active). Exposes add_score()/take_damage()
## for entities. Movement constants are @export for in-editor tuning.

signal score_changed(score: int)
signal health_changed(health: int)
signal died

@export var gravity: float = 980.0
@export var run_speed: float = 120.0
@export var jump_velocity: float = 300.0
@export var pogo_bounce: float = 380.0
@export var max_fall: float = 480.0
@export var coyote_time: float = 0.10
@export var jump_buffer: float = 0.10

var score: int = 0
var health: int = 3

var _pogo: bool = false
var _coyote: float = 0.0
var _buffer: float = 0.0


func _ready() -> void:
	add_to_group("player")


func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta
	if velocity.y > max_fall:
		velocity.y = max_fall

	var dir := Input.get_axis("move_left", "move_right")
	velocity.x = dir * run_speed

	var on_floor := is_on_floor()
	_coyote = coyote_time if on_floor else _coyote - delta

	if Input.is_action_just_pressed("jump"):
		_buffer = jump_buffer
	else:
		_buffer -= delta

	# Normal jump (disabled while pogo is active).
	if _buffer > 0.0 and _coyote > 0.0 and not _pogo:
		velocity.y = -jump_velocity
		_buffer = 0.0
		_coyote = 0.0

	# Toggle pogo stick on P.
	if Input.is_action_just_pressed("pogo"):
		_pogo = not _pogo

	# While pogo active, bounce automatically on each landing.
	if _pogo and on_floor:
		velocity.y = -pogo_bounce

	move_and_slide()


func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)


func take_damage(amount: int) -> void:
	health -= amount
	health_changed.emit(health)
	if health <= 0:
		died.emit()
```

- [ ] **Step 4: Create the player scene**

Create `/Users/eugene/git/keen_reloaded/src/runtime/player/player.tscn`:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://src/runtime/player/player.gd" id="1_player"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_1"]
size = Vector2(12, 16)

[node name="Player" type="CharacterBody2D"]
collision_layer = 1
collision_mask = 4
script = ExtResource("1_player")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_1")

[node name="Visual" type="ColorRect" parent="."]
offset_left = -6.0
offset_top = -8.0
offset_right = 6.0
offset_bottom = 8.0
color = Color(0.3, 0.8, 1, 1)

[node name="Camera2D" type="Camera2D" parent="."]
position_smoothing_enabled = true
```

Note: `collision_layer = 1` (player bit), `collision_mask = 4` (tiles bit) so the player collides with the procedural solid TileSet. The ColorRect is the placeholder sprite; the Camera2D follows the player.

- [ ] **Step 5: Verify the project imports**

Run:
```bash
cd /Users/eugene/git/keen_reloaded
"/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot" --headless --import --quit 2>&1 | tail -3
```
Expected: exits cleanly.

- [ ] **Step 6: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — player score/health/group tests green.

- [ ] **Step 7: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/runtime/player tests/unit/test_player.gd
git commit -m "feat: add Player (run/jump/pogo) with score + health API"
```

---

## Task 5: `GameManager` — pending level, return scene, input actions

**Files:**
- Modify: `src/core/game_manager.gd`
- Create: `tests/unit/test_game_manager.gd`

Adds `pending_level` / `return_scene` slots for the Test ▶ round-trip and registers the player input actions in code (avoids fragile `project.godot` `[input]` editing).

- [ ] **Step 1: Write the failing test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_game_manager.gd`:

```gdscript
extends GutTest

func test_pending_level_round_trip():
	var ld := LevelData.new()
	ld.level_id = "t"
	GameManager.pending_level = ld
	assert_eq(GameManager.pending_level, ld)
	GameManager.pending_level = null

func test_return_scene_round_trip():
	var ps := PackedScene.new()
	GameManager.return_scene = ps
	assert_eq(GameManager.return_scene, ps)
	GameManager.return_scene = null

func test_input_actions_registered():
	# GameManager._ready runs at autoload load, before tests.
	assert_true(InputMap.has_action("move_left"))
	assert_true(InputMap.has_action("move_right"))
	assert_true(InputMap.has_action("jump"))
	assert_true(InputMap.has_action("pogo"))
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `pending_level` / `return_scene` not found (input actions may also be absent).

- [ ] **Step 3: Replace the `GameManager` stub**

Overwrite `/Users/eugene/git/keen_reloaded/src/core/game_manager.gd` with:

```gdscript
extends Node
## Top-level game state singleton (autoload). Holds the Test ▶ round-trip state
## and registers player input actions in code (so we don't hand-edit the fragile
## [input] section of project.godot). Expanded in later plans.

var pending_level: LevelData = null
var return_scene: PackedScene = null


func _ready() -> void:
	_ensure_input_actions()


func _ensure_input_actions() -> void:
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("pogo", KEY_P)


func _add_key_action(action_name: String, keycode: int) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action_name, ev)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — GameManager tests green.

- [ ] **Step 5: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/core/game_manager.gd tests/unit/test_game_manager.gd
git commit -m "feat: add GameManager pending_level/return_scene + input actions"
```

---

## Task 6: `LevelRuntime.build`

**Files:**
- Create: `src/runtime/level_runtime.gd`
- Create: `tests/unit/test_level_runtime.gd`

`LevelRuntime(Node2D).build(level)` builds the world: 3 `TileMapLayer`s (bg/fg/geo), spawns the player, spawns entities. Member vars `layers` (dict), `player`, `entities_spawned` expose the result for tests. `_ready()` auto-builds from `GameManager.pending_level` (used by Test ▶; the test sets it null to isolate `build()`).

- [ ] **Step 1: Write the failing test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_level_runtime.gd`:

```gdscript
extends GutTest

func _level() -> LevelData:
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.set_geometry_tile(0, 2, 1)
	ld.set_geometry_tile(1, 2, 1)
	ld.set_foreground_tile(2, 0, 3)
	ld.player_spawn = Vector2i(0, 1)
	ld.entities.append(EntityDef.new("candy", 3, 1))
	ld.entities.append(EntityDef.new("butler", 1, 0))
	return ld


func test_build_assembles_three_tile_layers():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child(rt)
	rt.build(_level())
	assert_eq(rt.layers.size(), 3)
	assert_true(rt.layers.has(LevelData.LAYER_GEOMETRY))
	assert_true(rt.layers.has(LevelData.LAYER_FOREGROUND))
	assert_true(rt.layers.has(LevelData.LAYER_BACKGROUND))


func test_build_sets_geometry_cells():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child(rt)
	rt.build(_level())
	var geo: TileMapLayer = rt.layers[LevelData.LAYER_GEOMETRY]
	assert_eq(geo.get_cell_atlas_coords(Vector2i(0, 2)), Vector2i(0, 0), "tile id 1 -> atlas (0,0)")
	assert_eq(geo.get_cell_source_id(Vector2i(0, 0)), -1, "empty cell has no source")


func test_build_spawns_player_and_entities():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child(rt)
	var lvl := _level()
	rt.build(lvl)
	assert_not_null(rt.player, "player spawned")
	assert_true(rt.player.is_in_group("player"))
	var ts := lvl.tile_size
	assert_eq(rt.player.position, Vector2(lvl.player_spawn) * float(ts), "player at spawn")
	assert_eq(rt.entities_spawned.size(), lvl.entities.size(), "all entities spawned")


func test_ready_auto_builds_from_pending_level():
	var lvl := _level()
	GameManager.pending_level = lvl
	var rt := LevelRuntime.new()
	add_child(rt)
	# _ready fired on add_child and should have built from pending_level.
	assert_eq(rt.layers.size(), 3)
	assert_not_null(rt.player)
	GameManager.pending_level = null
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `LevelRuntime` class not found.

- [ ] **Step 3: Implement `LevelRuntime`**

Create `/Users/eugene/git/keen_reloaded/src/runtime/level_runtime.gd`:

```gdscript
class_name LevelRuntime
extends Node2D
## Builds a playable scene from a LevelData. Creates 3 TileMapLayers from the
## level's tile arrays (geometry=solid TileSet w/ collision; fg/bg=decor TileSet),
## spawns the Player at player_spawn, and spawns every EntityDef via the registry.
## Test ▶ stashes the level in GameManager.pending_level, which _ready() consumes.

const RUNTIME_SCALE := 3

var layers: Dictionary = {}  # layer_name -> TileMapLayer
var player: Node2D = null
var entities_spawned: Array[Node2D] = []


func _ready() -> void:
	if GameManager != null and GameManager.pending_level != null:
		build(GameManager.pending_level)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		if GameManager != null and GameManager.return_scene != null:
			get_tree().change_scene_to_packed(GameManager.return_scene)


## Tear down any previous build and assemble the world from `level`.
func build(level: LevelData) -> void:
	_clear()
	scale = Vector2(RUNTIME_SCALE, RUNTIME_SCALE)
	var ts := level.tile_size
	var max_id := _max_tile_id(level)
	var solid := ProceduralTileSet.build(max_id, ts, true)
	var decor := ProceduralTileSet.build(max_id, ts, false)
	layers[LevelData.LAYER_BACKGROUND] = _add_tile_layer(level, LevelData.LAYER_BACKGROUND, decor)
	layers[LevelData.LAYER_FOREGROUND] = _add_tile_layer(level, LevelData.LAYER_FOREGROUND, decor)
	layers[LevelData.LAYER_GEOMETRY] = _add_tile_layer(level, LevelData.LAYER_GEOMETRY, solid)
	_spawn_player(level, ts)
	_spawn_entities(level, ts)


func _add_tile_layer(level: LevelData, layer_name: String, tileset: TileSet) -> TileMapLayer:
	var tml := TileMapLayer.new()
	tml.name = "Tiles_" + layer_name
	tml.tile_set = tileset
	var src_id: int = tileset.get_source_id(0) if tileset.get_source_count() > 0 else -1
	for y in range(level.height):
		for x in range(level.width):
			var id := level.get_tile(layer_name, x, y)
			if id > 0 and src_id >= 0:
				tml.set_cell(Vector2i(x, y), src_id, Vector2i(id - 1, 0))
	add_child(tml)
	return tml


func _spawn_player(level: LevelData, ts: int) -> void:
	var p := preload("res://src/runtime/player/player.tscn").instantiate()
	p.position = Vector2(level.player_spawn) * float(ts)
	add_child(p)
	player = p


func _spawn_entities(level: LevelData, ts: int) -> void:
	for def: EntityDef in level.entities:
		var node := EntityRegistry.instantiate(def.type, Vector2(def.x, def.y) * float(ts), def.properties)
		if node != null:
			add_child(node)
			entities_spawned.append(node)


func _max_tile_id(level: LevelData) -> int:
	var m := 0
	for arr in [level.geometry_tiles, level.foreground_tiles, level.background_tiles]:
		for v in arr:
			m = maxi(m, v)
	return m


func _clear() -> void:
	player = null
	entities_spawned.clear()
	layers.clear()
	for c in get_children():
		c.queue_free()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all LevelRuntime build tests green.

- [ ] **Step 5: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/runtime/level_runtime.gd tests/unit/test_level_runtime.gd
git commit -m "feat: add LevelRuntime.build (assembles tile world, player, entities)"
```

---

## Task 7: `level_runtime.tscn` + Esc-to-return

**Files:**
- Create: `src/runtime/level_runtime.tscn`

A bare scene root so `change_scene_to_packed` has a `PackedScene` to load. The Esc handler already exists in the script (Task 6).

- [ ] **Step 1: Create the scene**

Create `/Users/eugene/git/keen_reloaded/src/runtime/level_runtime.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/runtime/level_runtime.gd" id="1_runtime"]

[node name="LevelRuntime" type="Node2D"]
script = ExtResource("1_runtime")
```

- [ ] **Step 2: Verify the project imports**

Run:
```bash
cd /Users/eugene/git/keen_reloaded
"/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot" --headless --import --quit 2>&1 | tail -3
```
Expected: exits cleanly.

- [ ] **Step 3: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/runtime/level_runtime.tscn
git commit -m "feat: add LevelRuntime scene root"
```

---

## Task 8: Wire editor Test ▶ + restore on return

**Files:**
- Modify: `src/editor/level_editor.gd`

`test_run()` stashes the level + return scene and swaps to the runtime. `_ready()` restores the level from `GameManager.pending_level` when returning instead of starting blank.

- [ ] **Step 1: Update `_ready` to restore-or-new**

In `/Users/eugene/git/keen_reloaded/src/editor/level_editor.gd`, replace the `_ready` function:

```gdscript
func _ready() -> void:
	undo_stack = UndoStack.new()
	undo_stack.changed.connect(_on_history_changed)
	_restore_or_new()
	_build_ui()


## On a fresh open, start a blank level. When returning from Test ▶, restore the
## level that was stashed in GameManager.pending_level.
func _restore_or_new() -> void:
	if GameManager != null and GameManager.pending_level != null:
		level = GameManager.pending_level
		undo_stack.clear()
		selected_entity_index = -1
		_last_path = ""
	else:
		_new_level()
```

- [ ] **Step 2: Replace the `test_run` stub with the live swap**

In `/Users/eugene/git/keen_reloaded/src/editor/level_editor.gd`, replace the `test_run` function:

```gdscript
## Public entry used by the toolbar "Test ▶" button. Stashes the current level
## and swaps to the runtime scene for live play; Esc in the runtime returns here.
func test_run() -> void:
	GameManager.pending_level = level
	GameManager.return_scene = preload("res://src/editor/level_editor.tscn")
	get_tree().change_scene_to_packed(preload("res://src/runtime/level_runtime.tscn"))
```

- [ ] **Step 3: Verify the project imports + tests stay green**

Run:
```bash
cd /Users/eugene/git/keen_reloaded
"/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot" --headless --import --quit 2>&1 | tail -3
./tests/run_all.sh
```
Expected: import clean; all tests PASS (no new tests here — wiring is manual).

- [ ] **Step 4: Manual verification**

Run: `make edit` (or `godot -e`), open the editor from the main menu.
1. Paint a floor of geometry tiles along the bottom row.
2. Place a `candy` entity and set the player spawn.
3. Click **Test ▶** → the runtime launches; the floor renders as colored cells.
4. Run (A/D), jump (Space), toggle pogo (P) and bounce.
5. Press **Esc** → returns to the editor with the same level intact (tiles, entities, spawn all preserved).

- [ ] **Step 5: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/editor/level_editor.gd
git commit -m "feat: wire editor Test ▶ to runtime + restore level on return"
```

---

## Task 9: Integration test — spawn every registered entity type

**Files:**
- Create: `tests/unit/test_runtime_integration.gd`

Mirrors spec §9's integration expectation: `LevelRuntime` builds a level and spawns every registered entity type without error.

- [ ] **Step 1: Write the integration test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_runtime_integration.gd`:

```gdscript
extends GutTest

func test_build_spawns_every_registered_entity_type():
	GameManager.pending_level = null
	var ld := LevelData.new()
	ld.width = 16
	ld.height = 8
	ld.tile_size = 16
	ld.fill_blank()
	ld.player_spawn = Vector2i(1, 1)
	# Add one EntityDef per registered type, spaced along a row.
	var x := 2
	for entry in EntityRegistry.get_palette_entries():
		ld.entities.append(EntityDef.new(String(entry["type_id"]), x, 1))
		x += 1

	var rt := LevelRuntime.new()
	add_child(rt)
	rt.build(ld)

	assert_eq(rt.entities_spawned.size(), ld.entities.size(), "every entity spawned")
	# Each spawned node must be a real Entity on the tree.
	for node in rt.entities_spawned:
		assert_true(node is Entity)
		assert_true(node.is_inside_tree())
```

- [ ] **Step 2: Run the full suite**

Run: `./tests/run_all.sh`
Expected: ALL tests PASS across every file (procedural_tileset, runtime_entities, entity_registry_instantiate, player, game_manager, level_runtime, runtime_integration) plus the pre-Plan-3 suite.

- [ ] **Step 3: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add tests/unit/test_runtime_integration.gd
git commit -m "test: add runtime integration test (spawn all entity types)"
```

---

## Plan 3 Complete Criteria

- [ ] `ProceduralTileSet` builds solid (collision) + decor TileSets with no art (GUT).
- [ ] Base entity classes dispatch contact correctly (GUT): Collectible scores+frees, Hazard/Enemy damage, Enemy dies at 0.
- [ ] `EntityRegistry.instantiate` spawns every registered type by category; unknown → null (GUT).
- [ ] `Player` exposes score/health and joins group `"player"` (GUT); run/jump/pogo work (manual).
- [ ] `GameManager` holds `pending_level`/`return_scene` and registers input actions (GUT).
- [ ] `LevelRuntime.build` assembles 3 tile layers + player + entities from any `LevelData` (GUT).
- [ ] Editor **Test ▶** launches the runtime; **Esc** returns; level is restored intact (manual).
- [ ] Integration test: every registered entity type spawns without error (GUT).
- [ ] `./tests/run_all.sh` is green; `godot --headless --import --quit` is clean.
- [ ] All work committed to `main`.

## Next Plans (out of scope here)

- **Plan 4:** Keen 1 content — real tileset/art, full entity roster (vorticon, yorp, items, hazards), `shoot` ability, exit/special completion, first level authored via editor.
- **Plan 5:** Pack loading — `PackLoader` (res:// + user://), level-select menu, `GameManager` progression.
- **Plan 6:** Polish — audio, parallax, HUD, save/progression, gamepad mapping.
