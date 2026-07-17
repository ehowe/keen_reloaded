# Future Work

Deferred items captured during development so they aren't forgotten. Not
committed to a timeline; promoted into a plan when prioritized.

## Tile palette: search / filter

**Status:** Deferred (post Plan 4).

**Goal:** Let the author find a tile quickly in the palette when a TileSet has
many tiles (e.g. a full ripped sheet → hundreds/thousands of cells).

**Why deferred:** The palette currently has no searchable tile metadata. A
filter needs something to filter *on*, and today's `.tres` TileSets only define
atlas coords — no names, tags, or categories per tile.

**Prerequisite work (do first):**
1. Decide a tile-naming / tagging convention (e.g. per-tile name, category
   groups like "terrain"/"decor"/"hazard", or tags).
2. Author that metadata into the TileSet (TileData custom data layers in Godot,
   or a sidecar manifest keyed by tile id).
3. Expose it via `TileAtlas` (e.g. `tile_label(ts, id)`, `tile_tags(ts, id)`).

**Then the feature itself is small:** a `LineEdit` at the top of the palette
that filters `_tile_buttons` by matching the tile's metadata; hide non-matches.
Re-filter on text change, no rebuild needed (buttons already exist).

**Related bonus improvements (optional, independent):**
- More columns / smaller thumbnails for higher density.
- A "jump to tile id N" text field for direct selection.

**Touched when implemented:** `src/editor/palette_panel.gd`,
`src/core/tile_atlas.gd`, TileSet authoring workflow.

## Code cleanup — review follow-ups

**Status:** Tracked (from the code-review pass on 2026-07-16). Tier 1 landed in
commit `f83f0cd`. Tier 2 was addressed 2026-07-16: items 6, 7, 9, 10 are done;
item 8 resolved as intentional (see below). Tier 3 was addressed 2026-07-16:
items 11, 12, 14, 15 are done; item 13 resolved as intentional (see below). The
full review pass is closed.

### Tier 2 — antipatterns

- [x] **Pure-data score-pickup subclasses (5 files, zero behavior).** DONE.
  `Collectible.score_value` is now `@export`; the 5 scenes (lollipop/pizza/
  soda/book/teddy) point at `collectible.gd` and bake their value. The 5
  subclass scripts were deleted. `test_pickups.gd` still verifies every value +
  contact-award via the registry instantiate path.

- [x] **`TILE := 64` duplicated in two base classes.** DONE. Single source of
  truth is now `Constants.TILE` (`src/core/constants.gd`); `entity.gd` and
  `proximity_interactable.gd` alias it (`const TILE := Constants.TILE`) so the
  ~15 entity subclasses inherit unchanged.

- [ ] **Player duck-typing via `has_method("…")` — RESOLVED AS INTENTIONAL.**
  Investigated: 5 test files rely on `FakePlayer` stubs (extends `Node` /
  `CharacterBody2D`, not `Player`) to avoid real-`Player` `_ready` weight.
  Typing the param as `Player` would break all of them. More importantly, the
  duck-typing is a deliberate lightweight protocol that *decouples* entities
  from the concrete `Player` class — tighter typing would be worse coupling.
  Decision: leave as-is. (Original sites: ~13 `has_method` checks across
  `collectible.gd`, `enemy.gd`, `hazard.gd`, `garg.gd`, `ammo_pickup.gd`,
  `exit_door.gd`, `yorp.gd`, `projectile.gd`, `level_runtime.gd`.)

- [x] **"Find the player" lookup scattered.** DONE. `Player.find(tree) -> Node`
  static (`src/runtime/player/player.gd`) consolidates the null-tree guard +
  group lookup; the 4 external sites (`garg._player_node`, `yorp._choose_walk_
  dir`, `yorp._player_body`, `enemy._die`) route through it. Unit-tested in
  `tests/unit/test_player_find.gd` (RED-first).

- [x] **`"keen1.pogo"` magic string duplicated.** DONE. Single source is now
  `ItemIDs` (`src/core/item_ids.gd`, holds `POGO` + `BLASTER`).
  `player.gd`, `pogo_stick.gd`, and `hud.gd` reference `ItemIDs.POGO`; the
  `BLASTER` const aliases `ItemIDs.BLASTER`. (The `keen4.*` HUD display keys
  are left as literals — they're display-only, not granted/consumed yet.)

### Tier 3 — nits

- [x] **`garg._hit_wall()` reimplements `enemy._pressing_into_wall()`.** DONE.
  `garg.gd:74` now calls the inherited static `_pressing_into_wall(_dir,
  get_wall_normal().x)` instead of re-deriving `dir * wall_normal.x < 0.0`.
  Behavior-identical (same expression the base uses at `enemy.gd:159`).

- [x] **Identical `undo` loop in tile commands.** DONE. A shared
  `EditorCommand.restore_tiles(level, layer, prev)` static
  (`src/editor/editor_command.gd`) writes back a `Vector2i -> int` snapshot.
  `PaintCells`, `FloodFill`, and `MoveTiles` (both its dst-restore and
  src-restore passes) route through it.

- [ ] **`setup()` contract is inconsistent across entities — RESOLVED AS
  INTENTIONAL.** Investigated: the *signatures* are already uniform
  (`setup(type_id, props)` everywhere; `entity_registry.gd:134` calls it
  duck-typed via `has_method`). The *body* differences exist for sound
  reasons: `Message` bypasses `Entity.setup`'s generic `set()` apply loop
  deliberately — it needs `String()`/`bool()` coercion of its props and does
  not use the `properties` dict; `Spike` legitimately layers
  `EntityVariant.apply` on top of the base. Forcing "always call super" would
  route Message's props through the un-coerced generic apply and risk type
  bugs for no gain. Decision: leave as-is.

- [x] **`GameManager.ammo` dual source of truth.** DONE. `Player._set_ammo(v)`
  (`player.gd`) is now the single mutation point: it sets the runtime field,
  writes through to `GameManager.ammo`, and emits `ammo_changed`. `shoot` and
  `add_ammo` both route through it, so the runtime/persistent pair can no
  longer drift. (The persistent->runtime *seed* at `level_runtime.gd:178` is a
  separate direction and stays a direct field write; `_ready`'s `ammo = 0`
  default likewise is not a mutation that needs syncing.)

- [x] **Proximity entities parallel-reimplement `setup` / `type_id`.** DONE.
  `type_id` + a base `setup` (that records the type id) are hoisted into
  `ProximityInteractable`; the three `var type_id` redeclarations are gone.
  `Ship` drops its `setup` override entirely (it only set the id); `Teleporter`
  and `LevelEntrance` now call `super.setup` first, then read their own props.
  Mirrors `Entity.setup`'s contract. The registry's duck-typed
  `node.setup(...)` call is unchanged.
