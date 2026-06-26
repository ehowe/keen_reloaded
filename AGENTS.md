# keen_reloaded — Agent Notes

## Project
Godot 4.7 game (Commander Keen remaster). GDScript. Desktop-only.

## Godot binary
`/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot`

## Commands
- **Build macOS app:** `make build` (auto-installs export templates on first run; output in `build/keen_reloaded.app`)
- **Build + launch:** `make run-app`
- **Run tests (headless):** `make test` (or `./tests/run_all.sh`)
- **Import project:** `make import` (or `godot --headless --import --quit`)
- **Open editor:** `make edit` (or `godot -e`)
- See `make help` for all targets.

## Testing
GUT (Godot Unit Test) framework, vendored in `addons/gut/`.
Tests live in `tests/unit/` and extend `GutTest`.
Always run `./tests/run_all.sh` after changes — it must pass before commit.

## Architecture
See `docs/superpowers/specs/2026-06-25-keen-reloaded-design.md`.
Levels = `LevelData` Resource (.tres). Editor writes, runtime reads.
Entities are data-driven via EntityRegistry (per-episode registration).
