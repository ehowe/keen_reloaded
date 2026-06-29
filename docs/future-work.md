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
