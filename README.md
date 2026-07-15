```
    __ __                   ____       __                __         __
   / //_/__  ___  ____     / __ \___  / /___  ____ _____/ /__  ____/ /
  / ,< / _ \/ _ \/ __ \   / /_/ / _ \/ / __ \/ __ `/ __  / _ \/ __  / 
 / /| /  __/  __/ / / /  / _, _/  __/ / /_/ / /_/ / /_/ /  __/ /_/ /  
/_/ |_\___/\___/_/ /_/  /_/ |_|\___/_/\____/\__,_/\__,_/\___/\__,_/   
                                                                      
```

# keen_reloaded

A modern, open remake of the entire **Commander Keen** series — all six
episodes plus *Keen Dreams* — built in [Godot 4.7](https://godotengine.org) on
an episodic, data-driven architecture where each episode is its own module that
registers its own content without touching the core engine. Development begins
with *Commander Keen 1: Marooned on Mars* and expands outward, with
player-authored level packs supported alongside the bundled episodes.

> **Disclaimer:** This is a non-commercial fan project. *Commander Keen* and all
> related characters are property of **id Software**. This project is not
> affiliated with, endorsed by, or associated with id Software. See
> [Credits](#credits).

> **Vibe coded:** This project is built primarily through AI-assisted "vibe
> coding" — iterating with LLMs rather than hand-writing every line. The result
> is exploratory and fast-moving. **All contributions are welcome**, whether
> that's code, levels, art, audio, bug reports, or ideas. See
> [Contributing](#contributing).

---

## Goals

1. **Complete remake of the full series** — all six episodes and *Keen Dreams*:
   - *Invasion of the Vorticons* — Keen 1: Marooned on Mars, Keen 2: The Earth
     Explodes, Keen 3: Keen Must Die!
   - *Goodbye, Galaxy!* — Keen 4: Secret of the Oracle, Keen 5: The Armageddon
     Machine, Keen 6: Aliens Ate My Babysitter!
   - *Keen Dreams* (the standalone spinoff)
   
   Each gets the run / jump / **pogo** / shoot platforming, its overworld, and
   its full enemy & item roster. Development is underway on Keen 1 and expands
   episode by episode.
2. **Episodic, modular architecture** — each episode is a self-contained module
   that registers its own entities. Adding an episode = adding a folder, not
   editing the engine.
3. **Integrated level editor** (the original MVP) — ships inside the same
   executable, dev-gated, so bundled levels are authored with the same tool
   players could later use.
4. **Data-driven levels & entities** — levels are portable `LevelData` resources
   (`.tres`), and entities are registered at runtime, so the engine never
   hardcodes content.
5. **Drop-in level packs** — bundled levels ship with the game; players can drop
   their own packs into a local folder, with a format designed to extend to an
   online catalog later.
6. **Desktop-first** (Windows / macOS / Linux) with keyboard + gamepad support.

Full design rationale lives in
[`docs/superpowers/specs/2026-06-25-keen-reloaded-design.md`](docs/superpowers/specs/2026-06-25-keen-reloaded-design.md).

---

## Project Status

The project is under active development. Here is what works and what is planned.

### Completed

- **Core data model** — `LevelData`, `EntityDef`, and `LevelPack` resources with
  `.tres` serialization, plus a binary `.res` export pipeline that preserves
  tile-array data.
- **Level editor** — 3-panel UI (palette / canvas / inspector) with paint,
  erase, flood-fill, entity placement, move-selection, undo/redo, level-metadata
  editing, `level_id` rename, player-spawn placement, and live **Test ▶**.
- **Game runtime** — `LevelRuntime` builds a playable scene from a `LevelData`,
  with camera bounds, collision, and real (and procedural fallback) tilesets.
- **Player** — run, jump (with coyote-time, jump-buffer, and jump-cut feel
  tuning), **pogo stick**, **raygun shoot** (ammo-limited), damage, and a death
  launch animation.
- **Overworld** — top-down 4-directional exploration, level entrances, the
  Mars ship, cross-map teleporters (with animated transit), and "level cleared"
  tracking.
- **Keen 1 entity roster** — vorticon, yorp (with AI), butler robot, clapper,
  spike hazard; collectibles (lollipop, soda, pizza, book, teddy bear), raygun
  ammo, exit door, exit sign, level entrances, ship, and teleporters.
- **Data-driven entity system** — `EntityRegistry` autoload with per-episode
  registration; the editor palette and runtime spawner read from one catalog.
- **Level packs** — `PackLoader` scans bundled (`res://`) and drop-in
  (`user://levelpacks/`) packs, dedupes by `level_id`, supports `.zip` import,
  and a pack-select menu.
- **Audio** — `AudioManager` autoload with menu/level/overworld music and 12 SFX
  (jump, pogo, shoot, hurt, die, pickup, complete, menu move/select, …).
- **HUD & UI** — score / health / ammo icon HUD, completion overlays, main menu
  with New Game / Continue flow, and a pause menu (Esc).
- **Save system** — `SaveSystem` autoload with 6 named slots, atomic saves with
  `.bak` fallback, auto-save on overworld transitions, and pack save support.
- **Input** — keyboard + gamepad bindings (d-pad, stick, face buttons).
- **Tests** — ~50 GUT test files covering data model, editor commands, runtime,
  entity AI, packs, save system, and UI smoke tests.
- **Cross-platform builds** — `make build-all` produces macOS, Windows, and
  Linux binaries from one project.

### Not Yet Done

- **Full Keen 1 level set** — only level 1 and the overworld are currently
  authored; the original game has ~16 levels.
- **Complete Keen 1 enemy roster** — e.g. the **Garg** has sprite art but is not
  yet implemented as an entity.
- **Remaining episodes (Keen 2–6 + Keen Dreams)** — the architecture supports
  them, but only the Keen 1 episode is currently implemented. The rest of the
  series is the project's core roadmap.
- **Tile palette search/filter** — deferred until per-tile metadata exists
  (names/tags). Tracked in [`docs/future-work.md`](docs/future-work.md).
- **Final audio** — current music and SFX are programmatically generated CC0
  placeholders meant to be replaced with proper Keen-style tracks.

### Out of Scope (for now)

- **Online marketplace / server backend** — local packs only today, but the
  pack format is designed so an online catalog can be added later without rework.
- **Web or mobile builds** — desktop only.
- **C# / GDExtension** — GDScript only.

---

## Future Goals

- Finish Keen 1: author the complete level set (Border Village, …, ending) and
  the full enemy roster (Garg, behavior pass on all enemies).
- Build out the rest of the series — Keen 2 (The Earth Explodes), Keen 3 (Keen
  Must Die!), Keen 4–6 (Goodbye, Galaxy!), and Keen Dreams — as new episode
  modules.
- Replace placeholder audio with composed Keen-style music and SFX.
- Richer backgrounds/parallax and visual polish.
- Story / intro / ending cutscenes.
- Online level-pack catalog when the local format has stabilized.

---

## Getting Started

Requires [Godot 4.7](https://godotengine.org/download) and GNU Make.

```bash
make templates   # one-time: install export templates (~1.3 GB)
make run         # run the project from source
make edit        # open the Godot editor
make test        # run the GUT test suite (headless)
make build       # export a standalone app for the current OS
make build-all   # cross-build macOS + Windows + Linux into build/
make run-app     # build for current host, then launch it
```

See `make help` for the full list of targets.

### Controls

| Action   | Keyboard | Gamepad         |
|----------|----------|-----------------|
| Move     | WASD     | D-pad / Stick   |
| Jump     | Space    | A / Cross       |
| Pogo     | P        | B / Circle      |
| Shoot    | X        | X / Square      |
| Interact | Up       | Y / Triangle    |
| Pause    | Esc      | Start (menu)    |

The integrated level editor is reachable from the main menu when developer mode
is enabled.

---

## Architecture

Levels are a custom `LevelData` resource (tile data + entity list + metadata),
serialized to native `.tres` files. At runtime, `LevelRuntime` feeds a
`LevelData` into a `TileMapLayer` for rendering and collision. The editor
manipulates the single `LevelData` model and rendering stays in sync.

```
LevelData (.tres)  ← source of truth
   ├─ written/read by → LevelEditor (dev-gated)
   └─ fed to          → LevelRuntime → TileMapLayer + entities + player

Packs
   res://levels/        bundled (ships with game)
   user://levelpacks/   drop-in (local folder)   → PackLoader (dedupes by id)
```

Entities are data-driven: each episode registers its types into an
`EntityRegistry` autoload, and both the editor palette and the runtime spawner
read from the same catalog — so the core engine never needs modification to
support new content.

See the [design spec](docs/superpowers/specs/2026-06-25-keen-reloaded-design.md)
for the full breakdown.

## Contributing

All contributions are welcome — this is a vibe-coded, community-friendly project.
See [`CONTRIBUTING.md`](CONTRIBUTING.md) for how to get started.

---



### Commander Keen

*Commander Keen* was created in 1990 by **id Software** — designed by **Tom
Hall**, programmed by **John Carmack** and **John Romero**, with art by **Adrian
Carmack** — and published by **Apogee Software** (now Apogee Entertainment) and
Softdisk. *Marooned on Mars* (Invasion of the Vorticons, Episode 1) is the
inspiration and reference for this remake. All Keen characters, names, and
concepts remain the property of id Software; this project claims no ownership of
that intellectual property.

### Engine & Tools

- **[Godot Engine](https://godotengine.org)** (MIT license) — the game engine.
- **[GUT](https://github.com/bitwes/Gut)** (MIT license) — Godot Unit Test
  framework, vendored in `addons/gut/`.
- **[Aseprite](https://www.aseprite.org)** — sprite authoring format used for
  the game's art.

### Assets

- **Sprites** (`assets/sprites/`) — sourced from the original *Commander Keen*
  games, then edited: scaled up from the original 16px art to 64px and, in many
  cases, retouched or redrawn to be more usable in a modern game engine (cleaner
  shapes, separated animation frames, etc.). Authoring files are Aseprite
  (`.aseprite`/`.asesprite`).
- **Tilesets** (`assets/tilesets/`) — likewise sourced from the original games,
  upscaled from 16px to 64px and modified for modern engine use.
- **Audio** (`assets/audio/`) — all music and SFX are programmatically
  generated placeholders (`tools/gen_audio.gd`), released to the public domain
  (**CC0**). See `assets/audio/LICENSE.txt`. They exist only so the audio system
  has a real playback path and are meant to be replaced.
- **HUD icons** — generated CC0 art (`tools/gen_hud_icons.gd`).

The original *Commander Keen* art remains the property of id Software; the
edits here are made for this non-commercial fan project only.

---

## License

See [`LICENSE`](LICENSE) for the full terms. In short:

- **Source code** — licensed under the **MIT License**. Use, modify, and
  distribute it for any purpose (including commercial), just keep the copyright
  notice.
- **Commander Keen IP & derived sprite/tile art** — belong to **id Software**.
  This is a non-commercial fan project; the art is derived from the original
  games and is **not** licensed for redistribution. Bring your own assets.
- **Audio & HUD icons** — generated original works, dedicated to the public
  domain (CC0).
- **Godot / GUT** — retain their own MIT licenses.
