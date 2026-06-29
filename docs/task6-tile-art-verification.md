# Task 6 — Tile-Art Import Verification Guide

Manual walkthrough for validating Plan 4's tile-art import pipeline end-to-end.
Covers authoring a sample tile sheet, configuring a Godot TileSet resource,
assigning it via the in-game editor, and confirming the Test ▶ round-trip.

## What you're building

Plan 4 added a "tile-art import pipeline": the ability to assign a real TileSet
(with actual art) to a level, replacing the procedural colored squares.
Everything is wired up except the actual art. Task 6 is you creating a sample
tile sheet, turning it into a Godot TileSet resource, assigning it to a level
via the inspector dropdown, and confirming the editor and the Test ▶ runtime
both render the art correctly and consistently.

The goal is to prove the full round-trip works before moving on to
entities/enemies/etc. in later plans.

---

## Step 1 — Create a tile sheet PNG

You need a single PNG image containing a grid of tiles (like a sprite sheet,
but for tiles).

**Layout rules (these matter — the code assumes them):**

- **Uniform cell size.** Every tile cell is the same square size (e.g. 16×16 or
  32×32 px). Pick one and stick to it.
- **Row-major ordering.** Tiles are numbered left-to-right, top-to-bottom. The
  top-left cell is **tile id 1**, the one to its right is **id 2**, and so on.
  Numbering wraps to the next row. A 4-column sheet: id 1 = (0,0), id 2 =
  (1,0), id 3 = (2,0), id 4 = (3,0), id 5 = (0,1).
- **No padding between tiles** (easiest path). If you want margins or spacing,
  set them manually in the TileSet editor (Step 2).
- **No animation frames.** Each id maps to exactly one cell. A static sheet.

For a first test, keep it simple: a 4×2 or 8×2 grid (8–16 tiles). Include a few
distinct tiles you can tell apart — e.g. a solid block, a decorative plant, a
background sky tile — so you can verify different ids render and layering works.

**Where to put it:** save the PNG into `res://assets/tilesets/`. Name it
something obvious like `test_tiles.png`.

You can make this PNG in any image editor (Aseprite, Photoshop, GIMP, Krita, or
a quick procedural generator). Export as PNG.

---

## Step 2 — Turn the PNG into a TileSet resource

Open the Godot editor on the project (`make edit`, or run the Godot binary with
`-e`).

1. In the FileSystem dock, right-click `res://assets/tilesets/` ▸ **New ▸
   Resource**.
2. Search for and select **TileSet**. Save it immediately as `test_tiles.tres`
   in that same folder (the `.tres` extension is what the picker looks for).
3. Select the new `test_tiles.tres` in the FileSystem. Its properties appear in
   the Inspector.
4. In the TileSet resource, find the **Tile Set Sources** section. Click **Add
   Element** and choose **Atlas**. This creates an Atlas Source (the thing that
   holds your texture + tile grid). The source id number does not matter — the
   code resolves it by position.
5. Set the source's **Texture** to your `test_tiles.png` (drag it in, or pick
   it).
6. Set **Texture Region Size** to your cell size (e.g. `16, 16`).
7. If your PNG has margins (a border) or separation (gaps between tiles), set
   **Margins** and **Separation** accordingly. If you made a clean no-padding
   sheet, leave these at `0, 0`.
8. Now create the actual tiles: in Godot 4.7's TileSet editor (the bottom-panel
   that appears when you select a TileSet, or via the "Setup" tab), select the
   region of the texture that contains tiles to auto-populate the grid. Make
   sure every cell you want selectable has a tile created in it. The number of
   created tiles = the highest id you can select in the palette.

**Save** the `.tres`.

**Register it so the picker can see it.** The editor's TileSet dropdown can no
longer auto-scan a folder (directory listing doesn't work over the packed
`res://` in an exported build). Instead it reads the `TileSetRegistry` autoload
(`src/core/tileset_registry.gd`). Open that file and add a line in
`_register_defaults()`:

```gdscript
register("res://assets/tilesets/test_tiles.tres", "Test Tiles")
```

The label is what shows in the dropdown. Entries whose file is missing are
skipped gracefully, so this stays safe on a fresh checkout.

---

## Step 3 — (Important) Author collision on geometry tiles only

This is the part most likely to surprise you. In the procedural fallback, the
code built **two** TileSets — a solid one (with collision) for the geometry
layer, and a decor one (no collision) for foreground/background. But when you
assign a real TileSet, **all three layers share that single TileSet**, and its
collision applies to every layer.

What that means in practice: if you put collision on a tile, that tile will be
solid **everywhere** you paint it — including the foreground and background
layers. A plant tile with collision painted in the background becomes an
invisible wall.

So the convention to follow for now: **only put collision on tiles you intend
to use in the geometry layer.** Decorative tiles (used in fg/bg) should have no
collision authored.

To author collision:

1. In the TileSet, add a **Physics Layer** (TileSet property ▸ Physics Layers ▸
   add one).
2. Select the tile(s) that should be solid in the atlas.
3. In the tile's physics settings, add a collision polygon (usually a full-rect
   square for a block, or a custom polygon).

Leave decor tiles without any collision polygon.

---

## Step 4 — Assign the TileSet via the editor

Open your level editor (the in-game editor scene — run the project or open the
editor scene). On the right side, the **Inspector panel** has a **TileSet**
section with a **File** dropdown (an OptionButton).

1. Click the dropdown. You should see "None (procedural)" plus your
   `test_tiles.tres` listed (it scans `res://assets/tilesets/*.tres`, sorted
   alphabetically).
2. Select your `.tres`.

**What you should immediately see:**

- The **Palette** (left panel) rebuilds: instead of numbered color buttons, you
  see thumbnail icons of your tiles. If any are blank, that tile had no texture
  region or the icon resolved null (shouldn't happen if Step 2 was correct).
- The **Canvas** re-renders any already-placed tiles using your art. Note: the
  canvas tints art by layer color (geometry/foreground/background each get a
  color tint so you can tell layers apart). The art looks slightly color-shifted
  in the editor — intentional and expected.
- The dropdown stays on your selected file (if it snaps back to "None",
  something went wrong with the load — check Godot's Output dock for a "TileSet
  load failed" warning).

---

## Step 5 — Paint tiles and run Test ▶

1. Select a tile in the palette.
2. Paint some tiles across all three layers (geometry, foreground, background)
   in the canvas. Put a solid (collision) tile in geometry, decor tiles in
   fg/bg.
3. Set the player spawn if needed.
4. Hit **Test ▶**.

**In the runtime, verify:**

- **Alignment:** tiles appear at the exact cell positions you painted. No
  offset, no gaps, no doubled tiles.
- **True color:** unlike the editor canvas, runtime art is NOT tinted — it
  renders in the PNG's true colors.
- **Layering:** geometry renders beneath foreground beneath background (or
  whatever the TileMapLayer order is) — art shouldn't clip weirdly.
- **Collision:** the player walks on / collides with solid tiles and passes
  freely through decor. **This is the key invisible-wall check** — if the player
  stops where there's no visible block, a decor tile has collision it shouldn't
  (Step 3 issue).
- **Thumbnails match:** the palette icon for tile id N looks like the runtime
  appearance of that tile.

---

## Step 6 — Verify the procedural fallback still works

1. Back in the editor, set the inspector TileSet dropdown back to **"None
   (procedural)"**.
2. The palette should revert to the 8 colored text buttons.
3. The canvas should revert to colored rectangles.
4. Test ▶ should run with the old procedural colors and collision.

This confirms the null/real-art branch logic didn't regress.

---

## Step 7 — Round-trip persistence

1. With your `.tres` assigned, save the level (the level is a `.tres` LevelData
   resource).
2. Close and reopen the project/editor.
3. The inspector dropdown should still show your `.tres` selected, and the
   palette/canvas should render your art.

This confirms `tileset_ref` serializes correctly.

---

## Step 8 — Esc returns cleanly

After Test ▶, pressing Esc should return you to the editor with the same level
and the same `tileset_ref` intact.

---

## What to report back

Note what you observed, especially:

- Did the dropdown populate with your `.tres`?
- Did palette thumbnails render correctly?
- Did editor canvas + runtime render the art at the same positions (alignment)?
- **Did you hit any invisible walls?** (the collision-sharing check)
- Did the procedural fallback revert cleanly?
- Any errors/warnings in Godot's Output dock?

Most likely failure points: collision on decor tiles (Step 3 convention), or a
tile count mismatch (palette shows ids beyond what you actually painted).

---

## Reference: key files and seams

- `src/data/level_data.gd` — `tileset_ref: TileSet = null` is the seam (null =
  procedural; non-null = real art).
- `src/core/tile_atlas.gd` — row-major id→atlas-cell math, shared by runtime +
  editor so they never disagree.
- `src/runtime/level_runtime.gd` — `build()` branches on `tileset_ref`; real-art
  path shares one TileSet across all 3 layers (collision applies to all).
- `src/editor/canvas_editor.gd` — `_layer_pass` renders real art, tinted by
  layer.
- `src/editor/palette_panel.gd` — rebuilds tile grid with thumbnails when
  `tileset_ref` changes (crash-safe: never rebuilds during a tile click).
- `src/editor/inspector_panel.gd` — the **File** dropdown that scans
  `res://assets/tilesets/*.tres` and assigns `level.tileset_ref`.
