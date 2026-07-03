# Sprite-Backed Entities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let any `.tscn` in `assets/sprites/` become a placeable, decor-only entity via one `register_sprite(...)` line in `Keen1Episode`, placed by the existing entity tool and spawned by the existing runtime — no new editor tool, command, or data field.

**Architecture:** A thin `SpriteEntity` (`Node2D`) wrapper bridges bare-`Node` sprite scenes into the `Node2D`-based entity spawn path. `EntityRegistry` gains a `CATEGORY_DECOR` + `register_sprite()` (stores a `scene_path` string, lazy-loaded at spawn) and an `instantiate()` branch that wraps the loaded scene in a `SpriteEntity`. Placement, undo/redo, serialization, palette, and runtime spawning are reused unchanged.

**Tech Stack:** Godot 4.7, GDScript, GUT (Godot Unit Test).

**Spec:** `docs/superpowers/specs/2026-07-03-sprite-backed-entities-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `src/runtime/entities/sprite_entity.gd` | Create | `Node2D` wrapper exposing `type_id` / `properties` / `setup()` — the entity contract for raw sprite scenes. No collision, no AI. |
| `src/core/entity_registry.gd` | Modify | Add `CATEGORY_DECOR` const, `register_sprite()` entry point, and the `scene_path` branch in `instantiate()`. |
| `src/episodes/keen1/episode.gd` | Modify | Register `keen1.exit_sign` as the first sprite-backed decor entity. |
| `src/editor/palette_panel.gd` | Modify (optional polish) | Friendly label "Decoration" for the `decor` category in the filter dropdown. |
| `tests/unit/test_sprite_entity.gd` | Create | Unit tests for `SpriteEntity`, `register_sprite`, and the sprite `instantiate` branch (incl. missing-path + scripted-entity regression). |
| `tests/unit/test_episode.gd` | Modify | Assert `keen1.exit_sign` is registered as `CATEGORY_DECOR`. |

---

## Task 1: SpriteEntity wrapper node

**Files:**
- Create: `src/runtime/entities/sprite_entity.gd`
- Test: `tests/unit/test_sprite_entity.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_sprite_entity.gd`:

```gdscript
extends GutTest

func after_each():
	# Restore the autoload's default roster so clearing here doesn't leak an
	# empty registry into later test scripts (e.g. test_level_runtime).
	GameManager.register_episodes()


func test_sprite_entity_is_node2d_with_setup():
	var s := add_child_autofree(SpriteEntity.new()) as SpriteEntity
	s.setup("keen1.exit_sign", {"foo": 1})
	assert_true(s is Node2D, "SpriteEntity is a Node2D")
	assert_eq(s.type_id, "keen1.exit_sign")
	assert_eq(s.properties.get("foo"), 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
./tests/run_all.sh 2>&1 | grep -iE "sprite_entity|Parse Error|Identifier not found" | head
```
Expected: FAIL — `SpriteEntity` identifier not found (the class does not exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `src/runtime/entities/sprite_entity.gd`:

```gdscript
class_name SpriteEntity
extends Node2D
## Wrapper that gives a pure-visual sprite scene (bare Node root, no script) the
## entity contract: a Node2D transform + setup(type_id, props). Built by
## EntityRegistry.instantiate around a .tscn loaded from assets/sprites/.
## Deliberately has no collision, no AI, no signals — it is a positioned
## container; the wrapped sprite scene's children (e.g. AnimatedSprite2D) render
## and animate on their own.

@export var type_id: String = ""
@export var properties: Dictionary = {}


## Called by EntityRegistry.instantiate after constructing the wrapper.
func setup(p_type_id: String, p_props: Dictionary = {}) -> void:
	type_id = p_type_id
	properties = p_props
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
./tests/run_all.sh 2>&1 | tail -20
```
Expected: PASS — `test_sprite_entity_is_node2d_with_setup` passes, all prior tests still pass.

- [ ] **Step 5: Commit**

```bash
git add src/runtime/entities/sprite_entity.gd tests/unit/test_sprite_entity.gd
git commit -m "feat(entity): add SpriteEntity wrapper for decor sprites"
```

---

## Task 2: register_sprite + CATEGORY_DECOR in EntityRegistry

**Files:**
- Modify: `src/core/entity_registry.gd`
- Test: `tests/unit/test_sprite_entity.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_sprite_entity.gd` (before the closing of the file, after `test_sprite_entity_is_node2d_with_setup`):

```gdscript
func test_register_sprite_adds_decor_entry():
	EntityRegistry.clear()
	EntityRegistry.register_sprite("keen1.exit_sign", EntityRegistry.CATEGORY_DECOR, "Exit Sign",
		"res://assets/sprites/Exit Sign.tscn")
	assert_true(EntityRegistry.has("keen1.exit_sign"))
	var e: Dictionary = EntityRegistry.get_entry("keen1.exit_sign")
	assert_eq(e["category"], EntityRegistry.CATEGORY_DECOR)
	assert_eq(e["label"], "Exit Sign")
	assert_eq(e["scene_path"], "res://assets/sprites/Exit Sign.tscn")
	# Surfaced in the palette, grouped under decor.
	var entries := EntityRegistry.get_palette_entries()
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["type_id"], "keen1.exit_sign")
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
./tests/run_all.sh 2>&1 | grep -iE "register_sprite|CATEGORY_DECOR|Invalid call" | head
```
Expected: FAIL — `register_sprite` method does not exist / `CATEGORY_DECOR` identifier not found.

- [ ] **Step 3: Write minimal implementation**

In `src/core/entity_registry.gd`:

3a. Add the `CATEGORY_DECOR` const immediately after the existing category consts (after `const CATEGORY_SPECIAL := "special"`, around line 10):

```gdscript
const CATEGORY_DECOR := "decor"
```

3b. Add the `register_sprite` method immediately after the existing `register(...)` method (after its closing `}` / end, around line 23):

```gdscript
## Register a pure-decoration sprite scene (.tscn under assets/sprites/) as a
## placeable entity. The scene is loaded lazily at spawn time, so a missing file
## is skipped gracefully. Mirrors register()'s entry shape but stores a path
## string (scene_path) instead of a preloaded PackedScene.
func register_sprite(type_id: String, category: String, label: String, scene_path: String, properties: Array = []) -> void:
	_entries[type_id] = {
		"type_id": type_id,
		"category": category,
		"label": label,
		"properties": properties,
		"scene_path": scene_path,
	}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
./tests/run_all.sh 2>&1 | tail -20
```
Expected: PASS — `test_register_sprite_adds_decor_entry` passes; all other tests still pass.

- [ ] **Step 5: Commit**

```bash
git add src/core/entity_registry.gd tests/unit/test_sprite_entity.gd
git commit -m "feat(core): add register_sprite + CATEGORY_DECOR to EntityRegistry"
```

---

## Task 3: instantiate() sprite-wrapping branch

**Files:**
- Modify: `src/core/entity_registry.gd` (the `instantiate` method)
- Test: `tests/unit/test_sprite_entity.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_sprite_entity.gd`:

```gdscript
func test_instantiate_sprite_wraps_scene_in_sprite_entity():
	EntityRegistry.clear()
	EntityRegistry.register_sprite("keen1.exit_sign", EntityRegistry.CATEGORY_DECOR, "Exit Sign",
		"res://assets/sprites/Exit Sign.tscn")
	var node := add_child_autofree(EntityRegistry.instantiate("keen1.exit_sign", Vector2(100, 200))) as Node2D
	assert_not_null(node)
	assert_true(node is SpriteEntity, "sprite entry instantiates a SpriteEntity wrapper")
	assert_eq(node.position, Vector2(100, 200))
	assert_eq(node.type_id, "keen1.exit_sign")
	assert_true(node.is_in_group("entity"))
	# The raw sprite scene is the wrapper's only child.
	assert_eq(node.get_child_count(), 1)
	assert_true(node.get_child(0) is Node)


func test_instantiate_sprite_missing_path_returns_null():
	EntityRegistry.clear()
	EntityRegistry.register_sprite("bogus", EntityRegistry.CATEGORY_DECOR, "Bogus",
		"res://assets/sprites/does_not_exist.tscn")
	assert_null(EntityRegistry.instantiate("bogus", Vector2.ZERO))


func test_instantiate_scripted_entity_not_wrapped():
	# Real default-roster scripted entity must still instantiate via its
	# PackedScene branch, NOT the sprite wrapper.
	var y := add_child_autofree(EntityRegistry.instantiate("keen1.yorp", Vector2.ZERO)) as Node2D
	assert_not_null(y)
	assert_false(y is SpriteEntity, "scripted entity is not wrapped in SpriteEntity")
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
./tests/run_all.sh 2>&1 | grep -iE "wraps_scene|missing_path|not_wrapped|SpriteEntity" | head
```
Expected: FAIL — `instantiate` returns null for the sprite entry (no `scene_path` branch yet) so `test_instantiate_sprite_wraps_scene_in_sprite_entity` fails on `assert_not_null`.

- [ ] **Step 3: Write minimal implementation**

In `src/core/entity_registry.gd`, replace the body of the `instantiate(...)` method. The current body is:

```gdscript
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
```

Replace it with (adds the `scene_path` branch between the `PackedScene` branch and the category-default fallback):

```gdscript
func instantiate(type_id: String, pos: Vector2, props: Dictionary = {}) -> Node2D:
	if not _entries.has(type_id):
		push_warning("EntityRegistry: unknown entity type '%s'" % type_id)
		return null
	var entry: Dictionary = _entries[type_id]
	var node: Node2D = null
	var scene: Variant = entry.get("scene", null)
	var scene_path: String = String(entry.get("scene_path", ""))
	if scene is PackedScene:
		node = scene.instantiate()
	elif scene_path != "":
		if not ResourceLoader.exists(scene_path):
			push_warning("EntityRegistry: sprite scene not found '%s'" % scene_path)
			return null
		var wrapper := SpriteEntity.new()
		var packed := load(scene_path) as PackedScene
		wrapper.add_child(packed.instantiate())
		node = wrapper
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
./tests/run_all.sh 2>&1 | tail -25
```
Expected: PASS — all three new tests pass; the existing scripted-entity and default-category tests still pass (no regression).

- [ ] **Step 5: Commit**

```bash
git add src/core/entity_registry.gd tests/unit/test_sprite_entity.gd
git commit -m "feat(core): wrap sprite scenes in SpriteEntity at instantiate"
```

---

## Task 4: Register Exit Sign as a keen1 decor entity

**Files:**
- Modify: `src/episodes/keen1/episode.gd`
- Test: `tests/unit/test_episode.gd`

- [ ] **Step 1: Write the failing test**

In `tests/unit/test_episode.gd`, add this new test function immediately after `test_player_spawn_has_no_scene` (before the `after_each` function):

```gdscript
func test_exit_sign_registered_as_decor():
	Keen1Episode.new().register_entities(EntityRegistry)
	assert_true(EntityRegistry.has("keen1.exit_sign"), "keen1.exit_sign registered")
	var e: Dictionary = EntityRegistry.get_entry("keen1.exit_sign")
	assert_eq(e["category"], EntityRegistry.CATEGORY_DECOR)
	assert_eq(e["scene_path"], "res://assets/sprites/Exit Sign.tscn")
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
./tests/run_all.sh 2>&1 | grep -iE "exit_sign|not registered" | head
```
Expected: FAIL — `keen1.exit_sign` is not registered, so `assert_true(EntityRegistry.has("keen1.exit_sign"), ...)` fails.

- [ ] **Step 3: Write minimal implementation**

In `src/episodes/keen1/episode.gd`, add the registration line at the end of `register_entities()` (immediately after the `registry.register("keen1.player_spawn", ...)` line, which is the current last line of the method):

```gdscript
	registry.register_sprite("keen1.exit_sign", registry.CATEGORY_DECOR, "Exit Sign",
		"res://assets/sprites/Exit Sign.tscn")
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
./tests/run_all.sh 2>&1 | tail -25
```
Expected: PASS — `test_exit_sign_registered_as_decor` passes; `test_keen1_categories`, `test_register_episodes_populates_catalog_via_disk_scan`, and `test_player_spawn_has_no_scene` still pass.

- [ ] **Step 5: Commit**

```bash
git add src/episodes/keen1/episode.gd tests/unit/test_episode.gd
git commit -m "feat(keen1): register Exit Sign sprite as decor entity"
```

---

## Task 5: Palette friendly label (optional polish)

**Files:**
- Modify: `src/editor/palette_panel.gd`

This task is **optional**. Without it the filter dropdown renders "Decor" (via the `_category_label` fallback `cat.capitalize()`). With it, it renders the friendlier "Decoration". Skip if you want to honor strict YAGNI.

- [ ] **Step 1: Write the change**

In `src/editor/palette_panel.gd`, in the `_category_label(cat: String)` method (around line 224), add a `CATEGORY_DECOR` case to the `match` statement. The current method is:

```gdscript
func _category_label(cat: String) -> String:
	match cat:
		EntityRegistry.CATEGORY_ITEM:
			return "Pickups"
		EntityRegistry.CATEGORY_ENEMY:
			return "Enemies"
		EntityRegistry.CATEGORY_HAZARD:
			return "Hazards"
		EntityRegistry.CATEGORY_SPECIAL:
			return "Special"
	return cat.capitalize()
```

Replace it with:

```gdscript
func _category_label(cat: String) -> String:
	match cat:
		EntityRegistry.CATEGORY_ITEM:
			return "Pickups"
		EntityRegistry.CATEGORY_ENEMY:
			return "Enemies"
		EntityRegistry.CATEGORY_HAZARD:
			return "Hazards"
		EntityRegistry.CATEGORY_SPECIAL:
			return "Special"
		EntityRegistry.CATEGORY_DECOR:
			return "Decoration"
	return cat.capitalize()
```

- [ ] **Step 2: Run full test suite to confirm no regression**

Run:
```bash
./tests/run_all.sh 2>&1 | tail -20
```
Expected: PASS — all tests pass (the label change is not unit-tested; it is verified manually in Task 6).

- [ ] **Step 3: Commit**

```bash
git add src/editor/palette_panel.gd
git commit -m "polish(editor): friendly Decoration label for decor category"
```

---

## Task 6: Full verification + manual editor/runtime check

**Files:** none (verification only)

- [ ] **Step 1: Run the full headless test suite**

Run:
```bash
./tests/run_all.sh
```
Expected: all tests pass, exit code 0. Confirm no warnings about `keen1.exit_sign`, missing scenes, or `SpriteEntity`.

- [ ] **Step 2: Open the editor and place the sprite**

Run:
```bash
make edit
```
Then in the running editor:
1. Open or create a level.
2. Select the **Entity** tool.
3. In the Entities palette, set the category filter to **Decoration** (or **All**).
4. Select **Exit Sign**.
5. Click a tile cell to place it. Confirm it appears as an orange box + "keen1.exit_sign" label.
6. Click **Undo** — the box disappears. **Redo** — it reappears.

- [ ] **Step 3: Save, reopen, and Test ▶**

Still in the editor:
1. **Save** the level.
2. Close and reopen the level — confirm the Exit Sign `EntityDef` round-tripped (the box reappears at the same cell).
3. Click **Test ▶** — confirm the Exit Sign `AnimatedSprite2D` renders in-level at the placed cell, animating (2 fps, per the scene's `SpriteFrames`).

- [ ] **Step 4: Verify export-safety (optional but recommended)**

Run:
```bash
make build
```
Open the exported app (e.g. `build/keen_reloaded.app`), enter the editor, place an Exit Sign, Test ▶. Confirm it renders. This validates that `load("res://assets/sprites/Exit Sign.tscn")` resolves inside the exported `.pck` (the core export-safety claim of the spec).

---

## Self-Review (completed by plan author)

**Spec coverage:**
- §3.1 `CATEGORY_DECOR` → Task 2 step 3a. ✓
- §3.2 `register_sprite()` → Task 2 step 3b. ✓
- §3.3 `instantiate()` branch → Task 3. ✓
- §4 `SpriteEntity` wrapper → Task 1. ✓
- §5 Exit Sign registration → Task 4. ✓
- §6 palette friendly label (optional) → Task 5. ✓
- §7 runtime spawning — unchanged, covered by manual Test ▶ (Task 6 step 3) + existing `test_level_runtime` / `test_runtime_entities`. ✓
- §9 unit tests — every listed assertion maps to a test in Task 1–4. ✓

**Placeholder scan:** None. Every code step shows complete, exact code.

**Type/signature consistency:**
- `SpriteEntity.setup(p_type_id: String, p_props: Dictionary = {})` (Task 1) matches the existing `instantiate()` call `node.setup(type_id, props)` (2 args). ✓
- `register_sprite(type_id, category, label, scene_path, properties=[])` (Task 2) matches the call sites in Task 4 and all tests. ✓
- `CATEGORY_DECOR` referenced consistently in registry, episode, palette, and tests. ✓
- Scene path string `"res://assets/sprites/Exit Sign.tscn"` matches the actual file (verified: `assets/sprites/Exit Sign.tscn` exists, root `Node` named `ExitSign`). ✓

**Scope:** Single focused feature, one plan. No sub-project decomposition needed.
