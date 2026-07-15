# Pogo Stick Entity + Persistent Inventory — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a pogo stick pickup entity and a persistent `Inventory` autoload so that once Keen collects the pogo, it is available in every level (never the overworld) and survives save/load.

**Architecture:** New `Inventory` autoload (Dictionary item store) wired into `GameManager.serialize()`/`deserialize()`/`clear_progress()`. New `PogoStick` entity extends `Entity`, grants `"keen1.pogo"` on contact. Player pogo toggle gated by one `Inventory.has_item("pogo")` check.

**Tech Stack:** Godot 4.7, GDScript, GUT test framework

**Spec:** `docs/superpowers/specs/2026-07-15-pogo-stick-inventory-design.md`

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `src/core/inventory.gd` | `Inventory` autoload — Dictionary item store + serialize/deserialize |
| Create | `src/runtime/entities/pogo_stick.gd` | `PogoStick extends Entity` — grants pogo on contact |
| Create | `src/runtime/entities/pogo_stick.tscn` | Minimal scene: CharacterBody2D + script (ColorRect fallback via base class) |
| Create | `tests/unit/test_inventory.gd` | GUT tests for Inventory autoload |
| Create | `tests/unit/test_pogo_pickup.gd` | GUT tests for PogoStick entity + registration |
| Modify | `project.godot` | Register `Inventory` autoload after `SaveSystem` |
| Modify | `src/core/game_manager.gd` | Wire Inventory into serialize/deserialize/clear_progress |
| Modify | `src/runtime/player/player.gd` | Gate pogo toggle behind `Inventory.has_item("pogo")` |
| Modify | `src/episodes/keen1/episode.gd` | Register `keen1.pogo_stick` entity |
| Modify | `tests/unit/test_game_manager_loop.gd` | Assert inventory round-trips through serialize/deserialize |

---

## Task 1: Inventory Autoload

**Files:**
- Create: `src/core/inventory.gd`
- Test: `tests/unit/test_inventory.gd`
- Modify: `project.godot` (add autoload entry)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_inventory.gd`:

```gdscript
extends GutTest

func before_each():
	Inventory.clear()

func after_each():
	Inventory.clear()

func test_has_item_false_by_default():
	assert_false(Inventory.has_item("keen1.pogo"))

func test_add_then_has():
	Inventory.add_item("keen1.pogo")
	assert_true(Inventory.has_item("keen1.pogo"))

func test_add_is_idempotent():
	Inventory.add_item("keen1.pogo")
	Inventory.add_item("keen1.pogo")
	assert_true(Inventory.has_item("keen1.pogo"))

func test_remove_item():
	Inventory.add_item("keen1.pogo")
	Inventory.remove_item("keen1.pogo")
	assert_false(Inventory.has_item("keen1.pogo"))

func test_remove_nonexistent_is_noop():
	Inventory.remove_item("keen1.pogo")
	assert_false(Inventory.has_item("keen1.pogo"))

func test_clear_empties_all():
	Inventory.add_item("keen1.pogo")
	Inventory.add_item("keen1.key")
	Inventory.clear()
	assert_false(Inventory.has_item("keen1.pogo"))
	assert_false(Inventory.has_item("keen1.key"))

func test_serialize_round_trip():
	Inventory.add_item("keen1.pogo")
	Inventory.add_item("keen1.key")
	var data := Inventory.serialize()
	Inventory.clear()
	assert_false(Inventory.has_item("keen1.pogo"))
	Inventory.deserialize(data)
	assert_true(Inventory.has_item("keen1.pogo"))
	assert_true(Inventory.has_item("keen1.key"))

func test_deserialize_replaces_not_merges():
	Inventory.add_item("stale_item")
	Inventory.deserialize({"keen1.pogo": true})
	assert_false(Inventory.has_item("stale_item"))
	assert_true(Inventory.has_item("keen1.pogo"))

func test_deserialize_empty_dict_is_noop():
	Inventory.add_item("keen1.pogo")
	Inventory.deserialize({})
	assert_false(Inventory.has_item("keen1.pogo"))

func test_item_collected_emits_on_first_add():
	watch_signals(Inventory)
	Inventory.add_item("keen1.pogo")
	assert_signal_emitted_with_parameters(Inventory, "item_collected", ["keen1.pogo"])

func test_item_collected_does_not_emit_on_duplicate():
	Inventory.add_item("keen1.pogo")
	watch_signals(Inventory)
	Inventory.add_item("keen1.pogo")
	assert_signal_emitted_count(Inventory, "item_collected", 0)
```

- [ ] **Step 2: Create the autoload script**

Create `src/core/inventory.gd`:

```gdscript
class_name Inventory
extends Node
## Persistent item store (autoload). Dictionary-based: an item_id key exists if
## and only if the player owns it. Wired into GameManager.serialize()/deserialize()
## so items survive save/load. Emits item_collected on first acquisition of each id.

signal item_collected(item_id: String)

var _items: Dictionary = {}  # item_id (String) -> true


func has_item(item_id: String) -> bool:
	return _items.has(item_id)


func add_item(item_id: String) -> void:
	if _items.has(item_id):
		return
	_items[item_id] = true
	item_collected.emit(item_id)


func remove_item(item_id: String) -> void:
	_items.erase(item_id)


func clear() -> void:
	_items.clear()


func serialize() -> Dictionary:
	return _items.duplicate(true)


func deserialize(data: Dictionary) -> void:
	_items = data.duplicate(true)
```

- [ ] **Step 3: Register the autoload in project.godot**

In `project.godot`, add after the `SaveSystem` line in the `[autoload]` section:

```ini
Inventory="*res://src/core/inventory.gd"
```

- [ ] **Step 4: Run tests**

Run: `./tests/run_all.sh`
Expected: All `test_inventory.gd` tests PASS. Other tests unaffected (Inventory.clear() is harmless when empty).

- [ ] **Step 5: Commit**

```bash
git add src/core/inventory.gd project.godot tests/unit/test_inventory.gd
git commit -m "feat: add Inventory autoload for persistent item tracking"
```

---

## Task 2: Persistence Wiring

**Files:**
- Modify: `src/core/game_manager.gd` (serialize, deserialize, clear_progress)
- Test: `tests/unit/test_game_manager_loop.gd` (add inventory assertions)

- [ ] **Step 1: Write the failing test**

Add to `tests/unit/test_game_manager_loop.gd`:

```gdscript
func test_serialize_carries_inventory():
	Inventory.add_item("keen1.pogo")
	var data := GameManager.serialize()
	assert_true(data.has("inventory"))
	assert_true(data["inventory"].has("keen1.pogo"))


func test_deserialize_restores_inventory():
	var data := {"completed_levels": [], "current_episode_id": "", "current_scope_kind": "episode", "inventory": {"keen1.pogo": true}}
	GameManager.deserialize(data)
	assert_true(Inventory.has_item("keen1.pogo"))


func test_clear_progress_clears_inventory():
	Inventory.add_item("keen1.pogo")
	GameManager.clear_progress()
	assert_false(Inventory.has_item("keen1.pogo"))


func test_deserialize_old_save_without_inventory_key():
	# Pre-this-plan saves lack the inventory key — must not error.
	var data := {"completed_levels": ["x"], "current_episode_id": "keen1", "current_scope_kind": "episode"}
	GameManager.deserialize(data)
	assert_false(Inventory.has_item("keen1.pogo"))
	assert_true(GameManager.is_level_completed("x"))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `serialize()` does not yet include `"inventory"`.

- [ ] **Step 3: Wire Inventory into GameManager**

In `src/core/game_manager.gd`, modify `serialize()`:

```gdscript
func serialize() -> Dictionary:
	return {
		"completed_levels": completed_levels.duplicate(),
		"current_episode_id": current_episode_id,
		"current_scope_kind": current_scope_kind,
		"inventory": Inventory.serialize(),
	}
```

Modify `deserialize()` — add at the end:

```gdscript
func deserialize(data: Dictionary) -> void:
	completed_levels.clear()
	var loaded: Array = data.get("completed_levels", [])
	for id in loaded:
		completed_levels.append(String(id))
	current_episode_id = String(data.get("current_episode_id", ""))
	# Older saves (pre-Plan-6c) lack this key; default to "episode".
	current_scope_kind = String(data.get("current_scope_kind", "episode"))
	Inventory.deserialize(data.get("inventory", {}))
```

Modify `clear_progress()` — add `Inventory.clear()`:

```gdscript
func clear_progress() -> void:
	state = State.MENU
	completed_levels.clear()
	current_episode_id = ""
	current_scope_kind = "episode"
	current_overworld = null
	current_level = null
	last_entrance_pos = Vector2i.ZERO
	pending_player_spawn = Vector2i(-1, -1)
	pending_level = null
	pending_teleport_arrival_id = ""
	return_scene = null
	_levels_by_id.clear()
	Inventory.clear()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: All tests PASS including new inventory assertions.

- [ ] **Step 5: Commit**

```bash
git add src/core/game_manager.gd tests/unit/test_game_manager_loop.gd
git commit -m "feat: persist inventory through GameManager serialize/deserialize"
```

---

## Task 3: PogoStick Entity

**Files:**
- Create: `src/runtime/entities/pogo_stick.gd`
- Create: `src/runtime/entities/pogo_stick.tscn`
- Modify: `src/episodes/keen1/episode.gd` (register entity)
- Test: `tests/unit/test_pogo_pickup.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_pogo_pickup.gd`:

```gdscript
extends GutTest

class FakePlayer extends Node:
	func _ready() -> void:
		add_to_group("player")

func before_each():
	Inventory.clear()

func after_each():
	Inventory.clear()
	GameManager.register_episodes()

func test_pogo_pickup_grants_inventory_item():
	var pogo: PogoStick = add_child_autofree(load("res://src/runtime/entities/pogo_stick.tscn").instantiate())
	assert_false(Inventory.has_item("keen1.pogo"), "pogo not owned before pickup")
	var p := FakePlayer.new()
	add_child_autofree(p)
	pogo._on_body_entered(p)
	assert_true(Inventory.has_item("keen1.pogo"), "pogo owned after pickup")
	assert_true(pogo.is_queued_for_deletion(), "pickup frees after use")

func test_pogo_stick_registered_as_level_item():
	var entry: Dictionary = EntityRegistry.get_entry("keen1.pogo_stick")
	assert_eq(entry.get("category", ""), "item")
	var kinds: Array = entry.get("map_kinds", [])
	assert_true(kinds.has(LevelData.MapKind.LEVEL), "available on LEVEL maps")
	assert_false(kinds.has(LevelData.MapKind.OVERWORLD), "not available on OVERWORLD")

func test_pogo_stick_palette_hidden_on_overworld():
	var level_entries := EntityRegistry.get_palette_entries_for_kind(LevelData.MapKind.LEVEL)
	var overworld_entries := EntityRegistry.get_palette_entries_for_kind(LevelData.MapKind.OVERWORLD)
	var has_level := false
	for e in level_entries:
		if String(e.get("type_id", "")) == "keen1.pogo_stick":
			has_level = true
	assert_true(has_level, "pogo_stick in LEVEL palette")
	var has_ow := false
	for e in overworld_entries:
		if String(e.get("type_id", "")) == "keen1.pogo_stick":
			has_ow = true
	assert_false(has_ow, "pogo_stick NOT in OVERWORLD palette")

func test_pogo_stick_instantiates_as_entity():
	var node := add_child_autofree(EntityRegistry.instantiate("keen1.pogo_stick", Vector2.ZERO)) as Node2D
	assert_not_null(node)
	assert_true(node is PogoStick)
	assert_eq(node.type_id, "keen1.pogo_stick")
	assert_true(node.is_in_group("entity"))
```

- [ ] **Step 2: Create the PogoStick script**

Create `src/runtime/entities/pogo_stick.gd`:

```gdscript
class_name PogoStick
extends Entity
## Pogo stick pickup. Grants the "keen1.pogo" inventory item on contact, then
## frees. Registered as a LEVEL-only item so it cannot be placed on the overworld.

const POGO_ITEM_ID := "keen1.pogo"


func _handle_player(_player: Node) -> void:
	Inventory.add_item(POGO_ITEM_ID)
	AudioManager.play_sfx("pickup_score")
	queue_free()


func _color() -> Color:
	return Color(0.2, 0.9, 0.2, 0.8)
```

- [ ] **Step 3: Create the PogoStick scene**

Create `src/runtime/entities/pogo_stick.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/runtime/entities/pogo_stick.gd" id="1_pogo"]

[node name="PogoStick" type="CharacterBody2D"]
script = ExtResource("1_pogo")
```

(The base `Entity._build_contact()` creates a green `ColorRect` fallback visual named "Visual" at runtime via the `_color()` override.)

- [ ] **Step 4: Register the entity in keen1 episode**

In `src/episodes/keen1/episode.gd`, add after the `raygun` registration (line 37) and before `exit_door`:

```gdscript
	var pogo_stick := preload("res://src/runtime/entities/pogo_stick.tscn")
```

And add the register call after the raygun register line:

```gdscript
	registry.register("keen1.pogo_stick", registry.CATEGORY_ITEM, "Pogo Stick", [], pogo_stick)
```

(No `map_kinds` argument — defaults to `[LevelData.MapKind.LEVEL]`.)

- [ ] **Step 5: Run tests**

Run: `./tests/run_all.sh`
Expected: All tests PASS including pogo pickup, registration, palette filtering, and instantiation.

- [ ] **Step 6: Commit**

```bash
git add src/runtime/entities/pogo_stick.gd src/runtime/entities/pogo_stick.tscn src/episodes/keen1/episode.gd tests/unit/test_pogo_pickup.gd
git commit -m "feat: add PogoStick pickup entity (LEVEL-only)"
```

---

## Task 4: Pogo Mechanic Gate

**Files:**
- Modify: `src/runtime/player/player.gd:164` (gate pogo toggle)

- [ ] **Step 1: Gate the pogo toggle**

In `src/runtime/player/player.gd`, change line 164 from:

```gdscript
	if not _input_locked and Input.is_action_just_pressed("pogo"):
		_pogo = not _pogo
```

to:

```gdscript
	if not _input_locked and Inventory.has_item("pogo") and Input.is_action_just_pressed("pogo"):
		_pogo = not _pogo
```

- [ ] **Step 2: Run the full test suite**

Run: `./tests/run_all.sh`
Expected: All tests PASS. The pogo toggle is now gated behind inventory ownership.

- [ ] **Step 3: Commit**

```bash
git add src/runtime/player/player.gd
git commit -m "feat: gate pogo behind inventory ownership"
```

---

## Task 5: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `./tests/run_all.sh`
Expected: All tests PASS, zero failures.

- [ ] **Step 2: Verify import works**

Run: `make import`
Expected: Completes without errors (new .tscn and autoload recognized).

- [ ] **Step 3: Commit any remaining work**

If any files remain uncommitted:
```bash
git status
```
Ensure all source, tests, and the spec/plan docs are committed.
