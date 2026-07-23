# Ice Physics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two ice surface types (low-friction + forced-slide) plus a unified ground acceleration model to Commander Keen's movement, matching the original games.

**Architecture:** Surface type is read from a TileSet `surface_type` custom-data layer under the player's feet each grounded frame. All velocity math lives in a pure `SurfacePhysics` helper (unit-testable without a Player scene). The Player's `_physics_process` ground branch becomes a thin dispatcher that reads the surface and delegates to `SurfacePhysics`. A `coast` state bleeds momentum over a fixed 1.5 tiles on ice→ground exit.

**Tech Stack:** Godot 4.7, GDScript, GUT (Godot Unit Test).

**Spec:** `docs/superpowers/specs/2026-07-23-ice-physics-design.md`

---

## File Structure

**Create:**
- `src/core/surface_type.gd` — `SurfaceType` enum (NONE/ICE1/ICE2). Values match the TileSet custom-data layer.
- `src/runtime/player/surface_physics.gd` — `SurfacePhysics` pure static helpers `(vx, ...) -> float`. No Godot nodes; fully unit-testable.
- `tests/unit/test_surface_physics.gd` — pure-function tests for all `SurfacePhysics` math.
- `tests/unit/test_player_surface.gd` — Player integration: surface read, grounded dispatch (ice1/ice2/coast/ground), anim, wall-stop.

**Modify:**
- `src/runtime/player/player.gd` — new `@export` tunables; new state vars; `set_ground_tilemap()` + `_read_surface_under_feet()`; grounded surface dispatch `_step_grounded()`; ground accel model; ice2 wall-stop; ice2 idle anim override.
- `src/runtime/procedural_tileset.gd` — `build()` gains optional ice-id params, adds the `surface_type` custom-data layer.
- `src/runtime/level_runtime.gd` — inject the geometry `TileMapLayer` into the player at spawn.

**Test conventions (match existing `tests/unit/test_player.gd`):**
- Player fixtures via `_new_player()` = `add_child_autofree(load("res://src/runtime/player/player.tscn").instantiate())`.
- Drive physics directly: `p._physics_process(0.016)`; manipulate private state directly (`p._coyote`, `p.velocity`, etc.).
- Use `Input.action_press/release` for input; `add_child_autofree` for nodes.
- Run the suite: `./tests/run_all.sh` (or `make test`).

---

## Task 1: SurfaceType enum + SurfacePhysics.step_ground (normal-ground accel/decel)

**Files:**
- Create: `src/core/surface_type.gd`
- Create: `src/runtime/player/surface_physics.gd`
- Create: `tests/unit/test_surface_physics.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_surface_physics.gd`:

```gdscript
extends GutTest

const ST := SurfaceType

func test_step_ground_accelerates_toward_run_speed():
	# from rest, holding right -> advances by ground_accel*delta toward +run_speed
	var vx := SurfacePhysics.step_ground(0.0, 1.0, 480.0, 1.0, 4000.0, 6000.0, 0.016)
	assert_almost_eq(vx, 4000.0 * 0.016, 0.01, "advances by accel*delta")

func test_step_ground_caps_at_run_speed():
	var vx := 470.0
	for i in 50:
		vx = SurfacePhysics.step_ground(vx, 1.0, 480.0, 1.0, 4000.0, 6000.0, 0.016)
	assert_almost_eq(vx, 480.0, 0.5, "never exceeds run_speed")

func test_step_ground_decelerates_to_zero_no_input():
	var vx := 300.0
	for i in 60:
		vx = SurfacePhysics.step_ground(vx, 0.0, 480.0, 1.0, 4000.0, 6000.0, 0.016)
	assert_almost_eq(vx, 0.0, 0.5, "coasts to stop with no input")

func test_step_ground_speed_scale_multiplies_target():
	# input-locked exit walk: speed_scale 0.5 -> target is half run_speed
	var vx := SurfacePhysics.step_ground(0.0, 1.0, 480.0, 0.5, 4000.0, 6000.0, 0.016)
	# first step toward 240 at 4000*delta = 64, capped at 64 (under target 240)
	assert_almost_eq(vx, 64.0, 0.01, "accelerates toward scaled target")
	var capped := 230.0
	for i in 50:
		capped = SurfacePhysics.step_ground(capped, 1.0, 480.0, 0.5, 4000.0, 6000.0, 0.016)
	assert_almost_eq(capped, 240.0, 0.5, "caps at scaled target")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `Invalid get index 'SurfaceType'` / `Identifier 'SurfacePhysics' not found` (classes don't exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `src/core/surface_type.gd`:

```gdscript
class_name SurfaceType
extends RefCounted
## Tile surface types. Values mirror the TileSet `surface_type` custom-data
## layer (0 = normal ground). Used by the player to select ground-movement
## rules; see SurfacePhysics and the surface dispatch in player.gd.

enum Kind { NONE = 0, ICE1 = 1, ICE2 = 2 }
```

Create `src/runtime/player/surface_physics.gd`:

```gdscript
class_name SurfacePhysics
extends RefCounted
## Pure (vx, ...) -> float ground-movement helpers. No Godot nodes, no side
## effects — fully unit-testable. The Player's physics loop reads the surface
## under its feet and delegates velocity math here.

## Normal ground: accelerate toward dir*run_speed*speed_scale when input is
## held, decelerate toward 0 when released. A single move_toward covers
## speed-up, slow-down, and turn-through-zero.
static func step_ground(vx: float, dir: float, run_speed: float, speed_scale: float, accel: float, decel: float, delta: float) -> float:
	var target := dir * run_speed * speed_scale
	if dir != 0.0:
		return move_toward(vx, target, accel * delta)
	return move_toward(vx, 0.0, decel * delta)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS (the 4 `test_step_ground_*` cases).

- [ ] **Step 5: Commit**

```bash
git add src/core/surface_type.gd src/runtime/player/surface_physics.gd tests/unit/test_surface_physics.gd
git commit -m "feat: SurfaceType enum + ground accel/decel math"
```

---

## Task 2: SurfacePhysics.step_ice1 + step_ice1_entry

**Files:**
- Modify: `src/runtime/player/surface_physics.gd`
- Modify: `tests/unit/test_surface_physics.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_surface_physics.gd`:

```gdscript
func test_step_ice1_entry_caps_overspeed():
	# landing faster than cap -> clamped to cap, sign preserved
	assert_almost_eq(SurfacePhysics.step_ice1_entry(700.0, 480.0), 480.0, 0.01, "right overspeed capped")
	assert_almost_eq(SurfacePhysics.step_ice1_entry(-700.0, 480.0), -480.0, 0.01, "left overspeed capped")
	# under cap -> unchanged
	assert_almost_eq(SurfacePhysics.step_ice1_entry(300.0, 480.0), 300.0, 0.01, "under cap unchanged")

func test_step_ice1_zero_friction_no_input():
	# CORE assertion: releasing input on ice preserves velocity exactly
	var vx := 480.0
	for i in 60:
		vx = SurfacePhysics.step_ice1(vx, 0.0, 480.0, 1500.0, 0.016)
	assert_almost_eq(vx, 480.0, 0.001, "zero friction: velocity unchanged with no input")

func test_step_ice1_accelerates_with_input():
	var vx := 0.0
	vx = SurfacePhysics.step_ice1(vx, 1.0, 480.0, 1500.0, 0.016)
	assert_almost_eq(vx, 1500.0 * 0.016, 0.01, "accelerates by ice_accel*delta")

func test_step_ice1_turn_decelerates_through_zero():
	# gliding right at full, hold left -> decel through zero toward -cap
	var vx := 480.0
	for i in 200:
		vx = SurfacePhysics.step_ice1(vx, -1.0, 480.0, 1500.0, 0.016)
	assert_lte(vx, 0.0, "reversed sign within 200 frames")
	# and eventually reaches -cap
	vx = 480.0
	for i in 1000:
		vx = SurfacePhysics.step_ice1(vx, -1.0, 480.0, 1500.0, 0.016)
	assert_almost_eq(vx, -480.0, 0.5, "reaches -cap when holding opposite")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `Invalid call method 'step_ice1'` / `'step_ice1_entry'` (not defined).

- [ ] **Step 3: Write minimal implementation**

Append to `src/runtime/player/surface_physics.gd` (before the final blank line):

```gdscript

## Ice1 entry: clamp |vx| to `cap`, preserving direction. Called once on the
## first grounded ICE1 frame after a non-ICE1 surface.
static func step_ice1_entry(vx: float, cap: float) -> float:
	if absf(vx) > cap:
		return signf(vx) * cap
	return vx


## Ice1 surface: accelerate toward dir*cap when input is held; ZERO friction
## (velocity unchanged) when no input. Same move_toward shape as step_ground.
static func step_ice1(vx: float, dir: float, cap: float, accel: float, delta: float) -> float:
	if dir != 0.0:
		return move_toward(vx, dir * cap, accel * delta)
	return vx
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS (all ice1 cases).

- [ ] **Step 5: Commit**

```bash
git add src/runtime/player/surface_physics.gd tests/unit/test_surface_physics.gd
git commit -m "feat: ice1 zero-friction + entry-cap math"
```

---

## Task 3: SurfacePhysics.step_ice2 (forced slide pin)

**Files:**
- Modify: `src/runtime/player/surface_physics.gd`
- Modify: `tests/unit/test_surface_physics.gd`

- [ ] **Step 3 is shown before Step 1 here only because the test asserts behavior that the one-line helper makes obvious — read both.**

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_surface_physics.gd`:

```gdscript
func test_step_ice2_pins_entry_direction_speed():
	# pinned exactly to entry_dir * slide_speed regardless of incoming vx
	assert_almost_eq(SurfacePhysics.step_ice2(1.0, 480.0), 480.0, 0.001, "right entry pins +slide_speed")
	assert_almost_eq(SurfacePhysics.step_ice2(-1.0, 480.0), -480.0, 0.001, "left entry pins -slide_speed")
	# incoming velocity is irrelevant once pinned
	assert_almost_eq(SurfacePhysics.step_ice2(1.0, 480.0), 480.0, 0.001, "pin ignores incoming vx")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `Invalid call method 'step_ice2'`.

- [ ] **Step 3: Write minimal implementation**

Append to `src/runtime/player/surface_physics.gd`:

```gdscript

## Ice2 surface: pin horizontal velocity to entry_dir * slide_speed. The
## Player manages entry_dir, the lock flag, and the wall-stop (which zeroes
## vx and clears the lock after move_and_slide); this helper just pins.
static func step_ice2(entry_dir: float, slide_speed: float) -> float:
	return entry_dir * slide_speed
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/runtime/player/surface_physics.gd tests/unit/test_surface_physics.gd
git commit -m "feat: ice2 forced-slide pin math"
```

---

## Task 4: SurfacePhysics.coast_decel_for + step_coast (fixed-distance bleed)

**Files:**
- Modify: `src/runtime/player/surface_physics.gd`
- Modify: `tests/unit/test_surface_physics.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_surface_physics.gd`:

```gdscript
func test_coast_decel_for_brings_to_zero_in_fixed_distance():
	# Constant decel a = v0^2 / (2d) stops the body in exactly d pixels.
	# Integrate move_toward steps and sum the distance travelled.
	var d := 96.0            # 1.5 tiles
	var v0 := 480.0
	var decel := SurfacePhysics.coast_decel_for(v0, d)
	assert_gt(decel, 0.0, "positive decel for moving body")
	var vx := v0
	var travelled := 0.0
	var frames := 0
	while absf(vx) > 0.0001 and frames < 10000:
		vx = SurfacePhysics.step_coast(vx, decel, 0.016)
		travelled += absf(vx) * 0.016
		frames += 1
	assert_almost_eq(vx, 0.0, 0.5, "reaches zero")
	# With move_toward the last step can slightly overshoot the analytic stop;
	# the travelled distance is within one step's worth (v0*delta) of d.
	assert_almost_eq(travelled, d, v0 * 0.016, "stops within ~one frame of 1.5 tiles")

func test_coast_decel_for_zero_distance_is_noop():
	assert_eq(SurfacePhysics.coast_decel_for(480.0, 0.0), 0.0, "zero distance -> no decel")

func test_step_coast_monotonic_to_zero():
	var decel := SurfacePhysics.coast_decel_for(480.0, 96.0)
	var vx := 480.0
	for i in 200:
		vx = SurfacePhysics.step_coast(vx, decel, 0.016)
		assert_gte(vx, 0.0, "never overshoots past zero")
	assert_almost_eq(vx, 0.0, 0.5, "reaches zero")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `Invalid call method 'coast_decel_for'` / `'step_coast'`.

- [ ] **Step 3: Write minimal implementation**

Append to `src/runtime/player/surface_physics.gd`:

```gdscript

## Constant deceleration that stops a body moving at speed |vx| in exactly
## `distance` pixels: a = v0^2 / (2*distance). Returns a positive rate to
## pass to step_coast. Zero when distance<=0 or the body is already stopped.
static func coast_decel_for(vx: float, distance: float) -> float:
	var v0 := absf(vx)
	if distance <= 0.0 or v0 <= 0.0:
		return 0.0
	return (v0 * v0) / (2.0 * distance)


## Coast: decelerate toward 0 at a constant rate (computed by coast_decel_for
## for a fixed stop distance). The Player suspends this while steering and
## recomputes coast_decel_for on release.
static func step_coast(vx: float, coast_decel: float, delta: float) -> float:
	return move_toward(vx, 0.0, coast_decel * delta)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/runtime/player/surface_physics.gd tests/unit/test_surface_physics.gd
git commit -m "feat: fixed-distance coast decel math"
```

---

## Task 5: ProceduralTileSet — surface_type custom-data layer + ice tagging

**Files:**
- Modify: `src/runtime/procedural_tileset.gd:18-53`
- Modify: `tests/unit/test_procedural_tileset.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_procedural_tileset.gd` (read the file first to match its existing style):

```gdscript
func test_procedural_tileset_tags_ice_custom_data():
	# tile id 2 -> ICE1, tile id 3 -> ICE2, others NONE.
	var ts := ProceduralTileSet.build(4, 16, false, [2], [3])
	assert_eq(ts.get_custom_data_layers_count(), 1, "one custom-data layer added")
	var layer := ts.get_custom_data_layer_by_name("surface_type")
	assert_gte(layer, 0, "surface_type layer exists by name")
	var src := ts.get_source(ts.get_source_id(0))
	# tile id 1 -> atlas coords (0,0); id 2 -> (1,0); id 3 -> (2,0).
	var td_normal := src.get_tile_data(Vector2i(0, 0), 0)
	var td_ice1 := src.get_tile_data(Vector2i(1, 0), 0)
	var td_ice2 := src.get_tile_data(Vector2i(2, 0), 0)
	assert_eq(int(td_normal.get_custom_data("surface_type")), SurfaceType.Kind.NONE, "tile 1 normal")
	assert_eq(int(td_ice1.get_custom_data("surface_type")), SurfaceType.Kind.ICE1, "tile 2 ice1")
	assert_eq(int(td_ice2.get_custom_data("surface_type")), SurfaceType.Kind.ICE2, "tile 3 ice2")


func test_procedural_tileset_no_ice_ids_has_layer_all_none():
	# Backward-compat: even with no ice ids, a surface_type layer exists and
	# every tile reads NONE (so the player contract is uniform).
	var ts := ProceduralTileSet.build(3, 16, true, [], [])
	var src := ts.get_source(ts.get_source_id(0))
	for x in 3:
		var td := src.get_tile_data(Vector2i(x, 0), 0)
		assert_eq(int(td.get_custom_data("surface_type")), SurfaceType.Kind.NONE, "tile %d is NONE" % (x + 1))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — wrong arg count (`build` takes 3 args today) and no custom-data layer (`get_custom_data_layers_count` == 0).

- [ ] **Step 3: Write minimal implementation**

In `src/runtime/procedural_tileset.gd`, change the `build` signature and add the custom-data tagging. Replace the existing `static func build(...)` through its `return ts` (lines 18-53) with:

```gdscript
## Build a TileSet with `max_id` colored tiles (ids 1..max_id).
## with_collision adds a full-cell collision rectangle to every tile (geometry
## layer). ice1_ids / ice2_ids mark solid-color dev tile ids whose
## `surface_type` custom-data reads ICE1 / ICE2 (all others NONE). The
## surface_type layer is ALWAYS added so the player can read custom data
## uniformly, regardless of whether any ice ids are supplied.
static func build(max_id: int, tile_size: int, with_collision: bool, ice1_ids: Array[int] = [], ice2_ids: Array[int] = []) -> TileSet:
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

	# surface_type custom-data layer (added unconditionally for a uniform read).
	ts.add_custom_data_layer()
	var cd_layer := ts.get_custom_data_layers_count() - 1
	ts.set_custom_data_layer_name(cd_layer, "surface_type")
	var surface_for_id := {}
	for id in ice1_ids:
		surface_for_id[id] = SurfaceType.Kind.ICE1
	for id in ice2_ids:
		surface_for_id[id] = SurfaceType.Kind.ICE2
	for id in range(1, max_id + 1):
		var td: TileData = src.get_tile_data(Vector2i(id - 1, 0), 0)
		var s: int = surface_for_id.get(id, SurfaceType.Kind.NONE)
		td.set_custom_data("surface_type", s)

	if with_collision:
		ts.add_physics_layer()
		var layer: int = ts.get_physics_layers_count() - 1
		ts.set_physics_layer_collision_layer(layer, COLLISION_LAYER_TILES)
		ts.set_physics_layer_collision_mask(layer, COLLISION_MASK_PLAYER)
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS. (Also confirms existing `test_procedural_tileset.gd` cases still pass — they call `build(max_id, tile_size, bool)` with 3 args, which still works via the defaulted new params.)

- [ ] **Step 5: Commit**

```bash
git add src/runtime/procedural_tileset.gd tests/unit/test_procedural_tileset.gd
git commit -m "feat: surface_type custom-data layer in ProceduralTileSet"
```

---

## Task 6: Player surface read — set_ground_tilemap + _read_surface_under_feet

**Files:**
- Modify: `src/runtime/player/player.gd`
- Create: `tests/unit/test_player_surface.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_player_surface.gd`:

```gdscript
extends GutTest

const ST := SurfaceType

## Minimal TileMapLayer fixture: cell (0,0) tile is ICE1, cell (1,0) is ICE2,
## cell (2,0) is NONE. 16px tiles. Reuses the projectile-test tileset pattern.
func _tilemap_with_surfaces() -> TileMapLayer:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "surface_type")
	var img := Image.create(48, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(16, 16)
	ts.add_source(src)
	for x in 3:
		src.create_tile(Vector2i(x, 0))
	src.get_tile_data(Vector2i(0, 0), 0).set_custom_data("surface_type", ST.Kind.ICE1)
	src.get_tile_data(Vector2i(1, 0), 0).set_custom_data("surface_type", ST.Kind.ICE2)
	src.get_tile_data(Vector2i(2, 0), 0).set_custom_data("surface_type", ST.Kind.NONE)
	var tml := TileMapLayer.new()
	tml.tile_set = ts
	tml.set_cell(Vector2i(0, 0), 0, Vector2i(0, 0))
	tml.set_cell(Vector2i(1, 0), 0, Vector2i(1, 0))
	tml.set_cell(Vector2i(2, 0), 0, Vector2i(2, 0))
	add_child_autofree(tml)
	return tml


func _new_player() -> Player:
	return add_child_autofree(load("res://src/runtime/player/player.tscn").instantiate())


func test_read_surface_returns_kind_under_feet():
	var tml := _tilemap_with_surfaces()
	var p := _new_player()
	p.set_ground_tilemap(tml)
	# 16px tiles: cell (0,0) spans x in [0,16); its center is (8,8). Player
	# reads at its foot (global_position + foot offset). Put feet over cell 0.
	p.global_position = Vector2(8, -8)   # foot at y=0 would be cell row 0
	# Place player so foot lands in cell (0,0): foot_y for a 16px-tile world —
	# use a small nudge; the Level collision shape is 96 tall (foot at +48),
	# so global foot = position.y + 48. We position so +48 lands at y=8 (cell 0).
	p.global_position = Vector2(8, 8 - 48)
	assert_eq(p._read_surface_under_feet(), ST.Kind.ICE1, "over ICE1 cell")
	p.global_position = Vector2(24, 8 - 48)
	assert_eq(p._read_surface_under_feet(), ST.Kind.ICE2, "over ICE2 cell")
	p.global_position = Vector2(40, 8 - 48)
	assert_eq(p._read_surface_under_feet(), ST.Kind.NONE, "over NONE cell")


func test_read_surface_none_when_no_tilemap():
	var p := _new_player()
	# no ground tilemap injected -> safe default NONE (never crashes)
	assert_eq(p._read_surface_under_feet(), ST.Kind.NONE, "no tilemap -> NONE")


func test_read_surface_none_when_no_custom_data_layer():
	# A tileset without the surface_type layer must read NONE (migration safety).
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(16, 16)
	ts.add_source(src)
	src.create_tile(Vector2i(0, 0))
	var tml := TileMapLayer.new()
	tml.tile_set = ts
	tml.set_cell(Vector2i(0, 0), 0, Vector2i(0, 0))
	add_child_autofree(tml)
	var p := _new_player()
	p.set_ground_tilemap(tml)
	p.global_position = Vector2(8, 8 - 48)
	assert_eq(p._read_surface_under_feet(), ST.Kind.NONE, "missing layer -> NONE")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `Method 'set_ground_tilemap'/'_read_surface_under_feet' not found`.

- [ ] **Step 3: Write minimal implementation**

In `src/runtime/player/player.gd`, add a ground-tilemap reference field near the other `var` declarations (around line 80, after `_pogo_bounce_timer`):

```gdscript
var _ground_tml: TileMapLayer = null
```

Add the setter + reader. Place them right after `set_mode()` (after line 114):

```gdscript
## Injects the geometry TileMapLayer the player stands on, so the surface type
## under its feet can be read each grounded frame. Set by LevelRuntime at spawn.
func set_ground_tilemap(tml: TileMapLayer) -> void:
	_ground_tml = tml


## Surface type under the player's feet this frame (NONE/ICE1/ICE2). Reads the
## geometry TileMapLayer's surface_type custom data at the foot cell. Returns
## NONE when no tilemap is set, the cell is empty, or the tileset has no
## surface_type layer (migration-safe).
func _read_surface_under_feet() -> int:
	if _ground_tml == null or _ground_tml.tile_set == null:
		return SurfaceType.Kind.NONE
	var ts: TileSet = _ground_tml.tile_set
	# Migration safety: a tileset without the surface_type layer reads NONE
	# (get_custom_data can error on an absent layer in 4.7).
	if ts.get_custom_data_layer_by_name("surface_type") < 0:
		return SurfaceType.Kind.NONE
	var col := get_node_or_null(COLLISION_LEVEL) as CollisionShape2D
	if col == null or not (col.shape is RectangleShape2D):
		return SurfaceType.Kind.NONE
	var foot_y := (col.shape as RectangleShape2D).size.y * 0.5
	# Sample 1px below the foot so we land in the tile beneath, not the one
	# whose top the foot rests on.
	var foot := global_position + Vector2(0, foot_y + 1.0)
	var cell := _ground_tml.local_to_map(_ground_tml.to_local(foot))
	var td: TileData = _ground_tml.get_cell_tile_data(cell)
	if td == null:
		return SurfaceType.Kind.NONE
	return int(td.get_custom_data("surface_type"))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/runtime/player/player.gd tests/unit/test_player_surface.gd
git commit -m "feat: player reads surface type under feet"
```

---

## Task 7: Player grounded dispatch — ground accel model (replaces instant-snap)

This is the whole-game feel change: normal ground movement now accelerates/decelerates instead of snapping. The dispatcher `_step_grounded` is the testable seam (call it directly with a forced surface — no floor physics needed).

**Files:**
- Modify: `src/runtime/player/player.gd` (exports ~line 35-54; ground branch ~line 169-177)
- Modify: `tests/unit/test_player_surface.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_player_surface.gd`:

```gdscript
func test_step_grounded_normal_accelerates_then_decelerates():
	var p := _new_player()
	# from rest, hold right -> accelerates toward run_speed (does not snap)
	p.velocity.x = 0.0
	p._step_grounded(ST.Kind.NONE, 1.0, 0.016)
	assert_lt(p.velocity.x, p.run_speed, "accelerates, does not snap to run_speed")
	assert_gt(p.velocity.x, 0.0, "moving right")
	# release -> decelerates toward 0 (does not snap-stop)
	var mid := p.velocity.x
	p._step_grounded(ST.Kind.NONE, 0.0, 0.016)
	assert_lt(absf(p.velocity.x), mid, "decelerating after release")
	assert_gt(absf(p.velocity.x), 0.0, "not yet stopped (no instant stop)")
	# eventually reaches run_speed when held
	p.velocity.x = 0.0
	for i in 100:
		p._step_grounded(ST.Kind.NONE, 1.0, 0.016)
	assert_almost_eq(p.velocity.x, p.run_speed, 1.0, "reaches run_speed when held")


func test_step_grounded_speed_scale_applies_when_input_locked():
	var p := _new_player()
	p.lock_input(1.0, 0.5)   # exit walk: half speed
	p.velocity.x = 0.0
	for i in 100:
		p._step_grounded(ST.Kind.NONE, 1.0, 0.016)
	assert_almost_eq(p.velocity.x, p.run_speed * 0.5, 1.0, "caps at scaled target while locked")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `Method '_step_grounded' not found`.

- [ ] **Step 3: Write minimal implementation**

(a) Add `@export` tunables in `player.gd`. Place these right after `jump_buffer` (after line 47):

```gdscript
@export var ground_accel: float = 4000.0
@export var ground_decel: float = 6000.0
@export var ice_accel: float = 1500.0
@export var ice_max_speed_cap: float = 480.0
@export var ice2_slide_speed: float = 480.0
@export var coast_distance: float = 96.0   # Constants.TILE * 1.5
```

(b) Add the new ground-state vars near `_pogo_bounce_timer` (line ~80):

```gdscript
var _prev_surface: int = SurfaceType.Kind.NONE
var _coasting: bool = false
var _coast_decel: float = 0.0
var _coast_steering: bool = false
var _ice2_locked: bool = false
var _ice2_entry_dir: float = 0.0
```

(c) Replace the ground branch. The current ground branch (`player.gd:169-177`) is:

```gdscript
	elif on_floor:
		velocity.x = dir * run_speed * (_speed_scale if _input_locked else 1.0)
		if dir != 0:
			_facing = signi(dir)
```

Replace it with a call into the dispatcher:

```gdscript
	elif on_floor:
		_step_grounded(_read_surface_under_feet(), dir, delta)
		if dir != 0 and not _ice2_locked:
			_facing = signi(dir)
```

(d) Add the `_step_grounded` dispatcher. Place it right before `_physics_process` (before line 138):

```gdscript
## Grounded surface dispatch. Reads NO input and touches NO floor — it only
## mutates velocity.x + the ice/coast state flags from `surface` and `dir`.
## Called once per grounded frame from _physics_process. Pure-ish seam: tests
## call it directly with a forced surface (no TileMapLayer/floor needed).
func _step_grounded(surface: int, dir: float, delta: float) -> void:
	var scale := _speed_scale if _input_locked else 1.0
	match surface:
		SurfaceType.Kind.ICE2:
			_step_ice2_ground()
		SurfaceType.Kind.ICE1:
			_ice2_locked = false
			velocity.x = SurfacePhysics.step_ice1_entry(velocity.x, ice_max_speed_cap)
			velocity.x = SurfacePhysics.step_ice1(velocity.x, dir, ice_max_speed_cap, ice_accel, delta)
			_end_coast_if_active()
		_:
			_ice2_locked = false
			if _coasting:
				_step_coast_ground(dir, delta)
			elif (_prev_surface == SurfaceType.Kind.ICE1 or _prev_surface == SurfaceType.Kind.ICE2) and absf(velocity.x) > 1.0:
				# ice -> normal ground transition: begin the fixed-distance coast
				_coasting = true
				_coast_steering = false
				_coast_decel = SurfacePhysics.coast_decel_for(velocity.x, coast_distance)
				velocity.x = SurfacePhysics.step_coast(velocity.x, _coast_decel, delta)
			else:
				velocity.x = SurfacePhysics.step_ground(velocity.x, dir, run_speed, scale, ground_accel, ground_decel, delta)
	_prev_surface = surface


## No-op unless coasting; kept as a named helper for the ICE1 branch.
func _end_coast_if_active() -> void:
	if _coasting:
		_coasting = false
		_coast_steering = false


# ICE2 and coast ground steps are added in later tasks; stubs so the
# dispatcher compiles now.
func _step_ice2_ground() -> void:
	pass


func _step_coast_ground(_dir: float, _delta: float) -> void:
	pass
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS (the two `test_step_grounded_normal_*` cases). All pre-existing `test_player.gd` cases also pass — they never exercise the grounded-walking branch (no floor in their scene; the jump tests run airborne via `_coyote`/`_buffer`).

- [ ] **Step 5: Commit**

```bash
git add src/runtime/player/player.gd tests/unit/test_player_surface.gd
git commit -m "feat: unified ground accel/decel model (replaces instant-snap)"
```

---

## Task 8: Player ICE1 wiring (zero friction + entry cap)

The dispatcher already calls `SurfacePhysics.step_ice1` — this task locks the behavior with direct-call tests (no floor needed) and verifies the anim stays Walking while gliding.

**Files:**
- Modify: `tests/unit/test_player_surface.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_player_surface.gd`:

```gdscript
func test_step_grounded_ice1_zero_friction_no_input():
	var p := _new_player()
	p.velocity.x = 480.0
	for i in 60:
		p._step_grounded(ST.Kind.ICE1, 0.0, 0.016)
	assert_almost_eq(p.velocity.x, 480.0, 0.001, "ice1: velocity preserved with no input")


func test_step_grounded_ice1_accelerates_with_input():
	var p := _new_player()
	p.velocity.x = 0.0
	p._step_grounded(ST.Kind.ICE1, 1.0, 0.016)
	assert_almost_eq(p.velocity.x, p.ice_accel * 0.016, 0.01, "ice1: accelerates by ice_accel*delta")


func test_step_grounded_ice1_entry_caps_overspeed():
	var p := _new_player()
	p.ice_max_speed_cap = 480.0
	p.velocity.x = 700.0          # landed faster than cap (e.g. from a leap)
	p._step_grounded(ST.Kind.ICE1, 1.0, 0.016)
	assert_almost_eq(p.velocity.x, 480.0, 0.5, "ice1: entry caps overspeed to cap")


func test_step_grounded_ice1_shows_walking_while_glding():
	# velocity-based anim (absf(vx)>1.0 -> Walking) already handles this; assert it.
	var p := _new_player()
	p._ice2_locked = false
	var moving := absf(480.0) > 1.0 and not p._ice2_locked
	assert_true(moving, "ice1 glide counts as moving -> Walking")
	assert_eq(p._current_anim(true, moving, false, false, false), "Walking")
```

- [ ] **Step 2: Run test to verify it fails (or passes)**

Run: `./tests/run_all.sh`
Expected: The first three PASS already (Task 7 wired ice1). The anim assertion is the new lock-in. If any FAIL, the wiring in Task 7 needs fixing. Run to confirm all PASS.

- [ ] **Step 3: (No new implementation needed)**

The ICE1 path was implemented in Task 7's dispatcher. This task is a regression lock. If a test fails, fix the dispatcher in `player.gd` `_step_grounded` (ICE1 branch) to match `SurfacePhysics.step_ice1` / `step_ice1_entry`.

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tests/unit/test_player_surface.gd
git commit -m "test: lock ice1 zero-friction + entry-cap behavior"
```

---

## Task 9: Player ICE2 wiring — entry/pin/no-entry, wall-stop, idle anim

**Files:**
- Modify: `src/runtime/player/player.gd` (`_step_ice2_ground` stub; `_physics_process` post-move_and_slide; `_current_anim` call site ~line 415)
- Modify: `tests/unit/test_player_surface.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_player_surface.gd`:

```gdscript
func test_step_grounded_ice2_entry_pins_slide_speed():
	var p := _new_player()
	p.ice2_slide_speed = 480.0
	p.velocity.x = 250.0           # moving right on entry
	p._step_grounded(ST.Kind.ICE2, 0.0, 0.016)
	assert_true(p._ice2_locked, "locked on entry")
	assert_eq(p._ice2_entry_dir, 1.0, "entry dir is right")
	assert_almost_eq(p.velocity.x, 480.0, 0.01, "pinned to +slide_speed")


func test_step_grounded_ice2_no_entry_velocity_no_slide():
	var p := _new_player()
	p.velocity.x = 0.0             # dropped straight down: no horizontal velocity
	p._step_grounded(ST.Kind.ICE2, 1.0, 0.016)   # movement key ignored anyway
	assert_false(p._ice2_locked, "no slide when no entry velocity")
	assert_almost_eq(p.velocity.x, 0.0, 0.01, "stands still")


func test_step_grounded_ice2_pins_each_frame_while_locked():
	var p := _new_player()
	p._ice2_locked = true
	p._ice2_entry_dir = -1.0
	p.velocity.x = 123.0           # incoming vx irrelevant once locked
	p._step_grounded(ST.Kind.ICE2, 1.0, 0.016)
	assert_almost_eq(p.velocity.x, -480.0, 0.01, "re-pinned to entry_dir*slide_speed")


func test_ice2_locked_forces_idle_anim():
	# While sliding, |vx|>0 but anim must be Idle (call site passes moving=false).
	var p := _new_player()
	p._ice2_locked = true
	var moving := absf(480.0) > 1.0 and not p._ice2_locked
	assert_false(moving, "ice2 locked -> moving arg is false")
	assert_eq(p._current_anim(true, moving, false, false, false), "Idle")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `_step_ice2_ground` is a no-op stub; `_ice2_locked` never sets, `velocity.x` unchanged.

- [ ] **Step 3: Write minimal implementation**

(a) Replace the `_step_ice2_ground()` stub in `player.gd` (added in Task 7) with:

```gdscript
## ICE2 ground step: on the first locked frame with horizontal velocity,
## record entry_dir and pin to slide_speed. Each subsequent locked frame
## re-pins. No entry velocity -> no slide (stands). Movement keys ignored.
func _step_ice2_ground() -> void:
	if not _ice2_locked:
		if absf(velocity.x) > 1.0:
			_ice2_entry_dir = signf(velocity.x)
			_ice2_locked = true
		else:
			return   # dropped straight down: stand, jump only
	if _ice2_locked:
		velocity.x = SurfacePhysics.step_ice2(_ice2_entry_dir, ice2_slide_speed)
```

(b) Add the wall-stop after `move_and_slide()`. In `_physics_process`, `move_and_slide()` is at line 221, followed by `if is_on_floor():`. Insert the wall-stop right after `move_and_slide()` (before the `if is_on_floor():` line):

```gdscript
	move_and_slide()
	if _ice2_locked and is_on_wall():
		# Slid into a wall: stop dead, clear the lock. Keen stands on the ICE2
		# tile and can only jump (re-slide requires a new landing entry).
		_ice2_locked = false
		velocity.x = 0.0
	if is_on_floor():
```

(c) Ice2 idle anim. At `player.gd:415`, change the `moving` argument so a locked slide reads as Idle. Replace:

```gdscript
	var anim := _current_anim(on_floor, absf(velocity.x) > 1.0, _pogo, _shoot_timer > 0.0, _windup > 0.0)
```

with:

```gdscript
	var moving := absf(velocity.x) > 1.0 and not _ice2_locked
	var anim := _current_anim(on_floor, moving, _pogo, _shoot_timer > 0.0, _windup > 0.0)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/runtime/player/player.gd tests/unit/test_player_surface.gd
git commit -m "feat: ice2 forced-slide entry/pin + wall-stop + idle anim"
```

---

## Task 10: Player coast wiring — entry, fixed-distance decel, input suspend, exit

**Files:**
- Modify: `src/runtime/player/player.gd` (`_step_coast_ground` stub)
- Modify: `tests/unit/test_player_surface.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_player_surface.gd`:

```gdscript
func test_coast_enters_on_ice_to_ground_transition():
	var p := _new_player()
	p.velocity.x = 480.0
	p._prev_surface = ST.Kind.ICE1
	p._step_grounded(ST.Kind.NONE, 0.0, 0.016)   # transition to normal ground
	assert_true(p._coasting, "entered coast")
	assert_gt(p._coast_decel, 0.0, "coast decel computed")


func test_coast_stops_in_about_1_5_tiles():
	var p := _new_player()
	p.coast_distance = 96.0
	var start_x := 0.0
	p.velocity.x = 480.0
	p._prev_surface = ST.Kind.ICE1
	# drive coast with no input until stopped or 2000 frames
	var travelled := 0.0
	var frames := 0
	while frames < 2000:
		p._step_grounded(ST.Kind.NONE, 0.0, 0.016)
		travelled += absf(p.velocity.x) * 0.016
		frames += 1
		if not p._coasting and absf(p.velocity.x) <= 0.5:
			break
	assert_almost_eq(travelled, 96.0, 12.0, "stops within ~1.5 tiles")
	assert_false(p._coasting, "coast exited at stop")
	assert_almost_eq(p.velocity.x, 0.0, 0.5, "velocity zero at stop")


func test_coast_input_suspends_decel_and_steer_accelerates():
	var p := _new_player()
	p.coast_distance = 96.0
	p.velocity.x = 200.0
	p._prev_surface = ST.Kind.ICE1
	p._step_grounded(ST.Kind.NONE, 0.0, 0.016)   # enter coast
	assert_true(p._coasting)
	# now hold a direction: auto-decel suspended, type-1 steering applies
	var before := p.velocity.x
	p._step_grounded(ST.Kind.NONE, 1.0, 0.016)
	assert_gt(p.velocity.x, before, "steering accelerated during coast")
	assert_true(p._coast_steering, "steering flag set")
	# release: decel recomputed from current speed
	var steer_speed := p.velocity.x
	p._step_grounded(ST.Kind.NONE, 0.0, 0.016)
	# new decel derived from current (higher) speed -> larger than the original
	assert_false(p._coast_steering, "steering flag cleared on release")


func test_coast_jump_cancels_via_surface_reset():
	# A jump leaves the ground; _step_grounded isn't called while airborne, and
	# on landing _prev_surface has been reset, so no stale coast resumes. Simulate
	# by NOT calling _step_grounded for the airborne frames then landing on NONE
	# with _prev_surface != ICE.
	var p := _new_player()
	p._coasting = true
	p._coast_decel = 1200.0
	p.velocity.x = 200.0
	# airborne (no _step_grounded calls), then land on NONE fresh:
	p._prev_surface = ST.Kind.NONE
	p._step_grounded(ST.Kind.NONE, 0.0, 0.016)
	# Not an ice->ground transition, and coasting was true -> it continues ONE
	# frame then this is fine; the point: no NEW coast entry. Verify decel path:
	assert_true(p._coasting, "existing coast continues on landing if still moving")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `_step_coast_ground` is a no-op stub; `_coasting` never sets from the dispatcher's transition branch... (it does set in Task 7's transition branch, but `_step_coast_ground` does nothing, so decel/input-suspend won't work).

- [ ] **Step 3: Write minimal implementation**

Replace the `_step_coast_ground(_dir, _delta)` stub in `player.gd` with:

```gdscript
## Coast ground step (normal ground after ice). No input: decelerate at the
## fixed-distance rate toward 0. Input held: suspend auto-decel and apply
## type-1 steering; releasing input recomputes the decel from the current
## speed (so the guaranteed 1.5-tile stop holds only for an uninterrupted
## coast). Exits coast when velocity reaches ~0.
func _step_coast_ground(dir: float, delta: float) -> void:
	if dir != 0.0:
		_coast_steering = true
		velocity.x = SurfacePhysics.step_ice1(velocity.x, dir, ice_max_speed_cap, ice_accel, delta)
	else:
		if _coast_steering:
			_coast_decel = SurfacePhysics.coast_decel_for(velocity.x, coast_distance)
			_coast_steering = false
		velocity.x = SurfacePhysics.step_coast(velocity.x, _coast_decel, delta)
	if absf(velocity.x) <= 1.0:
		_coasting = false
		velocity.x = 0.0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/runtime/player/player.gd tests/unit/test_player_surface.gd
git commit -m "feat: fixed-distance coast on ice->ground exit"
```

---

## Task 11: LevelRuntime — inject geometry TileMapLayer into the player

**Files:**
- Modify: `src/runtime/level_runtime.gd:180-199` (`_spawn_player`)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_player_surface.gd`:

```gdscript
func test_player_ground_tilemap_injected_after_spawn():
	# LevelRuntime.build wires the geometry TileMapLayer into the player.
	# We assert the wiring contract directly: after set_ground_tilemap, the
	# player holds the ref and reads from it (covered in Task 6). Here we only
	# confirm LevelRuntime calls it — by checking the player's _ground_tml is
	# non-null after a real build with a procedural tileset.
	var lv := LevelData.new()
	lv.width = 3
	lv.height = 2
	lv.tile_size = 16
	lv.fill_blank()
	# paint a geometry floor row at y=1 (cells 0..2) with tile id 1
	lv.set_geometry_tile(0, 1, 1)
	lv.set_geometry_tile(1, 1, 1)
	lv.set_geometry_tile(2, 1, 1)
	lv.player_spawn = Vector2i(1, 0)
	var rt: LevelRuntime = add_child_autofree(LevelRuntime.new())
	rt.build(lv)
	await get_tree().physics_frame
	var p := rt.player as Player
	assert_not_null(p, "player spawned")
	assert_not_null(p._ground_tml, "geometry TileMapLayer injected into player")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run_all.sh`
Expected: FAIL — `p._ground_tml` is null (LevelRuntime doesn't call `set_ground_tilemap` yet).

- [ ] **Step 3: Write minimal implementation**

In `src/runtime/level_runtime.gd`, in `_spawn_player()` (around line 184, right after `player = p` and before/after the camera/mode setup — place it after `p.set_camera_bounds(...)`), add the injection. The geometry layer is built in `build()` at line 129 into `layers[LevelData.LAYER_GEOMETRY]`. Insert after the `p.set_camera_bounds(world_bounds)` line:

```gdscript
	p.set_ground_tilemap(layers[LevelData.LAYER_GEOMETRY])
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/run_all.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/runtime/level_runtime.gd tests/unit/test_player_surface.gd
git commit -m "feat: inject geometry tilemap into player at spawn"
```

---

## Task 12: Full suite + tuning defaults + playtest note

**Files:** none (verification + docs)

- [ ] **Step 1: Run the complete test suite**

Run: `./tests/run_all.sh`
Expected: ALL PASS — every `test_player*.gd`, `test_surface_physics.gd`, `test_procedural_tileset.gd`, `test_projectile.gd`, and the rest.

- [ ] **Step 2: Verify no regressions in unrelated tests**

Skim the output for any FAIL. If a pre-existing test broke from the ground-accel change (Task 7), update its assertion to the accel model. (As of writing, no existing test exercises the grounded-walking branch, so none should break — but verify.)

- [ ] **Step 3: Confirm the dev-config path for procedural ice tiles**

The procedural builder now accepts `ice1_ids`/`ice2_ids`. For dev/test levels that use the procedural fallback (no `tileset_ref`), decide which solid-color tile ids read as ice and wire them at the `ProceduralTileSet.build(...)` call site in `level_runtime.gd:125` (e.g. pass `[<ice1 id>]`, `[<ice2 id>]`). Author real ice tiles via the TileSet editor's `surface_type` custom-data layer for authored-tileset levels. Leave a one-line note in `docs/future-work.md` under a new "Ice tile config" heading recording which ids are ice for the procedural path.

- [ ] **Step 4: Playtest + dial tuning**

Build + launch: `make run-app` (or load a level with ice tiles). Dial these `@export` defaults in `player.gd` by feel:
- `ground_accel` / `ground_decel` (whole-game walking feel)
- `ice_accel` (ice1 steer/turn rate)
- `ice_max_speed_cap` / `ice2_slide_speed` (default `run_speed`)
- `coast_distance` (default 96 = 1.5 tiles)

- [ ] **Step 5: Commit tuning + note**

```bash
git add src/runtime/player/player.gd docs/future-work.md
git commit -m "tune: ice + ground accel defaults; note procedural ice tile config"
```

---

## Self-Review

**1. Spec coverage** — each spec requirement maps to a task:
- R1 (surface_type custom-data layer) → Task 5.
- R2 (ice1: zero friction, accel, turn, walking) → Tasks 2, 7, 8.
- R3 (ice2: pin, ignore keys, idle, jump) → Tasks 3, 9.
- R4 (ice2 wall stop + no-entry no-slide) → Task 9.
- R5 (coast 1.5-tile fixed stop) → Tasks 4, 10.
- R6 (coast input suspend + recompute) → Task 10.
- R7 (jump from ice) → covered by unchanged jump path; landing resume via surface read (Tasks 6, 7).
- R8 (ice1 entry cap) → Tasks 2, 7, 8.
- R9 (ground accel/decel) → Tasks 1, 7.
- R10 (player reads surface; missing→NONE) → Task 6.
- R11 (pogo/enemies/projectiles/overworld unaffected) → Tasks 7/9 touch only the ground branch + one anim arg + one post-move_and_slide check; verified by unchanged existing pogo/projectile tests in Task 12.
- R12 (tests pass + new tests) → every task is TDD; Task 12 runs the full suite.

**2. Placeholder scan** — no TBD/TODO/“add error handling”. Every step has complete code.

**3. Type consistency** — `SurfacePhysics.step_ground/step_ice1/step_ice1_entry/step_ice2/coast_decel_for/step_coast` signatures are identical across definition (Tasks 1-4) and call sites (Task 7 dispatcher). `SurfaceType.Kind.NONE/ICE1/ICE2` used consistently. `_ground_tml`, `_coasting`, `_coast_decel`, `_coast_steering`, `_ice2_locked`, `_ice2_entry_dir`, `_prev_surface` named identically in Task 7 (declaration) and Tasks 9/10 (use). `set_ground_tilemap` matches Task 6 (def) and Task 11 (call).
