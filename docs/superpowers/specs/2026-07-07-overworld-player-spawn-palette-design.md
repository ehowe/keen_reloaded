# Overworld Player Spawn — Palette Visibility Fix

**Date:** 2026-07-07
**Status:** Approved
**Scope:** Bug fix (editor palette)

## Problem

When editing an overworld map, the entity palette shows only **Level Entrance**.
**Player Spawn** is missing, so there is no click-to-place way to change where the
player starts the episode on the overworld.

The inspector's "Player Spawn" X/Y spinboxes still work on overworld (no
map_kind gate), but the natural canvas placement flow used on levels is broken.

## Root Cause

`EntityRegistry.register()` defaults an empty `map_kinds` argument to
`[MapKind.LEVEL]` only (`src/core/entity_registry.gd:18-19`):

```gdscript
if map_kinds.is_empty():
    map_kinds = [LevelData.MapKind.LEVEL]
```

`keen1.player_spawn` is registered without `map_kinds`
(`src/episodes/keen1/episode.gd:35`):

```gdscript
registry.register("keen1.player_spawn", registry.CATEGORY_SPECIAL, "Player Spawn")
```

It therefore silently becomes level-only, and the palette's
`get_palette_entries_for_kind(OVERWORLD)` filters it out. Only
`keen1.level_entrance` (explicitly registered `overworld_only`) survives the
overworld filter.

## Fix

Register `keen1.player_spawn` for **both** map kinds in `episode.gd`:

```gdscript
var all_kinds: Array[int] = [LevelData.MapKind.LEVEL, LevelData.MapKind.OVERWORLD]
registry.register("keen1.player_spawn", registry.CATEGORY_SPECIAL, "Player Spawn", [], null, all_kinds)
```

No other code change required:

- **Runtime**: `start_episode_no_scene_swap` sets `pending_player_spawn = (-1,-1)`,
  which makes `LevelRuntime._ready()` fall back to `level.player_spawn`.
  `overworld.tres` already has `player_spawn = Vector2i(0, 45)`. Editing it already
  moves the initial episode spawn; this fix only makes that edit reachable from the
  palette.
- **Inspector**: the "Player Spawn" X/Y spinboxes already render for all map kinds.

## Why Not Change the Default

The `map_kinds` default of `[LEVEL]` is correct for gameplay entities — enemies,
items, and hazards must stay off the overworld. The existing test
`test_palette_filters_by_map_kind` asserts `keen1.vorticon` is hidden on overworld.
Broadening the default would regress that intended filter. Only `player_spawn` is
wrongly caught, so the fix is surgical.

## Testing

Extend `tests/unit/test_editor_map_kind.gd::test_palette_filters_by_map_kind` to
assert `keen1.player_spawn` appears in **both** the LEVEL and OVERWORLD palettes.

## Out of Scope

- `keen1.exit_sign` (decor) is also level-only by the same default and may warrant
  the same both-kinds treatment, but is not part of this change.
- No new "overworld start" concept: the single `player_spawn` field already serves
  both level entry and episode start, and the runtime already handles both paths.
