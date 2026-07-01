# keen_reloaded — Plan 4: Gameplay Content (Design Spec)

**Date:** 2026-07-01
**Status:** Draft (pending spec review)
**Parent spec:** `docs/superpowers/specs/2026-06-25-keen-reloaded-design.md` (§6 Game Runtime, §7 Episodes)
**Predecessors:** Plans 1–3 (data model, editor MVP, runtime core) + Plan 4 tile-art pipeline.
**Scope owner:** runtime + episode content

## 1. Goal

Turn the placeholder runtime into a playable, Keen-1-flavored loop: shootable multi-hit enemies with patrol AI, the raygun + ammo system, level completion via exit door, concrete entity scenes (procedural, scene-ready for a future sprite swap), and per-episode entity registration through a global union catalog. Plus author the first real level. **No new art assets** — entities keep procedural visuals.

This finishes the gameplay scope that the Plan 4 tile-art spec explicitly deferred (entity sprites, shoot, enemy AI, exit/special logic, first level).

## 2. Scope

### In scope
- **Entity base restructure** — `Entity` becomes `CharacterBody2D`; contact via a child `Area2D`; physics entities add a body `CollisionShape2D` + gravity.
- **Concrete Keen 1 entities** as scenes — Vorticon (patrol + random hop, 3 HP), Yorp (slow patrol + knockback, 1 HP), Butler (fast patrol, armored), Candy (score pickup), Raygun ammo pickup, Exit door.
- **Player shoot** — ammo-limited raygun; fires a `Projectile` in facing direction; `add_ammo()` + `ammo_changed` signal; new `shoot` input action.
- **Projectile system** — `Area2D` projectile, kills enemies on hit, despawns on wall/timer.
- **Exit / completion** — `ExitDoor` emits `level_completed`; `LevelRuntime` shows a "Level Complete" overlay (score + elapsed time), freezes input, returns on any key/Esc.
- **Minimal in-play HUD** — plain `Label`s (score / ammo / health). Full HUD polish stays Plan 6.
- **Per-episode registration** — `Episode` base class + `src/episodes/keen1/episode.gd`; `GameManager` auto-discovers episodes at boot and registers each into the global `EntityRegistry` (union catalog, namespaced type ids).
- **Editor migration** — update hardcoded type-id defaults/checks to namespaced ids.
- **First level** — author `assets/levels/keen1/level1.tres` via `make edit`.
- GUT tests for all deterministic logic.

### Out of scope (deferred)
- Level-pack loading, level-select menu, level-to-level progression chain (Plan 5). Reaching the exit returns to editor (Test ▶) or main menu (standalone) — no "next level".
- Entity sprite art (this plan is procedural, scene-ready; sprite swap is a later art pass).
- Pack-local entity registration — custom level packs **reuse** registered types only (Plan 5 may revisit).
- Audio, parallax/backgrounds, full HUD styling, save/progression, gamepad (Plan 6).

## 3. Key decisions (resolved during brainstorm)

| Decision | Choice | Rationale |
|---|---|---|
| Entity visuals | **Procedural, scene-ready** | Each entity = `.tscn` with a placeholder `Visual` node; swapping in a `Sprite2D` later is trivial. No asset authoring this plan. |
| Shoot | **Ammo-limited, kills** | Faithful to Keen 1: start ammo `@export` (default 5); `keen1.raygun` pickups grant ammo; projectile kills on hit. |
| Entity behaviors | **Faithful roster** | Vorticon (patrol+hop, 3 HP, deadly), Yorp (slow, knockback+minor dmg, 1 HP), Butler (fast patrol, contact dmg, **armored** = unshootable), Candy, Exit. |
| Enemy physics | **CharacterBody2D** uniform | `Entity extends CharacterBody2D`; physics entities add body collision + gravity; static ones (candy/exit/raygun) don't. One base class, clean gravity/turn-at-walls/ledge detection. |
| Exit | **Complete overlay** | Freeze, show score+time, any key/Esc returns (editor if Test ▶, menu if standalone). No progression wiring. |
| Registration | **Per-episode union catalog** | `episodes/keen1/episode.gd` registers namespaced types into the global catalog at boot; union of all shipped episodes. |
| Custom-level entity reuse | **Reuse only** | Catalog is a global union of shipped episodes; custom packs reference existing type ids — no pack-local types (deferred to Plan 5). |

## 4. Architecture

### 4.1 Collision layers (already in `project.godot`)

| Layer | Name | Bit value |
|---|---|---|
| 1 | player | 1 |
| 2 | enemies | 2 |
| 3 | tiles | 4 |
| 4 | items | 8 |

- **Enemy body**: `collision_layer = enemies(2)`, `collision_mask = tiles(4)` (gravity/patrol collide with floor; never with player). Its contact `Area2D` child: `collision_mask = player(1)`.
- **Projectile `Area2D`**: `collision_mask = enemies(2) | tiles(4) = 6` → detects enemies + walls, ignores items.
- **Static entities** (candy/raygun/exit): body `collision_layer = items(8)`, `collision_mask = 0` (no physics); contact `Area2D` `mask = player(1)`.

### 4.2 Entity base restructure

`Entity extends CharacterBody2D` (was `Node2D`). Unchanged: `type_id`, `properties`, `setup()` property-binding, `player_touched` signal, contact `Area2D`, `_handle_player()` hook.

- `_ready()`: builds the contact `Area2D` (mask = player bit) as today. For the visual: if the scene provides a child node named **`Visual`**, it is used as-is; otherwise a fallback `ColorRect` is built. This makes each entity's `.tscn` the art seam (swap `Visual` later).
- The `CharacterBody2D` body has **no** `CollisionShape2D` by default. Physics subclasses add one (via their scene) and set body `collision_layer`/`collision_mask`.
- `TILE = 64` retained for shape sizing.

### 4.3 `Enemy` (physics base) `extends Entity`

```gdscript
class_name Enemy
extends Entity
# Physics-enabled base. Concrete enemies extend this and override AI knobs/hook.

@export var gravity: float = 3920.0
@export var patrol_speed: float = 120.0
@export var max_fall: float = 1920.0

var health: int = 1
var contact_damage: int = 1
var score_value: int = 100

var _dir: int = -1            # patrol facing: -1 left, +1 right
@export var turns_at_ledges: bool = true
@export var turns_at_walls: bool = true
```

- `_physics_process(delta)`: apply gravity (clamp `max_fall`); set `velocity.x = _dir * patrol_speed`; flip `_dir` on `is_on_wall()` (if `turns_at_walls`) and on missing-floor-ahead (if `turns_at_ledges`, via a `RayCast2D` child pointing ahead-and-down that stops targeting when the enemy turns); `move_and_slide()`.
- `_handle_player(player)`: `player.take_damage(contact_damage)`. (Yorp overrides to add knockback.)
- `take_damage(amount)`: `health -= amount`; at `<= 0` award `score_value` to the player (found via `get_tree().get_first_node_in_group("player")`, guarded) then `queue_free()`.
- Concrete overrides:
  - **Vorticon**: `health = 3`, `score_value = 300`; random hop — small per-second chance, when on floor set `velocity.y = -hop_force`. `turns_at_ledges = true`.
  - **Yorp**: `health = 1`, `score_value = 100`, slow `patrol_speed`; `_handle_player` knockback: `player.velocity += Vector2(sign(player.global_position.x - global_position.x) * KB_X, -KB_Y)` + `player.take_damage(1)`.
  - **Butler**: fast `patrol_speed`; `score_value = 0` (unkillable); overrides `take_damage()` → **no-op** (armored). `turns_at_ledges = true`.

### 4.4 Player extensions (`player.gd` / `player.tscn`)

- `_facing: int = 1` updated from `Input.get_axis("move_left","move_right")` each frame (last non-zero dir wins; default right).
- Ammo: `@export var max_ammo: int = 5`; `var ammo: int`; `add_ammo(n)` (clamps to `max_ammo`); `signal ammo_changed(ammo: int)`. Initialized to `max_ammo` in `_ready()`.
- `shoot()`: on `Input.is_action_just_pressed("shoot")` and `ammo > 0` → instantiate `projectile.tscn` at the **Muzzle** `Marker2D` (added to the scene at the player's front), set its velocity to `Vector2(_facing * PROJECTILE_SPEED, 0)`, `ammo -= 1`, `ammo_changed.emit(ammo)`.
- New input action **`shoot`** (physical key **X**), registered in `GameManager._ensure_input_actions()`.
- `player.tscn`: add a `Muzzle` `Marker2D` child offset to the player's front (e.g. `Vector2(32, 0)`).

### 4.5 Projectile (`projectile.gd` / `projectile.tscn`)

`Area2D` root, `collision_mask = 6` (enemies|tiles), `monitoring = true`. Small `CollisionShape2D` (rect) + a procedural `Line2D`/`ColorRect` visual.

- `var velocity: Vector2`; `var lifetime: float` (set by spawner, e.g. `2.0`s).
- `_physics_process(delta)`: `global_position += velocity * delta`; `lifetime -= delta`; if `lifetime <= 0` → `queue_free()`.
- `body_entered(body)`:
  - if `body.has_method("take_damage")` → `body.take_damage(1)` + `queue_free()` (enemy hit);
  - elif `body` not in group `"entity"` → `queue_free()` (wall/tile hit);
  - else (an `"entity"` without `take_damage`, e.g. an item) → **pass through** (no-op).
- **Risk note:** `Area2D.body_entered` detecting `TileMapLayer` physics bodies — if unreliable in testing, fallback to a `CharacterBody2D` projectile that despawns on `move_and_collide` contact. This is a test gate, not an open question.

### 4.6 Pickups

- **`Candy` `extends Collectible`** — scene only; `score_value = 100` (base behavior unchanged: `add_score` + free).
- **`AmmoPickup` `extends Collectible`** — `@export var ammo_value: int = 5`; `_handle_player(player)`: `if player.has_method("add_ammo"): player.add_ammo(ammo_value)` then `queue_free()`. Registered as `keen1.raygun`.

### 4.7 Exit / completion

- `Special extends Entity` gains `signal level_completed` (declared on `Special`; harmless no-op default — only `ExitDoor` emits).
- **`ExitDoor extends Special`**: `_handle_player(_player)` emits `level_completed` **once** (an `_triggered` guard prevents repeat emits).
- **`LevelRuntime`**:
  - `var elapsed: float = 0`; `var _completed: bool = false`; `_process(delta)` accumulates `elapsed` only while `not _completed`.
  - `_spawn_entities()`: after `EntityRegistry.instantiate`, if `node.has_signal("level_completed")` → `node.level_completed.connect(_on_level_completed)`.
  - `_on_level_completed()`: set `_completed = true`; build a **completion overlay** (`CanvasLayer`, `process_mode = PROCESS_MODE_ALWAYS`) with `Label`s (score, elapsed time, "press any key / Esc"); `get_tree().paused = true` (freezes player/enemy physics).
  - Overlay input: any key or click → `get_tree().paused = false` → return via the same path as Esc (`GameManager.return_scene` if set, else `main_menu.tscn`).

### 4.8 Minimal HUD

`LevelRuntime` builds a `CanvasLayer` (below the overlay) with plain `Label`s: **Score / Ammo / Health**. Built in `_spawn_player()`; connected to the player's `score_changed`, `ammo_changed`, `health_changed` signals. No styling (Plan 6 owns polish).

### 4.9 Per-episode registration (union catalog)

- **`src/core/episode.gd`** — new base:
  ```gdscript
  class_name Episode
  extends RefCounted
  ## A content module that registers its entity types into the global catalog.
  var id: String
  var title: String
  func register_entities(_registry: Node) -> void:
      pass
  ```
- **`src/episodes/keen1/episode.gd`** — `extends Episode`; `id = "keen1"`, `title = "Marooned on Mars"`; `register_entities(registry)` binds each concrete `.tscn` to a namespaced id with its category + tunable `properties` list (so the editor inspector exposes per-entity knobs):
  | type_id | category | label | scene |
  |---|---|---|---|
  | `keen1.vorticon` | enemy | Vorticon | vorticon.tscn |
  | `keen1.yorp` | enemy | Yorp | yorp.tscn |
  | `keen1.butler` | hazard | Butler Robot | butler.tscn |
  | `keen1.candy` | item | Candy | candy.tscn |
  | `keen1.raygun` | item | Raygun Ammo | ammo_pickup.tscn |
  | `keen1.exit_door` | special | Exit Door | exit_door.tscn |
  | `keen1.player_spawn` | special | Player Spawn | — (marker; no scene) |
- **`EntityRegistry`**: drop `_register_defaults()` / `register_defaults()` and the hardcoded roster → becomes a **pure union catalog** (`register`, `has`, `get_entry`, `get_palette_entries`, `clear`, `instantiate`). Type-id conflict on duplicate registration = last-wins (no merge logic needed this plan).
- **`GameManager._ready()`**: after input actions, `_register_episodes()`: `DirAccess.open("res://src/episodes")`, enumerate subdirs, `load("res://src/episodes/<ep>/episode.gd").new()`, call `.register_entities(EntityRegistry)`; collect episode metadata. (Listing `res://` scripts works in exported builds since they're packaged.)
- `keen1.player_spawn` is a **non-spawning marker**: the editor special-cases its placement (see §4.10). `instantiate("keen1.player_spawn")` returns a harmless default `Special` node, but runtime never calls it — the player spawns from `level.player_spawn`, not from `entities`.

### 4.10 Editor migration

Two hardcoded type-id references in `level_editor.gd` must move to namespaced ids:
- `var selected_entity_type: String = "vorticon"` (line ~28) → `"keen1.vorticon"`.
- `_place_entity()` check `if selected_entity_type == "player_spawn":` (line ~234) → `"keen1.player_spawn"`.

(No other editor logic depends on the literal ids; the palette already reads dynamically from `EntityRegistry.get_palette_entries()`.)

## 5. Data flow

```
Boot
  GameManager._ready
    → _ensure_input_actions() (adds "shoot" = KEY_X alongside existing)
    → _register_episodes()
         DirAccess src/episodes/*/episode.gd → .new().register_entities(EntityRegistry)
    → catalog = { keen1.vorticon, keen1.yorp, keen1.butler, keen1.candy,
                  keen1.raygun, keen1.exit_door, keen1.player_spawn(marker) }

Editor Test ▶  (unchanged handoff)
  GameManager.pending_level = level; return_scene = level_editor.tscn
  → change_scene_to_packed(level_runtime.tscn)

LevelRuntime.build(level)
  → tiles (tileset_ref or procedural)
  → player @ player_spawn (connect HUD signals; build HUD)
  → entities: EntityRegistry.instantiate(type_id, pos, props) per EntityDef
       connect node.level_completed → _on_level_completed (when present)
  → build bounds (unchanged)

Run loop
  player: run / jump / pogo / shoot (ammo--)
  enemies: gravity + patrol (turn at walls/ledges); vorticon hop; yorp knockback
  Area2D contacts:
    projectile→enemy(2): take_damage(1) → (dead? award score + free) ; projectile free
    projectile→tile(4): projectile free ; projectile→item: pass-through
    enemy→player: take_damage / knockback
    candy→player: add_score + free ; raygun→player: add_ammo + free
    exit→player: level_completed.emit (once)

Completion
  _on_level_completed → _completed=true, overlay(score,time), tree.paused
  any key/Esc → unpause → return (return_scene ? editor : main_menu)
```

## 6. Testing

| Area | Approach |
|---|---|
| `EntityRegistry` (union) | GUT: after `clear()` the catalog is empty (no hardcoded defaults); register keen1 episode → all 7 ids present with correct category (6 gameplay types carry a scene; `player_spawn` carries none); `get_palette_entries()` sorted by category/label; `instantiate` returns the right scene node per gameplay type; unknown type → `null`. |
| `Episode` discovery | GUT: keen1 episode `.new().register_entities(registry)` yields exactly the namespaced ids above. |
| `Enemy` logic | GUT: `take_damage` reduces HP + frees at 0 + awards `score_value` to a fake player; Butler `take_damage` no-op (armored, not freed); Vorticon 3 HP. (Movement/patrol = manual.) |
| `Projectile` | GUT: `lifetime` expiry → free; `body_entered` enemy(stub w/ take_damage) → take_damage + free; tile body → free; item(group "entity", no take_damage) → no-op (passes through). |
| `AmmoPickup` / `Candy` / `ExitDoor` | GUT: ammo → `add_ammo` + free; candy → `add_score` + free; exit → emits `level_completed` exactly once. |
| `Player` shoot | GUT: shoot with `ammo>0` → ammo-- + a projectile node exists at muzzle; `ammo==0` → no projectile spawned; `add_ammo` clamps to `max_ammo` + emits. (Facing = manual.) |
| `LevelRuntime` completion | GUT: spawn an `ExitDoor`, emit its signal → overlay node exists + `_completed == true` + tree paused; `elapsed` increments pre-completion, frozen after. |
| Movement feel, patrol AI, overlay UX, editor authoring | **Manual** via Test ▶ / `make edit`. |

Existing tests referencing un-namespaced ids (`vorticon`, `yorp`, …) and calling `register_defaults()` are **migrated**: either register keen1 via the episode, or register in-test fixtures directly.

### Manual verification (`make edit` + Test ▶)
- Palette lists namespaced keen1 entities; placing each spawns correctly.
- Player shoots left/right per facing; ammo decrements; raygun pickups refill.
- Vorticon patrols + hops, takes 3 shots to die, awards score; Yorp knocks player back; Butler ignores shots.
- Reaching the exit door shows the overlay; any key returns to editor.

## 7. Defaults / conventions

- Projectile speed `600 px/s`, lifetime `2.0 s` (tunable).
- Vorticon: `health 3`, `score_value 300`, `patrol_speed 140`, hop force `700`, hop chance `~0.5/s`.
- Yorp: `health 1`, `score_value 100`, `patrol_speed 70`, knockback `KB_X 400 / KB_Y 300`.
- Butler: `health 1` (armored), `score_value 0`, `patrol_speed 220`.
- Player: `max_ammo 5`; `shoot` = physical **X**.
- Entity scenes live under `src/runtime/entities/`; episode script under `src/episodes/keen1/`.
- All movement constants `@export` for live tuning.

## 8. Complete-criteria for the plan

- [ ] Per-episode union catalog; keen1 registers 7 namespaced ids (6 gameplay types with scenes + `player_spawn` marker); `EntityRegistry` has no hardcoded defaults — GUT.
- [ ] Player runs/jumps/pogos/**shoots** (ammo-limited, facing dir) — manual.
- [ ] Vorticon/Yorp/Butler patrol + faithful contact/death/knockback/armor behaviors — manual; `take_damage` GUT.
- [ ] Projectile kills enemies, despawns on wall/lifetime, passes through items — GUT + manual.
- [ ] Candy/raygun pickups work; exit door → completion overlay (score + time) → return — GUT + manual.
- [ ] Minimal HUD (score/ammo/health) visible during play — manual.
- [ ] Editor palette + placement work with namespaced ids (incl. `player_spawn`) — manual.
- [ ] First level authored at `assets/levels/keen1/level1.tres` via `make edit` — manual.
- [ ] `./tests/run_all.sh` green; `godot --headless --import --quit` clean; all work committed to `main`.

## 9. Migration / risk notes

- **Editor literals:** two hardcoded type-id strings in `level_editor.gd` migrate to namespaced ids (§4.10). The palette itself is dynamic — no other editor change.
- **Existing authored level:** `level1.tres` is re-authored as part of this plan; any stale un-namespaced `EntityDef.type` values in it are replaced during authoring.
- **Projectile vs tiles:** Area2D tile detection is the one runtime uncertainty; the spec names a concrete fallback (CharacterBody2D projectile). Resolved at the test gate, not left open.
- **`res://` DirAccess in export:** listing `src/episodes/*/episode.gd` relies on packaged scripts being enumerable; verified at the import/clean gate. If export strips them, fall back to an explicit episode list in `GameManager` (documented escape hatch).
