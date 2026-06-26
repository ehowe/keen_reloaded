# keen_reloaded — Plan 3 Design: Runtime Core

**Date:** 2026-06-26
**Status:** Approved (pending spec review)
**Parent spec:** `docs/superpowers/specs/2026-06-25-keen-reloaded-design.md` (§6 Game Runtime)

## 1. Goal

Build the gameplay runtime that turns a `LevelData` resource into a playable scene: a procedural no-art tile world with collision, a `CharacterBody2D` player that can run / jump / pogo, the base entity-class hierarchy, and a live **Test ▶** path from the editor. No real art assets and no concrete Keen 1 entities — those arrive in Plan 4. Plan 3 ships a fully working runtime so the editor's Test ▶ is immediately useful for iteration.

## 2. Scope

### In scope
- `LevelRuntime` — builds a scene tree from a `LevelData`.
- Procedural `TileSet` + `TileMapLayer` rendering and collision with **no art files**.
- Player `CharacterBody2D`: run, jump, **pogo** (no shoot — deferred to Plan 4).
- Base entity classes: `Entity`, `Enemy`, `Collectible`, `Hazard`, `Special`.
- `EntityRegistry` extension: scene binding + `instantiate(...)`.
- `GameManager` extension: `pending_level` / `return_scene` for the Test ▶ round-trip.
- Editor wiring: live Test ▶ + level restore on return.
- GUT unit tests for all deterministic/pure logic.

### Out of scope (deferred to Plan 4 / later)
- Real art / sprite / tileset assets (placeholder procedural visuals only).
- Concrete Keen 1 entities (vorticon, yorp, butler, candy, exit door) — Plan 3 spawns default base-class placeholder nodes for the registered types.
- Player **shoot** ability + projectile system.
- Exit / special-entity completion logic and level advancement (a Plan 4 concern once real exits exist).
- Audio, parallax, HUD, save/progression (Plan 6).

## 3. Key decisions (resolved during brainstorm)

| Decision | Choice | Rationale |
|---|---|---|
| Tile render + collision, no art | Procedural `TileSet` + `TileMapLayer` | Matches spec §6 architecture; Godot handles render + collision; zero art files; editor Test ▶ and runtime share the look. |
| Solid vs decorative tiles | Two procedural TileSets: `solid` (collision per tile) and `decor` (no collision) | Clean, symmetric, unambiguous which layers collide; trivially testable. |
| Player abilities (Plan 3) | Run + jump + pogo | Pogo is a signature Keen move worth landing now; shoot (needs projectiles + damage hook) waits for content. |
| Testing depth | GUT for pure logic; manual for movement feel | Physics-stepping in headless GUT is fragile; don't fight it. Scene assembly + entity logic are deterministic and worth TDD. |
| Test ▶ handoff | `GameManager.pending_level` stash + `change_scene_to_packed`; Esc returns | Clean scene separation; editor state survives the round-trip. |

## 4. Architecture

### 4.1 Components

```
src/runtime/
  procedural_tileset.gd     builds TileSet(s) from tile ids, no art
  level_runtime.gd          LevelRuntime(Node2D) controller
  level_runtime.tscn        runtime scene root
  player/
    player.gd               CharacterBody2D: run/jump/pogo + score/health
    player.tscn
  entities/
    entity.gd               Entity(Node2D) base
    enemy.gd
    collectible.gd
    hazard.gd
    special.gd
src/core/
  entity_registry.gd        extend: scene + instantiate(type_id,pos,props)
  game_manager.gd           extend: pending_level, return_scene
src/editor/
  level_editor.gd           wire live Test ▶ + restore on return
tests/unit/
  test_procedural_tileset.gd
  test_level_runtime.gd
  test_entity_registry_instantiate.gd
  test_runtime_entities.gd
```

### 4.2 ProceduralTileSet

`ProceduralTileSet` is a `RefCounted` helper with a static builder.

```
static func build(max_id: int, tile_size: int, with_collision: bool) -> TileSet
```

- Generates one atlas `Image` of width `max_id * tile_size`, height `tile_size`.
- For each id `1..max_id`, paints that id's cell with `EditorColors.tile_color(id)` (reuses the Plan 2 editor palette so editor and runtime look consistent).
- Creates a `TileSet`, adds a `TileSetAtlasSource` from the `ImageTexture2D`, creates each tile, sets texture origin / spacing so `get_tile_id == id`.
- If `with_collision`: adds one physics layer to the TileSet and, for each tile, a full-cell `PackedVector2Array` rectangle collision polygon. If not: no physics layer, no polygons.
- `max_id` is derived at runtime from the maximum non-zero tile id present across the level's three arrays (clamped to a sane floor like 8 so the default palette always exists).

`LevelRuntime` builds `solid_tileset = build(max_id, tile_size, true)` once and `decor_tileset = build(max_id, tile_size, false)` once.

### 4.3 LevelRuntime

`LevelRuntime extends Node2D`, scene `level_runtime.tscn` is a bare `Node2D` with this script. Children are built in code (consistent with the Plan 2 editor's code-built approach).

`build(level: LevelData)`:
1. `scale = Vector2(RUNTIME_SCALE, RUNTIME_SCALE)` on self.
2. Compute `max_id`.
3. Build `solid_tileset` + `decor_tileset`.
4. Create a `TileMapLayer` for **background** → `decor_tileset`, set every non-zero `background_tiles` cell.
5. Create a `TileMapLayer` for **foreground** → `decor_tileset`, set every non-zero `foreground_tiles` cell.
6. Create a `TileMapLayer` for **geometry** → `solid_tileset`, set every non-zero `geometry_tiles` cell.
7. Spawn player: `preload(player.tscn).instantiate()`, position = `player_spawn * tile_size` (the self-scale handles the rest), add to tree, add to group `"player"`. The player scene carries its own `Camera2D` (centered automatically).
8. Spawn each `EntityDef`: `EntityRegistry.instantiate(def.type, Vector2(def.x, def.y) * tile_size, def.properties)`, add to tree.

`_ready()`: if `GameManager.pending_level != null`, call `build(GameManager.pending_level)`.

`_unhandled_input()`: `KEY_ESCAPE` → `get_tree().change_scene_to_packed(GameManager.return_scene)` (back to editor).

### 4.4 Player

`Player extends CharacterBody2D` (scene `player.tscn`: CharacterBody2D + CollisionShape2D(rect) + ColorRect visual + Camera2D). Constants are `@export` for tuning.

Movement model:
- **Run:** `Input.get_vector("move_left","move_right")` → `velocity.x = dir * RUN_SPEED`. Apply friction/snap as needed.
- **Gravity:** `velocity.y += GRAVITY * delta` when not on floor (clamped to a terminal velocity).
- **Jump:** coyote timer (`COYOTE_TIME`) + jump buffer (`JUMP_BUFFER`). Press `jump` while coyote-active and on/near floor → `velocity.y = JUMP_VELOCITY`.
- **Pogo:** toggle (press `pogo`). While pogo is active, on landing set `velocity.y = POGO_BOUNCE` (auto-bounce each contact). Pogo bounces higher than jump. Pressing `pogo` again deactivates.
- `move_and_slide()` each `_physics_process`.

Player-facing API used by entities:
- `add_score(amount: int)` — increments `score`, emits `score_changed`.
- `take_damage(amount: int)` — decrements `health`, emits `health_changed`; emits `died` at 0.

Groups: added to group `"player"` so entities detect it generically.

### 4.5 Base entity classes

All `extends Node2D` (not CharacterBody2D — entities use an `Area2D` child for contact detection in Plan 4; Plan 3 base classes keep it minimal but functional).

- `Entity`: holds `type_id: String`, `properties: Dictionary`. Has an `Area2D` + `CollisionShape2D`(rect) + placeholder `ColorRect` visual sized to one tile. `body_entered` connected to `_on_body_entered(body)`, which dispatches to subclass hooks. Helper `_get_player() -> Node` finds body in group `"player"`.
- `Collectible extends Entity`: `score_value: int`. On player contact → `player.add_score(score_value)` → `queue_free()`.
- `Hazard extends Entity`: `damage: int`. On player contact → `player.take_damage(damage)`.
- `Enemy extends Entity`: `health: int`, `contact_damage: int`. On player contact → `player.take_damage(contact_damage)`. `take_damage(amount)` → `health -= amount`; `queue_free()` at 0. (No AI movement in Plan 3 — Plan 4.)
- `Special extends Entity`: no-op hooks (`_on_player_entered` override point). Exits/doors/triggers are concrete Plan 4 content.

### 4.6 EntityRegistry extension

Add scene binding to the existing data-layer API.

```
func register(type_id, category, label, properties=[], scene: PackedScene=null)
func instantiate(type_id: String, pos: Vector2, props: Dictionary={}) -> Node2D
```

- If the registered type has a `scene`, instance it; else build a default node by category: enemy→`Enemy.new()`, item→`Collectible.new()`, hazard→`Hazard.new()`, special→`Special.new()` (each wires its own Area2D/visual).
- Set `type_id`, `properties`, `position = pos`.
- Unknown `type_id` → return `null` (caller logs/skips).
- The existing default roster (vorticon, yorp, butler, candy, exit_door, player_spawn) keeps working: with no scene they spawn as default base-class nodes, so "spawn all registered entity types" succeeds for the integration test and the editor Test ▶.

### 4.7 GameManager extension

```
var pending_level: LevelData = null
var return_scene: PackedScene = null
```

(Used only for the Test ▶ round-trip; not persisted to disk in Plan 3.)

### 4.8 Editor wiring

- `LevelEditor.test_run()`: `GameManager.pending_level = level`; `GameManager.return_scene = preload("res://src/editor/level_editor.tscn")`; `get_tree().change_scene_to_packed(preload("res://src/runtime/level_runtime.tscn"))`.
- `LevelEditor._ready()`: if `GameManager.pending_level != null`, restore `level = GameManager.pending_level`, rebuild canvas/inspector instead of `_new_level()`.

## 5. Data flow

```
Editor Test ▶
  → GameManager.pending_level = editor.level
  → GameManager.return_scene = level_editor.tscn
  → change_scene_to_packed(level_runtime.tscn)
       → LevelRuntime._ready reads GameManager.pending_level
       → build(level)
            → ProceduralTileSet.build(solid) + build(decor)
            → 3 TileMapLayers (bg/fg/geo) cells from arrays
            → Player @ player_spawn * tile_size (scaled)
            → EntityRegistry.instantiate per EntityDef
       → play: run/jump/pogo, gravity, tile collision, entity Area2D contact
  → Esc → change_scene_to_packed(return_scene = level_editor.tscn)
       → LevelEditor._ready restores level from GameManager.pending_level
```

## 6. Testing

| Layer | Approach |
|---|---|
| `ProceduralTileSet` | GUT: tile count == max_id; atlas dims correct; **solid** TileSet tiles have collision polygons + a physics layer; **decor** tiles have none. |
| `LevelRuntime.build` | GUT (headless, nodes added to a temp parent, not ticked): exactly 3 TileMapLayers; correct cells set per layer (sample coords); a node in group `"player"` exists at the expected position; child entity count == `level.entities.size()`. |
| `EntityRegistry.instantiate` | GUT: each category returns the right base-class node; `type_id`/`properties`/`position` applied; unknown type → `null`; default roster (no scenes) instantiates without error. |
| Base entity logic | GUT: synthesize a body added to group `"player"` and call `_on_body_entered(body)` directly — `Collectible` raises player score + frees self; `Hazard`/`Enemy` lower player health; `Enemy.take_damage` reduces health and frees at 0. |
| Movement feel (run/jump/pogo) | **Manual** via editor Test ▶. |

## 7. Defaults (tunable)

- `RUNTIME_SCALE = 3` (tile_size 16 → 48px on screen).
- `GRAVITY = 980`, `RUN_SPEED = 120`, `JUMP_VELOCITY = -300`, `POGO_BOUNCE = -380`, `MAX_FALL = 480`.
- `COYOTE_TIME = 0.10`, `JUMP_BUFFER = 0.10`.
- All as `@export` on `Player` for live tuning.

## 8. Complete-criteria for the plan

- `LevelRuntime` builds a correct scene from any `LevelData` (proven by GUT).
- Player runs, jumps, pogos against procedural tile collision (proven manually).
- Base entity classes function on contact (proven by GUT).
- `EntityRegistry.instantiate` spawns every registered type (proven by GUT).
- Editor Test ▶ launches the runtime; Esc returns; level is restored intact.
- `./tests/run_all.sh` green; `godot --headless --import --quit` clean.
