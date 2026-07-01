# Editor: Pick Tile From Canvas (Eyedropper)

**Date:** 2026-06-30
**Status:** Approved (design)
**Scope:** Level editor only. No runtime/data-model changes.

## Problem

When a level already contains tiles, there is no way to grab one of those placed
tiles to paint more of it. The only path today is to scan the left `PalettePanel`
thumbnail grid, visually match the art, and click the right tile-id button. With a
large atlas this is tedious, and with no TileSet assigned (procedural colors) it is
guesswork.

## Goal

Let the user click a tile that is already placed on the canvas grid and have it
become the active brush, with its texture shown clearly so it can be reused
immediately.

## Decisions (confirmed with user)

1. **Goal type:** eyedropper — pick from canvas → becomes active brush.
2. **Trigger:** both a dedicated **Pick** tool button **and** an **Alt+click**
   shortcut (works in any tool).
3. **Feedback:** highlight the picked tile in the palette **+** auto-scroll the
   palette to it **+** add a "Current tile" preview box at the top of the Tiles
   section.
4. **Source layer:** the **active layer** only (matches where paint lands). Empty
   cells are a no-op.
5. **After a successful pick:** auto-switch to the **Paint** tool.
6. **Undo:** picking is UI selection state, not a level mutation → **not** recorded
   on the `UndoStack`.

## Architecture

No new classes or resources. The change threads through three existing scripts
following their current patterns (`edit_at_cell`, `set_selected_tile_id`,
`_broadcast`).

### Data flow

```
CanvasEditor._gui_input (MOUSE_BUTTON_LEFT pressed)
   ├─ mb.alt_pressed == true           (any tool)
   └─ active_tool == "pick"            (Pick tool)
              │
              ▼
   LevelEditor.pick_tile_at(cell)          ← NEW
      ├─ bounds check  (cell in level)
      ├─ id = level.get_tile(active_layer, cell.x, cell.y)
      ├─ if id <= 0:
      │      _set_status("Nothing to pick (empty cell)")
      │      return                         ← brush unchanged
      ├─ set_selected_tile_id(id)           ← existing; broadcasts
      └─ set_tool("paint")                  ← auto-switch, broadcasts
              │
              ▼  _broadcast() refreshes panels
   PalettePanel.refresh
      ├─ set_pressed_no_signal on matching tile button   (existing)
      ├─ _tile_scroll.ensure_control_visible(button)      ← NEW
      └─ update Current-tile preview                      ← NEW
```

The Pick-tool path and the Alt+click path converge on the same
`LevelEditor.pick_tile_at(cell)` method, so behavior is identical.

## Components

### `src/editor/level_editor.gd`

- `TOOLS` dict (lines 11–17): add `"pick": "Pick"`.
- New method `pick_tile_at(cell: Vector2i) -> void`, placed near `edit_at_cell`
  (after line 136). Behavior as in the data flow above. Bounds check mirrors
  `edit_at_cell` (line 121). Reads `active_layer` via `level.get_tile(...)`.
  Calls `set_selected_tile_id(id)` then `set_tool("paint")`; each broadcasts, so
  the status line ends with `Tool: paint | Tile: <id>`.
- No change to `_cursor_status` (already reports `Tile: %d`).

### `src/editor/canvas_editor.gd`

- `_gui_input`, `MOUSE_BUTTON_LEFT` pressed branch (lines 103–108): when
  `mb.pressed` and `mb.alt_pressed`, call `editor.pick_tile_at(cell)` instead of
  `_on_left_down(cell)`. (Pick tool is handled inside `_on_left_down`.)
- `_on_left_down` match (lines 122–138): add a `"pick":` arm calling
  `editor.pick_tile_at(cell)`.
- Right-click and mouse-motion drag logic unchanged. Paint/erase stroke drag is
  not affected because after a pick the tool is `paint` but the mouse button has
  already been released before the next press (pick happens on press, not drag).
  Note: Alt+click does not start a stroke, so no spurious paint stroke begins.

### `src/editor/palette_panel.gd`

- Tool button loop (line 49): add `"pick"` to the list so a Pick toggle button
  appears after "select".
- Store a reference to the tile `ScrollContainer` (`_tile_scroll`) instead of the
  current local, so `ensure_control_visible` can be called.
- New **Current tile preview** at the top of the Tiles section (built once in
  `build()`, right after the "Tiles" label at line 24 and before the scroll grid):
  an `HBoxContainer` containing:
  - a `ColorRect _preview_bg` (64×64) — background swatch for the procedural case;
  - a `TextureRect _preview_icon` (64×64, `expand_mode = true`,
    `stretch_mode = STRETCH_KEEP_ASPECT_CENTERED`) overlaid on the swatch;
  - a `Label _preview_label` showing `Tile %d`.
- `refresh(e)` additions:
  - After the pressed-state loop, if `e.selected_tile_id` is in
    `[1, _tile_buttons.size()]`, call
    `_tile_scroll.ensure_control_visible(_tile_buttons[id - 1])`.
  - Update preview: `_preview_bg.color = EditorColors.tile_color(id)`;
    `_preview_icon.texture = TileAtlas.tile_icon(ts, id)` when a TileSet is set
    (else `null`); `_preview_label.text = "Tile %d" % id`.

### `src/editor/editor_colors.gd`
No change. `tile_color(id)` already supports any id.

## Edge cases & behavior

| Case | Behavior |
|------|----------|
| Empty cell (id 0) | No-op; status `Nothing to pick (empty cell)`; brush/tool unchanged. |
| Out-of-bounds cell | Ignored (bounds check). |
| No TileSet (procedural) | Pick still works on ids; preview shows colored swatch + id. |
| Pick tool used repeatedly | Each click re-picks and stays ready; auto-switches to Paint only on a successful pick. |
| Alt+click in Select/Entity/Fill tool | Picks the active-layer tile and switches to Paint (consistent, grab-and-go). |
| Alt+drag | Only the press triggers pick; motion does not start a stroke. |
| Active layer empty at cell, but another layer has a tile | Still a no-op (active-layer-only by decision 4). |

## Testing

GUT, run via `./tests/run_all.sh` (must pass before commit). The unit-testable
seam is `LevelEditor.pick_tile_at`. New test file under `tests/unit/`:

- `pick_tile_at` on a non-empty active-layer cell sets `selected_tile_id` to that
  id and `active_tool` becomes `"paint"`.
- `pick_tile_at` on an empty cell leaves `selected_tile_id` and `active_tool`
  unchanged.
- Picks read from `active_layer`: tile present only on a different layer is a
  no-op.
- After switching `active_layer`, a pick reads the new layer.
- Out-of-bounds cell is a no-op.

Canvas `_gui_input` routing (Alt detection, tool arm) is verified by a manual
editor run (launch editor, place tiles, Pick tool + Alt+click, confirm preview,
scroll, and that painting uses the picked tile).

## Out of scope

- Hover tooltip / live cursor preview of the tile under the pointer.
- "Used tiles" derived palette.
- Cross-layer ("topmost non-empty") picking.
- Undo of a pick (intentionally not recorded).
