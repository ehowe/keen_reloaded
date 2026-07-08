# Entity Variant Properties Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a placed `keen1.spike` entity select its facing (`right` / `left`) via an inspector `OptionButton`, driven by a general enum property schema that any future multi-variant entity can reuse with no per-entity code.

**Architecture:** Activate the property schema the original design specified but never wired: `EntityRegistry` entries declare `{name, default, type, options?}` schemas; `LevelEditor._place_entity` seeds defaults into the `EntityDef`; `InspectorPanel` renders an `OptionButton` per enum (schema-first, with an instance-key fallback so `keen1.level_entrance` keeps rendering); `SpriteEntity` walks its subtree and shows the descendant CanvasItem whose name contains the enum value, hiding the rest; the canvas label appends the variant. The spike is registered as `keen1.spike` (CATEGORY_HAZARD) with `facing:right|left`.

**Tech Stack:** Godot 4.7, GDScript, GUT (Godot Unit Test).

**Spec:** `docs/superpowers/specs/2026-07-08-entity-variant-properties-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `src/core/entity_registry.gd` | Modify | Add `get_properties_schema()` + coerce invalid enum defaults in `register()` / `register_sprite()` via a `_normalize_properties()` helper. |
| `src/runtime/entities/sprite_entity.gd` | Modify | `setup()` applies enum variant properties: walk descendants, show the CanvasItem whose name contains the value, hide sibling variants. |
| `src/editor/level_editor.gd` | Modify | `_place_entity` seeds schema defaults into the new `EntityDef`; add `_default_properties()` helper. |
| `src/editor/inspector_panel.gd` | Modify | `_rebuild_entity_box`: schema-first controls (OptionButton for enum) + instance-key fallback for keys absent from the schema. |
| `src/editor/canvas_editor.gd` | Modify | Extract static `entity_label(e)` that appends enum variant values; use it in `_draw`. |
| `src/episodes/keen1/episode.gd` | Modify | Register `keen1.spike` (CATEGORY_HAZARD) with the `facing` enum schema. |
| `tests/unit/test_entity_registry_data.gd` | Modify | Schema retrieval + enum-validation tests. |
| `tests/unit/test_sprite_entity.gd` | Modify | Variant-visibility tests (right/left/default) + spike end-to-end. |
| `tests/unit/test_editor_workflow.gd` | Modify | Placement-seeding test (spike gets `{facing:"right"}`; empty-schema type gets `{}`). |
| `tests/unit/test_editor_map_kind.gd` | Modify | Inspector enum OptionButton writeback test (existing string/bool test must still pass). |
| `tests/unit/test_episode.gd` | Modify | Assert `keen1.spike` registered as CATEGORY_HAZARD with the facing schema. |
| `tests/unit/test_canvas_rect.gd` | Modify | `CanvasEditor.entity_label` suffix test. |

**Dependency order:** Task 1 (registry schema) is the foundation. Tasks 2–4 each depend only on Task 1 (they register a throwaway spike ad-hoc in their tests). Task 5 (register keen1.spike in the real roster) builds on Task 1. Task 6's `entity_label` function depends on Task 1, but its tests assert the real `keen1.spike` schema, so Task 6 must run **after** Task 5. Execute in document order (1→6).

---

## Task 1: EntityRegistry schema retrieval + enum validation

**Files:**
- Modify: `src/core/entity_registry.gd`
- Test: `tests/unit/test_entity_registry_data.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_entity_registry_data.gd` (before the final blank line):

```gdscript
func test_get_properties_schema_returns_declared_array():
	EntityRegistry.clear()
	var schema := [{name = "facing", default = "right", type = "enum", options = ["right", "left"]}]
	EntityRegistry.register_sprite("keen1.spike", EntityRegistry.CATEGORY_HAZARD, "Spike",
		"res://assets/sprites/Spike.tscn", schema)
	var got := EntityRegistry.get_properties_schema("keen1.spike")
	assert_eq(got.size(), 1)
	assert_eq(String(got[0].get("name")), "facing")
	assert_eq(String(got[0].get("default")), "right")

func test_get_properties_schema_empty_for_unknown_and_schemaless():
	EntityRegistry.clear()
	assert_eq(EntityRegistry.get_properties_schema("nope"), [], "unknown type -> empty")
	EntityRegistry.register("vorticon", EntityRegistry.CATEGORY_ENEMY, "Vorticon")
	assert_eq(EntityRegistry.get_properties_schema("vorticon"), [], "schemaless type -> empty")

func test_enum_invalid_default_coerced_to_first_option():
	# An enum whose default is not in options should be coerced to options[0],
	# not crash. Registration still succeeds.
	EntityRegistry.clear()
	var bad := [{name = "mood", default = "angry", type = "enum", options = ["happy", "sad"]}]
	EntityRegistry.register("thing", EntityRegistry.CATEGORY_ITEM, "Thing", bad)
	var s := EntityRegistry.get_properties_schema("thing")
	assert_eq(String(s[0].get("default")), "happy", "bad default coerced to options[0]")
	assert_eq(s[0].get("options"), ["happy", "sad"], "options preserved")
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
./tests/run_all.sh 2>&1 | grep -iE "get_properties_schema|Invalid call|method not found" | head
```
Expected: FAIL — `get_properties_schema` not found on `EntityRegistry` (the method does not exist yet).

- [ ] **Step 3: Implement schema retrieval + validation**

In `src/core/entity_registry.gd`:

1. In `register()` (around line 20), change the stored `properties` value from the raw argument to the normalized copy. Replace:
```gdscript
		"properties": properties,
```
with:
```gdscript
		"properties": _normalize_properties(properties),
```

2. In `register_sprite()` (around line 42), make the same change. Replace:
```gdscript
		"properties": properties,
```
with:
```gdscript
		"properties": _normalize_properties(properties),
```

3. Add the two new methods (place them just after `register_sprite`, before `func has`):

```gdscript
## Schema entries for a type: each is {name, default, type, options?}. Empty
## for unknown types or types registered without a schema.
func get_properties_schema(type_id: String) -> Array:
	return Array(_entries.get(type_id, {}).get("properties", []))


## Return a shallow copy of `properties` with enum entries normalized: an enum
## whose default is not in its options (or whose options are empty) is coerced
## to options[0] with a push_warning. Non-enum entries pass through unchanged.
func _normalize_properties(properties: Array) -> Array:
	var out: Array = []
	for entry in properties:
		var e: Dictionary = entry.duplicate()
		if String(e.get("type", "")) == "enum":
			var options: Array = e.get("options", [])
			var n := String(e.get("name", ""))
			if options.is_empty():
				push_warning("EntityRegistry: enum property '%s' has no options" % n)
			elif not options.has(e.get("default", null)):
				push_warning("EntityRegistry: enum property '%s' default not in options; using '%s'" % [n, String(options[0])])
				e["default"] = options[0]
		out.append(e)
	return out
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
./tests/run_all.sh 2>&1 | tail -5
```
Expected: PASS — all tests green, including the three new ones.

- [ ] **Step 5: Commit**

```bash
git add src/core/entity_registry.gd tests/unit/test_entity_registry_data.gd
git commit -m "feat(core): entity property schema retrieval + enum validation"
```

---

## Task 2: SpriteEntity applies enum variant to child visibility

**Files:**
- Modify: `src/runtime/entities/sprite_entity.gd`
- Test: `tests/unit/test_sprite_entity.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_sprite_entity.gd` (before the existing `_first_canvas_descendant` helper, i.e. after the last `test_*` function):

```gdscript
func _register_spike_ad_hoc() -> void:
	EntityRegistry.clear()
	EntityRegistry.register_sprite("keen1.spike", EntityRegistry.CATEGORY_HAZARD, "Spike",
		"res://assets/sprites/Spike.tscn",
		[{name = "facing", default = "right", type = "enum", options = ["right", "left"]}])

func test_variant_right_shows_right_child_hides_left():
	_register_spike_ad_hoc()
	var n := add_child_autofree(EntityRegistry.instantiate("keen1.spike", Vector2.ZERO,
		{"facing": "right"})) as Node2D
	assert_not_null(n)
	assert_true(_find_child_named(n, "Spike Right").visible, "right variant visible")
	assert_false(_find_child_named(n, "SpikeLeft").visible, "left variant hidden")

func test_variant_left_shows_left_child_hides_right():
	_register_spike_ad_hoc()
	var n := add_child_autofree(EntityRegistry.instantiate("keen1.spike", Vector2.ZERO,
		{"facing": "left"})) as Node2D
	assert_not_null(n)
	assert_true(_find_child_named(n, "SpikeLeft").visible, "left variant visible")
	assert_false(_find_child_named(n, "Spike Right").visible, "right variant hidden")

func test_variant_default_applied_when_property_absent():
	# No facing key -> schema default "right" applies.
	_register_spike_ad_hoc()
	var n := add_child_autofree(EntityRegistry.instantiate("keen1.spike", Vector2.ZERO)) as Node2D
	assert_not_null(n)
	assert_true(_find_child_named(n, "Spike Right").visible, "default right variant visible")
	assert_false(_find_child_named(n, "SpikeLeft").visible, "non-default left variant hidden")

func _find_child_named(root: Node, want: String) -> CanvasItem:
	for c in root.get_children():
		if c is CanvasItem and String(c.name) == want:
			return c
		var deeper := _find_child_named(c, want)
		if deeper != null:
			return deeper
	return null
```

> Note: `instantiate()` calls `attach_sprite()` then `setup()`, so the variant children exist before the variant rule runs.

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
./tests/run_all.sh 2>&1 | grep -iE "test_variant|visible" | head
```
Expected: FAIL — `test_variant_left_*` fails (both children remain at their `.tscn` visibility: right visible, left hidden), because `setup()` does not yet apply the variant. (`test_variant_right_*` and `test_variant_default_*` may accidentally pass since the `.tscn` defaults to right-visible — that's fine; the left test is the discriminator.)

- [ ] **Step 3: Implement variant application**

Replace the entire `setup` function in `src/runtime/entities/sprite_entity.gd`:

```gdscript
## Called by EntityRegistry.instantiate after constructing the wrapper and
## attaching the sprite scene. Applies enum "variant" properties: for each
## enum in the type's schema, the descendant CanvasItem whose name contains
## the property value (case-insensitive) is shown; sibling variants hidden.
func setup(p_type_id: String, p_props: Dictionary = {}) -> void:
	type_id = p_type_id
	properties = p_props
	_apply_variant_properties()


func _apply_variant_properties() -> void:
	for s in EntityRegistry.get_properties_schema(type_id):
		if String(s.get("type", "")) != "enum":
			continue
		var options: Array = s.get("options", [])
		if options.is_empty():
			continue
		var key: String = String(s.get("name", ""))
		var val := String(properties.get(key, s.get("default", "")))
		_select_variant_child(options, val)


## Variant group = descendant CanvasItems whose node names contain an enum
## option (case-insensitive). Show the one whose option == val; hide the rest.
## Descendants not matching any option are left untouched. Descendant walk is
## required because attach_sprite() adds the scene root as the wrapper's only
## child, so variant sprites are typically grandchildren of the wrapper.
func _select_variant_child(options: Array, val: String) -> void:
	var want := val.to_lower()
	var matched: CanvasItem = null
	var to_hide: Array[CanvasItem] = []
	for c in _descendants(self):
		if not (c is CanvasItem):
			continue
		var nm := String(c.name).to_lower()
		for o in options:
			if nm.contains(String(o).to_lower()):
				if String(o).to_lower() == want:
					matched = c
				else:
					to_hide.append(c)
				break
	for c in to_hide:
		c.visible = false
	if matched != null:
		matched.visible = true


func _descendants(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_descendants(c))
	return out
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
./tests/run_all.sh 2>&1 | tail -5
```
Expected: PASS — all three new variant tests green; existing `test_sprite_entity.gd` tests still pass (`get_properties_schema` returns `[]` for the ad-hoc `keen1.exit_sign` test registrations → variant rule is a no-op).

- [ ] **Step 5: Commit**

```bash
git add src/runtime/entities/sprite_entity.gd tests/unit/test_sprite_entity.gd
git commit -m "feat(runtime): SpriteEntity applies enum variant to child visibility"
```

---

## Task 3: Placement seeds schema defaults into EntityDef

**Files:**
- Modify: `src/editor/level_editor.gd`
- Test: `tests/unit/test_editor_workflow.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_editor_workflow.gd`:

```gdscript
func test_place_entity_seeds_schema_defaults():
	# A registered type with an enum schema should place with the default
	# written into EntityDef.properties (self-describing data).
	EntityRegistry.clear()
	EntityRegistry.register_sprite("keen1.spike", EntityRegistry.CATEGORY_HAZARD, "Spike",
		"res://assets/sprites/Spike.tscn",
		[{name = "facing", default = "right", type = "enum", options = ["right", "left"]}])
	var ed := LevelEditor.new()
	add_child_autofree(ed)
	ed._ready()
	ed.selected_entity_type = "keen1.spike"
	ed._place_entity(Vector2i(3, 4))
	assert_eq(ed.level.entities.size(), 1)
	var def: EntityDef = ed.level.entities[0]
	assert_eq(def.x, 3)
	assert_eq(def.y, 4)
	assert_eq(def.properties.get("facing"), "right", "schema default seeded on placement")

func test_place_entity_empty_schema_yields_empty_props():
	# A schemaless type places with an empty properties dict (unchanged).
	EntityRegistry.clear()
	EntityRegistry.register("keen1.vorticon", EntityRegistry.CATEGORY_ENEMY, "Vorticon")
	var ed := LevelEditor.new()
	add_child_autofree(ed)
	ed._ready()
	ed.selected_entity_type = "keen1.vorticon"
	ed._place_entity(Vector2i(1, 2))
	assert_eq(ed.level.entities.size(), 1)
	assert_eq(ed.level.entities[0].properties, {}, "no schema -> empty props")
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
./tests/run_all.sh 2>&1 | grep -iE "test_place_entity_seeds|facing|seeded on placement" | head
```
Expected: FAIL — `test_place_entity_seeds_schema_defaults` fails: `_place_entity` creates `EntityDef.new(type, x, y)` with no props, so `properties.get("facing")` is `null`. (`test_place_entity_empty_schema_yields_empty_props` passes already.)

- [ ] **Step 3: Implement default seeding**

In `src/editor/level_editor.gd`, replace the `_place_entity` function (line 251):

```gdscript
func _place_entity(cell: Vector2i) -> void:
	if selected_entity_type == "keen1.player_spawn":
		undo_stack.execute(level, SetPlayerSpawnCmd.new(cell))
		return
	var props := _default_properties(selected_entity_type)
	undo_stack.execute(level, AddEntityCmd.new(
		EntityDef.new(selected_entity_type, cell.x, cell.y, props)))


## Build a properties Dictionary from a type's schema defaults. Used at
## placement so each EntityDef carries its full property set (self-describing
## data; the runtime reads def.properties only and stays schema-agnostic).
func _default_properties(type_id: String) -> Dictionary:
	var out: Dictionary = {}
	for entry in EntityRegistry.get_properties_schema(type_id):
		var n: String = String(entry.get("name", ""))
		if n == "":
			continue
		out[n] = entry.get("default", null)
	return out
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
./tests/run_all.sh 2>&1 | tail -5
```
Expected: PASS — both new tests green; existing `test_editor_workflow.gd` tests unaffected.

- [ ] **Step 5: Commit**

```bash
git add src/editor/level_editor.gd tests/unit/test_editor_workflow.gd
git commit -m "feat(editor): placement seeds schema defaults into EntityDef"
```

---

## Task 4: Inspector renders enum OptionButton (schema-first, instance fallback)

**Files:**
- Modify: `src/editor/inspector_panel.gd`
- Test: `tests/unit/test_editor_map_kind.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_editor_map_kind.gd`:

```gdscript
func test_inspector_enum_option_button_writes_back():
	# A registered type with an enum schema renders an OptionButton; selecting
	# an item writes the chosen option into EntityDef.properties.
	EntityRegistry.clear()
	EntityRegistry.register_sprite("keen1.spike", EntityRegistry.CATEGORY_HAZARD, "Spike",
		"res://assets/sprites/Spike.tscn",
		[{name = "facing", default = "right", type = "enum", options = ["right", "left"]}])
	var ed := LevelEditor.new()
	add_child_autofree(ed)
	ed._ready()
	var def := EntityDef.new("keen1.spike", 1, 1, {"facing": "right"})
	ed.level.entities.append(def)
	ed.select_entity(ed.level.entities.size() - 1)
	var ob: OptionButton = ed._inspector.find_child("Prop_facing", true, false)
	assert_not_null(ob, "enum property renders an OptionButton")
	assert_eq(ob.selected, 0, "default 'right' is item 0")
	# Select 'left' (item 1) and emit the signal.
	ob.select(1)
	ob.item_selected.emit(1)
	assert_eq(def.properties["facing"], "left", "OptionButton writes chosen option back")
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
./tests/run_all.sh 2>&1 | grep -iE "test_inspector_enum|Prop_facing|OptionButton" | head
```
Expected: FAIL — `Prop_facing` not found (the inspector has no enum/OptionButton path; `find_child` returns null → `assert_not_null` fails).

- [ ] **Step 3: Rewrite `_rebuild_entity_box` to be schema-first with fallback**

In `src/editor/inspector_panel.gd`, replace the **entire** `_rebuild_entity_box` function (lines 91–149) with:

```gdscript
func _rebuild_entity_box(e: LevelEditor) -> void:
	for c in _entity_box.get_children():
		c.queue_free()
	if e.selected_entity_index < 0 or e.selected_entity_index >= e.level.entities.size():
		var l := Label.new()
		l.text = "(none — use Select/Entity tool)"
		l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_entity_box.add_child(l)
		return
	var ent: EntityDef = e.level.entities[e.selected_entity_index]
	_entity_box.add_child(_kv_label("type", ent.type))

	# X / Y (unchanged).
	var xs := SpinBox.new()
	xs.min_value = 0
	xs.max_value = 511
	xs.set_value_no_signal(ent.x)
	xs.value_changed.connect(func(_v: float) -> void: ent.x = int(xs.value))
	_entity_box.add_child(_labeled("X", xs))

	var ys := SpinBox.new()
	ys.min_value = 0
	ys.max_value = 511
	ys.set_value_no_signal(ent.y)
	ys.value_changed.connect(func(_v: float) -> void: ent.y = int(ys.value))
	_entity_box.add_child(_labeled("Y", ys))

	# 1. Schema-driven controls (enum -> OptionButton; int/bool/string typed).
	var covered: Dictionary = {}
	for s in EntityRegistry.get_properties_schema(ent.type):
		var key: String = String(s.get("name", ""))
		if key == "":
			continue
		covered[key] = true
		var stype := String(s.get("type", ""))
		var val = ent.properties.get(key, s.get("default"))
		match stype:
			"enum":
				var options: Array = s.get("options", [])
				var ob := OptionButton.new()
				ob.name = "Prop_" + key
				for opt in options:
					ob.add_item(String(opt))
				var idx := options.find(val)
				ob.select(idx if idx >= 0 else 0)
				var k_enum: Variant = key
				var opts_enum: Array = options
				ob.item_selected.connect(func(i: int) -> void:
					ent.properties[k_enum] = opts_enum[i])
				_entity_box.add_child(_labeled(key, ob))
			"bool":
				var cb := CheckBox.new()
				cb.name = "Prop_" + key
				cb.set_pressed_no_signal(bool(val))
				var kb: Variant = key
				cb.toggled.connect(func(p: bool) -> void: ent.properties[kb] = p)
				_entity_box.add_child(_labeled(key, cb))
			"int":
				var ps := SpinBox.new()
				ps.name = "Prop_" + key
				ps.min_value = -9999
				ps.max_value = 9999
				ps.set_value_no_signal(val)
				var ki: Variant = key
				ps.value_changed.connect(func(_v: float) -> void: ent.properties[ki] = int(ps.value))
				_entity_box.add_child(_labeled(key, ps))
			_:
				# "string" or unknown -> free-text LineEdit.
				var sle := LineEdit.new()
				sle.name = "Prop_" + key
				sle.text = String(val)
				var sk: Variant = key
				sle.text_changed.connect(func(t: String) -> void: ent.properties[sk] = t)
				_entity_box.add_child(_labeled(key, sle))

	# 2. Instance-key fallback: keys present on the entity but not in the schema
	#    (e.g. keen1.level_entrance, which has an empty schema today). Rendered
	#    by typeof, exactly as before.
	for key in ent.properties.keys():
		if covered.has(key):
			continue
		var val = ent.properties[key]
		match typeof(val):
			TYPE_INT, TYPE_FLOAT:
				var ps := SpinBox.new()
				ps.name = "Prop_" + str(key)
				ps.min_value = -9999
				ps.max_value = 9999
				ps.set_value_no_signal(val)
				var k: Variant = key
				ps.value_changed.connect(func(_v: float) -> void: ent.properties[k] = int(ps.value))
				_entity_box.add_child(_labeled(str(key), ps))
			TYPE_BOOL:
				var cb := CheckBox.new()
				cb.name = "Prop_" + str(key)
				cb.set_pressed_no_signal(val)
				var kb: Variant = key
				cb.toggled.connect(func(p: bool) -> void: ent.properties[kb] = p)
				_entity_box.add_child(_labeled(str(key), cb))
			TYPE_STRING:
				var sle := LineEdit.new()
				sle.name = "Prop_" + str(key)
				sle.text = val
				var sk: Variant = key
				sle.text_changed.connect(func(t: String) -> void: ent.properties[sk] = t)
				_entity_box.add_child(_labeled(str(key), sle))

	var del := Button.new()
	del.text = "Delete entity"
	del.pressed.connect(e.remove_selected_entity)
	_entity_box.add_child(del)
```

- [ ] **Step 4: Run tests to verify they pass (new + existing)**

Run:
```bash
./tests/run_all.sh 2>&1 | tail -5
```
Expected: PASS — the new enum test green, AND the existing `test_inspector_edits_string_and_bool_props` (which relies on the fallback for `keen1.level_entrance`) still green.

- [ ] **Step 5: Commit**

```bash
git add src/editor/inspector_panel.gd tests/unit/test_editor_map_kind.gd
git commit -m "feat(editor): inspector renders enum OptionButton, schema-first w/ fallback"
```

---

## Task 5: Register keen1.spike

**Files:**
- Modify: `src/episodes/keen1/episode.gd`
- Test: `tests/unit/test_episode.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_episode.gd` (before the final `func after_each():`):

```gdscript
func test_spike_registered_as_hazard_with_facing_schema():
	EntityRegistry.clear()
	Keen1Episode.new().register_entities(EntityRegistry)
	assert_true(EntityRegistry.has("keen1.spike"), "keen1.spike registered")
	var e: Dictionary = EntityRegistry.get_entry("keen1.spike")
	assert_eq(e["category"], EntityRegistry.CATEGORY_HAZARD)
	assert_eq(e["scene_path"], "res://assets/sprites/Spike.tscn")
	var schema := EntityRegistry.get_properties_schema("keen1.spike")
	assert_eq(schema.size(), 1)
	assert_eq(String(schema[0].get("name")), "facing")
	assert_eq(String(schema[0].get("default")), "right")
	assert_eq(schema[0].get("options"), ["right", "left"])
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
./tests/run_all.sh 2>&1 | grep -iE "spike_registered|keen1.spike registered" | head
```
Expected: FAIL — `keen1.spike` not registered yet.

- [ ] **Step 3: Register the spike**

In `src/episodes/keen1/episode.gd`, add this line inside `register_entities()`, immediately after the `keen1.exit_sign` `register_sprite` call (after line 38, before the `level_entrance` block):

```gdscript
	registry.register_sprite("keen1.spike", registry.CATEGORY_HAZARD, "Spike",
		"res://assets/sprites/Spike.tscn",
		[{name = "facing", default = "right", type = "enum", options = ["right", "left"]}])
```

- [ ] **Step 4: Run full suite to verify pass + no regression**

Run:
```bash
./tests/run_all.sh 2>&1 | tail -5
```
Expected: PASS — new spike-registration test green. The variant/instantiation behavior is already covered by Task 2's ad-hoc tests; with `keen1.spike` now in the default roster, `test_sprite_entity.gd`'s `after_each` (`GameManager.register_episodes()`) re-registers it between tests without conflict.

- [ ] **Step 5: Commit**

```bash
git add src/episodes/keen1/episode.gd tests/unit/test_episode.gd
git commit -m "feat(keen1): register spike entity with facing variant schema"
```

---

## Task 6: Canvas appends enum variant to entity label

**Files:**
- Modify: `src/editor/canvas_editor.gd`
- Test: `tests/unit/test_canvas_rect.gd`

- [ ] **Step 1: Write the failing tests**

Add a `before_each` to `tests/unit/test_canvas_rect.gd` (the file has none today) that guarantees the keen1 roster is registered, then append the three tests:

```gdscript
extends GutTest

func before_each():
	# entity_label() reads the registry; ensure the keen1 roster (incl. spike)
	# is present even if an earlier test script left the registry cleared.
	GameManager.register_episodes()


func test_rect_from_corners_normal():
	var r := CanvasEditor.rect_from_corners(Vector2i(2, 3), Vector2i(5, 7))
	assert_eq(r.position, Vector2i(2, 3), "position is min corner")
	assert_eq(r.size, Vector2i(4, 5), "size is inclusive cell count")


func test_rect_from_corners_reversed():
	# Corners given in any order; result is the same normalized rect.
	var r := CanvasEditor.rect_from_corners(Vector2i(5, 7), Vector2i(2, 3))
	assert_eq(r.position, Vector2i(2, 3), "position is min corner regardless of order")
	assert_eq(r.size, Vector2i(4, 5), "size is inclusive cell count")


func test_rect_from_corners_same_cell():
	var r := CanvasEditor.rect_from_corners(Vector2i(4, 4), Vector2i(4, 4))
	assert_eq(r.position, Vector2i(4, 4))
	assert_eq(r.size, Vector2i(1, 1), "single cell -> 1x1")


func test_entity_label_appends_enum_variant():
	# A spike EntityDef with facing=left -> "keen1.spike (left)".
	var def := EntityDef.new("keen1.spike", 0, 0, {"facing": "left"})
	assert_eq(CanvasEditor.entity_label(def), "keen1.spike (left)")

func test_entity_label_uses_schema_default_when_property_absent():
	var def := EntityDef.new("keen1.spike", 0, 0, {})
	# Schema default for facing is "right".
	assert_eq(CanvasEditor.entity_label(def), "keen1.spike (right)")

func test_entity_label_no_suffix_for_schemaless_entity():
	# A type with no enum schema (vorticon) -> bare type id.
	var def := EntityDef.new("keen1.vorticon", 0, 0, {"speed": 20})
	assert_eq(CanvasEditor.entity_label(def), "keen1.vorticon")
```

> Replace the whole file content with the above (it keeps the three existing `rect_from_corners` tests verbatim and adds `before_each` + the three new `entity_label` tests). The `before_each` is defensive: autoload boot already registers the roster, but earlier test scripts clear the registry.

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
./tests/run_all.sh 2>&1 | grep -iE "test_entity_label|entity_label|Invalid call" | head
```
Expected: FAIL — `CanvasEditor.entity_label` does not exist (`Invalid call / method not found`).

- [ ] **Step 3: Add the static helper and use it in `_draw`**

In `src/editor/canvas_editor.gd`:

1. Add the static helper. Place it right after the existing `static func rect_from_corners` (find it; it's near the top of the file). Add:

```gdscript
## Label drawn for an entity in the canvas: the type id, plus the value of
## each enum (variant) property in parentheses — e.g. "keen1.spike (left)".
## Static so it is unit-testable without instantiating the canvas.
static func entity_label(e: EntityDef) -> String:
	var label := e.type
	for s in EntityRegistry.get_properties_schema(e.type):
		if String(s.get("type", "")) != "enum":
			continue
		var k: String = String(s.get("name", ""))
		var v := String(e.properties.get(k, s.get("default", "")))
		if v != "":
			label = "%s (%s)" % [label, v]
	return label
```

2. In `_draw`, replace the `draw_string` call at line 76 that uses `e.type`:

```gdscript
		draw_string(get_theme_default_font(), rect.position + Vector2(2, 12), e.type, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.9))
```
with:
```gdscript
		draw_string(get_theme_default_font(), rect.position + Vector2(2, 12), CanvasEditor.entity_label(e), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.9))
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
./tests/run_all.sh 2>&1 | tail -5
```
Expected: PASS — all three new `entity_label` tests green; existing `test_canvas_rect.gd` tests unaffected.

- [ ] **Step 5: Commit**

```bash
git add src/editor/canvas_editor.gd tests/unit/test_canvas_rect.gd
git commit -m "feat(editor): canvas label appends enum variant value"
```

---

## Final verification

- [ ] **Run the complete test suite**

```bash
./tests/run_all.sh
```
Expected: all tests pass, zero failures. Pay special attention to:
- `test_editor_map_kind.gd::test_inspector_edits_string_and_bool_props` (the level_entrance fallback regression guard).
- `test_sprite_entity.gd` (variant visibility + existing wrapper tests).
- `test_entity_registry_instantiate.gd` (existing scripted-entity spawn unchanged).

- [ ] **Manual smoke test (optional but recommended)**

```bash
make run-app   # or: make edit
```
In the editor: pick the **Entity** tool, select **Spike** from the palette (Hazards group), place a cell. The inspector shows a **facing** `OptionButton` defaulting to `right`; the canvas labels it `keen1.spike (right)`. Switch to `left` → label becomes `keen1.spike (left)`. Click **Test ▶** → the placed spike renders facing left. Esc returns to the editor; the choice persisted.

---

## Spec coverage map

| Spec section | Task(s) |
|---|---|
| §3 Property schema model (shape, validation, `get_properties_schema`) | Task 1 |
| §4 Placement seeds defaults | Task 3 |
| §5 Schema-driven inspector (OptionButton + instance fallback) | Task 4 |
| §6 SpriteEntity variant application (descendant walk) | Task 2 |
| §7 Spike registration | Task 5 |
| §8 Canvas label suffix | Task 6 |
| §10 Testing | Every task (TDD) |
