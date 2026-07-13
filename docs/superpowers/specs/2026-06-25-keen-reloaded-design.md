# keen_reloaded — Design Spec

**Date:** 2026-06-25
**Status:** Draft
**Engine:** Godot 4.7 (stable)
**Language:** GDScript
**Platforms:** Desktop (Windows / macOS / Linux)

## 1. Overview

**keen_reloaded** is a remastered, rewritten version of Commander Keen, built in Godot 4. It begins with a faithful-in-spirit remake of **Commander Keen 1: Marooned on Mars**, but the architecture is episodic and modular so additional episodes (Keen 4–6, etc.) and entirely new content can be added without touching the core engine.

The project's first deliverable (MVP) is a **level editor** — an integrated, developer-gated tool used to author the bundled levels. The editor ships inside the same executable as the game, behind a developer-mode flag, and can be unlocked for players later.

### Core Requirements

| # | Requirement |
|---|-------------|
| 1 | Episodic, modular architecture — new episodes add content, not engine code |
| 2 | Integrated level editor is the MVP (dev-gated, one executable) |
| 3 | Bundled levels (ship with game) **and** local drop-in level-packs |
| 4 | Desktop-only targets: Windows, macOS, Linux (keyboard + gamepad) |
| 5 | Modern pixel-art visual style (expanded palette, pixel aesthetic, richer than EGA) |
| 6 | Extensible entity system — episodes register their own enemies/items |
| 7 | Level-pack format must be server-ready (designed so an online catalog can be added later without rework) |

### Out of Scope (for this design)

- Online marketplace / server backend (local files only for now; designed to extend)
- Web or mobile builds
- Full HD hand-drawn art direction
- C# / GDExtension components (GDScript only)

## 2. Architecture — Approach C (Hybrid)

The level/editor/pack system uses a **hybrid data-model + Godot-rendering** approach.

- **Levels** are a custom `LevelData` GDScript `Resource` (tile data + entity list + metadata), serialized to native `.tres` files.
- **Runtime** feeds a `LevelData` into a `TileMapLayer` for rendering and collision, reusing Godot's fast, battle-tested tile system.
- **Editor** manipulates the single `LevelData` model; rendering is automatic.
- **Packs** are folders of `.tres` level files plus a `manifest.json`, loaded from `res://` (bundled) or `user://levelpacks/` (drop-in).

This combines the portability and shareability of a pure-data format (Approach B) with the rendering performance and collision handling of Godot's native tiles (Approach A), without either extreme's downsides.

### Why not the alternatives

- **Approach A (TileMap-native):** Levels become Godot-internal `.tscn` scenes. Harder to diff, version, and share as clean portable data; bundling drop-in packs gets awkward due to scene dependency chains.
- **Approach B (Pure data-driven):** Reinvents tile rendering and collision — more code, performance risk at scale, duplicates work Godot already does well.

## 3. Component & Data-Flow Overview

```
                    ┌─────────────────────────────────────────┐
   DATA MODEL        │  LevelData (Resource, .tres)            │
   (source of truth) │  LevelPack (manifest.json + .tres files)│
                    └─────────────────────────────────────────┘
                          ↑ reads / writes ↓
        ┌─────────────────┴───────────────────┐
        │                                     │
   ┌────┴────────────┐              ┌─────────┴─────────┐
   │  LevelEditor    │              │  LevelRuntime     │
   │  (dev-gated)    │              │  builds scene     │
   │  edits LevelData│              │  from LevelData   │
   └─────────────────┘              └─────────┬─────────┘
        │                                     │
        └─────────────────┬───────────────────┘
                          ↓
               ┌──────────────────────┐
   GODOT LAYER │  TileMapLayer        │  render + collision
               │  CharacterBody2D     │  player physics
               │  Node2D entities     │  enemies / items
               └──────────────────────┘

   LEVEL-PACK LOADING
   res://levels/        bundled (shipped with game)
   user://levelpacks/   drop-in (local folder)
           │
           └──→ PackLoader (scans + catalogs both, dedupes by level_id)
```

## 4. Data Schemas

### 4.1 `LevelData` (Resource → `.tres`)

| Field | Type | Description |
|-------|------|-------------|
| `metadata.level_id` | `String` | Unique ID, e.g. `"keen1_01"` |
| `metadata.name` | `String` | Display name, e.g. `"Border Village"` |
| `metadata.episode` | `String` | Episode ID, e.g. `"keen1"` |
| `metadata.order` | `int` | Sequence within episode |
| `metadata.music` | `Resource` | Audio stream |
| `metadata.bg_ref` | `Resource` | Background texture/config |
| `dimensions.width` | `int` | Level width in tiles |
| `dimensions.height` | `int` | Level height in tiles |
| `dimensions.tile_size` | `int` | Pixel size per tile (e.g. 16, scaled up at render) |
| `tile_layers.geometry` | `PackedInt32Array` | Solid tiles → collision |
| `tile_layers.foreground` | `PackedInt32Array` | Decorative, no collision |
| `tile_layers.background` | `PackedInt32Array` | Parallax background layer |
| `entities` | `Array[EntityDef]` | Spawned entities |
| `player_spawn` | `Vector2i` | Tile coords of player start |
| `exit` | `{type, position, target_level_id}` | Level exit |
| `tileset_ref` | `TileSet` | Shared tileset resource |

**`EntityDef`** (per-entity entry in `entities[]`):

| Field | Type | Description |
|-------|------|-------------|
| `type` | `String` | Entity type ID, resolved via `EntityRegistry` (e.g. `"vorticon"`) |
| `x`, `y` | `int` | Tile coordinates |
| `properties` | `Dictionary` | Per-entity overrides (e.g. patrol range, score value) |

### 4.2 `LevelPack` (folder + manifest)

```
user://levelpacks/<pack_name>/
├── manifest.json
│   ├── pack_id        : String
│   ├── name           : String
│   ├── author         : String
│   ├── version        : String
│   ├── episode        : String (optional grouping)
│   └── levels[]       : [{ level_id, file: "01.tres", name, order }]
├── 01.tres, 02.tres ...   (LevelData files)
└── tilesets/              (shared TileSet overrides, optional)
```

Bundled packs live at `res://assets/levels/<episode>/` with the same manifest structure.

### 4.3 Load Paths

`PackLoader` (autoload singleton) scans both locations at boot:

- `res://levels/` — bundled, read-only, ships with the build
- `user://levelpacks/` — user-writable drop-in folder

Results are merged and deduplicated by `level_id` (drop-in overrides bundled on conflict), then exposed as a catalog to the level-select menu.

## 5. Level Editor (MVP)

The editor is an **integrated, dev-gated mode** in the same executable. Accessed from the main menu when developer mode is enabled. One codebase, one build.

### 5.1 UI Layout (3-panel)

```
┌──────────────────────────────────────────────────────────────┐
│ Toolbar: [keen_reloaded — Editor] File … New │ Save │ Test ▶ │
├────────────┬───────────────────────────────┬─────────────────┤
│  PALETTE   │                               │   INSPECTOR     │
│            │                               │                 │
│ ▸ TILES    │                               │ Selected: Tile  │
│  [grid of  │         TILE CANVAS           │ Properties:     │
│   tiles]   │      (scroll / zoom)          │  solid, damage  │
│            │                               │                 │
│ ▸ ENTITIES │   place tiles & entities      │ Level Settings: │
│  Player    │                               │  name, music,   │
│  Vorticon  │                               │  bg             │
│  Candy …   │                               │                 │
│            │                               │ Tools:          │
│ ▸ LAYERS   │                               │  Paint/Erase/   │
│  Geometry  │                               │  Fill           │
│  Foreground│                               │                 │
│  Background│                               │                 │
├────────────┴───────────────────────────────┴─────────────────┤
│ Status: Cursor (24,12) · Layer · Tool · Undo history         │
└──────────────────────────────────────────────────────────────┘
```

- **Palette (left):** tile picker, entity spawner list (driven by `EntityRegistry`), layer toggles.
- **Canvas (center):** the editable tile grid; scroll/zoom; paint/erase/fill tools.
- **Inspector (right):** context-sensitive properties for the selected tile/entity; level-level settings (name, music, background).
- **Toolbar:** New / Save / **Test ▶** (drops into the level in-place for instant iteration).
- **Status bar:** cursor coords, active layer, active tool, undo state.

### 5.2 Editor Responsibilities

- Build/modify a `LevelData` resource in memory.
- Paint tiles into `tile_layers` by active layer.
- Place/remove entities (spawned from `EntityRegistry` palette entries).
- Edit level metadata and per-entity properties via the inspector.
- Save to `.tres` (into a pack folder).
- Undo/redo history.
- Test-run: hand the current `LevelData` to `LevelRuntime` and switch to gameplay.

## 6. Game Runtime

### 6.1 Runtime Loop

```
PackLoader → catalog → [menu: pick level]
  → LevelRuntime.build(LevelData)
      → instantiate TileMapLayer from tile_layers
      → load TileSet, configure collisions
      → spawn entities from EntityRegistry (by type ID)
      → place Player at player_spawn
  → gameplay loop (player physics, entity AI, collisions)
  → on reach exit → advance / complete
```

### 6.2 Player

`CharacterBody2D` using Godot's built-in kinematic body — no custom physics engine.

Abilities (Keen's signature moves): run, jump, **pogo stick**, shoot.

### 6.3 Extensible Entity System

Entities are **data-driven**, not hardcoded. Each episode/pack registers its entity types; the core engine never needs modification to support new content.

```
EntityRegistry (autoload singleton)
├── register(type_id, EntityDef)
│      EntityDef = { scene: PackedScene,
│                    category: enemy | item | hazard | special,
│                    properties: [{ name, default, type }] }
├── instantiate(type_id, position, props) → Node2D
└── get_palette_entries() → drives editor entity dropdown
```

**Base class hierarchy:**

```
Entity (Node2D)            ← all entities extend this
├── Enemy (Entity)         ← health, damage, AI hook
├── Collectible (Entity)   ← pickup logic, score
├── Hazard (Entity)        ← damages player on contact
└── Special (Entity)       ← exits, triggers, doors
```

**Per-episode registration:** each episode folder ships an `entity_registry.gd` that registers its types at load. Example: `episodes/keen1/entity_registry.gd` registers `"vorticon"`, `"yorp"`, `"candy"`, etc. A future `episodes/keen4/` registers its own distinct set. The editor's palette and the runtime's spawner both read from the same registry.

## 7. Episode Structure

Episodes are **self-contained modules**. Adding a new episode = creating a new folder under `episodes/` with its content and entity registration. Zero core-engine changes required.

Each episode provides:

- Episode metadata (title, ID, ordering)
- Entity registration (`entity_registry.gd`)
- Entity scenes/scripts (enemies, items)
- Bundled levels (`levels/<episode>/`)
- Shared tilesets and assets

## 8. Project Structure

```
keen_reloaded/
├── project.godot              # Godot project config
├── .gitignore
├── docs/                      # specs, design docs
│   └── superpowers/specs/
├── src/
│   ├── core/                  # autoloads / singletons
│   │   ├── game_manager.gd        # episode + save state
│   │   ├── pack_loader.gd         # scans res:// + user:// packs
│   │   └── entity_registry.gd     # extensible entity catalog
│   ├── data/                  # data model (Resources)
│   │   ├── level_data.gd
│   │   ├── level_pack.gd
│   │   └── entity_def.gd
│   ├── runtime/               # gameplay
│   │   ├── level_runtime.gd       # builds scene from LevelData
│   │   ├── player/                # player.tscn + .gd (CharacterBody2D)
│   │   └── entities/              # base classes (Entity/Enemy/...)
│   ├── editor/                # level editor (MVP)
│   │   ├── level_editor.tscn
│   │   ├── canvas_editor.gd
│   │   ├── palette_panel.gd
│   │   └── inspector_panel.gd
│   ├── ui/                    # menus, HUD, level-select
│   └── episodes/              # per-episode content (modular)
│       └── keen1/
│           ├── episode.gd         # metadata + bootstrap
│           ├── entity_registry.gd # registers keen1 entities
│           └── entities/          # vorticon.tscn, yorp.tscn, candy.tscn ...
├── levels/                    # bundled levels (ships in build)
│   └── keen1/
│       ├── manifest.json
│       └── 01.tres, 02.tres ...
├── assets/                    # shared art/audio
│   ├── tilesets/                  # keen1_tiles.tres (TileSet)
│   ├── sprites/
│   ├── audio/
│   └── backgrounds/
└── tests/
```

## 9. Testing & Verification

| Layer | Approach |
|-------|----------|
| **Unit tests** | [GUT](https://github.com/bitwes/Gut) (Godot Unit Test). Covers: `LevelData` serialization round-trips, `PackLoader` scanning/dedup, `EntityRegistry` register/lookup, `LevelData` build correctness. |
| **Integration tests** | `LevelRuntime` builds a level from a test `LevelData` and spawns all registered entity types without errors. |
| **Manual test loop** | Editor's **Test ▶** button drops directly into the level in-place — fastest iteration for level design. |
| **CI gate** | GUT test scene runs headless: `godot --headless --script res://tests/runtests.gd`. Failing tests block merges. |

## 10. Build Phases (high-level)

Implementation is broken into plans, one per phase. Status as of 2026-07-09:

| Plan | Phase | Status |
|------|-------|--------|
| Plan 1 | **Foundation + data model** — Godot 4.7 init, scaffold, GUT, `LevelData`/`EntityDef`/`LevelPack` resources + serialization | ✅ Done |
| Plan 2 | **Editor MVP** — 3-panel UI, tile painting, entity placement, undo/redo, save/load `.tres`, Test ▶ (stubbed) | ✅ Done |
| Plan 3 | **Runtime core** — `LevelRuntime` build-from-data, procedural no-art `TileSet`+`TileMapLayer`, player (run/jump/**pogo**), base entity classes, `EntityRegistry.instantiate`, Test ▶ live | 🚧 In progress |
| Plan 4 | **Keen 1 content** — real tileset + art pipeline, full entity roster (vorticon, yorp, items, hazards), **shoot** ability, exit/special logic, first level authored via editor | Planned |
| Plan 5 | **Pack loading** — `PackLoader` custom user packs via `.zip` import into `user://levelpacks/`, `pack_select` menu, `GameManager.start_pack` progression (bundled content stays scene-wired) | ✅ Done |
| Plan 6 | **Polish** — audio, background/parallax, HUD, save/progression, gamepad mapping | 🚧 In progress — **6a Audio ✅ done** (music + 12 SFX, `AudioManager` autoload, generated CC0 assets); **6b Feel/Feedback ✅ done** (icon HUD + overworld cleared label, `Player.max_health`, default gamepad bindings, generated CC0 icon assets); **6c Persistence ✅ done** (SaveSystem autoload, 6 named slots, auto-save at overworld transitions, pause menu, Continue/New Game main-menu flow, pack save support) |

**Descopes carried from Plan 3 → Plan 4:** real art/tileset assets, the full Keen 1 entity roster + concrete entity scenes, the `shoot` player ability, and exit/special-entity behavior. Plan 3 ships a fully working runtime with placeholder procedural visuals so the editor's Test ▶ is immediately useful. (See `docs/superpowers/specs/2026-06-26-plan3-runtime-core-design.md`.)
