# Message Entity — Design Spec

**Date:** 2026-07-16
**Status:** Approved
**Engine:** Godot 4.7 (stable)
**Language:** GDScript

## 1. Overview

A new entity type that displays a message to the player. On contact, gameplay pauses and a full-screen overlay renders the message content centered on the viewport. Message content is authored as a special kind of level (`MapKind.MESSAGE`) — fully data-driven, editable in the integrated level editor.

### Requirements

| # | Requirement |
|---|-------------|
| 1 | Player contact with the entity pauses gameplay and shows an overlay |
| 2 | Message content is a `LevelData` resource with `map_kind = MESSAGE` |
| 3 | Overlay renders the message level's tiles centered on the viewport (no physics, no collision) |
| 4 | Entity has two visual states: **unread** (default) and **read** |
| 5 | `repeat` property (default `false` = one-shot): one-shot entities switch to "read" after first contact; repeatable entities stay "unread" |
| 6 | Overlay dismisses on any key/mouse/gamepad input, unpauses, and returns control |
| 7 | Entity is available in LEVEL maps only (where the player encounters it) |

## 2. Data Model Changes

### 2.1 `MapKind` Enum

Add `MESSAGE` to `LevelData.MapKind`:

```gdscript
enum MapKind { LEVEL, OVERWORLD, MESSAGE }
```

Message levels are authored like any other level (tile layers + entities + metadata) but with `map_kind = MESSAGE`. They carry no player_spawn and no collision — purely visual content. Text is rendered as tiles; decorative tile art forms the message composition.

### 2.2 Episode Level Loading

`Episode.load_levels()` currently filters `res.map_kind == LevelData.MapKind.LEVEL`. Change the filter to also include `MESSAGE` so message levels are registered via `GameManager.register_level()` and resolvable by `get_level_by_id()`:

```gdscript
if res is LevelData and res.map_kind in [LevelData.MapKind.LEVEL, LevelData.MapKind.MESSAGE]:
    levels.append(res)
```

**PackLoader** needs no changes — `_scan_pack()` already loads all non-overworld levels into `_levels`, and `GameManager.start_pack_no_scene_swap()` registers them all via `register_level()`. MESSAGE levels in custom packs are automatically resolvable.

### 2.3 Editor MapKind Picker

`InspectorPanel._ready()` builds an `OptionButton` for map kind. Add the third option:

```gdscript
_map_kind_picker.add_item("Message", LevelData.MapKind.MESSAGE)
```

This lets authors create message levels in the editor. The palette panel automatically filters entities by map kind via `get_palette_entries_for_kind()` — the message entity is registered for LEVEL maps only, so it won't clutter the palette when editing a message level.

## 3. MessageEntity

**File:** `src/runtime/entities/message.gd`
**Extends:** `Entity` (base contact-entity class)

### 3.1 Signals

```gdscript
signal message_requested(target_level_id: String)
```

Emitted on player contact. `LevelRuntime` connects this to `_on_message_requested()`.

### 3.2 Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `target_level_id` | `String` | `""` | Level ID of the MESSAGE-kind `LevelData` to display |
| `repeat` | `bool` | `false` | `false` = one-shot (switches to read state, blocks re-trigger). `true` = re-readable (stays unread) |

**Runtime state:**

| Var | Type | Description |
|-----|------|-------------|
| `_read` | `bool` | Whether this entity has been consumed. Starts `false`. Set `true` on first contact. |

### 3.3 Behavior

**`_handle_player(player)`:**
1. If `_read == true` and `repeat == false`: return (already consumed, no re-trigger).
2. Set `_read = true`.
3. Call `_update_visual()`.
4. Emit `message_requested(target_level_id)`.

**`_update_visual():**
Manages two child sprite states by name, mirroring the `LevelEntrance._apply_done_visual()` pattern:
- If `_read == true`: show child named "Read", hide child named "Unread".
- If `_read == false`: show child named "Unread", hide child named "Read".

**Fallback visual (no scene sprites):**
If the scene provides no "Visual"/"Read"/"Unread" children, build a `ColorRect` — yellow when unread, gray when read. This matches the base `Entity._build_contact()` fallback pattern.

### 3.4 Registration

Registered in `src/episodes/keen1/episode.gd`:

```gdscript
var message := preload("res://src/runtime/entities/message.tscn")
registry.register("keen1.message", registry.CATEGORY_SPECIAL, "Message Sign",
    [
        {name = "target_level_id", default = "", type = "level_id"},
        {name = "repeat", default = false, type = "bool"},
    ],
    message)
```

`map_kinds` defaults to `[LevelData.MapKind.LEVEL]` — entity is placeable in LEVEL maps only.

## 4. MessageOverlay + LevelRuntime Integration

### 4.1 MessageOverlay

**File:** `src/ui/message_overlay.gd`
**Extends:** `Control` (full-screen)

Mirrors `CompletionOverlay` exactly:

```gdscript
class_name MessageOverlay
extends Control

signal dismissed

func _unhandled_input(event: InputEvent) -> void:
    var key: bool = event is InputEventKey and event.pressed and not event.echo
    var click: bool = event is InputEventMouseButton and event.pressed
    if key or click:
        dismissed.emit()
        get_viewport().set_input_as_handled()
```

Runs under pause (`process_mode = ALWAYS`) so it receives input while the tree is frozen.

### 4.2 LevelRuntime Wiring

In `_spawn_entities()`, connect the signal (alongside existing `level_completed`, `enter_requested`, `teleport_requested` connections):

```gdscript
elif node is Message:
    (node as Message).message_requested.connect(_on_message_requested)
```

### 4.3 `_on_message_requested(target_level_id)`

1. Resolve the level: `var msg_level := GameManager.get_level_by_id(target_level_id)`.
2. If null: `push_warning(...)`, return (no overlay, no pause — graceful degradation).
3. Create a `CanvasLayer` (layer = 10, `process_mode = PROCESS_MODE_ALWAYS`), add to scene.
4. Instantiate `MessageOverlay`, add to canvas layer.
5. Build a centered `Node2D` containing 3 `TileMapLayer`s from the message level's tile arrays (geometry + foreground + background). Centering: `node2d.position = viewport_size / 2 - level_pixel_size / 2`.
6. Add the centered Node2D as a child of the overlay (or the canvas layer).
7. `get_tree().paused = true`.
8. Connect `overlay.dismissed` to `_on_message_dismissed`.

**Tile rendering** extracts the tile-building logic from `_add_tile_layer()` into a reusable helper that accepts a parent node parameter (currently it hardcodes `add_child(tml)` which adds to `self`/LevelRuntime). The overlay calls this helper with the centered Node2D as parent. No collision shapes, no bounds walls, no player, no entity spawning — purely visual tile art from all 3 layers.

### 4.4 `_on_message_dismissed()`

1. `get_tree().paused = false`.
2. `queue_free()` the message overlay canvas layer.

Does NOT change game state — no scene swap, no state machine transition. Player resumes exactly where they were.

## 5. Files Changed / Created

| File | Action | Description |
|------|--------|-------------|
| `src/data/level_data.gd` | **Edit** | Add `MESSAGE` to `MapKind` enum |
| `src/core/episode.gd` | **Edit** | `load_levels()` filter includes `MESSAGE` kind |
| `src/editor/inspector_panel.gd` | **Edit** | Add "Message" to MapKindPicker |
| `src/runtime/entities/message.gd` | **Create** | MessageEntity script |
| `src/runtime/entities/message.tscn` | **Create** | MessageEntity scene (minimal, fallback visual) |
| `src/ui/message_overlay.gd` | **Create** | Overlay Control script |
| `src/ui/message_overlay.tscn` | **Create** | Overlay scene |
| `src/episodes/keen1/episode.gd` | **Edit** | Register `keen1.message` entity type |
| `src/runtime/level_runtime.gd` | **Edit** | Wire `message_requested` signal, add `_on_message_requested` + `_on_message_dismissed` |
| `tests/unit/test_message_entity.gd` | **Create** | Entity unit tests |
| `tests/unit/test_message_overlay.gd` | **Create** | Overlay dismiss unit tests |
| `tests/unit/test_map_kind.gd` | **Edit** | Add MESSAGE kind assertion |

## 6. Testing

### 6.1 `test_message_entity.gd`

| Test | Verifies |
|------|----------|
| `test_contact_emits_signal` | Contact triggers `message_requested` with correct `target_level_id` |
| `test_one_shot_blocks_reread` | Second contact does nothing when `repeat=false` |
| `test_repeat_allows_reread` | Second contact emits again when `repeat=true` |
| `test_sprite_state_unread_default` | "Unread" visible, "Read" hidden initially |
| `test_sprite_state_swaps_to_read` | After contact, "Read" visible, "Unread" hidden (one-shot) |
| `test_repeat_stays_unread` | After contact with `repeat=true`, stays "Unread" |

### 6.2 `test_message_overlay.gd`

| Test | Verifies |
|------|----------|
| `test_dismiss_on_key` | Key press emits `dismissed` |
| `test_dismiss_on_mouse` | Mouse click emits `dismissed` |

### 6.3 `test_map_kind.gd` (extend existing)

| Test | Verifies |
|------|----------|
| `test_message_kind_exists` | `MapKind.MESSAGE` is a valid enum value |

### 6.4 Runtime Integration

Add to `test_level_runtime.gd` or `test_runtime_integration.gd`:

| Test | Verifies |
|------|----------|
| `test_message_overlay_builds_and_dismisses` | Spawn Message entity, simulate contact, verify overlay appears + pause set + dismiss clears it |

All tests run via `./tests/run_all.sh` (GUT headless). Must pass before commit.

## 7. Design Decisions

1. **Approach A (entity signals up)** chosen over self-contained entity (B) or GameManager-managed (C). Matches the established pattern: ExitDoor emits `level_completed`, LevelEntrance emits `enter_requested`, Teleporter emits `teleport_requested`. MessageEntity emits `message_requested`. LevelRuntime is the single orchestration hub.

2. **Tiles-only overlay** (no entity spawning from message levels). Keeps MVP simple. Text-as-tiles and decorative tile art cover the use case. Entity spawning can be added later if needed.

3. **`repeat` default `false`** (one-shot). Most messages are story/hint content meant to be seen once. The entity visually communicates its state — unread entities look "active," read entities look "consumed."

4. **Sprite states by child name** ("Read" / "Unread"). Consistent with EntityVariant's name-matching approach and LevelEntrance's done-overlay pattern. Artists add Sprite2D children with these names; the entity manages visibility at runtime.

5. **No game state change on dismiss.** Unlike level completion or teleport, messages are display-only. No scene swap, no state machine transition, no save. Player resumes exactly where they were.
