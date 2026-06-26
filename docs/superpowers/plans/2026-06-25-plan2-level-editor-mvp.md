# keen_reloaded — Plan 2: Level Editor MVP

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the integrated, dev-gated Level Editor — a 3-panel UI (palette / canvas / inspector) that authors a `LevelData` resource in memory: paint tiles, place entities, edit metadata, undo/redo, and save/load `.tres`.

**Architecture:** A single `LevelEditor` controller is the source of truth (holds the `LevelData`, active layer, active tool, selection, and an `UndoStack`). UI is built programmatically in GDScript (trivial `.tscn` + code-built node trees) to keep scenes auditable. All mutating logic is expressed as `EditorCommand` objects applied to a `LevelData` — this layer is fully GUT-testable; the UI layer is verified by running the editor in Godot. The editor renders tiles itself via `_draw()` (colored cells) so it has **no art dependency** — real tilesets arrive in a later plan. The **Test ▶** button is wired but stubbed, because live gameplay needs the runtime (Plan 3).

**Tech Stack:** Godot 4.7, GDScript, GUT (Godot Unit Test).

**Godot binary:** `/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot`
(Set a shell alias if convenient: `alias godot="/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot"`)

---

## Scope & Dependencies

- **In scope:** 3-panel editor UI, tile painting (paint/erase/fill), entity placement/removal, player-spawn editing, metadata editing, undo/redo, New/Save/Load `.tres`, main-menu entry.
- **Deferred (needs Plan 3 runtime):** the **Test ▶** live gameplay drop-in. The button exists and emits a signal, but shows a "runtime arrives in Plan 3" message.
- **`EntityRegistry`** is extended here with its **data layer only** (`register` / `get_palette_entries`) — the editor's entity palette needs it. Plan 3 adds scene `instantiate(...)`.

## Testing strategy

| Layer | How tested |
|-------|-----------|
| `LevelData` generic accessors, `EditorCommand` family, `UndoStack`, `EntityRegistry` data layer, `EditorColors` | GUT unit tests (Tasks 1–6) |
| Editor UI (panels, input, dialogs) | Manual verification by opening the editor in Godot (Tasks 7–12) |

All tasks end with `./tests/run_all.sh` green or an explicit manual-verification checklist.

---

## File Structure (this plan)

| File | Responsibility |
|------|----------------|
| `src/data/level_data.gd` | Add generic `get_tile`/`set_tile` by layer name + layer name constants |
| `src/editor/editor_command.gd` | Base `EditorCommand` class (apply/undo/describe) |
| `src/editor/paint_cells_cmd.gd` | `PaintCellsCmd` — a paint/erase stroke (one undo per stroke) |
| `src/editor/flood_fill_cmd.gd` | `FloodFillCmd` — flood-fill connected region |
| `src/editor/add_entity_cmd.gd` | `AddEntityCmd` |
| `src/editor/remove_entity_cmd.gd` | `RemoveEntityCmd` |
| `src/editor/set_player_spawn_cmd.gd` | `SetPlayerSpawnCmd` |
| `src/editor/undo_stack.gd` | `UndoStack` — linear undo/redo of commands |
| `src/editor/editor_colors.gd` | `EditorColors` — tile-id → display color (no art deps) |
| `src/core/entity_registry.gd` | Extend stub: data layer (register/lookup/palette entries) |
| `src/editor/level_editor.tscn` | Minimal editor scene root (full-rect Control + script) |
| `src/editor/level_editor.gd` | Controller: state, undo stack, New/Save/Load, builds layout |
| `src/editor/canvas_editor.gd` | Tile canvas: `_draw()` rendering + mouse input + zoom |
| `src/editor/palette_panel.gd` | Left panel: tile picker, layer toggles, tools, entity list |
| `src/editor/inspector_panel.gd` | Right panel: level metadata + selected entity props + spawn |
| `src/ui/main_menu.tscn` | Add "Editor" button (dev entry point) |
| `tests/unit/test_level_data_layers.gd` | Generic layer accessor tests |
| `tests/unit/test_editor_commands.gd` | Command + UndoStack tests |
| `tests/unit/test_entity_registry_data.gd` | EntityRegistry data-layer tests |
| `tests/unit/test_editor_colors.gd` | EditorColors tests |

---

## Task 1: `LevelData` — generic tile accessors by layer name

**Files:**
- Modify: `src/data/level_data.gd` (add constants + `get_tile` / `set_tile`)
- Create: `tests/unit/test_level_data_layers.gd`

The command classes (Task 2+) reference a layer by name (`"geometry"` / `"foreground"` / `"background"`). We add generic accessors so commands need not branch per layer.

- [ ] **Step 1: Write the failing test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_level_data_layers.gd`:

```gdscript
extends GutTest

func _make_level() -> LevelData:
	var ld := LevelData.new()
	ld.width = 3
	ld.height = 2
	ld.fill_blank()
	return ld

func test_layer_name_constants_exist():
	assert_eq(LevelData.LAYER_GEOMETRY, "geometry")
	assert_eq(LevelData.LAYER_FOREGROUND, "foreground")
	assert_eq(LevelData.LAYER_BACKGROUND, "background")

func test_get_tile_and_set_tile_geometry():
	var ld := _make_level()
	ld.set_tile(LevelData.LAYER_GEOMETRY, 1, 0, 7)
	assert_eq(ld.get_tile(LevelData.LAYER_GEOMETRY, 1, 0), 7)
	assert_eq(ld.get_geometry_tile(1, 0), 7, "generic setter writes the same backing array")

func test_get_tile_and_set_tile_foreground():
	var ld := _make_level()
	ld.set_tile(LevelData.LAYER_FOREGROUND, 2, 1, 5)
	assert_eq(ld.get_tile(LevelData.LAYER_FOREGROUND, 2, 1), 5)
	assert_eq(ld.get_foreground_tile(2, 1), 5)

func test_get_tile_and_set_tile_background():
	var ld := _make_level()
	ld.set_tile(LevelData.LAYER_BACKGROUND, 0, 0, 9)
	assert_eq(ld.get_tile(LevelData.LAYER_BACKGROUND, 0, 0), 9)
	assert_eq(ld.get_background_tile(0, 0), 9)

func test_unknown_layer_get_returns_zero():
	var ld := _make_level()
	assert_eq(ld.get_tile("nope", 0, 0), 0)

func test_out_of_bounds_get_returns_zero():
	var ld := _make_level()
	assert_eq(ld.get_tile(LevelData.LAYER_GEOMETRY, 99, 99), 0)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `LAYER_GEOMETRY` / `get_tile` / `set_tile` not found on `LevelData`.

- [ ] **Step 3: Add constants + generic accessors to `LevelData`**

In `/Users/eugene/git/keen_reloaded/src/data/level_data.gd`, insert these constants right after the `extends Resource` line (before the `@export_group("Metadata")` line):

```gdscript

const LAYER_GEOMETRY := "geometry"
const LAYER_FOREGROUND := "foreground"
const LAYER_BACKGROUND := "background"
```

Then append at the end of the file (after `set_background_tile`):

```gdscript


## Generic layer access: returns the tile id at (x,y) for the named layer.
## Unknown layers and out-of-bounds cells return 0.
func get_tile(layer: String, x: int, y: int) -> int:
	match layer:
		LAYER_GEOMETRY:
			return get_geometry_tile(x, y)
		LAYER_FOREGROUND:
			return get_foreground_tile(x, y)
		LAYER_BACKGROUND:
			return get_background_tile(x, y)
	return 0


## Generic layer access: sets the tile id at (x,y) for the named layer.
## Unknown layers / out-of-bounds cells are ignored.
func set_tile(layer: String, x: int, y: int, tile_id: int) -> void:
	match layer:
		LAYER_GEOMETRY:
			set_geometry_tile(x, y, tile_id)
		LAYER_FOREGROUND:
			set_foreground_tile(x, y, tile_id)
		LAYER_BACKGROUND:
			set_background_tile(x, y, tile_id)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all layer accessor tests green (plus existing tests still green).

- [ ] **Step 5: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/data/level_data.gd tests/unit/test_level_data_layers.gd
git commit -m "feat: add generic layer-name tile accessors to LevelData"
```

---

## Task 2: `EditorCommand` base + `PaintCellsCmd` + `UndoStack`

**Files:**
- Create: `src/editor/editor_command.gd`
- Create: `src/editor/paint_cells_cmd.gd`
- Create: `src/editor/undo_stack.gd`
- Create: `tests/unit/test_editor_commands.gd`

`PaintCellsCmd` represents a paint/erase stroke: a set of cells each remembering its previous id, so one stroke = one undo step. The canvas (Task 8) applies cells live during a drag, then hands the already-applied command to `UndoStack.push_applied(...)`.

- [ ] **Step 1: Write the failing test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_editor_commands.gd`:

```gdscript
extends GutTest

const G := "geometry"

func _level() -> LevelData:
	var ld := LevelData.new()
	ld.width = 3
	ld.height = 3
	ld.fill_blank()
	return ld

func test_paint_cells_single():
	var ld := _level()
	var cmd := PaintCellsCmd.new(G, 1)
	cmd.paint(ld, 0, 0)
	assert_eq(ld.get_tile(G, 0, 0), 1)
	cmd.undo(ld)
	assert_eq(ld.get_tile(G, 0, 0), 0, "undo restores previous id")

func test_paint_cells_records_each_cell_once():
	var ld := _level()
	ld.set_tile(G, 1, 1, 4)  # pre-existing id
	var cmd := PaintCellsCmd.new(G, 2)
	cmd.paint(ld, 1, 1)
	cmd.paint(ld, 1, 1)  # same cell twice in a stroke
	cmd.paint(ld, 2, 0)
	assert_eq(ld.get_tile(G, 1, 1), 2)
	assert_eq(ld.get_tile(G, 2, 0), 2)
	cmd.undo(ld)
	assert_eq(ld.get_tile(G, 1, 1), 4, "restores original 4, not 0")
	assert_eq(ld.get_tile(G, 2, 0), 0)

func test_undo_stack_execute_and_undo():
	var ld := _level()
	var s := UndoStack.new()
	assert_false(s.can_undo())
	s.execute(ld, PaintCellsCmd.new(G, 5))
	assert_true(s.can_undo())
	assert_false(s.can_redo())
	s.undo(ld)
	assert_false(s.can_undo())
	assert_true(s.can_redo())

func test_undo_stack_push_applied_does_not_double_apply():
	var ld := _level()
	var s := UndoStack.new()
	var cmd := PaintCellsCmd.new(G, 3)
	cmd.paint(ld, 0, 0)  # applied live
	assert_eq(ld.get_tile(G, 0, 0), 3)
	s.push_applied(ld, cmd)  # record without re-applying
	assert_eq(ld.get_tile(G, 0, 0), 3, "no double apply")
	s.undo(ld)
	assert_eq(ld.get_tile(G, 0, 0), 0)
	s.redo(ld)
	assert_eq(ld.get_tile(G, 0, 0), 3)

func test_new_command_clears_redo():
	var ld := _level()
	var s := UndoStack.new()
	s.execute(ld, PaintCellsCmd.new(G, 1))
	s.undo(ld)
	assert_true(s.can_redo())
	s.execute(ld, PaintCellsCmd.new(G, 2))
	assert_false(s.can_redo(), "redo cleared after new command")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `EditorCommand` / `PaintCellsCmd` / `UndoStack` classes not found.

- [ ] **Step 3: Implement `EditorCommand` base class**

Create `/Users/eugene/git/keen_reloaded/src/editor/editor_command.gd`:

```gdscript
class_name EditorCommand
extends RefCounted
## Base class for an undoable editor action on a LevelData.
## Subclasses mutate the level in apply() and reverse it in undo().

func apply(_level: LevelData) -> void:
	push_warning("EditorCommand.apply not overridden: " + describe())

func undo(_level: LevelData) -> void:
	push_warning("EditorCommand.undo not overridden: " + describe())

func describe() -> String:
	return "EditorCommand"
```

- [ ] **Step 4: Implement `PaintCellsCmd`**

Create `/Users/eugene/git/keen_reloaded/src/editor/paint_cells_cmd.gd`:

```gdscript
class_name PaintCellsCmd
extends EditorCommand
## A paint or erase stroke over a set of cells. Each cell remembers its previous
## tile id so the whole stroke is a single undo step. Call paint() during a drag
## (applies live), then hand the command to UndoStack.push_applied() on mouse-up.

var layer: String
var new_id: int
var _prev: Dictionary = {}  # Vector2i -> int (previous id)

func _init(p_layer: String, p_new_id: int) -> void:
	layer = p_layer
	new_id = p_new_id

## Records the previous id (first time only) and writes the new id. Idempotent per cell.
func paint(level: LevelData, x: int, y: int) -> void:
	var cell := Vector2i(x, y)
	if not _prev.has(cell):
		_prev[cell] = level.get_tile(layer, x, y)
	level.set_tile(layer, x, y, new_id)

func apply(level: LevelData) -> void:
	for cell: Vector2i in _prev:
		level.set_tile(layer, cell.x, cell.y, new_id)

func undo(level: LevelData) -> void:
	for cell: Vector2i in _prev:
		level.set_tile(layer, cell.x, cell.y, int(_prev[cell]))

func describe() -> String:
	return "PaintCells(%s -> %d, %d cells)" % [layer, new_id, _prev.size()]
```

- [ ] **Step 5: Implement `UndoStack`**

Create `/Users/eugene/git/keen_reloaded/src/editor/undo_stack.gd`:

```gdscript
class_name UndoStack
extends RefCounted
## Linear undo/redo of EditorCommands applied to a LevelData.

signal changed

var _undo: Array[EditorCommand] = []
var _redo: Array[EditorCommand] = []

## Applies the command now, pushes it to undo history, and clears redo.
func execute(level: LevelData, cmd: EditorCommand) -> void:
	cmd.apply(level)
	_push(cmd)

## Records an already-applied command (e.g. a paint stroke applied live) without
## re-applying. Pushes to undo history and clears redo.
func push_applied(_level: LevelData, cmd: EditorCommand) -> void:
	_push(cmd)

func _push(cmd: EditorCommand) -> void:
	_undo.append(cmd)
	_redo.clear()
	changed.emit()

func undo(level: LevelData) -> void:
	if _undo.is_empty():
		return
	var cmd: EditorCommand = _undo.pop_back()
	cmd.undo(level)
	_redo.append(cmd)
	changed.emit()

func redo(level: LevelData) -> void:
	if _redo.is_empty():
		return
	var cmd: EditorCommand = _redo.pop_back()
	cmd.apply(level)
	_undo.append(cmd)
	changed.emit()

func can_undo() -> bool:
	return not _undo.is_empty()

func can_redo() -> bool:
	return not _redo.is_empty()

func clear() -> void:
	_undo.clear()
	_redo.clear()
	changed.emit()
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all PaintCells / UndoStack tests green.

- [ ] **Step 7: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/editor/editor_command.gd src/editor/paint_cells_cmd.gd src/editor/undo_stack.gd tests/unit/test_editor_commands.gd
git commit -m "feat: add EditorCommand base, PaintCellsCmd, and UndoStack"
```

---

## Task 3: `FloodFillCmd` — fill connected region

**Files:**
- Create: `src/editor/flood_fill_cmd.gd`
- Modify: `tests/unit/test_editor_commands.gd` (append flood-fill tests)

- [ ] **Step 1: Append failing tests**

Append to `/Users/eugene/git/keen_reloaded/tests/unit/test_editor_commands.gd`:

```gdscript
func test_flood_fill_fills_connected_region():
	var ld := _level()
	# carve an L-shaped region of 1s
	ld.set_tile(G, 0, 0, 1)
	ld.set_tile(G, 1, 0, 1)
	ld.set_tile(G, 0, 1, 1)
	var cmd := FloodFillCmd.new(G, Vector2i(0, 0), 2)
	UndoStack.new().execute(ld, cmd)
	assert_eq(ld.get_tile(G, 0, 0), 2)
	assert_eq(ld.get_tile(G, 1, 0), 2)
	assert_eq(ld.get_tile(G, 0, 1), 2)
	assert_eq(ld.get_tile(G, 1, 1), 0, "diagonal not connected, stays empty")
	assert_eq(ld.get_tile(G, 2, 0), 0)

func test_flood_fill_noop_when_same_id():
	var ld := _level()
	ld.set_tile(G, 0, 0, 3)
	var cmd := FloodFillCmd.new(G, Vector2i(0, 0), 3)  # same as target
	var s := UndoStack.new()
	s.execute(ld, cmd)
	assert_eq(ld.get_tile(G, 0, 0), 3)
	s.undo(ld)
	assert_eq(ld.get_tile(G, 0, 0), 3, "nothing changed, undo is a noop too")

func test_flood_fill_undo_restores_varied_region():
	var ld := _level()
	ld.set_tile(G, 0, 0, 1)
	ld.set_tile(G, 1, 0, 1)
	ld.set_tile(G, 2, 0, 5)  # different id, not filled
	var s := UndoStack.new()
	s.execute(ld, FloodFillCmd.new(G, Vector2i(0, 0), 9))
	assert_eq(ld.get_tile(G, 0, 0), 9)
	s.undo(ld)
	assert_eq(ld.get_tile(G, 0, 0), 1)
	assert_eq(ld.get_tile(G, 1, 0), 1)
	assert_eq(ld.get_tile(G, 2, 0), 5)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `FloodFillCmd` class not found.

- [ ] **Step 3: Implement `FloodFillCmd`**

Create `/Users/eugene/git/keen_reloaded/src/editor/flood_fill_cmd.gd`:

```gdscript
class_name FloodFillCmd
extends EditorCommand
## Flood-fills the 4-connected region (starting at origin) whose cells equal the
## origin's current id, setting them to new_id. Stores the previous id per changed
## cell so undo fully restores the region.

var layer: String
var origin: Vector2i
var new_id: int
var _changed: Dictionary = {}  # Vector2i -> int (previous id)

func _init(p_layer: String, p_origin: Vector2i, p_new_id: int) -> void:
	layer = p_layer
	origin = p_origin
	new_id = p_new_id

func apply(level: LevelData) -> void:
	_changed.clear()
	var target := level.get_tile(layer, origin.x, origin.y)
	if target == new_id:
		return
	var stack: Array[Vector2i] = [origin]
	var seen: Dictionary = {}
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if seen.has(c):
			continue
		if c.x < 0 or c.y < 0 or c.x >= level.width or c.y >= level.height:
			continue
		if level.get_tile(layer, c.x, c.y) != target:
			continue
		seen[c] = true
		_changed[c] = target
		level.set_tile(layer, c.x, c.y, new_id)
		stack.append(c + Vector2i(1, 0))
		stack.append(c + Vector2i(-1, 0))
		stack.append(c + Vector2i(0, 1))
		stack.append(c + Vector2i(0, -1))

func undo(level: LevelData) -> void:
	for cell: Vector2i in _changed:
		level.set_tile(layer, cell.x, cell.y, int(_changed[cell]))

func describe() -> String:
	return "FloodFill(%s @ %s -> %d)" % [layer, str(origin), new_id]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all flood-fill tests green.

- [ ] **Step 5: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/editor/flood_fill_cmd.gd tests/unit/test_editor_commands.gd
git commit -m "feat: add FloodFillCmd for editor fill tool"
```

---

## Task 4: Entity + player-spawn commands

**Files:**
- Create: `src/editor/add_entity_cmd.gd`
- Create: `src/editor/remove_entity_cmd.gd`
- Create: `src/editor/set_player_spawn_cmd.gd`
- Modify: `tests/unit/test_editor_commands.gd` (append entity/spawn tests)

- [ ] **Step 1: Append failing tests**

Append to `/Users/eugene/git/keen_reloaded/tests/unit/test_editor_commands.gd`:

```gdscript
func test_add_entity_command():
	var ld := _level()
	var s := UndoStack.new()
	assert_eq(ld.entities.size(), 0)
	s.execute(ld, AddEntityCmd.new(EntityDef.new("vorticon", 1, 2)))
	assert_eq(ld.entities.size(), 1)
	assert_eq(ld.entities[0].type, "vorticon")
	s.undo(ld)
	assert_eq(ld.entities.size(), 0)
	s.redo(ld)
	assert_eq(ld.entities.size(), 1)
	assert_eq(ld.entities[0].x, 1)

func test_remove_entity_command_restores_on_undo():
	var ld := _level()
	ld.entities.append(EntityDef.new("candy", 3, 4, {"value": 100}))
	ld.entities.append(EntityDef.new("yorp", 5, 6))
	var s := UndoStack.new()
	s.execute(ld, RemoveEntityCmd.new(0))  # remove candy
	assert_eq(ld.entities.size(), 1)
	assert_eq(ld.entities[0].type, "yorp")
	s.undo(ld)
	assert_eq(ld.entities.size(), 2)
	assert_eq(ld.entities[0].type, "candy")
	assert_eq(ld.entities[0].properties.get("value"), 100, "restored entity keeps props")
	assert_eq(ld.entities[1].type, "yorp")

func test_remove_entity_out_of_range_is_noop():
	var ld := _level()
	var s := UndoStack.new()
	s.execute(ld, RemoveEntityCmd.new(0))  # empty list
	assert_eq(ld.entities.size(), 0)
	s.undo(ld)
	assert_eq(ld.entities.size(), 0)

func test_set_player_spawn_command():
	var ld := _level()
	ld.player_spawn = Vector2i(0, 0)
	var s := UndoStack.new()
	s.execute(ld, SetPlayerSpawnCmd.new(Vector2i(7, 3)))
	assert_eq(ld.player_spawn, Vector2i(7, 3))
	s.undo(ld)
	assert_eq(ld.player_spawn, Vector2i(0, 0))
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `AddEntityCmd` / `RemoveEntityCmd` / `SetPlayerSpawnCmd` not found.

- [ ] **Step 3: Implement `AddEntityCmd`**

Create `/Users/eugene/git/keen_reloaded/src/editor/add_entity_cmd.gd`:

```gdscript
class_name AddEntityCmd
extends EditorCommand
## Appends one entity to the level. Undo removes it at its recorded index.

var entity: EntityDef
var _index: int = -1

func _init(p_entity: EntityDef) -> void:
	entity = p_entity

func apply(level: LevelData) -> void:
	_index = level.entities.size()
	level.entities.append(entity)

func undo(level: LevelData) -> void:
	if _index >= 0 and _index < level.entities.size():
		level.entities.remove_at(_index)

func describe() -> String:
	return "AddEntity(%s @ %d,%d)" % [entity.type, entity.x, entity.y]
```

- [ ] **Step 4: Implement `RemoveEntityCmd`**

Create `/Users/eugene/git/keen_reloaded/src/editor/remove_entity_cmd.gd`:

```gdscript
class_name RemoveEntityCmd
extends EditorCommand
## Removes the entity at a given index. Undo re-inserts it (with its properties).

var index: int
var _entity: EntityDef = null

func _init(p_index: int) -> void:
	index = p_index

func apply(level: LevelData) -> void:
	if index >= 0 and index < level.entities.size():
		_entity = level.entities[index]
		level.entities.remove_at(index)

func undo(level: LevelData) -> void:
	if _entity != null and index >= 0 and index <= level.entities.size():
		level.entities.insert(index, _entity)

func describe() -> String:
	return "RemoveEntity(@%d)" % index
```

- [ ] **Step 5: Implement `SetPlayerSpawnCmd`**

Create `/Users/eugene/git/keen_reloaded/src/editor/set_player_spawn_cmd.gd`:

```gdscript
class_name SetPlayerSpawnCmd
extends EditorCommand
## Sets the player spawn tile coordinate. Undo restores the previous spawn.

var new_spawn: Vector2i
var _prev: Vector2i = Vector2i.ZERO

func _init(p_new_spawn: Vector2i) -> void:
	new_spawn = p_new_spawn

func apply(level: LevelData) -> void:
	_prev = level.player_spawn
	level.player_spawn = new_spawn

func undo(level: LevelData) -> void:
	level.player_spawn = _prev

func describe() -> String:
	return "SetPlayerSpawn(%s)" % str(new_spawn)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all entity/spawn command tests green.

- [ ] **Step 7: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/editor/add_entity_cmd.gd src/editor/remove_entity_cmd.gd src/editor/set_player_spawn_cmd.gd tests/unit/test_editor_commands.gd
git commit -m "feat: add entity + player-spawn editor commands"
```

---

## Task 5: `EntityRegistry` data layer

**Files:**
- Modify: `src/core/entity_registry.gd` (replace stub with data layer)
- Create: `tests/unit/test_entity_registry_data.gd`

The editor's entity palette reads from this registry. We implement the catalog/data API only; Plan 3 adds scene instantiation.

- [ ] **Step 1: Write the failing test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_entity_registry_data.gd`:

```gdscript
extends GutTest

func test_register_and_lookup():
	EntityRegistry.clear()
	EntityRegistry.register("vorticon", EntityRegistry.CATEGORY_ENEMY, "Vorticon")
	assert_true(EntityRegistry.has("vorticon"))
	var e: Dictionary = EntityRegistry.get_entry("vorticon")
	assert_eq(e["type_id"], "vorticon")
	assert_eq(e["category"], EntityRegistry.CATEGORY_ENEMY)
	assert_eq(e["label"], "Vorticon")

func test_get_entry_missing_returns_empty():
	EntityRegistry.clear()
	assert_false(EntityRegistry.has("nope"))
	assert_eq(EntityRegistry.get_entry("nope"), {})

func test_palette_entries_sorted_by_category_then_label():
	EntityRegistry.clear()
	EntityRegistry.register("yorp", EntityRegistry.CATEGORY_ENEMY, "Yorp")
	EntityRegistry.register("candy", EntityRegistry.CATEGORY_ITEM, "Candy")
	EntityRegistry.register("vorticon", EntityRegistry.CATEGORY_ENEMY, "Vorticon")
	var entries: Array = EntityRegistry.get_palette_entries()
	assert_eq(entries.size(), 3)
	# enemies (e) sort before items (i); within enemies: Vorticon before Yorp
	assert_eq(entries[0]["type_id"], "vorticon")
	assert_eq(entries[1]["type_id"], "yorp")
	assert_eq(entries[2]["type_id"], "candy")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `register` / `get_entry` / `get_palette_entries` not found on `EntityRegistry`.

- [ ] **Step 3: Replace the `EntityRegistry` stub**

Overwrite `/Users/eugene/git/keen_reloaded/src/core/entity_registry.gd` with:

```gdscript
extends Node
## Extensible entity catalog (autoload). This plan implements the DATA layer:
## register / lookup / palette entries, which the editor's entity palette reads.
## Plan 3 adds scene instantiation: instantiate(type_id, position, props) -> Node2D.

const CATEGORY_ENEMY := "enemy"
const CATEGORY_ITEM := "item"
const CATEGORY_HAZARD := "hazard"
const CATEGORY_SPECIAL := "special"

var _entries: Dictionary = {}  # type_id -> { type_id, category, label, properties }


func _ready() -> void:
	_register_defaults()


## Ships a small default set so the editor palette isn't empty before episodes
## register their own content (Plan 3+). Tests call clear() to start clean.
func _register_defaults() -> void:
	register("vorticon", CATEGORY_ENEMY, "Vorticon")
	register("yorp", CATEGORY_ENEMY, "Yorp")
	register("butler", CATEGORY_HAZARD, "Butler Robot")
	register("candy", CATEGORY_ITEM, "Candy")
	register("exit_door", CATEGORY_SPECIAL, "Exit Door")
	register("player_spawn", CATEGORY_SPECIAL, "Player Spawn")


func register(type_id: String, category: String, label: String, properties: Array = []) -> void:
	_entries[type_id] = {
		"type_id": type_id,
		"category": category,
		"label": label,
		"properties": properties,
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all EntityRegistry data-layer tests green.

- [ ] **Step 5: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/core/entity_registry.gd tests/unit/test_entity_registry_data.gd
git commit -m "feat: add EntityRegistry data layer for editor palette"
```

---

## Task 6: `EditorColors` helper

**Files:**
- Create: `src/editor/editor_colors.gd`
- Create: `tests/unit/test_editor_colors.gd`

The editor renders tiles as colored cells (no art dependency yet). This helper maps a tile id to a stable color and tints per layer.

- [ ] **Step 1: Write the failing test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_editor_colors.gd`:

```gdscript
extends GutTest

func test_empty_tile_is_transparent():
	assert_eq(EditorColors.tile_color(0).a, 0.0)

func test_positive_tiles_are_opaque():
	assert_eq(EditorColors.tile_color(1).a, 1.0)
	assert_eq(EditorColors.tile_color(7).a, 1.0)

func test_tile_color_is_stable():
	assert_eq(EditorColors.tile_color(3), EditorColors.tile_color(3))

func test_distinct_ids_give_distinct_colors():
	assert_ne(EditorColors.tile_color(1), EditorColors.tile_color(2))

func test_layer_tint_unknown_returns_white():
	assert_eq(EditorColors.layer_tint("nope"), Color(1, 1, 1, 1))
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `EditorColors` class not found.

- [ ] **Step 3: Implement `EditorColors`**

Create `/Users/eugene/git/keen_reloaded/src/editor/editor_colors.gd`:

```gdscript
class_name EditorColors
extends RefCounted
## Maps tile ids to display colors for the editor canvas/palette. No art assets
## required — real TileSets arrive in a later plan.

const EMPTY := Color(0, 0, 0, 0)

static func tile_color(tile_id: int) -> Color:
	if tile_id <= 0:
		return EMPTY
	# golden-ratio hue stride => stable, well-spread distinct hues
	var h := fmod(float(tile_id) * 0.61803398875, 1.0)
	return Color.from_hsv(h, 0.55, 0.85, 1.0)

static func layer_tint(layer: String) -> Color:
	match layer:
		LevelData.LAYER_GEOMETRY:
			return Color(1, 1, 1, 1)
		LevelData.LAYER_FOREGROUND:
			return Color(1, 1, 1, 0.9)
		LevelData.LAYER_BACKGROUND:
			return Color(1, 1, 1, 0.6)
	return Color(1, 1, 1, 1)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_all.sh`
Expected: PASS — all EditorColors tests green.

- [ ] **Step 5: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/editor/editor_colors.gd tests/unit/test_editor_colors.gd
git commit -m "feat: add EditorColors helper for tile id -> color mapping"
```

---

## Task 7: `LevelEditor` scene + controller scaffold

**Files:**
- Create: `src/editor/level_editor.tscn`
- Create: `src/editor/level_editor.gd`

The controller is the single source of truth and builds the whole layout in `_ready()`. This task creates the scene, the controller state, the layout shell (toolbar / three columns / status bar), and the public API the panels call. Panels (Tasks 8–10) are added next; their `refresh()` methods are called defensively here.

> **Verification for Tasks 7–12 is manual** (run the editor in Godot). Parse errors are caught by `godot --headless --import --quit` after each task. Unit tests stay green throughout.

- [ ] **Step 1: Write the controller script**

Create `/Users/eugene/git/keen_reloaded/src/editor/level_editor.gd`:

```gdscript
class_name LevelEditor
extends Control
## Integrated level editor controller. Single source of truth: holds the active
## LevelData, active layer, active tool, selection, and the UndoStack. Builds the
## 3-panel layout in code; child panels read state and call back via methods here.

signal level_changed
signal selection_changed
signal status_changed(text: String)

const TOOLS := {
	"paint": "Paint",
	"erase": "Eraser",
	"fill": "Fill",
	"entity": "Entity",
	"select": "Select",
}
const PALETTE_TILE_COUNT := 8   # ids 1..N shown in the tile picker
const DEFAULT_WIDTH := 32
const DEFAULT_HEIGHT := 24

var level: LevelData
var undo_stack: UndoStack
var active_layer: String = LevelData.LAYER_GEOMETRY
var active_tool: String = "paint"
var selected_tile_id: int = 1
var selected_entity_type: String = "vorticon"
var selected_entity_index: int = -1

var _canvas: CanvasEditor
var _palette: PalettePanel
var _inspector: InspectorPanel
var _status: Label
var _save_dialog: FileDialog
var _load_dialog: FileDialog
var _last_path: String = ""


func _ready() -> void:
	undo_stack = UndoStack.new()
	undo_stack.changed.connect(_on_history_changed)
	_new_level()
	_build_ui()


# ------------------------------------------------------------------ state API

func _new_level() -> void:
	level = LevelData.new()
	level.level_id = "new_level"
	level.level_name = "Untitled"
	level.width = DEFAULT_WIDTH
	level.height = DEFAULT_HEIGHT
	level.fill_blank()
	undo_stack.clear()
	selected_entity_index = -1
	_last_path = ""
	_broadcast()


## Public entry used by the toolbar "New" button.
func new_level() -> void:
	_new_level()


## Public entry used by the toolbar "Save" button.
func save_level() -> void:
	_save_dialog.popup_centered_clamped(Vector2i(700, 500))


## Public entry used by the toolbar "Load" button.
func load_level() -> void:
	_load_dialog.popup_centered_clamped(Vector2i(700, 500))


## Public entry used by the toolbar "Test" button. Live gameplay needs the
## runtime (Plan 3); for now this just reports status.
func test_run() -> void:
	_set_status("Test: gameplay runtime arrives in Plan 3.")


func set_active_layer(layer: String) -> void:
	active_layer = layer
	_broadcast()


func set_tool(tool: String) -> void:
	active_tool = tool
	_broadcast()


func set_selected_tile_id(id: int) -> void:
	selected_tile_id = id
	_broadcast()


func set_selected_entity_type(type_id: String) -> void:
	selected_entity_type = type_id
	_broadcast()


## Paint/erase/fill at a tile cell, honoring the active tool. Pushes one command.
func edit_at_cell(cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= level.width or cell.y >= level.height:
		return
	match active_tool:
		"paint":
			var cmd := PaintCellsCmd.new(active_layer, selected_tile_id)
			cmd.paint(level, cell.x, cell.y)
			undo_stack.push_applied(level, cmd)
		"erase":
			var cmd := PaintCellsCmd.new(active_layer, 0)
			cmd.paint(level, cell.x, cell.y)
			undo_stack.push_applied(level, cmd)
		"fill":
			undo_stack.execute(level, FloodFillCmd.new(active_layer, cell, selected_tile_id))
		"entity":
			_place_entity(cell)
	_broadcast()


## Called repeatedly by the canvas during a paint/erase drag. Coalesces the whole
## stroke into one PaintCellsCmd that is recorded once on mouse-up.
var _stroke: PaintCellsCmd = null

func begin_stroke() -> void:
	if active_tool == "paint":
		_stroke = PaintCellsCmd.new(active_layer, selected_tile_id)
	elif active_tool == "erase":
		_stroke = PaintCellsCmd.new(active_layer, 0)


func stroke_to(cell: Vector2i) -> void:
	if _stroke == null:
		return
	if cell.x < 0 or cell.y < 0 or cell.x >= level.width or cell.y >= level.height:
		return
	_stroke.paint(level, cell.x, cell.y)
	_refresh_canvas_and_status()


func end_stroke() -> void:
	if _stroke != null:
		undo_stack.push_applied(level, _stroke)
		_stroke = null
		_broadcast()


func _place_entity(cell: Vector2i) -> void:
	if selected_entity_type == "player_spawn":
		undo_stack.execute(level, SetPlayerSpawnCmd.new(cell))
		return
	undo_stack.execute(level, AddEntityCmd.new(EntityDef.new(selected_entity_type, cell.x, cell.y)))


## Returns the entity nearest to a tile cell (within 1 tile), or -1.
func entity_at_cell(cell: Vector2i) -> int:
	var best := -1
	var best_d := 1.5
	for i in range(level.entities.size()):
		var e: EntityDef = level.entities[i]
		var d := Vector2(e.x - cell.x, e.y - cell.y).length()
		if d <= best_d:
			best_d = d
			best = i
	return best


func select_entity(index: int) -> void:
	selected_entity_index = index
	selection_changed.emit()
	_inspector.refresh(self)
	_set_status(_cursor_status())


func remove_selected_entity() -> void:
	if selected_entity_index >= 0 and selected_entity_index < level.entities.size():
		undo_stack.execute(level, RemoveEntityCmd.new(selected_entity_index))
		selected_entity_index = -1
		_broadcast()


func undo() -> void:
	undo_stack.undo(level)
	_broadcast()


func redo() -> void:
	undo_stack.redo(level)
	_broadcast()


# ------------------------------------------------------------------ UI build

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(PRESET_FULL_RECT)
	add_child(root)

	root.add_child(_build_toolbar())

	var columns := HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	_palette = preload("res://src/editor/palette_panel.gd").new()
	_palette.build(self)
	_palette.custom_minimum_size = Vector2(180, 0)
	columns.add_child(_palette)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas = preload("res://src/editor/canvas_editor.gd").new()
	_canvas.editor = self
	scroll.add_child(_canvas)
	columns.add_child(scroll)

	_inspector = preload("res://src/editor/inspector_panel.gd").new()
	_inspector.build(self)
	_inspector.custom_minimum_size = Vector2(240, 0)
	columns.add_child(_inspector)

	_status = Label.new()
	_status.text = ""
	root.add_child(_status)

	_save_dialog = _make_file_dialog(FileDialog.FILE_MODE_SAVE_FILE)
	_save_dialog.file_selected.connect(_on_save_path)
	add_child(_save_dialog)

	_load_dialog = _make_file_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	_load_dialog.file_selected.connect(_on_load_path)
	add_child(_load_dialog)

	_broadcast()


func _build_toolbar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	var title := Label.new()
	title.text = "keen_reloaded — Editor"
	title.custom_minimum_size = Vector2(220, 0)
	bar.add_child(title)
	bar.add_child(_tool_button("New", new_level))
	bar.add_child(_tool_button("Save", save_level))
	bar.add_child(_tool_button("Load", load_level))
	bar.add_child(_tool_button("Test ▶", test_run))
	bar.add_child(_tool_button("Undo", undo))
	bar.add_child(_tool_button("Redo", redo))
	return bar


func _tool_button(label: String, callable: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.pressed.connect(callable)
	return b


func _make_file_dialog(mode: int) -> FileDialog:
	var d := FileDialog.new()
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.file_mode = mode
	d.add_filter("*.tres", "Level Resource")
	d.title = "Level file"
	return d


# ------------------------------------------------------------------ save/load

func _on_save_path(path: String) -> void:
	_last_path = path
	var err := ResourceSaver.save(level, path)
	if err == OK:
		_set_status("Saved: %s" % path)
	else:
		_set_status("Save FAILED (error %d): %s" % [err, path])


func _on_load_path(path: String) -> void:
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	if loaded == null:
		_set_status("Load FAILED (not a LevelData): %s" % path)
		return
	level = loaded
	undo_stack.clear()
	selected_entity_index = -1
	_last_path = path
	_broadcast()
	_set_status("Loaded: %s" % path)


# ------------------------------------------------------------------ refresh

func _on_history_changed() -> void:
	_broadcast()


func _broadcast() -> void:
	level_changed.emit()
	if _canvas:
		_canvas.refresh(self)
	if _palette:
		_palette.refresh(self)
	if _inspector:
		_inspector.refresh(self)
	_set_status(_cursor_status())


func _refresh_canvas_and_status() -> void:
	if _canvas:
		_canvas.refresh(self)
	_set_status(_cursor_status())


func _set_status(text: String) -> void:
	status_changed.emit(text)
	if _status:
		_status.text = text


func _cursor_status() -> String:
	return "Tool: %s | Layer: %s | Tile: %d | Entity: %s | Undo: %d Redo: %d" % [
		active_tool, active_layer, selected_tile_id, selected_entity_type,
		undo_stack._undo.size(), undo_stack._redo.size()]
```

- [ ] **Step 2: Write the scene file**

Create `/Users/eugene/git/keen_reloaded/src/editor/level_editor.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/editor/level_editor.gd" id="1_editor"]

[node name="LevelEditor" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_editor")
```

- [ ] **Step 3: Create temporary stubs for the panels (so the project imports)**

The controller references `CanvasEditor`, `PalettePanel`, `InspectorPanel` via `preload`. Create these minimal stubs now (Tasks 8–10 flesh them out). They MUST each expose `refresh(editor)` / `build(editor)` so `_ready` doesn't crash.

Create `/Users/eugene/git/keen_reloaded/src/editor/canvas_editor.gd`:

```gdscript
class_name CanvasEditor
extends Control
var editor: LevelEditor
func refresh(_e: LevelEditor) -> void:
	pass
```

Create `/Users/eugene/git/keen_reloaded/src/editor/palette_panel.gd`:

```gdscript
class_name PalettePanel
extends VBoxContainer
func build(_e: LevelEditor) -> void:
	pass
func refresh(_e: LevelEditor) -> void:
	pass
```

Create `/Users/eugene/git/keen_reloaded/src/editor/inspector_panel.gd`:

```gdscript
class_name InspectorPanel
extends VBoxContainer
func build(_e: LevelEditor) -> void:
	pass
func refresh(_e: LevelEditor) -> void:
	pass
```

- [ ] **Step 4: Verify the project imports**

Run: `cd /Users/eugene/git/keen_reloaded && "/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot" --headless --import --quit 2>&1 | tail -5`
Expected: exits cleanly, no parse errors.

Run: `./tests/run_all.sh`
Expected: PASS — existing unit tests still green (no new tests, but nothing broken).

- [ ] **Step 5: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/editor/level_editor.tscn src/editor/level_editor.gd src/editor/canvas_editor.gd src/editor/palette_panel.gd src/editor/inspector_panel.gd
git commit -m "feat: add LevelEditor controller + 3-panel layout scaffold"
```

---

## Task 8: `CanvasEditor` — drawing, input, zoom

**Files:**
- Modify: `src/editor/canvas_editor.gd` (replace stub)

The canvas draws all three layers (background dimmed, foreground, geometry full) plus a grid, entities as markers, the player spawn, and the selection. Mouse input drives paint/erase strokes, fill, entity placement, and entity selection. Zoom is the mouse wheel; scrolling is handled by the parent `ScrollContainer` (the canvas sizes itself to `level.pixel_size * zoom`).

- [ ] **Step 1: Implement the canvas**

Overwrite `/Users/eugene/git/keen_reloaded/src/editor/canvas_editor.gd` with:

```gdscript
class_name CanvasEditor
extends Control
## Editable tile canvas for the level editor. Renders tiles via _draw() (colored
## cells) and translates mouse input into editor commands via the LevelEditor.

var editor: LevelEditor

var zoom: float = 2.0
var _last_cell: Vector2i = Vector2i(-1, -1)


func _level() -> LevelData:
	return editor.level


func _tile_size() -> int:
	return _level().tile_size


func _cell_size() -> float:
	return float(_tile_size()) * zoom


func refresh(_e: LevelEditor) -> void:
	var w := _level().width * _cell_size()
	var h := _level().height * _cell_size()
	# Only relayout when the canvas size actually changed (painting doesn't).
	if custom_minimum_size != Vector2(w, h):
		custom_minimum_size = Vector2(w, h)
	queue_redraw()


func _draw() -> void:
	if _level() == null:
		return
	var cs := _cell_size()
	var tint_bg := EditorColors.layer_tint(LevelData.LAYER_BACKGROUND)
	var tint_fg := EditorColors.layer_tint(LevelData.LAYER_FOREGROUND)
	var tint_geo := EditorColors.layer_tint(LevelData.LAYER_GEOMETRY)

	_layer_pass(LevelData.LAYER_BACKGROUND, cs, tint_bg)
	_layer_pass(LevelData.LAYER_FOREGROUND, cs, tint_fg)
	_layer_pass(LevelData.LAYER_GEOMETRY, cs, tint_geo)

	# grid
	var grid := Color(1, 1, 1, 0.08)
	for x in range(_level().width + 1):
		draw_line(Vector2(x * cs, 0), Vector2(x * cs, _level().height * cs), grid)
	for y in range(_level().height + 1):
		draw_line(Vector2(0, y * cs), Vector2(_level().width * cs, y * cs), grid)

	# entities
	for e in _level().entities:
		var rect := Rect2(e.x * cs + 2, e.y * cs + 2, cs - 4, cs - 4)
		draw_rect(rect, Color(1, 0.4, 0.2, 0.9), false, 2.0)
		draw_string(get_theme_default_font(), rect.position + Vector2(2, 12), e.type, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.9))

	# selection highlight
	if editor.selected_entity_index >= 0 and editor.selected_entity_index < _level().entities.size():
		var se: EntityDef = _level().entities[editor.selected_entity_index]
		draw_rect(Rect2(se.x * cs, se.y * cs, cs, cs), Color(1, 1, 0.4, 1.0), false, 2.0)

	# player spawn
	var ps := _level().player_spawn
	var psz := Vector2(ps.x * cs, ps.y * cs)
	draw_rect(Rect2(psz.x + 3, psz.y + 3, cs - 6, cs - 6), Color(0.3, 0.8, 1, 1), false, 2.0)
	draw_line(psz, psz + Vector2(cs, cs), Color(0.3, 0.8, 1, 1), 1.5)


func _layer_pass(layer: String, cs: float, tint: Color) -> void:
	for y in range(_level().height):
		for x in range(_level().width):
			var id := _level().get_tile(layer, x, y)
			if id <= 0:
				continue
			draw_rect(Rect2(x * cs, y * cs, cs, cs), EditorColors.tile_color(id) * tint, true)


func _gui_input(event: InputEvent) -> void:
	if _level() == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		var cell := _mouse_to_cell(mb.position)
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_set_zoom(zoom * 1.25)
					accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_set_zoom(zoom / 1.25)
					accept_event()
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_on_left_down(cell)
				else:
					_on_left_up()
				accept_event()
			# Right-click intentionally ignored: erasing is done with the Eraser
			# tool so it is properly undoable and doesn't mutate the active tool.
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		var cell := _mouse_to_cell(mm.position)
		if cell != _last_cell:
			editor._set_status(_status_at(cell))
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if editor.active_tool == "paint" or editor.active_tool == "erase":
				editor.stroke_to(cell)
		_last_cell = cell


func _on_left_down(cell: Vector2i) -> void:
	_last_cell = cell
	match editor.active_tool:
		"select":
			editor.select_entity(editor.entity_at_cell(cell))
		"entity":
			if editor.selected_entity_type == "player_spawn":
				editor.edit_at_cell(cell)
			else:
				editor.select_entity(editor.entity_at_cell(cell))
				if editor.selected_entity_index < 0:
					editor.edit_at_cell(cell)
		"paint", "erase":
			editor.begin_stroke()
			editor.stroke_to(cell)
		"fill":
			editor.edit_at_cell(cell)


func _on_left_up() -> void:
	editor.end_stroke()


func _mouse_to_cell(p: Vector2) -> Vector2i:
	var cs := _cell_size()
	if cs <= 0:
		return Vector2i(-1, -1)
	return Vector2i(int(p.x / cs), int(p.y / cs))


func _set_zoom(z: float) -> void:
	zoom = clampf(z, 0.25, 8.0)
	refresh(editor)


func _status_at(cell: Vector2i) -> String:
	return "(%d, %d) | Tool: %s | Layer: %s" % [cell.x, cell.y, editor.active_tool, editor.active_layer]
```

- [ ] **Step 2: Verify the project imports**

Run: `cd /Users/eugene/git/keen_reloaded && "/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot" --headless --import --quit 2>&1 | tail -5`
Expected: exits cleanly.

Run: `./tests/run_all.sh`
Expected: PASS (existing tests still green).

- [ ] **Step 3: Manual verification**

Open the editor (see Task 12 for the menu entry, or temporarily set `run/main_scene` to the editor scene) and confirm: grid draws, left-drag paints colored cells, right-drag erases, wheel zooms.

- [ ] **Step 4: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/editor/canvas_editor.gd
git commit -m "feat: add editor canvas with tile drawing, painting, zoom"
```

---

## Task 9: `PalettePanel` — tiles, layers, tools, entities

**Files:**
- Modify: `src/editor/palette_panel.gd` (replace stub)

Left panel: tile-id picker (colored cells), layer radio buttons, tool radio buttons, and the entity list (read from `EntityRegistry`).

- [ ] **Step 1: Implement the palette**

Overwrite `/Users/eugene/git/keen_reloaded/src/editor/palette_panel.gd` with:

```gdscript
class_name PalettePanel
extends VBoxContainer
## Left panel: tile picker, layer toggles, tool toggles, entity list.
## IMPORTANT: build() creates all nodes ONCE; refresh() only updates toggle
## states. Rebuilding the tile grid in refresh() would free a button while it is
## emitting its `pressed` signal (click tile -> set_selected_tile_id -> broadcast
## -> rebuild) and crash. So refresh() must never recreate nodes.

var _tile_buttons: Array[Button] = []
var _layer_buttons: Dictionary = {}  # layer -> Button
var _tool_buttons: Dictionary = {}   # tool -> Button
var _entity_list: ItemList
var _entity_ids: Array[String] = []


func build(e: LevelEditor) -> void:
	custom_minimum_size = Vector2(190, 0)

	add_child(_section_label("Tiles"))
	var grid := GridContainer.new()
	grid.columns = 4
	var tile_group := ButtonGroup.new()
	for id in range(1, LevelEditor.PALETTE_TILE_COUNT + 1):
		var b := Button.new()
		b.text = str(id)
		b.toggle_mode = true
		b.button_group = tile_group
		b.add_theme_color_override("font_color", EditorColors.tile_color(id))
		b.add_theme_color_override("font_hover_color", EditorColors.tile_color(id))
		var idv := id
		b.pressed.connect(func() -> void: e.set_selected_tile_id(idv))
		grid.add_child(b)
		_tile_buttons.append(b)
	add_child(grid)

	add_child(_section_label("Layer"))
	var layer_group := ButtonGroup.new()
	for layer in [LevelData.LAYER_GEOMETRY, LevelData.LAYER_FOREGROUND, LevelData.LAYER_BACKGROUND]:
		var b := Button.new()
		b.text = layer.capitalize()
		b.toggle_mode = true
		b.button_group = layer_group
		var lv := layer
		b.toggled.connect(func(_p: bool) -> void: e.set_active_layer(lv))
		_layer_buttons[layer] = b
		add_child(b)

	add_child(_section_label("Tool"))
	var tool_group := ButtonGroup.new()
	for tool in ["paint", "erase", "fill", "entity", "select"]:
		var b := Button.new()
		b.text = LevelEditor.TOOLS[tool]
		b.toggle_mode = true
		b.button_group = tool_group
		var tv := tool
		b.toggled.connect(func(_p: bool) -> void: e.set_tool(tv))
		_tool_buttons[tool] = b
		add_child(b)

	add_child(_section_label("Entities"))
	_entity_list = ItemList.new()
	_entity_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_entity_list.item_selected.connect(func(idx: int) -> void:
		e.set_selected_entity_type(_entity_ids[idx]))
	add_child(_entity_list)
	_populate_entities()
	refresh(e)


func _populate_entities() -> void:
	_entity_list.clear()
	_entity_ids.clear()
	for entry in EntityRegistry.get_palette_entries():
		var cat: String = entry.get("category", "")
		var label: String = entry.get("label", "")
		_entity_ids.append(entry.get("type_id", ""))
		_entity_list.add_item("[%s] %s" % [cat.left(3), label])


## Lightweight: only toggle states. Never recreates nodes (see class doc).
func refresh(e: LevelEditor) -> void:
	for i in range(_tile_buttons.size()):
		_tile_buttons[i].set_pressed_no_signal((i + 1) == e.selected_tile_id)
	for layer in _layer_buttons:
		_layer_buttons[layer].set_pressed_no_signal(layer == e.active_layer)
	for tool in _tool_buttons:
		_tool_buttons[tool].set_pressed_no_signal(tool == e.active_tool)
	_entity_list.deselect_all()
	for i in range(_entity_ids.size()):
		if _entity_ids[i] == e.selected_entity_type:
			_entity_list.select(i)
			break


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	return l
```

- [ ] **Step 2: Verify the project imports**

Run: `cd /Users/eugene/git/keen_reloaded && "/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot" --headless --import --quit 2>&1 | tail -5`
Expected: exits cleanly. Run: `./tests/run_all.sh` → PASS.

- [ ] **Step 3: Manual verification**

Open the editor; confirm the tile picker, layer toggles, tool toggles, and entity list render and that selecting them updates the status bar.

- [ ] **Step 4: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/editor/palette_panel.gd
git commit -m "feat: add editor palette panel (tiles, layers, tools, entities)"
```

---

## Task 10: `InspectorPanel` — metadata + entity props + spawn

**Files:**
- Modify: `src/editor/inspector_panel.gd` (replace stub)

Right panel: level metadata (id/name/episode/order + width/height, which re-`fill_blank`s), player spawn x/y, and the selected entity's type/x/y and properties (numeric keys editable). Includes a "Delete entity" button.

- [ ] **Step 1: Implement the inspector**

Overwrite `/Users/eugene/git/keen_reloaded/src/editor/inspector_panel.gd` with:

```gdscript
class_name InspectorPanel
extends VBoxContainer
## Right panel: level metadata, player spawn, and selected-entity properties.

var _e: LevelEditor
var _id_edit: LineEdit
var _name_edit: LineEdit
var _episode_edit: LineEdit
var _order_spin: SpinBox
var _width_spin: SpinBox
var _height_spin: SpinBox
var _spawn_x: SpinBox
var _spawn_y: SpinBox
var _entity_box: VBoxContainer


func build(e: LevelEditor) -> void:
	_e = e
	custom_minimum_size = Vector2(250, 0)

	add_child(_section_label("Level"))
	_id_edit = _line("level_id", _on_id_changed)
	add_child(_labeled("ID", _id_edit))
	_name_edit = _line("level_name", _on_name_changed)
	add_child(_labeled("Name", _name_edit))
	_episode_edit = _line("episode", _on_episode_changed)
	add_child(_labeled("Episode", _episode_edit))
	_order_spin = _spin(0, 9999, _on_order_changed)
	add_child(_labeled("Order", _order_spin))

	_width_spin = _spin(1, 512, _on_dims_changed)
	_height_spin = _spin(1, 512, _on_dims_changed)
	add_child(_labeled("Width", _width_spin))
	add_child(_labeled("Height", _height_spin))

	add_child(_section_label("Player Spawn"))
	_spawn_x = _spin(0, 511, _on_spawn_changed)
	_spawn_y = _spin(0, 511, _on_spawn_changed)
	add_child(_labeled("Spawn X", _spawn_x))
	add_child(_labeled("Spawn Y", _spawn_y))

	add_child(_section_label("Selected Entity"))
	_entity_box = VBoxContainer.new()
	add_child(_entity_box)


func refresh(e: LevelEditor) -> void:
	_e = e
	_set_if_focused(_id_edit, e.level.level_id)
	_set_if_focused(_name_edit, e.level.level_name)
	_set_if_focused(_episode_edit, e.level.episode)
	_order_spin.set_value_no_signal(e.level.order)
	_width_spin.set_value_no_signal(e.level.width)
	_height_spin.set_value_no_signal(e.level.height)
	_spawn_x.set_value_no_signal(e.level.player_spawn.x)
	_spawn_y.set_value_no_signal(e.level.player_spawn.y)
	_rebuild_entity_box(e)


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

	# Each SpinBox writes straight to the entity via a closure capturing itself,
	# so we avoid fragile get_node() lookups (and node-name collisions).
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

	# numeric properties only (int-valued) for MVP
	for key in ent.properties.keys():
		var val = ent.properties[key]
		if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
			var ps := SpinBox.new()
			ps.min_value = -9999
			ps.max_value = 9999
			ps.set_value_no_signal(val)
			var k := key
			ps.value_changed.connect(func(_v: float) -> void: ent.properties[k] = int(ps.value))
			_entity_box.add_child(_labeled(str(key), ps))

	var del := Button.new()
	del.text = "Delete entity"
	del.pressed.connect(e.remove_selected_entity)
	_entity_box.add_child(del)


# ---------------------------------------------------------------- handlers

func _on_id_changed(t: String) -> void: _e.level.level_id = t
func _on_name_changed(t: String) -> void: _e.level.level_name = t
func _on_episode_changed(t: String) -> void: _e.level.episode = t
func _on_order_changed(_v: float) -> void: _e.level.order = int(_order_spin.value)

func _on_dims_changed(_v: float) -> void:
	_e.level.width = int(_width_spin.value)
	_e.level.height = int(_height_spin.value)
	_e.level.fill_blank()
	_e._broadcast()

func _on_spawn_changed(_v: float) -> void:
	_e.level.player_spawn = Vector2i(int(_spawn_x.value), int(_spawn_y.value))
	_e._broadcast()


# ---------------------------------------------------------------- helpers

func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	return l

func _line(_ph: String, on_changed: Callable) -> LineEdit:
	var le := LineEdit.new()
	le.text_changed.connect(on_changed)
	return le

func _spin(minv: int, maxv: int, on_changed: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = minv
	s.max_value = maxv
	s.value_changed.connect(on_changed)
	return s

func _labeled(text: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(70, 0)
	h.add_child(l)
	h.add_child(control)
	return h

func _kv_label(k: String, v: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = "%s: %s" % [k, v]
	h.add_child(l)
	return h

func _set_if_focused(le: LineEdit, value: String) -> void:
	if not le.has_focus():
		le.text = value
```

- [ ] **Step 2: Verify the project imports**

Run: `cd /Users/eugene/git/keen_reloaded && "/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot" --headless --import --quit 2>&1 | tail -5`
Expected: exits cleanly. Run: `./tests/run_all.sh` → PASS.

- [ ] **Step 3: Manual verification**

Open the editor; edit metadata, change spawn coords, place an entity (Entity tool + entity list), select it (Select tool) and edit x/y; confirm the canvas updates and Delete works.

- [ ] **Step 4: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/editor/inspector_panel.gd
git commit -m "feat: add editor inspector panel (metadata, spawn, entity props)"
```

---

## Task 11: Main-menu "Editor" entry point

**Files:**
- Modify: `src/ui/main_menu.tscn` (replace placeholder with a real menu)

The editor is dev-gated but reachable from the main menu (dev-mode is effectively "on" until a flag is added later). This also replaces the placeholder label added at the end of Plan 1.

- [ ] **Step 1: Rewrite `main_menu.tscn`**

Overwrite `/Users/eugene/git/keen_reloaded/src/ui/main_menu.tscn` with:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/main_menu.gd" id="1_menu"]

[node name="MainMenu" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="ColorRect" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0.05, 0.04, 0.08, 1)

[node name="Title" type="Label" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -320.0
offset_right = 320.0
offset_top = -120.0
offset_bottom = -60.0
grow_horizontal = 2
grow_vertical = 2
text = "keen_reloaded"
horizontal_alignment = 1
vertical_alignment = 1

[node name="Subtitle" type="Label" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -320.0
offset_right = 320.0
offset_top = -60.0
offset_bottom = -30.0
grow_horizontal = 2
grow_vertical = 2
text = "Plan 1: data model  ·  Plan 2: level editor"
horizontal_alignment = 1
vertical_alignment = 1

[node name="EditorButton" type="Button" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -90.0
offset_right = 90.0
offset_top = 10.0
offset_bottom = 50.0
grow_horizontal = 2
grow_vertical = 2
text = "Open Level Editor"

[node name="QuitButton" type="Button" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -90.0
offset_right = 90.0
offset_top = 60.0
offset_bottom = 100.0
grow_horizontal = 2
grow_vertical = 2
text = "Quit"
```

- [ ] **Step 2: Create the menu script**

Create `/Users/eugene/git/keen_reloaded/src/ui/main_menu.gd`:

```gdscript
extends Control

const EDITOR_SCENE := preload("res://src/editor/level_editor.tscn")

func _ready() -> void:
	%EditorButton.pressed.connect(_open_editor)
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())

func _open_editor() -> void:
	get_tree().change_scene_to_packed(EDITOR_SCENE)
```

- [ ] **Step 3: Make the buttons unique nodes (so `%EditorButton` resolves)**

In `/Users/eugene/git/keen_reloaded/src/ui/main_menu.tscn`, add `unique_name_in_owner = true` to each button node. Edit the two button nodes so their definitions read:

```
[node name="EditorButton" type="Button" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -90.0
offset_right = 90.0
offset_top = 10.0
offset_bottom = 50.0
grow_horizontal = 2
grow_vertical = 2
text = "Open Level Editor"

[node name="QuitButton" type="Button" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -90.0
offset_right = 90.0
offset_top = 60.0
offset_bottom = 100.0
grow_horizontal = 2
grow_vertical = 2
text = "Quit"
```

- [ ] **Step 4: Verify the project imports + tests**

Run: `cd /Users/eugene/git/keen_reloaded && "/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot" --headless --import --quit 2>&1 | tail -5`
Expected: exits cleanly. Run: `./tests/run_all.sh` → PASS.

- [ ] **Step 5: Manual verification**

Launch the game: `"/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot"` (opens the main scene). Click "Open Level Editor" → the editor loads. Exercise: paint, erase, fill, switch layers/tools, place an entity, select + delete it, edit metadata, Save to a `.tres`, Load it back, Undo/Redo, click Test ▶ (shows the "Plan 3" message).

- [ ] **Step 6: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add src/ui/main_menu.tscn src/ui/main_menu.gd
git commit -m "feat: add main-menu entry to open the level editor"
```

---

## Task 12: Smoke-level integration test for the editor command layer

**Files:**
- Create: `tests/unit/test_editor_workflow.gd`

The UI can't be GUT-tested headlessly, but the full editor workflow (paint → fill → add entity → set spawn → undo/redo → serialize round-trip) can be exercised through the command layer. This locks the editor's non-UI behavior end-to-end.

- [ ] **Step 1: Write the integration test**

Create `/Users/eugene/git/keen_reloaded/tests/unit/test_editor_workflow.gd`:

```gdscript
extends GutTest

const G := "geometry"

func _level() -> LevelData:
	var ld := LevelData.new()
	ld.level_id = "keen1_01"
	ld.level_name = "Border Village"
	ld.episode = "keen1"
	ld.order = 1
	ld.width = 6
	ld.height = 4
	ld.fill_blank()
	return ld

func test_full_editor_workflow_then_serialize():
	var ld := _level()
	var s := UndoStack.new()

	# paint a floor
	var stroke := PaintCellsCmd.new(G, 1)
	for x in range(6):
		stroke.paint(ld, x, 3)
	s.push_applied(ld, stroke)

	# flood-fill the area above the floor with id 2
	s.execute(ld, FloodFillCmd.new(G, Vector2i(0, 0), 2))

	# place entities + spawn
	s.execute(ld, AddEntityCmd.new(EntityDef.new("vorticon", 2, 1, {"speed": 20})))
	s.execute(ld, AddEntityCmd.new(EntityDef.new("candy", 4, 2)))
	s.execute(ld, SetPlayerSpawnCmd.new(Vector2i(0, 2)))

	# sanity-check the model
	assert_eq(ld.get_tile(G, 0, 3), 1)
	assert_eq(ld.get_tile(G, 0, 0), 2)
	assert_eq(ld.entities.size(), 2)
	assert_eq(ld.player_spawn, Vector2i(0, 2))

	# undo the spawn + one entity
	s.undo(ld)
	s.undo(ld)
	assert_eq(ld.entities.size(), 1)
	assert_eq(ld.player_spawn, Vector2i.ZERO)

	# redo one
	s.redo(ld)
	assert_eq(ld.entities.size(), 2)

	# serialize round-trip and confirm
	var path := "user://tests/test_editor_workflow.tres"
	DirAccess.make_dir_recursive_absolute("user://tests/")
	assert_eq(ResourceSaver.save(ld, path), OK)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	assert_not_null(loaded)
	assert_eq(loaded.get_tile(G, 0, 3), 1)
	assert_eq(loaded.entities.size(), 2)
	assert_eq(loaded.entities[0].type, "vorticon")
	assert_eq(loaded.entities[0].properties.get("speed"), 20)

func test_clear_then_re_register_entities_for_palette():
	# The editor palette depends on registry ordering; verify a fresh registration
	# set still sorts deterministically.
	EntityRegistry.clear()
	EntityRegistry.register("z", EntityRegistry.CATEGORY_ITEM, "Zed")
	EntityRegistry.register("a", EntityRegistry.CATEGORY_ITEM, "Ay")
	var entries := EntityRegistry.get_palette_entries()
	assert_eq(entries[0]["type_id"], "a")
	assert_eq(entries[1]["type_id"], "z")
```

- [ ] **Step 2: Run the full suite**

Run: `./tests/run_all.sh`
Expected: ALL tests PASS across every file.

- [ ] **Step 3: Commit**

```bash
cd /Users/eugene/git/keen_reloaded
git add tests/unit/test_editor_workflow.gd
git commit -m "test: add editor command-layer workflow integration test"
```

---

## Plan 2 Complete Criteria

- [ ] `./tests/run_all.sh` is green (layer accessors, commands, undo stack, registry, colors, workflow)
- [ ] Godot imports cleanly (`--headless --import --quit` exits 0)
- [ ] Editor reachable from main menu; 3 panels render
- [ ] Tile paint / erase / fill across all three layers works; Undo/Redo works
- [ ] Entity placement + selection + delete works; metadata + spawn editable in inspector
- [ ] Save/Load `.tres` round-trips a level (incl. entities)
- [ ] Test ▶ button is present and clearly defers to Plan 3
- [ ] All work committed to `main`

## Next Plans (out of scope here)

- **Plan 3:** Runtime core (`LevelRuntime` builds a scene from `LevelData`; `Player` `CharacterBody2D`; base entity classes + Keen 1 entities; wire the editor's **Test ▶** to live gameplay; `EntityRegistry.instantiate(...)`)
- **Plan 4:** Pack loading (`PackLoader` scans `res://` + `user://`, level-select menu, `GameManager` progression)
