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
item 8 resolved as intentional (see below). Tier 3 remains open. Each remaining
item is small and covered by existing tests unless noted.

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

- [ ] **`garg._hit_wall()` reimplements `enemy._pressing_into_wall()`.**
  `src/runtime/entities/garg.gd:74` re-derives `dir * wall_normal.x < 0.0`,
  which already exists as the static `enemy.gd:173`. Have garg call the base
  static.

- [ ] **Identical `undo` loop in two tile commands.**
  `paint_cells_cmd.gd:26` and `flood_fill_cmd.gd:40` both do
  `for cell in _prev: set_tile(layer, cell.x, cell.y, int(_prev[cell]))`.
  Minor; could share a base `_restore_cells(level, prev)` helper.

- [ ] **`setup()` contract is inconsistent across entities.**
  `message.gd:25` reads props manually (bypasses the generic apply in
  `Entity.setup`), `spike.gd:8` calls `super` + `EntityVariant.apply`,
  `ship.gd:25` ignores props, `level_entrance.gd:41` reads specific props.
  Standardize one `setup` contract (e.g. always `super.setup` first, then
  entity-specific reads).

- [ ] **`GameManager.ammo` dual source of truth.**
  `player.gd:260,282` write `GameManager.ammo = ammo`; `level_runtime.gd:178`
  reads it back. `Player.ammo` and `GameManager.ammo` can drift. Pick a single
  owner.

- [ ] **Proximity entities still parallel-reimplement `setup` / `type_id`.**
  Tier 1 unified their proximity *plumbing* under `ProximityInteractable`, but
  `Ship`/`Teleporter`/`LevelEntrance` still each carry their own `setup` +
  `type_id`, parallel to `Entity`'s (`entity.gd:15,22`). A shared
  `InteractableEntity` base above `ProximityInteractable` could unify the
  setup/type_id contract too. Lowest priority — only worth it if more
  overworld interactables are planned.
