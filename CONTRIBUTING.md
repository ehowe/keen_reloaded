# Contributing to keen_reloaded

All contributions are welcome — this is a vibe-coded, community-friendly project.
Whether you want to fix a bug, implement a missing enemy, author a level, improve
the art or audio, write tests, or just report something broken, jump in.

Open an issue or pull request to get started.

## Before contributing

- **Run `make test` before submitting changes** — the GUT suite should pass. See
  the [README](README.md) for build and test commands.
- **Check known gaps and ideas** in [`docs/future-work.md`](docs/future-work.md)
  and the Project Status section of the [README](README.md).
- **Levels are authored with the integrated level editor.** The
  [design spec](docs/superpowers/specs/2026-06-25-keen-reloaded-design.md)
  explains the architecture and data model.
- **New episodes, enemies, and items are self-contained modules** — each episode
  registers its own entities, so no core engine changes are needed to add
  content.

## Asset note

Keep in mind this is a non-commercial fan project: the *Commander Keen* IP and
the derived sprite/tile art belong to **id Software** (see
[`LICENSE`](LICENSE)). Original code contributions are licensed under the MIT
License; generated audio/HUD icons are CC0.

## Contributor License Agreement

None. By contributing you agree your original work is licensed under the same
terms as the rest of the project (MIT for code, CC0 for generated assets), and
that you have the right to contribute it.
