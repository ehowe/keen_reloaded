# keen_reloaded — Agent Notes

## Project
Godot 4.7 game (Commander Keen remaster). GDScript. Desktop-only.

## Godot binary
`/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot`

## Commands
- **Build for current host:** `make build` (auto-installs export templates on first run; macOS→`build/keen_reloaded.app`, Windows→`.exe`, Linux→binary)
- **Cross-build all desktops:** `make build-all` (macOS + Windows + Linux into `build/`)
- **Build + launch:** `make run-app`
- **Install export templates:** `make templates` (~1.3 GB, one-time; powers both `build` and `build-all`)
- **Run tests (headless):** `make test` (or `./tests/run_all.sh`)
- **Import project:** `make import` (or `godot --headless --import --quit`)
- **Open editor:** `make edit` (or `godot -e`)
- **See version status:** `make version`
- **Preview a release:** `make release-dry` (no side effects)
- **Cut a release:** `make release` (bumps VERSION, patches project.godot, generates CHANGELOG.md, commits + tags — requires clean tree)
- See `make help` for all targets.

## Versioning
CalVer `YYYY.MM.DD` (same-day re-release → `.2`, `.3`).
Source of truth: `VERSION` file. `make release` patches it + `project.godot` + generates `CHANGELOG.md` from conventional commits.
Title screen reads `application/config/version` at runtime (shows `"dev"` if unreleased).

## Testing
GUT (Godot Unit Test) framework, vendored in `addons/gut/`.
Tests live in `tests/unit/` and extend `GutTest`.
Always run `./tests/run_all.sh` after changes — it must pass before commit.

## Architecture
See `docs/superpowers/specs/2026-06-25-keen-reloaded-design.md`.
Levels = `LevelData` Resource (.tres). Editor writes, runtime reads.
Entities are data-driven via EntityRegistry (per-episode registration).
