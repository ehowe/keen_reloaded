# Plan 4 Gameplay Content — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish Plan 4 gameplay — concrete Keen 1 entities with patrol AI, the ammo-limited raygun + projectile system, exit/level-completion, a minimal HUD, and per-episode entity registration via a global union catalog.

**Architecture:** `Entity` becomes `CharacterBody2D` (contact via child `Area2D`); physics enemies add body collision + gravity. A new `Episode` system registers namespaced entity types into a pure `EntityRegistry` at boot. Player gains facing/ammo/shoot. Reaching an exit shows a completion overlay and returns to editor-or-menu.

**Tech Stack:** Godot 4.7, GDScript, GUT (vendored), existing autoloads (GameManager, PackLoader, EntityRegistry, TileSetRegistry).

**Spec:** `docs/superpowers/specs/2026-07-01-plan4-gameplay-content-design.md`

**Collision layers** (already in `project.godot`): player=1, enemies=2, tiles=4, items=8.

**Test command:** `./tests/run_all.sh`
**Import check:** `make import`

---

## File map

**Created:**
- `src/core/episode.gd` — `Episode` base (RefCounted)
- `src/episodes/keen1/episode.gd` — registers keen1.* types
- `src/runtime/entities/vorticon.gd` + `.tscn`
- `src/runtime/entities/yorp.gd` + `.tscn`
- `src/runtime/entities/butler.gd` + `.tscn`
- `src/runtime/entities/candy.gd` + `.tscn`
- `src/runtime/entities/ammo_pickup.gd` + `.tscn`
- `src/runtime/entities/exit_door.gd` + `.tscn`
- `src/runtime/player/projectile.gd` + `.tscn`
- `src/ui/completion_overlay.gd` + `.tscn`
- `tests/unit/test_episode.gd`, `test_projectile.gd`, `test_concrete_enemies.gd`, `test_pickups.gd`, `test_player_shoot.gd`, `test_completion.gd`, `test_hud.gd`

**Modified:**
- `src/runtime/entities/entity.gd` — Node2D → CharacterBody2D
- `src/runtime/entities/enemy.gd` — physics base + score award
- `src/runtime/entities/special.gd` — `level_completed` signal
- `src/runtime/entities/collectible.gd` — (unchanged logic; base)
- `src/core/entity_registry.gd` — drop hardcoded defaults → pure catalog
- `src/core/game_manager.gd` — episode discovery + `shoot` input action
- `src/runtime/player/player.gd` + `.tscn` — facing, ammo, shoot, Muzzle
- `src/runtime/level_runtime.gd` — elapsed timer, exit wiring, completion overlay, HUD
- `src/editor/level_editor.gd` — namespaced id defaults
- Several existing tests (migration)

---

## Task 1: Entity base → CharacterBody2D

**Files:**
- Modify: `src/runtime/entities/entity.gd`
- Test: `tests/unit/test_runtime_entities.gd` (existing, must stay green); add assertion

- [ ] **Step 1: Replace `entity.gd` with the CharacterBody2D base**

```gdscript
class_name Entity
extends CharacterBody2D
## Base class for all runtime entities. Builds a contact Area2D (collision_mask =
## player bit) + a procedural visual in _ready(). If the scene provides a child
## named "Visual", it is used as-is (the art seam); otherwise a fallback ColorRect
## is built. Subclasses override _handle_player() to react on contact.
##
## Base defaults to static-item collision (layer=items, mask=0); physics
## subclasses (Enemy) override _ready() to set body collision + add a shape.

signal player_touched(player: Node)

const TILE := 64

var type_id: String = ""
var properties: Dictionary = {}

var _area: Area2D


## Called by EntityRegistry.instantiate after constructing the node.
func setup(p_type_id: String, p_props: Dictionary) -> void:
	type_id = p_type_id
	properties = p_props
	# Apply editor-set tuning keys onto matching instance vars.
	for key in p_props:
		if get(key) != null:
			set(key, p_props[key])


func _ready() -> void:
	_build_contact()
	# Static-item defaults; physics subclasses override after calling super.
	collision_layer = 8  # items
	collision_mask = 0


func _build_contact() -> void:
	_area = Area2D.new()
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

- [ ] **Step 2: Add an assertion to `test_runtime_entities.gd`**

Append this test to `tests/unit/test_runtime_entities.gd`:

```gdscript
func test_entity_base_is_character_body():
	var e := Enemy.new()
	add_child(e)
	assert_true(e is CharacterBody2D, "Entity is now CharacterBody2D")
	var area := e.find_child("Area2D", true, false)
	assert_not_null(area, "contact Area2D built")
	assert_eq(area.collision_mask, 1, "contact Area2D masks the player bit")
```

- [ ] **Step 3: Run tests**

Run: `./tests/run_all.sh`
Expected: ALL PASS (contact logic unchanged; Enemy still resolves contacts via the child Area2D). The existing `Collectible.new()` / `Hazard.new()` / `Enemy.new()` tests pass because `_on_body_entered` + `_handle_player` are unchanged.

- [ ] **Step 4: Commit**

```bash
git add src/runtime/entities/entity.gd tests/unit/test_runtime_entities.gd
git commit -m "refactor: Entity base becomes CharacterBody2D (contact via child Area2D)"
```

---

## Task 2: Episode system + pure union catalog + shoot input

**Files:**
- Create: `src/core/episode.gd`
- Modify: `src/core/entity_registry.gd`
- Modify: `src/core/game_manager.gd`
- Create: `src/episodes/keen1/episode.gd`
- Modify (migration): `tests/unit/test_entity_registry_data.gd`, `tests/unit/test_entity_registry_instantiate.gd`, `tests/unit/test_editor_workflow.gd`, `tests/unit/test_level_runtime.gd`, `tests/unit/test_game_manager.gd`
- Create: `tests/unit/test_episode.gd`

- [ ] **Step 1: Create `src/core/episode.gd`**

```gdscript
class_name Episode
extends RefCounted
## A content module that registers its entity types into the global EntityRegistry
## catalog at boot. Episodes live under src/episodes/<id>/episode.gd and are
## auto-discovered by GameManager. type_ids are namespaced (e.g. "keen1.vorticon")
## so multiple episodes can coexist in one union catalog.

var id: String = ""
var title: String = ""


## Override: register this episode's entity types into `registry`.
func register_entities(_registry: Node) -> void:
	pass
```

- [ ] **Step 2: Make `entity_registry.gd` a pure catalog (drop hardcoded defaults)**

Replace the body of `src/core/entity_registry.gd` with:

```gdscript
extends Node
## Extensible entity catalog (autoload). A pure union catalog: episodes register
## their namespaced types at boot via GameManager._register_episodes(); nothing
## is hardcoded here. The editor palette reads get_palette_entries(); the runtime
## spawns via instantiate(type_id, pos, props).

const CATEGORY_ENEMY := "enemy"
const CATEGORY_ITEM := "item"
const CATEGORY_HAZARD := "hazard"
const CATEGORY_SPECIAL := "special"

var _entries: Dictionary = {}  # type_id -> { type_id, category, label, properties, scene }


## Register (or overwrite) one entity type.
func register(type_id: String, category: String, label: String, properties: Array = [], scene: PackedScene = null) -> void:
	_entries[type_id] = {
		"type_id": type_id,
		"category": category,
		"label": label,
		"properties": properties,
		"scene": scene,
	}


func has(type_id: String) -> bool:
	return _entries.has(type_id)


func get_entry(type_id: String) -> Dictionary:
	return _entries.get(type_id, {})


func get_palette_entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.assign(_entries.values())
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := String(a.get("category", ""))
		var cb := String(b.get("category", ""))
		if ca != cb:
			return ca < cb
		return String(a.get("label", "")) < String(b.get("label", "")))
	return list


func clear() -> void:
	_entries.clear()


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
	if scene is PackedScene:
		node = scene.instantiate()
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

- [ ] **Step 3: Update `game_manager.gd` (episode discovery + shoot action)**

Replace `src/core/game_manager.gd` with:

```gdscript
extends Node
## Top-level game state singleton (autoload). Registers player input actions in
## code and discovers + registers all episodes into the global EntityRegistry at
## boot. Holds the Test ▶ round-trip state.

const EPISODES_DIR := "res://src/episodes"

var pending_level: LevelData = null
var return_scene: PackedScene = null
var episodes: Array = []  # registered Episode metadata ({id, title})


func _ready() -> void:
	_ensure_input_actions()
	register_episodes()


## Scan src/episodes/*/episode.gd, instantiate each Episode, and register its
## entity types into the global catalog. Idempotent: re-registering overwrites
## (last-wins on type_id conflict). Tests call this in after_each to restore the
## default catalog after clear().
func register_episodes() -> void:
	var dir := DirAccess.open(EPISODES_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.dir_exists(name) and dir.file_exists("%s/episode.gd" % name):
			var path := "%s/%s/episode.gd" % [EPISODES_DIR, name]
			var EpScript: GDScript = load(path)
			if EpScript != null:
				var ep: Episode = EpScript.new()
				ep.register_entities(EntityRegistry)
				episodes.append({"id": ep.id, "title": ep.title})
		name = dir.get_next()
	dir.list_dir_end()


func _ensure_input_actions() -> void:
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("pogo", KEY_P)
	_add_key_action("shoot", KEY_X)


func _add_key_action(action_name: String, keycode: int) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action_name, ev)
```

- [ ] **Step 4: Create `src/episodes/keen1/episode.gd` (no scenes yet → default nodes)**

```gdscript
class_name Keen1Episode
extends Episode
## Registers the Keen 1 ("Marooned on Mars") entity roster into the global
## catalog. type_ids are namespaced "keen1.*". Scenes are bound as they are
## authored (enemy/item/exit tasks update the preload lines below).

func _init() -> void:
	id = "keen1"
	title = "Marooned on Mars"


func register_entities(registry: Node) -> void:
	registry.register("keen1.vorticon", registry.CATEGORY_ENEMY, "Vorticon")
	registry.register("keen1.yorp", registry.CATEGORY_ENEMY, "Yorp")
	registry.register("keen1.butler", registry.CATEGORY_HAZARD, "Butler Robot")
	registry.register("keen1.candy", registry.CATEGORY_ITEM, "Candy")
	registry.register("keen1.raygun", registry.CATEGORY_ITEM, "Raygun Ammo")
	registry.register("keen1.exit_door", registry.CATEGORY_SPECIAL, "Exit Door")
	registry.register("keen1.player_spawn", registry.CATEGORY_SPECIAL, "Player Spawn")
```

- [ ] **Step 5: Create `tests/unit/test_episode.gd`**

```gdscript
extends GutTest

func test_keen1_registers_expected_types():
	EntityRegistry.clear()
	Keen1Episode.new().register_entities(EntityRegistry)
	for tid in ["keen1.vorticon", "keen1.yorp", "keen1.butler", "keen1.candy",
			"keen1.raygun", "keen1.exit_door", "keen1.player_spawn"]:
		assert_true(EntityRegistry.has(tid), "%s registered" % tid)

func test_keen1_categories():
	EntityRegistry.clear()
	Keen1Episode.new().register_entities(EntityRegistry)
	assert_eq(EntityRegistry.get_entry("keen1.vorticon")["category"], EntityRegistry.CATEGORY_ENEMY)
	assert_eq(EntityRegistry.get_entry("keen1.butler")["category"], EntityRegistry.CATEGORY_HAZARD)
	assert_eq(EntityRegistry.get_entry("keen1.candy")["category"], EntityRegistry.CATEGORY_ITEM)
	assert_eq(EntityRegistry.get_entry("keen1.exit_door")["category"], EntityRegistry.CATEGORY_SPECIAL)

func test_player_spawn_has_no_scene():
	EntityRegistry.clear()
	Keen1Episode.new().register_entities(EntityRegistry)
	var entry: Dictionary = EntityRegistry.get_entry("keen1.player_spawn")
	assert_null(entry.get("scene", null), "player_spawn is a marker with no scene")

func after_each():
	GameManager.register_episodes()
```

- [ ] **Step 6: Migrate existing tests off `register_defaults()`**

In `tests/unit/test_entity_registry_data.gd` and `tests/unit/test_entity_registry_instantiate.gd`, replace the `after_each` body:

```gdscript
func after_each():
	GameManager.register_episodes()
```

In `tests/unit/test_editor_workflow.gd` line 8, replace `EntityRegistry.register_defaults()` with:

```gdscript
	GameManager.register_episodes()
```

- [ ] **Step 7: Migrate `test_level_runtime.gd` entity ids (these RESOLVE via the registry at build time)**

In `tests/unit/test_level_runtime.gd`, in `_level()`, change:

```gdscript
	ld.entities.append(EntityDef.new("keen1.candy", 3, 1))
	ld.entities.append(EntityDef.new("keen1.butler", 1, 0))
```

- [ ] **Step 8: Migrate `test_game_manager.gd` to assert the shoot action**

In `tests/unit/test_game_manager.gd`, append to `test_input_actions_registered`:

```gdscript
	assert_true(InputMap.has_action("shoot"))
```

- [ ] **Step 9: Run tests**

Run: `./tests/run_all.sh`
Expected: ALL PASS. The keen1 catalog is restored between scripts by `GameManager.register_episodes()`. Note: pure-data tests that store arbitrary type strings (`test_entity_def`, `test_editor_commands`, `test_editor_workflow`'s `AddEntityCmd`) keep their literal `"vorticon"`/`"candy"` — those are serialized data, never resolved via the registry, so they are intentionally left.

- [ ] **Step 10: Commit**

```bash
git add src/core/episode.gd src/core/entity_registry.gd src/core/game_manager.gd \
        src/episodes/keen1/episode.gd tests/unit/test_episode.gd \
        tests/unit/test_entity_registry_data.gd tests/unit/test_entity_registry_instantiate.gd \
        tests/unit/test_editor_workflow.gd tests/unit/test_level_runtime.gd \
        tests/unit/test_game_manager.gd
git commit -m "feat(core): per-episode union catalog + shoot input (keen1 registers namespaced types)"
```

---

## Task 3: Enemy physics base (gravity, patrol, score award)

**Files:**
- Modify: `src/runtime/entities/enemy.gd`
- Test: `tests/unit/test_runtime_entities.gd` (migrate + add)

- [ ] **Step 1: Replace `enemy.gd`**

```gdscript
class_name Enemy
extends Entity
## Physics-enabled enemy base. Applies gravity + patrol movement, turns at walls
## and (optionally) ledges, deals contact damage, and awards score_value to the
## player on death. Concrete enemies (Vorticon/Yorp/Butler) extend this and tune
## knobs or override _ai_tick() / _handle_player() / take_damage().

@export var gravity: float = 3920.0
@export var patrol_speed: float = 120.0
@export var max_fall: float = 1920.0
@export var turns_at_walls: bool = true
@export var turns_at_ledges: bool = true

var health: int = 1
var contact_damage: int = 1
var score_value: int = 100

var _dir: int = -1  # patrol facing: -1 left, +1 right


func _ready() -> void:
	super._ready()
	collision_layer = 2  # enemies
	collision_mask = 4   # tiles (gravity/patrol collide with floor)
	if not has_node("BodyShape"):
		var s := CollisionShape2D.new()
		s.name = "BodyShape"
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE * 0.8, TILE * 0.9)
		s.shape = rect
		add_child(s)
	if not has_node("LedgeProbe"):
		var rc := RayCast2D.new()
		rc.name = "LedgeProbe"
		rc.enabled = true
		rc.target_position = Vector2(_dir * TILE * 0.5, TILE * 0.6)
		add_child(rc)


func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta
	if velocity.y > max_fall:
		velocity.y = max_fall
	velocity.x = _dir * patrol_speed
	if turns_at_walls and is_on_wall():
		_dir = -_dir
	if turns_at_ledges:
		var rc := get_node_or_null("LedgeProbe") as RayCast2D
		if rc != null:
			rc.target_position = Vector2(_dir * TILE * 0.5, TILE * 0.6)
			rc.force_raycast_update()
			if is_on_floor() and not rc.is_colliding():
				_dir = -_dir
	_ai_tick(delta)
	move_and_slide()


## Subclass hook, called each physics frame just before move_and_slide().
func _ai_tick(_delta: float) -> void:
	pass


func _color() -> Color:
	return Color(0.9, 0.4, 0.6, 1)


func _handle_player(player: Node) -> void:
	if player.has_method("take_damage"):
		player.take_damage(contact_damage)


func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		var tree := get_tree()
		if tree != null:
			var p := tree.get_first_node_in_group("player")
			if p != null and p.has_method("add_score"):
				p.add_score(score_value)
		queue_free()
```

- [ ] **Step 2: Add a score-award test to `test_runtime_entities.gd`**

Append:

```gdscript
func test_enemy_death_awards_score_to_player():
	var e := Enemy.new()
	e.health = 1
	e.score_value = 300
	add_child(e)
	var p := _fake_player()
	e.take_damage(1)
	assert_eq(p.score, 300, "score awarded on death")
	assert_true(e.is_queued_for_deletion(), "enemy freed on death")
```

- [ ] **Step 3: Run tests**

Run: `./tests/run_all.sh`
Expected: ALL PASS. The existing `test_enemy_take_damage_reduces_health_and_frees_at_zero` still passes: with no player in the tree at that point, the score-award is a guarded no-op, and the enemy still frees at 0 health.

- [ ] **Step 4: Commit**

```bash
git add src/runtime/entities/enemy.gd tests/unit/test_runtime_entities.gd
git commit -m "feat(runtime): Enemy physics base — gravity, patrol, turn-at-walls/ledges, score award"
```

---

## Task 4: Concrete enemies — Vorticon, Yorp, Butler (+ scenes)

**Files:**
- Create: `src/runtime/entities/vorticon.gd` + `.tscn`
- Create: `src/runtime/entities/yorp.gd` + `.tscn`
- Create: `src/runtime/entities/butler.gd` + `.tscn`
- Modify: `src/episodes/keen1/episode.gd` (bind scenes)
- Test: `tests/unit/test_concrete_enemies.gd`

- [ ] **Step 1: Create `src/runtime/entities/vorticon.gd`**

```gdscript
class_name Vorticon
extends Enemy
## Keen 1 Vorticon: patrols and randomly hops, takes 3 hits, deadly on contact,
## high score on death.

@export var hop_force: float = 700.0
@export var hop_chance: float = 0.5  # expected hops per second


func _ready() -> void:
	super._ready()
	health = 3
	score_value = 300
	patrol_speed = 140.0


func _ai_tick(delta: float) -> void:
	if is_on_floor() and randf() < hop_chance * delta:
		velocity.y = -hop_force
```

- [ ] **Step 2: Create `src/runtime/entities/vorticon.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/runtime/entities/vorticon.gd" id="1_vort"]

[node name="Vorticon" type="CharacterBody2D"]
script = ExtResource("1_vort")

[node name="Visual" type="ColorRect" parent="."]
offset_left = -32.0
offset_top = -32.0
offset_right = 32.0
offset_bottom = 32.0
color = Color(0.85, 0.3, 0.3, 1)
```

- [ ] **Step 3: Create `src/runtime/entities/yorp.gd`**

```gdscript
class_name Yorp
extends Enemy
## Keen 1 Yorp: slow patrol; on contact knocks the player back and deals minor
## damage; 1 hit to defeat.

@export var knockback_x: float = 400.0
@export var knockback_y: float = 300.0


func _ready() -> void:
	super._ready()
	health = 1
	score_value = 100
	patrol_speed = 70.0
	contact_damage = 1


func _handle_player(player: Node) -> void:
	var d := 1
	if player is CharacterBody2D:
		d = signi(player.global_position.x - global_position.x)
		player.velocity = Vector2(d * knockback_x, -knockback_y)
	if player.has_method("take_damage"):
		player.take_damage(contact_damage)
```

- [ ] **Step 4: Create `src/runtime/entities/yorp.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/runtime/entities/yorp.gd" id="1_yorp"]

[node name="Yorp" type="CharacterBody2D"]
script = ExtResource("1_yorp")

[node name="Visual" type="ColorRect" parent="."]
offset_left = -32.0
offset_top = -32.0
offset_right = 32.0
offset_bottom = 32.0
color = Color(0.95, 0.6, 0.2, 1)
```

- [ ] **Step 5: Create `src/runtime/entities/butler.gd`**

```gdscript
class_name Butler
extends Enemy
## Butler Robot: fast patrol hazard. ARMORED — projectiles do nothing (take_damage
## is a no-op), so it cannot be defeated by shooting.


func _ready() -> void:
	super._ready()
	health = 1
	score_value = 0
	patrol_speed = 220.0
	contact_damage = 1


## Armored: ignore all projectile damage.
func take_damage(_amount: int) -> void:
	pass
```

- [ ] **Step 6: Create `src/runtime/entities/butler.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/runtime/entities/butler.gd" id="1_but"]

[node name="Butler" type="CharacterBody2D"]
script = ExtResource("1_but")

[node name="Visual" type="ColorRect" parent="."]
offset_left = -32.0
offset_top = -32.0
offset_right = 32.0
offset_bottom = 32.0
color = Color(0.5, 0.5, 0.55, 1)
```

- [ ] **Step 7: Bind enemy scenes in `src/episodes/keen1/episode.gd`**

Update `register_entities` to preload + bind the three enemy scenes:

```gdscript
func register_entities(registry: Node) -> void:
	var vorticon := preload("res://src/runtime/entities/vorticon.tscn")
	var yorp := preload("res://src/runtime/entities/yorp.tscn")
	var butler := preload("res://src/runtime/entities/butler.tscn")
	registry.register("keen1.vorticon", registry.CATEGORY_ENEMY, "Vorticon", [], vorticon)
	registry.register("keen1.yorp", registry.CATEGORY_ENEMY, "Yorp", [], yorp)
	registry.register("keen1.butler", registry.CATEGORY_HAZARD, "Butler Robot", [], butler)
	registry.register("keen1.candy", registry.CATEGORY_ITEM, "Candy")
	registry.register("keen1.raygun", registry.CATEGORY_ITEM, "Raygun Ammo")
	registry.register("keen1.exit_door", registry.CATEGORY_SPECIAL, "Exit Door")
	registry.register("keen1.player_spawn", registry.CATEGORY_SPECIAL, "Player Spawn")
```

- [ ] **Step 8: Create `tests/unit/test_concrete_enemies.gd`**

```gdscript
extends GutTest

class FakeKinematicPlayer extends CharacterBody2D:
	var health: int = 3
	var score: int = 0
	func _ready() -> void:
		add_to_group("player")
	func take_damage(amount: int) -> void:
		health -= amount
	func add_score(amount: int) -> void:
		score += amount


func _fake_player() -> FakeKinematicPlayer:
	var p := FakeKinematicPlayer.new()
	add_child(p)
	return p


func test_vorticon_has_three_hp_and_awards_score():
	var v: Vorticon = add_child_autofree(load("res://src/runtime/entities/vorticon.tscn").instantiate())
	assert_eq(v.health, 3, "vorticon starts at 3 hp")
	v.score_value = 300
	var p := _fake_player()
	v.take_damage(1)
	assert_eq(v.health, 2)
	assert_false(v.is_queued_for_deletion(), "alive after 1 hit")
	v.take_damage(1)
	v.take_damage(1)
	assert_eq(p.score, 300, "score awarded on third hit")
	assert_true(v.is_queued_for_deletion(), "freed at 0 hp")


func test_butler_is_armored():
	var b: Butler = add_child_autofree(load("res://src/runtime/entities/butler.tscn").instantiate())
	b.take_damage(5)
	assert_false(b.is_queued_for_deletion(), "armored butler ignores damage")
	assert_eq(b.health, 1, "health unchanged")


func test_yorp_knockback_and_damage():
	var y: Yorp = add_child_autofree(load("res://src/runtime/entities/yorp.tscn").instantiate())
	y.global_position = Vector2(100, 0)
	var p := _fake_player()
	p.global_position = Vector2(200, 0)  # player to the right -> knockback +x
	y._handle_player(p)
	assert_gt(p.velocity.x, 0, "knocked right")
	assert_eq(p.health, 2, "took 1 contact damage")


func after_each():
	GameManager.register_episodes()
```

- [ ] **Step 9: Run tests**

Run: `./tests/run_all.sh`
Expected: ALL PASS.

- [ ] **Step 10: Commit**

```bash
git add src/runtime/entities/vorticon.gd src/runtime/entities/vorticon.tscn \
        src/runtime/entities/yorp.gd src/runtime/entities/yorp.tscn \
        src/runtime/entities/butler.gd src/runtime/entities/butler.tscn \
        src/episodes/keen1/episode.gd tests/unit/test_concrete_enemies.gd
git commit -m "feat(entities): Vorticon/Yorp/Butler concrete enemies + scenes"
```

---

## Task 5: Projectile system

**Files:**
- Create: `src/runtime/player/projectile.gd` + `.tscn`
- Test: `tests/unit/test_projectile.gd`

- [ ] **Step 1: Create `src/runtime/player/projectile.gd`**

```gdscript
class_name Projectile
extends Area2D
## Raygun bolt. Linear motion in the launch direction; despawns on lifetime
## expiry, on hitting an enemy (deals 1 damage), or on hitting a wall/tile.
## Passes through items (entities without take_damage).

@export var speed: float = 600.0
@export var lifetime: float = 2.0

var velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	if body_entered.is_connected(_on_body_entered) == false:
		body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


## Launch in facing direction (dir = +1 right / -1 left).
func launch(dir: int) -> void:
	velocity = Vector2(signi(dir) * speed, 0.0)


func _on_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		body.take_damage(1)
		queue_free()
	elif not body.is_in_group("entity"):
		queue_free()
	# else: an entity without take_damage (e.g. an item) -> pass through
```

- [ ] **Step 2: Create `src/runtime/player/projectile.tscn`**

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://src/runtime/player/projectile.gd" id="1_proj"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_1"]
size = Vector2(16, 8)

[node name="Projectile" type="Area2D"]
collision_layer = 0
collision_mask = 6
script = ExtResource("1_proj")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_1")

[node name="Visual" type="ColorRect" parent="."]
offset_left = -8.0
offset_top = -4.0
offset_right = 8.0
offset_bottom = 4.0
color = Color(1, 1, 0.4, 1)
```

- [ ] **Step 3: Create `tests/unit/test_projectile.gd`**

```gdscript
extends GutTest

class StubEnemy extends Node:
	var hp: int = 1
	var damaged: bool = false
	func take_damage(_a: int) -> void:
		damaged = true


func _new_proj() -> Projectile:
	var p: Projectile = add_child_autofree(load("res://src/runtime/player/projectile.tscn").instantiate())
	return p


func test_lifetime_expiry_frees():
	var p := _new_proj()
	p.lifetime = 0.1
	p._physics_process(0.2)
	assert_true(p.is_queued_for_deletion(), "despawns when lifetime runs out")


func test_enemy_hit_deals_damage_and_frees():
	var p := _new_proj()
	var e := StubEnemy.new()
	add_child(e)
	p._on_body_entered(e)
	assert_true(e.damaged, "enemy took damage")
	assert_true(p.is_queued_for_deletion(), "projectile freed after hit")


func test_tile_hit_frees():
	var p := _new_proj()
	var wall := StaticBody2D.new()  # not in group "entity", no take_damage
	add_child(wall)
	p._on_body_entered(wall)
	assert_true(p.is_queued_for_deletion(), "despawns on wall")


func test_item_passes_through():
	var p := _new_proj()
	var item := Node2D.new()
	item.add_to_group("entity")  # entity without take_damage -> pass through
	add_child(item)
	p._on_body_entered(item)
	assert_false(p.is_queued_for_deletion(), "passes through items")


func test_launch_sets_velocity_from_dir():
	var p := _new_proj()
	p.launch(1)
	assert_gt(p.velocity.x, 0, "right launch")
	p.launch(-1)
	assert_lt(p.velocity.x, 0, "left launch")
```

- [ ] **Step 4: Run tests**

Run: `./tests/run_all.sh`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add src/runtime/player/projectile.gd src/runtime/player/projectile.tscn tests/unit/test_projectile.gd
git commit -m "feat(runtime): raygun projectile (kill enemies, despawn on wall/lifetime)"
```

---

## Task 6: Player shoot + ammo + facing

**Files:**
- Modify: `src/runtime/player/player.gd`
- Modify: `src/runtime/player/player.tscn` (add Muzzle)
- Test: `tests/unit/test_player_shoot.gd`

- [ ] **Step 1: Replace `src/runtime/player/player.gd`**

```gdscript
class_name Player
extends CharacterBody2D
## Player avatar. Run, jump (coyote + buffer), toggle pogo, and shoot the raygun
## (ammo-limited) in the facing direction. Exposes add_score()/add_ammo()/
## take_damage() for entities. Movement constants are @export for tuning.

signal score_changed(score: int)
signal health_changed(health: int)
signal ammo_changed(ammo: int)
signal died

const PROJECTILE := preload("res://src/runtime/player/projectile.tscn")

@export var gravity: float = 3920.0
@export var run_speed: float = 480.0
@export var jump_velocity: float = 1200.0
@export var pogo_bounce: float = 1520.0
@export var max_fall: float = 1920.0
@export var coyote_time: float = 0.10
@export var jump_buffer: float = 0.10
@export var max_ammo: int = 5
@export var projectile_speed: float = 600.0

var score: int = 0
var health: int = 3
var ammo: int = 0

var _facing: int = 1
var _pogo: bool = false
var _coyote: float = 0.0
var _buffer: float = 0.0


func _ready() -> void:
	add_to_group("player")
	ammo = max_ammo
	ammo_changed.emit(ammo)


func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta
	if velocity.y > max_fall:
		velocity.y = max_fall

	var dir := Input.get_axis("move_left", "move_right")
	velocity.x = dir * run_speed
	if dir != 0:
		_facing = signi(dir)

	var on_floor := is_on_floor()
	_coyote = coyote_time if on_floor else _coyote - delta

	if Input.is_action_just_pressed("jump"):
		_buffer = jump_buffer
	else:
		_buffer -= delta

	if _buffer > 0.0 and _coyote > 0.0 and not _pogo:
		velocity.y = -jump_velocity
		_buffer = 0.0
		_coyote = 0.0

	if Input.is_action_just_pressed("pogo"):
		_pogo = not _pogo

	if _pogo and on_floor:
		velocity.y = -pogo_bounce

	if Input.is_action_just_pressed("shoot"):
		shoot()

	move_and_slide()


## Fire a projectile from the Muzzle in the facing direction (if ammo remains).
func shoot() -> void:
	if ammo <= 0:
		return
	var muzzle := get_node_or_null("Muzzle") as Marker2D
	var origin: Vector2 = muzzle.global_position if muzzle != null else global_position
	var proj: Node2D = PROJECTILE.instantiate()
	var host: Node = get_parent() if get_parent() != null else get_tree().current_scene
	host.add_child(proj)
	proj.global_position = origin
	if proj.has_method("launch"):
		proj.launch(_facing)
	ammo -= 1
	ammo_changed.emit(ammo)


func set_camera_bounds(rect: Rect2) -> void:
	var cam := get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	cam.limit_left = int(rect.position.x)
	cam.limit_top = int(rect.position.y)
	cam.limit_right = int(rect.end.x)
	cam.limit_bottom = int(rect.end.y)


func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)


func add_ammo(amount: int) -> void:
	ammo = clampi(ammo + amount, 0, max_ammo)
	ammo_changed.emit(ammo)


func take_damage(amount: int) -> void:
	health -= amount
	health_changed.emit(health)
	if health <= 0:
		died.emit()
```

- [ ] **Step 2: Add a Muzzle Marker2D to `player.tscn`**

Insert this node before the closing of `src/runtime/player/player.tscn` (after the Camera2D node):

```
[node name="Muzzle" type="Marker2D" parent="."]
position = Vector2(32, 0)
```

- [ ] **Step 3: Create `tests/unit/test_player_shoot.gd`**

```gdscript
extends GutTest

func _new_player() -> Player:
	var p := Player.new()
	add_child(p)
	return p


func test_ammo_inits_to_max():
	var p := _new_player()
	assert_eq(p.ammo, p.max_ammo, "ammo starts at max")


func test_shoot_spawns_projectile_and_decrements():
	var host := Node2D.new()
	add_child(host)
	var p := Player.new()
	host.add_child(p)  # parent = host so the projectile lands as a sibling
	var before := host.get_child_count()
	p.shoot()
	assert_eq(p.ammo, p.max_ammo - 1, "ammo decremented")
	assert_eq(host.get_child_count(), before + 1, "projectile spawned as sibling")
	var proj := host.get_child(host.get_child_count() - 1)
	assert_true(proj is Projectile, "spawned node is a Projectile")


func test_no_shoot_at_zero_ammo():
	var host := Node2D.new()
	add_child(host)
	var p := Player.new()
	host.add_child(p)
	p.ammo = 0
	var before := host.get_child_count()
	p.shoot()
	assert_eq(host.get_child_count(), before, "no projectile spawned at 0 ammo")


func test_shoot_uses_facing():
	var host := Node2D.new()
	add_child(host)
	var p := Player.new()
	host.add_child(p)
	p._facing = -1
	p.shoot()
	var proj := host.get_child(host.get_child_count() - 1) as Projectile
	assert_lt(proj.velocity.x, 0, "left-facing shot moves left")


func test_add_ammo_clamps_to_max():
	var p := _new_player()
	p.ammo = p.max_ammo
	p.add_ammo(10)
	assert_eq(p.ammo, p.max_ammo, "clamped to max_ammo")
```

- [ ] **Step 4: Run tests**

Run: `./tests/run_all.sh`
Expected: ALL PASS. The existing `test_player.gd` (score/health/group) still passes.

- [ ] **Step 5: Commit**

```bash
git add src/runtime/player/player.gd src/runtime/player/player.tscn tests/unit/test_player_shoot.gd
git commit -m "feat(player): ammo-limited raygun shoot + facing tracking + Muzzle"
```

---

## Task 7: Pickups — Candy scene + AmmoPickup (+ bind)

**Files:**
- Create: `src/runtime/entities/candy.gd` + `.tscn`
- Create: `src/runtime/entities/ammo_pickup.gd` + `.tscn`
- Modify: `src/episodes/keen1/episode.gd` (bind candy + raygun)
- Test: `tests/unit/test_pickups.gd`

- [ ] **Step 1: Create `src/runtime/entities/candy.gd`**

```gdscript
class_name Candy
extends Collectible
## Keen 1 candy bar — a score pickup (Collectible scene for the future art seam).


func _ready() -> void:
	super._ready()
	score_value = 100
```

- [ ] **Step 2: Create `src/runtime/entities/candy.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/runtime/entities/candy.gd" id="1_candy"]

[node name="Candy" type="CharacterBody2D"]
script = ExtResource("1_candy")

[node name="Visual" type="ColorRect" parent="."]
offset_left = -16.0
offset_top = -16.0
offset_right = 16.0
offset_bottom = 16.0
color = Color(1, 0.85, 0.2, 1)
```

- [ ] **Step 3: Create `src/runtime/entities/ammo_pickup.gd`**

```gdscript
class_name AmmoPickup
extends Collectible
## Raygun ammo pickup. Grants ammo_value to the player on contact, then frees.


@export var ammo_value: int = 5


func _handle_player(player: Node) -> void:
	if player.has_method("add_ammo"):
		player.add_ammo(ammo_value)
	queue_free()
```

- [ ] **Step 4: Create `src/runtime/entities/ammo_pickup.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/runtime/entities/ammo_pickup.gd" id="1_ammo"]

[node name="AmmoPickup" type="CharacterBody2D"]
script = ExtResource("1_ammo")

[node name="Visual" type="ColorRect" parent="."]
offset_left = -16.0
offset_top = -16.0
offset_right = 16.0
offset_bottom = 16.0
color = Color(0.3, 0.9, 0.4, 1)
```

- [ ] **Step 5: Bind pickups in `src/episodes/keen1/episode.gd`**

Add preload + scene args for candy and raygun (keep the existing enemy lines unchanged):

```gdscript
func register_entities(registry: Node) -> void:
	var vorticon := preload("res://src/runtime/entities/vorticon.tscn")
	var yorp := preload("res://src/runtime/entities/yorp.tscn")
	var butler := preload("res://src/runtime/entities/butler.tscn")
	var candy := preload("res://src/runtime/entities/candy.tscn")
	var raygun := preload("res://src/runtime/entities/ammo_pickup.tscn")
	registry.register("keen1.vorticon", registry.CATEGORY_ENEMY, "Vorticon", [], vorticon)
	registry.register("keen1.yorp", registry.CATEGORY_ENEMY, "Yorp", [], yorp)
	registry.register("keen1.butler", registry.CATEGORY_HAZARD, "Butler Robot", [], butler)
	registry.register("keen1.candy", registry.CATEGORY_ITEM, "Candy", [], candy)
	registry.register("keen1.raygun", registry.CATEGORY_ITEM, "Raygun Ammo", [], raygun)
	registry.register("keen1.exit_door", registry.CATEGORY_SPECIAL, "Exit Door")
	registry.register("keen1.player_spawn", registry.CATEGORY_SPECIAL, "Player Spawn")
```

- [ ] **Step 6: Create `tests/unit/test_pickups.gd`**

```gdscript
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


func test_candy_awards_score():
	var c: Candy = add_child_autofree(load("res://src/runtime/entities/candy.tscn").instantiate())
	assert_eq(c.score_value, 100)
	var p := FakePlayer.new()
	add_child(p)
	c._on_body_entered(p)
	assert_eq(p.score, 100)
	assert_true(c.is_queued_for_deletion())


func test_raygun_grants_ammo():
	var r: AmmoPickup = add_child_autofree(load("res://src/runtime/entities/ammo_pickup.tscn").instantiate())
	assert_eq(r.ammo_value, 5)
	var p := FakePlayer.new()
	p.ammo = 1
	add_child(p)
	r._on_body_entered(p)
	assert_eq(p.ammo, 5, "ammo granted and clamped to max")
	assert_true(r.is_queued_for_deletion(), "pickup frees after use")


func after_each():
	GameManager.register_episodes()
```

- [ ] **Step 7: Run tests**

Run: `./tests/run_all.sh`
Expected: ALL PASS.

- [ ] **Step 8: Commit**

```bash
git add src/runtime/entities/candy.gd src/runtime/entities/candy.tscn \
        src/runtime/entities/ammo_pickup.gd src/runtime/entities/ammo_pickup.tscn \
        src/episodes/keen1/episode.gd tests/unit/test_pickups.gd
git commit -m "feat(entities): Candy + Raygun ammo pickups + scenes"
```

---

## Task 8: Exit door + level completion

**Files:**
- Modify: `src/runtime/entities/special.gd` (signal)
- Create: `src/runtime/entities/exit_door.gd` + `.tscn`
- Create: `src/ui/completion_overlay.gd` + `.tscn`
- Modify: `src/runtime/level_runtime.gd` (elapsed, exit wiring, overlay)
- Modify: `src/episodes/keen1/episode.gd` (bind exit)
- Test: `tests/unit/test_completion.gd`

- [ ] **Step 1: Add a `level_completed` signal to `special.gd`**

Replace `src/runtime/entities/special.gd`:

```gdscript
class_name Special
extends Entity
## Base for exits / triggers / doors. Emits `level_completed` (LevelRuntime
## connects it to show the completion overlay). Default is a visible no-op.


signal level_completed

func _color() -> Color:
	return Color(0.4, 0.9, 1.0, 1)
```

- [ ] **Step 2: Create `src/runtime/entities/exit_door.gd`**

```gdscript
class_name ExitDoor
extends Special
## Level exit. On player contact, emits level_completed exactly once.


var _triggered: bool = false


func _handle_player(_player: Node) -> void:
	if _triggered:
		return
	_triggered = true
	level_completed.emit()
```

- [ ] **Step 3: Create `src/runtime/entities/exit_door.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/runtime/entities/exit_door.gd" id="1_exit"]

[node name="ExitDoor" type="CharacterBody2D"]
script = ExtResource("1_exit")

[node name="Visual" type="ColorRect" parent="."]
offset_left = -32.0
offset_top = -48.0
offset_right = 32.0
offset_bottom = 48.0
color = Color(0.4, 0.9, 1.0, 1)
```

- [ ] **Step 4: Create `src/ui/completion_overlay.gd`**

```gdscript
class_name CompletionOverlay
extends Control
## Full-screen "Level Complete" overlay shown on exit. Runs under pause
## (process_mode = ALWAYS) so it can receive input while the tree is frozen.
## Emits `dismissed` on any key/mouse press; LevelRuntime returns to the editor
## (Test ▶) or main menu.

signal dismissed

func _unhandled_input(event: InputEvent) -> void:
	var key := event is InputEventKey and event.pressed and not event.echo
	var click := event is InputEventMouseButton and event.pressed
	if key or click:
		dismissed.emit()
		get_viewport().set_input_as_handled()
```

- [ ] **Step 5: Create `src/ui/completion_overlay.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/completion_overlay.gd" id="1_ov"]

[node name="CompletionPanel" type="Control"]
process_mode = 3
layout_mode = 3
anchors_preset = 15
script = ExtResource("1_ov")

[node name="Label" type="Label" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -200.0
offset_top = -80.0
offset_right = 200.0
offset_bottom = 80.0
horizontal_alignment = 1
vertical_alignment = 1
text = "Level Complete!"
```

- [ ] **Step 6: Update `level_runtime.gd` for completion + elapsed timer**

In `src/runtime/level_runtime.gd`, add the elapsed/completion state and wire the exit signal. Make these changes:

Add new vars near the top (after `var entities_spawned`):

```gdscript
var elapsed: float = 0.0
var _completed: bool = false
```

Add a `_process` function (if none exists) and the completion methods. Add near the `_unhandled_input` function:

```gdscript
func _process(delta: float) -> void:
	if not _completed:
		elapsed += delta
```

In `_spawn_entities`, connect the exit signal after `add_child(node)`:

```gdscript
func _spawn_entities(level: LevelData, ts: int) -> void:
	for def: EntityDef in level.entities:
		var node := EntityRegistry.instantiate(def.type, Vector2(def.x, def.y) * float(ts), def.properties)
		if node != null:
			add_child(node)
			entities_spawned.append(node)
			if node.has_signal("level_completed"):
				node.level_completed.connect(_on_level_completed)
```

Add the completion handlers (e.g. after `_spawn_entities`):

```gdscript
func _on_level_completed() -> void:
	if _completed:
		return
	_completed = true
	# Screen-space layer that keeps processing under pause (process_mode = ALWAYS).
	var layer := CanvasLayer.new()
	layer.name = "CompletionOverlay"
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var panel: CompletionOverlay = preload("res://src/ui/completion_overlay.tscn").instantiate()
	layer.add_child(panel)
	var score := 0
	if is_instance_valid(player) and player.get("score") != null:
		score = int(player.score)
	panel.get_node("Label").text = "Level Complete!\nScore: %d\nTime: %.1f s\n\nPress any key / Esc" % [score, elapsed]
	panel.dismissed.connect(_on_completion_dismissed)
	get_tree().paused = true


func _on_completion_dismissed() -> void:
	get_tree().paused = false
	if GameManager != null and GameManager.return_scene != null:
		get_tree().change_scene_to_packed(GameManager.return_scene)
	else:
		get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")
```

Also reset `_completed`/`elapsed` in `_clear()`:

```gdscript
func _clear() -> void:
	player = null
	entities_spawned.clear()
	layers.clear()
	_level = null
	_tile_size = 64
	_completed = false
	elapsed = 0.0
	for c in get_children():
		c.queue_free()
```

- [ ] **Step 7: Bind exit in `src/episodes/keen1/episode.gd`**

Add `var exit_door := preload("res://src/runtime/entities/exit_door.tscn")` and change its register line to pass the scene:

```gdscript
	registry.register("keen1.exit_door", registry.CATEGORY_SPECIAL, "Exit Door", [], exit_door)
```

- [ ] **Step 8: Create `tests/unit/test_completion.gd`**

```gdscript
extends GutTest

func _level_with_exit() -> LevelData:
	var ld := LevelData.new()
	ld.width = 8
	ld.height = 4
	ld.tile_size = 16
	ld.fill_blank()
	ld.player_spawn = Vector2i(1, 1)
	ld.entities.append(EntityDef.new("keen1.exit_door", 6, 1))
	return ld


func test_exit_door_emits_once():
	var door: ExitDoor = add_child_autofree(load("res://src/runtime/entities/exit_door.tscn").instantiate())
	var count := 0
	door.level_completed.connect(func() -> void: count += 1)
	var stub := Node.new()
	stub.add_to_group("player")
	add_child(stub)
	door._handle_player(stub)
	door._handle_player(stub)  # second contact must not re-emit
	assert_eq(count, 1, "level_completed emitted exactly once")


func test_runtime_completion_shows_overlay_and_pauses():
	GameManager.pending_level = null
	GameManager.return_scene = preload("res://src/editor/level_editor.tscn")
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level_with_exit())
	assert_false(rt._completed, "not completed before exit")
	rt._on_level_completed()
	assert_true(rt._completed, "marked completed")
	assert_not_null(rt.find_child("CompletionOverlay", true, false), "overlay added")
	assert_true(get_tree().paused, "tree paused")
	get_tree().paused = false  # reset for the test harness
	GameManager.return_scene = null


func after_each():
	GameManager.register_episodes()
```

- [ ] **Step 9: Run tests**

Run: `./tests/run_all.sh`
Expected: ALL PASS.

- [ ] **Step 10: Commit**

```bash
git add src/runtime/entities/special.gd src/runtime/entities/exit_door.gd src/runtime/entities/exit_door.tscn \
        src/ui/completion_overlay.gd src/ui/completion_overlay.tscn src/runtime/level_runtime.gd \
        src/episodes/keen1/episode.gd tests/unit/test_completion.gd
git commit -m "feat(runtime): exit door + level completion overlay (score/time, pause, return)"
```

---

## Task 9: Minimal in-play HUD

**Files:**
- Modify: `src/runtime/level_runtime.gd` (build HUD, connect player signals)
- Test: `tests/unit/test_hud.gd`

- [ ] **Step 1: Add HUD building to `level_runtime.gd`**

In `_spawn_player`, after `player = p` and the camera-bounds call, build the HUD. Replace `_spawn_player` with:

```gdscript
func _spawn_player(level: LevelData, ts: int) -> void:
	var p := preload("res://src/runtime/player/player.tscn").instantiate()
	p.position = Vector2(level.player_spawn) * float(ts)
	add_child(p)
	player = p
	var world_bounds := Rect2(
		Vector2.ZERO,
		Vector2(level.width * ts, level.height * ts) * RUNTIME_SCALE
	)
	p.set_camera_bounds(world_bounds)
	_build_hud(p)


func _build_hud(p: Node) -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var label := Label.new()
	label.name = "HUDLabel"
	label.position = Vector2(12, 8)
	label.text = _hud_text(int(p.get("score")), int(p.get("ammo")), int(p.get("health")))
	layer.add_child(label)
	if p.has_signal("score_changed"):
		p.score_changed.connect(func(s: int) -> void: label.text = _hud_text(s, int(p.get("ammo")), int(p.get("health"))))
	if p.has_signal("ammo_changed"):
		p.ammo_changed.connect(func(a: int) -> void: label.text = _hud_text(int(p.get("score")), a, int(p.get("health"))))
	if p.has_signal("health_changed"):
		p.health_changed.connect(func(h: int) -> void: label.text = _hud_text(int(p.get("score")), int(p.get("ammo")), h))


func _hud_text(score: int, ammo: int, hp: int) -> String:
	return "Score: %d   Ammo: %d   HP: %d" % [score, ammo, hp]
```

- [ ] **Step 2: Create `tests/unit/test_hud.gd`**

```gdscript
extends GutTest

func test_build_creates_hud():
	GameManager.pending_level = null
	var ld := LevelData.new()
	ld.width = 6
	ld.height = 4
	ld.tile_size = 16
	ld.fill_blank()
	ld.player_spawn = Vector2i(1, 1)
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	var hud := rt.find_child("HUD", true, false)
	assert_not_null(hud, "HUD canvas layer created")
	var label := hud.find_child("HUDLabel", true, false) if hud != null else null
	assert_not_null(label, "HUD label present")
	assert_eq(label.text, "Score: 0   Ammo: 5   HP: 3", "HUD reflects initial player state")


func after_each():
	GameManager.register_episodes()
```

- [ ] **Step 3: Run tests**

Run: `./tests/run_all.sh`
Expected: ALL PASS. (The HUD label is read after the player's `_ready` has set `ammo = max_ammo = 5`.)

- [ ] **Step 4: Commit**

```bash
git add src/runtime/level_runtime.gd tests/unit/test_hud.gd
git commit -m "feat(runtime): minimal in-play HUD (score/ammo/health)"
```

---

## Task 10: Editor migration to namespaced ids

**Files:**
- Modify: `src/editor/level_editor.gd`
- Modify (migration): `tests/unit/test_editor_ui_smoke.gd`

- [ ] **Step 1: Update the two hardcoded type-id references in `level_editor.gd`**

In `src/editor/level_editor.gd`, change the default selected entity type (around the `var selected_entity_type` declaration):

```gdscript
var selected_entity_type: String = "keen1.vorticon"
```

In `_place_entity`, change the spawn special-case (around line 234):

```gdscript
func _place_entity(cell: Vector2i) -> void:
	if selected_entity_type == "keen1.player_spawn":
		undo_stack.execute(level, SetPlayerSpawnCmd.new(cell))
		return
	undo_stack.execute(level, AddEntityCmd.new(EntityDef.new(selected_entity_type, cell.x, cell.y)))
```

- [ ] **Step 2: Migrate `test_editor_ui_smoke.gd`'s selected type**

In `tests/unit/test_editor_ui_smoke.gd`, change line ~37:

```gdscript
	inst.set_selected_entity_type("keen1.vorticon")
```

- [ ] **Step 3: Run tests**

Run: `./tests/run_all.sh`
Expected: ALL PASS.

- [ ] **Step 4: Commit**

```bash
git add src/editor/level_editor.gd tests/unit/test_editor_ui_smoke.gd
git commit -m "refactor(editor): migrate entity type ids to namespaced keen1.* "
```

---

## Task 11: Author the first level (manual)

**Files:**
- Modify: `assets/levels/keen1/level1.tres` (via the editor)

This task is manual (the editor must be driven interactively to place tiles, spawn, and entities).

- [ ] **Step 1: Open the editor and load/create the level**

Run: `make edit`
- Load `assets/levels/keen1/level1.tres` (or New, then Save As that path).
- In the inspector, assign the tileset (`assets/tilesets/Invasion of the Vorticons.tres`) if not already set.
- Set `level_id = "keen1_01"`, `level_name = "Border Village"`, `episode = "keen1"`.

- [ ] **Step 2: Author content**

- Paint a walkable geometry floor + a few platforms (one-way platforms where appropriate).
- Set the player spawn (entity palette → Player Spawn, then click).
- Place 3–5 Candy pickups, 1–2 Raygun Ammo pickups.
- Place 1–2 Vorticons, 1–2 Yorps, and 1 Butler Robot.
- Place one Exit Door near the far end.
- Save (`Ctrl+S` or File → Save).

- [ ] **Step 3: Verify via Test ▶**

Click **Test ▶** in the editor toolbar. Confirm:
- Player runs/jumps/pogos; shooting (X) fires bolts and decrements ammo.
- Vorticon patrols + hops, takes 3 bolts to die; Yorp knocks the player; Butler ignores bolts.
- Candy/raygun pickups collect; HUD updates.
- Reaching the Exit Door shows the completion overlay; any key returns to the editor.

- [ ] **Step 4: Commit the authored level**

```bash
git add assets/levels/keen1/level1.tres
git commit -m "feat(levels): author keen1 level 1 (Border Village)"
```

---

## Task 12: Final verification

- [ ] **Step 1: Full test suite**

Run: `./tests/run_all.sh`
Expected: ALL PASS, zero failures.

- [ ] **Step 2: Import / headless clean**

Run: `make import`
Expected: imports with no errors, quits cleanly.

- [ ] **Step 3: Spec complete-criteria checklist**

Re-check each box in spec §8 against the implementation:
- Per-episode union catalog (keen1, 7 ids) — GUT ✅
- Player run/jump/pogo/shoot (ammo-limited, facing) — manual ✅
- Vorticon/Yorp/Butler faithful behaviors — manual + GUT ✅
- Projectile kills/despawns/passes-through-items — GUT + manual ✅
- Candy/raygun + exit overlay → return — GUT + manual ✅
- HUD visible — manual ✅
- Editor palette/placement with namespaced ids — manual ✅
- First level authored — manual ✅

- [ ] **Step 4: Commit any remaining generated `.uid` files**

```bash
git add $(git ls-files --others --exclude-standard | grep '\.uid$')
git commit -m "chore: add generated .uid files for new scripts/scenes" || echo "no new uid files"
```

---

## Plan self-review notes

- **Spec coverage:** Every spec §4 component maps to a task: entity base (T1), Enemy (T3), concrete enemies (T4), player shoot (T6), projectile (T5), pickups (T7), exit/completion (T8), HUD (T9), episode registration (T2), editor migration (T10), first level (T11).
- **Type consistency:** `level_completed` signal name is identical in `special.gd`, `exit_door.gd`, and the `level_runtime.gd` `has_signal`/`connect` calls. `_handle_player`, `take_damage`, `add_ammo`, `ammo_changed` signatures are consistent across player/enemy/pickup/projectile tasks.
- **No placeholders:** every code step contains full GDScript/.tscn content; manual steps (T11) describe exact editor actions.
- **Risk items from spec §9 are addressed:** the projectile Area2D-vs-tile detection is exercised by `test_projectile.gd` (`test_tile_hit_frees`); the `res://` DirAccess discovery is exercised implicitly by every test that relies on `GameManager.register_episodes()` populating the keen1 catalog.
