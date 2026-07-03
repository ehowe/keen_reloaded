# Sprite-Backed Entities — Design Spec

**Date:** 2026-07-03
**Status:** Approved
**Engine:** Godot 4.7 (stable)
**Language:** GDScript

## 1. Overview

Turn sprite `.tscn` files in `assets/sprites/` into first-class, placeable
entities — without a new editor tool, a new command class, or a new data field.
A sprite becomes placeable by adding one `register_sprite(...)` line to
`Keen1Episode.register_entities()`. Placement reuses the existing entity tool
(tile-cell snapped), undo/redo reuses `AddEntityCmd` / `RemoveEntityCmd`, and
serialization is unchanged (`EntityDef.type` stores the type_id, scene resolved
at runtime via the registry).

The only real engineering work is bridging raw sprite scenes — whose roots are
bare `Node`s with no script, no `type_id`, no `setup()` — into the `Node2D`-based
entity spawn path. A thin `SpriteEntity` wrapper node handles that.

### Requirements

| # | Requirement |
|---|-------------|
| 1 | Any `.tscn` under `assets/sprites/` becomes a placeable entity with one registration line. |
| 2 | Placement is tile-cell snapped via the existing entity tool — no new tool. |
| 3 | Export-safe in shipped builds (no `DirAccess` enumeration of `res://`). |
| 4 | Pure-decoration sprites have no gameplay script, no collision, no AI. |
| 5 | Existing scripted entities (vorticon, yorp, exit_door, …) are untouched. |

### Out of scope

- Auto-scan / `DirAccess` discovery of `assets/sprites/` — rejected as
  export-unsafe (see `a34e1b6`: "DirAccess can't enumerate `res://` inside an
  exported `.pck`").
- Free-pixel placement, rotation, per-sprite scale — rejected; tile-cell snapped.
- Sprite-thumbnail rendering in the editor canvas (deferred — see §8).
- Per-sprite collision authoring. Sprites are decor-only; anything needing
  gameplay is authored as a scripted entity scene under `src/runtime/entities/`.
- Migration of existing scripted entities onto `register_sprite`.

## 2. Background — why a wrapper is needed

The current entity spawn path (`EntityRegistry.instantiate` →
`LevelRuntime._spawn_entities`) assumes the registered scene's root is a
`Node2D` with either a `setup(type_id, props)` method or settable `type_id` /
`properties` properties. Existing entity scenes satisfy this: their roots are
`CharacterBody2D` / `Sprite2D` with a script extending `Entity`
(`src/runtime/entities/exit_door.tscn`, etc.).

Sprite `.tscn` files do not. Example — `assets/sprites/Exit Sign.tscn`:

```
[node name="ExitSign" type="Node"]
[node name="AnimatedSprite2D" type="AnimatedSprite2D" parent="."]
```

Root is a bare `Node`: not a `Node2D` (no `.position`), no script, no `setup()`,
no `type_id`/`properties`. Feeding it straight into `instantiate()` would fail
the `Node2D` return contract and error on `node.set("type_id", …)`. The
`SpriteEntity` wrapper (§4) supplies the missing `Node2D` transform and entity
contract; the raw sprite scene becomes its child.

## 3. EntityRegistry changes

File: `src/core/entity_registry.gd`.

### 3.1 New category

```gdscript
const CATEGORY_DECOR := "decor"
```

Pure-visual sprites group under `decor`. The palette's category filter
(commit `98b8a95`) surfaces the new group automatically. Existing categories
(`enemy` / `item` / `hazard` / `special`) are unchanged.

### 3.2 New registration entry point

```gdscript
func register_sprite(type_id: String, category: String, label: String,
        scene_path: String, properties: Array = []) -> void
```

Stores an entry identical in shape to `register()`'s, but with `scene_path`
(a `String`) in place of a preloaded `scene` (`PackedScene`). The path is
**not** loaded at registration time — load is deferred to spawn, so a missing
file is skipped gracefully (mirrors `TileSetRegistry.available()`'s
`ResourceLoader.exists` guard pattern). `category` may be `CATEGORY_DECOR` or
any existing category.

The existing `register(...)` signature and the entries it produces are
unchanged.

### 3.3 Instantiate branching

`instantiate(type_id, pos, props)` gains one branch. Pseudocode:

```
entry = _entries[type_id]
if entry has "scene" (PackedScene):          # existing scripted-entity path
    node = entry.scene.instantiate()
elif entry has "scene_path":                  # new sprite path
    if not ResourceLoader.exists(scene_path):
        push_warning(...); return null
    wrapper = SpriteEntity.new()
    child = load(scene_path).instantiate()
    wrapper.add_child(child)
    node = wrapper
else:                                         # category default (unchanged)
    node = _default_node_for_category(...)
# unchanged tail: setup/type_id set, position, add_to_group("entity")
```

The tail of `instantiate` (the `setup()`-vs-`set()` branch, position assignment,
group add) is reused unchanged. `SpriteEntity` implements `setup()`, so it takes
the `setup()` branch.

`get_palette_entries()`, `has()`, `get_entry()`, `clear()` need no changes —
sprite entries are dictionaries of the same shape and surface everywhere
automatically.

## 4. SpriteEntity wrapper

File: `src/runtime/entities/sprite_entity.gd`.

```gdscript
class_name SpriteEntity
extends Node2D
## Wrapper that gives a pure-visual sprite scene (bare Node root) the entity
## contract: a Node2D transform + setup(type_id, props) + "entity" group.

@export var type_id: String = ""
@export var properties: Dictionary = {}

func setup(p_type_id: String, p_props: Dictionary = {}) -> void:
    type_id = p_type_id
    properties = p_props
```

Responsibilities:

- Be the `Node2D` the spawn path positions and `add_child`s.
- Host the instantiated sprite scene as a child (added by the registry).
- Satisfy the `setup(type_id, props)` method check in `instantiate()`.

It deliberately has **no** `_ready` logic, no collision, no AI, no signals. It
is a positioned container. A sprite's animation (e.g. Exit Sign's
`AnimatedSprite2D`) plays on its own via the child scene's existing setup.

## 5. Episode registration

File: `src/episodes/keen1/episode.gd`.

`register_entities()` gains one line per placeable sprite. Initial set
(limited to sprites that exist today and are not already registered as scripted
entities):

```gdscript
registry.register_sprite("keen1.exit_sign", registry.CATEGORY_DECOR, "Exit Sign",
    "res://assets/sprites/Exit Sign.tscn")
```

type_id naming stays namespaced (`keen1.*`) for consistency with existing
entries. `Exit Door` is **not** added here — it is already registered as a
scripted `keen1.exit_door` entity with gameplay behavior. Only pure-decoration
sprites use `register_sprite`.

Adding a new sprite later = drop the `.tscn` in `assets/sprites/` + add one
`register_sprite` line. No other code touches.

### Export safety

`export_filter="all_resources"` (in `export_presets.cfg`, all three platforms)
bundles every resource under `res://` into the PCK, including all
`assets/sprites/*.tscn` and their `.png` dependencies. The `scene_path` string
is resolved via `load()` at spawn, not via `DirAccess`, so this approach avoids
the export pitfall that forced `TileSetRegistry` to be explicit.

## 6. Editor integration (no new tool)

| Editor piece | Change |
|---|---|
| Palette panel | No required change. `_populate_category_filter` (`palette_panel.gd:203`) scans `get_palette_entries()` dynamically, so `decor` appears in the filter dropdown automatically; `_category_label` (`palette_panel.gd:224`) falls back to `cat.capitalize()` → renders "Decor". An optional friendly-label case ("Decoration") may be added but is cosmetic. |
| Entity tool / canvas input | None. Already places any registered type at a cell (`canvas_editor.gd:166-183`). |
| Undo / redo | None. `AddEntityCmd` / `RemoveEntityCmd` operate on `EntityDef` and are type-agnostic. |
| Canvas rendering | None. Entities draw as an orange box + type label (`canvas_editor.gd:73-76`); sprite entities render identically. Sprite-thumbnail preview is deferred (§8). |
| Inspector | None. `EntityDef` is unchanged. |

This is the central simplification: a "sprite placement tool" is just the
existing entity tool once sprites are registered entities.

## 7. Runtime spawning (mostly unchanged)

`LevelRuntime._spawn_entities` (`level_runtime.gd:125-132`) calls
`EntityRegistry.instantiate(def.type, _cell_center(...), def.properties)` and
`add_child(node)`. With §3.3's new branch, sprite entries return a
`SpriteEntity` (a `Node2D`) — position + add_child work as-is. The
`level_completed` signal check (`node.has_signal(...)`) returns false for
`SpriteEntity` and is harmlessly skipped.

### Position semantics

Spawn position is cell center (`_cell_center`, `level_runtime.gd:86-88`). The
`SpriteEntity` sits at cell center; its child sprite renders relative to that.

- A 64×64 sprite (Exit Sign) on a `tile_size=64` level centers on its cell.
- A larger sprite (e.g. a 96×128 Garg) overflows from the anchor cell. Fine-tune
  via the child's local offset inside the `.tscn` — not via the spawn path.

### No collision

`SpriteEntity` adds no `CollisionShape2D` / `Area2D`. Decor sprites never block
the player. If a sprite needs gameplay, it should be authored as a scripted
entity scene (existing pattern), not via `register_sprite`.

## 8. Deferred / future

- **Sprite-thumbnail rendering in the editor canvas.** Currently all entities
  render as a uniform orange box + type label. A future enhancement could draw
  the sprite's first frame as the palette/canvas preview. Out of scope here to
  keep the change minimal and consistent.
- **Property authoring for decor sprites.** `properties` is passed through
  unchanged; no decor sprite uses it today. If a decor sprite later needs e.g.
  a tint or animation-speed override, the `properties` Dictionary and the
  existing inspector path already support it.
- **Migration of scripted entities to `register_sprite`.** Possible once a
  script-attached sprite scene is distinguishable from a bare one; not needed
  now.

## 9. Testing

### Unit (`tests/unit/`)

- `register_sprite(...)` adds an entry retrievable via `get_entry()` and listed
  by `get_palette_entries()` with the given category/label.
- `instantiate()` for a sprite entry returns a `SpriteEntity` whose child is the
  loaded scene's root, positioned at the requested `pos`, in group `"entity"`.
- `instantiate()` for a sprite entry whose `scene_path` does not resolve returns
  `null` and pushes a warning (no crash) — guard via `ResourceLoader.exists`.
- `instantiate()` for an existing scripted entity (e.g. `keen1.yorp`) still
  returns the scene's root `Node2D` with `setup()` called — no regression.
- `CATEGORY_DECOR` entries sort into their own group in `get_palette_entries()`.

### Existing tests

`test_episode.gd` and `test_entity_registry.gd` (if present) must still pass
unchanged; the disk-scan registration test
(`test_register_episodes_populates_catalog_via_disk_scan`) must continue to
register `keen1.vorticon` / `keen1.exit_door` after the new code lands.

### Manual

Editor: entity tool places `keen1.exit_sign` from the palette; it appears as an
orange box + label, undoable. Save → reopen the `.tres`: the `EntityDef` round-
trips. Test ▶: the Exit Sign `AnimatedSprite2D` renders in-level at the placed
cell, playing its animation.

Run `./tests/run_all.sh` after changes — must pass before commit.
