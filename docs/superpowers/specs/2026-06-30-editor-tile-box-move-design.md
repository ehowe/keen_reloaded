# Editor: Box-Select + Move Tiles

**Date:** 2026-06-30
**Status:** Approved (design)
**Scope:** Level editor only. No runtime/data-model changes.

## Problem

When a built section of a level lands in the wrong place, the only way to shift it
today is to repaint tile-by-tile on each layer. With multi-layer sections dozens of
tiles wide, this is slow and error-prone. A marquee-select + drag-move (like Tiled
or Photoshop's move tool) lets the user relocate large chunks in one gesture.

## Goal

Let the user drag a rectangle to select a tile region, then drag that region to a new
location. All three layers move together in one undoable step. Empty cells in the
selection are skipped (only filled tiles relocate).

## Decisions (confirmed with user)

1. **Interaction:** marquee box-select (drag) + drag-move inside the selection.
2. **Tool home:** folded into the existing **Select** tool. A plain click keeps the
   current entity-select behavior; a drag draws/moves a tile marquee.
3. **Layer scope:** all three layers (geometry, foreground, background) move
   together. A built section relocates as one unit.
4. **Bounds:** the move is **blocked entirely** if any filled tile would land
   outside the level. No clipping, no partial move.
5. **Destination:** filled source tiles overwrite destination cells. **Empty**
   source cells are skipped — gaps do not punch holes in the destination.
6. **After move:** the selection **persists and follows** the moved tiles, so the
   block can be grabbed and moved again. Esc or a click on an empty cell clears it.
7. **Undo:** one `MoveTilesCmd` per move, recorded on the `UndoStack`. Marquee
   selection itself is UI state, not recorded.

## Architecture

No new top-level classes beyond one command. The change threads through the
existing three editor scripts (`level_editor.gd`, `canvas_editor.gd`,
`palette_panel.gd`) plus a new `move_tiles_cmd.gd`, all following current patterns
(`EditorCommand` subclasses, `_broadcast`, `_gui_input` routing).

### Data flow

```
CanvasEditor._gui_input (Select tool, MOUSE_BUTTON_LEFT pressed)
   ├─ tile_selection active AND cell inside selection
   │        → _move_dragging = true; anchor = cell           (move mode)
   └─ otherwise
            → _marquee_dragging = true; _marquee_anchor = cell
              (entity-select DEFERRED until mouse-up if no drag occurs)
                 │
   on motion (button held)
   ├─ _move_dragging      → _move_delta = cell - anchor; redraw ghost outline
   └─ _marquee_dragging   → tile_selection = rect from corners (anchor, cell)
                 │
   on left-up
   ├─ _move_dragging
   │      ├─ delta == 0           → no-op
   │      ├─ bounds-check fails   → revert delta; status "Move blocked: out of bounds"
   │      └─ ok                   → LevelEditor.move_selection(delta)  ← NEW
   │                                   pushes MoveTilesCmd (all layers)
   │                                   tile_selection.position += delta  (follow)
   ├─ _marquee_dragging, box non-empty → keep selection
   └─ no drag happened (click)          → Select tool: entity select (existing)
```

## Components

### `src/editor/move_tiles_cmd.gd` (NEW)

`class_name MoveTilesCmd extends EditorCommand`. One undo step relocates filled
tiles across all three layers.

- `_init()` takes no args; the command is populated by a builder method.
- Fields:
  - `_delta: Vector2i` — the move offset.
  - `_layers: Dictionary` — `String(layer) → Dictionary[Vector2i → int]` of the
    filled source cells (id > 0) being moved, captured at build time.
  - `_dst_prev: Dictionary` — `String(layer) → Dictionary[Vector2i → int]` of the
    destination cells' previous ids, captured in `apply()` for undo.
- `add_layer(layer: String, cells: Dictionary)` — called by `LevelEditor` while
  building; stores the filled-cell map for that layer.
- `set_delta(d: Vector2i)` — sets `_delta`.
- `apply(level)`:
  1. For each layer, for each src cell `c`: compute `d := c + _delta`; record
     `_dst_prev[layer][d] = level.get_tile(layer, d.x, d.y)` (first time only).
  2. Clear every src cell (`set_tile(layer, c.x, c.y, 0)`).
  3. Write each src id to its dest: `set_tile(layer, d.x, d.y, src_id)`.
  - Order matters: save dst_prev and clear src **before** writing dest so that
    overlapping src/dest regions are handled correctly (src ids were already
    captured in `_layers` at build time).
- `undo(level)`:
  1. Restore dest cells: `set_tile(layer, d.x, d.y, _dst_prev[layer][d])`.
  2. Restore src cells: `set_tile(layer, c.x, c.y, _layers[layer][c])`.
  - When a cell is both src and dest (overlap), step 1 restores its pre-move
    value and step 2 restores the original src id — they agree on overlapping
    cells because `_dst_prev[overlap]` captured the pre-move src id.
- `describe()`: `"MoveTiles(Δ%s, %d layers)" % [str(_delta), _layers.size()]`.

### `src/editor/level_editor.gd`

- New state:
  - `var tile_selection: Rect2i = Rect2i()` — active marquee in tile coords;
    zero-area (`size == Vector2i.ZERO`) means "no selection".
- New method `move_selection(delta: Vector2i) -> bool`, placed near `edit_at_cell`
  (after line 141). Returns `true` if the move was committed.
  1. If `tile_selection` has zero area → return `false`.
  2. If `delta == Vector2i.ZERO` → return `false` (no-op).
  3. **Bounds check:** for each layer in
     `[LAYER_GEOMETRY, LAYER_FOREGROUND, LAYER_BACKGROUND]`, for each cell in
     `tile_selection` whose `get_tile` id > 0, test `c + delta` is in
     `[0, width) × [0, height)`. If any fails → `_set_status("Move blocked: out
     of bounds")`, return `false`.
  4. Build `MoveTilesCmd`: for each layer, collect
     `Dictionary[Vector2i → int]` of filled cells in `tile_selection`; call
     `cmd.add_layer(...)`; `cmd.set_delta(delta)`.
  5. `undo_stack.push_applied(level, cmd)` (apply runs inside).
  6. `tile_selection.position += delta` (selection follows the moved tiles).
  7. `_broadcast()`; return `true`.
- New method `clear_tile_selection() -> void`: `tile_selection = Rect2i()`;
  `_broadcast()`.
- `set_tool("select")` path unchanged; the tool already exists.
- No change to `_cursor_status` body beyond optionally noting selection (see
  Canvas rendering for the visible cue).

### `src/editor/canvas_editor.gd`

New drag state:
```
var _marquee_anchor: Vector2i = Vector2i(-1, -1)
var _marquee_dragging: bool = false
var _move_dragging: bool = false
var _move_delta: Vector2i = Vector2i.ZERO
```

`_gui_input`, `MOUSE_BUTTON_LEFT` pressed branch — when `active_tool == "select"`:
- If `tile_selection` is active (non-zero area) **and** `cell` is inside it:
  `_move_dragging = true`; `_marquee_anchor = cell`; `_move_delta = Vector2i.ZERO`.
- Else: **clear** `editor.tile_selection` immediately (so a new marquee starts
  clean and a subsequent gesture correctly detects "inside"); set
  `_marquee_dragging = true`; `_marquee_anchor = cell`. **Do not** call
  `select_entity` yet (deferred to mouse-up).

`InputEventMouseMotion` branch — add Select-tool handling when button held:
- If `_move_dragging`: `_move_delta = cell - _marquee_anchor`; `queue_redraw()`.
- Elif `_marquee_dragging` and `cell != _marquee_anchor`:
  `editor.tile_selection = _rect_from_corners(_marquee_anchor, cell)`; `queue_redraw()`.
  (Godot's `Rect2i(pos, size)` constructor treats arg 2 as size, not a corner, so
  a helper is needed: see below.)
- Existing paint/erase stroke motion is unaffected (only runs for those tools).

`_on_left_up()` additions (Select tool):
- If `_move_dragging`:
  - `editor.move_selection(_move_delta)`.
  - On failure (returns false), the selection stays; `_move_delta` is discarded.
  - Reset `_move_dragging = false`; `_move_delta = Vector2i.ZERO`.
- Elif `_marquee_dragging`:
  - If the box never moved (`cell == _marquee_anchor`, i.e. it was a click):
    `editor.clear_tile_selection()` then `editor.select_entity(editor.entity_at_cell(cell))`
    (preserves click-selects-entity).
  - Else: the selection set during motion is kept.
  - Reset `_marquee_dragging = false`; `_marquee_anchor = Vector2i(-1, -1)`.
- Non-select tools: unchanged (`end_stroke()`).

`_draw()` additions (after the entity/spawn drawing, near the bottom):
- If `editor.tile_selection` has non-zero area: draw a solid yellow outline
  `Rect2(pos.x, pos.y, size.x*cs, size.y*cs)` with `Color(1, 1, 0.4, 1.0)`,
  line width 2.0, around the selection.
- If `_move_dragging`: draw a second outline at the destination
  (`tile_selection.position + _move_delta`) in a paler yellow
  `Color(1, 1, 0.4, 0.5)` as a ghost cue. Outline only — no texture ghost.

`_unhandled_input` (or `_gui_input` key handling): when `active_tool == "select"`
and `KEY_ESCAPE` pressed → `editor.clear_tile_selection()`.

New helper `static func _rect_from_corners(a: Vector2i, b: Vector2i) -> Rect2i`:
returns the inclusive tile rect spanning both corners —
`Rect2i(Vector2i(mini(a.x,b.x), mini(a.y,b.y)), Vector2i(absi(b.x-a.x)+1, absi(b.y-a.y)+1))`.
Godot has no two-corners `Rect2i` constructor, so the min corner and positive
size (cell count) are computed explicitly.

### `src/editor/palette_panel.gd`

No change. The Select tool button already exists in the tool loop.

### `src/editor/editor_colors.gd`

No change.

## Edge cases & behavior

| Case | Behavior |
|------|----------|
| Click (no drag) on empty cell | Clears selection, then entity-select (no-op if no entity). |
| Click (no drag) on entity | Clears selection, then selects the entity (unchanged Select behavior). |
| Drag in empty area | Defines a new marquee box; all-layer tiles captured lazily on move. |
| Drag starting inside selection | Move; source cleared, dest overwritten (filled cells only). |
| Move delta == 0 | No-op; no command pushed; selection unchanged. |
| Move lands partly out of bounds | Blocked entirely; status set; selection + tiles unchanged. |
| Selection active, Esc pressed | Selection cleared. |
| Selection active, click outside it | Clears selection (does not start a new move). |
| Overlapping src/dest (small delta) | Handled: dst_prev saved before clearing src; undo restores exactly. |
| Empty cell inside selection | Not moved; destination under it preserved (no hole punched). |
| Switching tools / layers while selection active | Selection persists across tool/layer switches (it is editor-wide state). |
| Undo after move | Restores all three layers to pre-move state; selection follows back. |

## Testing

GUT, run via `./tests/run_all.sh` (must pass before commit).

New test file `tests/unit/test_move_tiles_cmd.gd`:
- Move filled tiles on a single layer; `apply` writes dest + clears src; `undo`
  restores exact prior state.
- Empty src cells in the rect are not moved and do not erase dest.
- Multi-layer move: geometry + foreground + background all relocate; undo
  restores all three.
- Overlap case (delta of 1): moving right, dest of one tile equals src of
  another; apply + undo leaves the level byte-identical to before.
- `describe()` returns a non-empty string containing the delta.

New test file `tests/unit/test_move_selection.gd` (or added to an existing
editor test):
- `move_selection` with a zero-area selection is a no-op (returns false).
- `move_selection` with delta == 0 is a no-op.
- Bounds check: a move that would push any filled tile OOB returns false,
  leaves the level and selection unchanged, and sets the status.
- Bounds check passes when all dest cells are in-bounds; command is pushed and
  applies; `tile_selection.position` advances by delta.
- After a successful move, `undo_stack.undo()` reverts all layers and the next
  `move_selection` reads the restored tiles.

Canvas routing (click-vs-drag disambiguation, ghost outline, Esc clearing) is
verified by a manual editor run (launch editor, draw tiles on all layers, drag
a box, drag-move it, confirm undo and the out-of-bounds block).

## Out of scope

- Texture/ghost preview of the moved tiles during drag (outline-only ghost).
- Copy/duplicate via a modifier (move only).
- Arrow-key nudge (drag-move only).
- Moving entities that sit inside the selection (entities stay put; tiles only).
- Resize handles on the selection box (fixed box; re-drag to reselect).
- Cross-tool persistence of a "clipboard" region.
