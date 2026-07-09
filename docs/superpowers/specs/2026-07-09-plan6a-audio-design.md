# Plan 6a — Audio — Design Spec

**Date:** 2026-07-09
**Status:** Implemented (merged to `main`; audible smoke confirmed)
**Parent spec:** `docs/superpowers/specs/2026-06-25-keen-reloaded-design.md` (§6 Game Runtime)
**Engine:** Godot 4.7 (stable), GDScript
**Predecessors:** Plans 1–5 (data model, editor, runtime core, Keen 1 content, pack loading)
**Scope owner:** runtime + core

## 1. Overview

Plan 6 (Polish) was decomposed into three independent sub-plans:

| Sub-plan | Areas | Status |
|---|---|---|
| **6a — Audio** | music + SFX | **this spec** |
| 6b — Feel & Feedback | HUD polish + gamepad mapping | later |
| 6c — Persistence | save / progression (disk) | later |

Background/parallax was considered for 6a but **descoped by decision**: levels already ship static backgrounds via the existing `background_tiles` TileMapLayer (rendered in `LevelRuntime._add_tile_layer`). `LevelData.background_ref` stays unused and out of scope.

Plan 6a delivers **game audio**: looping per-level/overworld/menu music driven by `LevelData.music`, plus twelve SFX covering player, pickup, enemy, completion, and UI events. The audio assets are **generated placeholder WAV files** (synthesized blips/loops), committed under `assets/audio/`, and free to replace later with real Keen-style tracks. The system is built around a new `AudioManager` autoload singleton that owns a music `AudioStreamPlayer` and a polyphonic SFX player, keyed by a name→stream registry loaded by filename convention.

```
Boot
  AudioManager._ready → preload assets/audio/sfx/*.wav into _sfx registry
                      → build _music_player + _sfx_player

main_menu._ready  → AudioManager.play_music(menu_theme)
                   → menu_move / menu_select on UI interaction

LevelRuntime.build(level)
  → if level.music is AudioStream: AudioManager.play_music(level.music)
    else: AudioManager.stop_music()

Gameplay events
  player.shoot() / jump frame / pogo / take_damage / _die
  collectible._handle_player / ammo_pickup._handle_player
  enemy.take_damage / level_runtime._on_level_completed
    → AudioManager.play_sfx("<name>")
```

### Goals

| # | Goal |
|---|------|
| 1 | A global `AudioManager` autoload plays looping music and overlapping SFX that survive scene swaps. |
| 2 | Per-level music is driven by `LevelData.music` (level + overworld); a menu theme plays on `main_menu`. |
| 3 | Twelve SFX cover player, pickup, enemy, completion, and UI events, triggered at their source via direct calls. |
| 4 | Real WAV playback path from day one: CC0/generated placeholder files committed under `assets/audio/`. |
| 5 | The bundled keen1 levels (`overworld.tres`, `level1.tres`) ship with placeholder music assigned. |
| 6 | GUT tests verify registry state, music play/stop, and level-build wiring — headless and deterministic (no audio-output assertion). |

### Out of scope

- **Background / parallax** — descoped by decision (static backgrounds already render).
- **Volume / mute / settings UI** — deferred (no plan currently; YAGNI).
- **Bus layout file / per-bus volume control** — both players sit on the default `Master` bus.
- **Dynamic / adaptive music, crossfades, music layers.**
- **3D positional audio** — game is 2D with a single listener.
- **Real Keen audio** — generated placeholders only; asset swap is a later art pass.
- **HUD polish, gamepad mapping, save/progression** — sub-plans 6b / 6c.

## 2. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Audio entry point | **Autoload `AudioManager` + direct calls** (Approach A) | Simplest, idiomatic Godot; one global source of truth; survives scene swaps. Gameplay calls `play_sfx(name)` at the event source — unambiguous (unlike `ammo_changed`, which fires on both shoot and pickup). Polyphonic player handles overlapping SFX. |
| SFX polyphony | **Round-robin voice pool of 8 `AudioStreamPlayer` nodes** | Rapid jump+pogo+shoot and multiple enemy hits overlap without cutting each other off. **Deviation from original intent:** the spec first proposed Godot's `AudioStreamPlayerPolyphonic`, but that node class does **not** exist in Godot 4.7 stable (verified via `ClassDB`); only `AudioStreamPlaybackPolyphonic` exists. A round-robin pool realizes the same non-cutting polyphony. |
| SFX registry | **Name → preloaded `AudioStream`, keyed by filename** | `assets/audio/sfx/jump.wav` → `play_sfx("jump")`. Convention over config; new SFX = drop a file. No hardcoded list in code. |
| Trigger mechanism | **Direct calls at the source** | `shoot()` is only the success path → unambiguous. Avoids the `ammo_changed` ambiguity that forces new signals under a signal-driven design. No new signals needed. |
| Assets | **Generated placeholder WAVs (CC0/public-domain)** | No audio files exist; can't browse a CC0 library. A one-off generator script writes valid WAV bytes (synthesized blips/loops). Generated = original = free to license; real playback path; replaceable later. |
| Music drive | **`LevelData.music` (existing `Resource` field)** | Field already exists (line 40), unused. Runtime checks `is AudioStream` defensively. No schema change. |
| Buses | **Default `Master` only, two players** | Avoids a bus-layout file and volume UI this plan. YAGNI. |
| Menu music | **`main_menu._ready` plays a preloaded theme** | Each scene sets its own music on entry; completion overlay leaves music running. |

## 3. Architecture

### 3.1 Components & responsibilities

| Component | File | Role |
|---|---|---|
| `AudioManager` (**new** autoload) | `src/core/audio_manager.gd` | Preloads `assets/audio/sfx/*` into a name→stream registry at boot; owns music `AudioStreamPlayer` + a round-robin voice pool of 8 `AudioStreamPlayer` nodes (polyphony). API: `play_sfx`, `play_music`, `stop_music`, `stop_all`, `register_sfx`. Pure playback — no gameplay logic. |
| `LevelRuntime` (exists) | `src/runtime/level_runtime.gd` | In `build()`, after spawn: if `level.music is AudioStream` → `AudioManager.play_music(level.music)` else `stop_music()`. In `_on_level_completed` → `AudioManager.play_sfx("complete")`. |
| `Player` (exists) | `src/runtime/player/player.gd` | Direct `AudioManager.play_sfx(...)` calls at: jump wind-up start, pogo toggle + bounce, `shoot()` success, `take_damage()`, `_die()`. |
| `Enemy` (exists) | `src/runtime/entities/enemy.gd` | In `take_damage()`: `enemy_hit` when still alive, `enemy_die` at the `<= 0` branch. Butler overrides `take_damage` to no-op (no SFX). |
| `Collectible` (exists) | `src/runtime/entities/collectible.gd` | `pickup_score` in `_handle_player` on `add_score`. |
| `AmmoPickup` (exists) | `src/runtime/entities/ammo_pickup.gd` | `pickup_ammo` in `_handle_player` on `add_ammo`. |
| `main_menu` (exists) | `src/ui/main_menu.gd` | `play_music(menu_theme)` on `_ready`; `menu_move`/`menu_select` on UI interaction. |
| `pack_select` (exists) | `src/ui/pack_select.gd` | `menu_move`/`menu_select` on UI interaction. |
| `LevelData` (exists) | `src/data/level_data.gd` | Unchanged — `music: Resource` field reused as-is. |
| `project.godot` | (config) | Add `AudioManager` autoload (last). |

### 3.2 AudioManager API

> **Implemented as** `src/core/audio_manager.gd` (authoritative source; the block
> below mirrors it). **Deviation from original draft:** Godot 4.7 stable has **no
> `AudioStreamPlayerPolyphonic` node** and `AudioStreamPlayer` has **no
> `play_stream()` method** (verified via `ClassDB.class_exists`/`class_has_method`).
> Polyphony is realized with a round-robin voice pool of `MAX_POLYPHONY`
> `AudioStreamPlayer` nodes instead. Behavior (non-cutting, name→stream registry,
> music loop) matches the original intent.

```gdscript
extends Node
## Global audio bus: music + SFX. Owns players that survive scene swaps.
## SFX registry maps name -> preloaded AudioStream (keyed by sfx/ filename).
## Gameplay calls play_sfx(name) directly at the event source.

const SFX_DIR := "res://assets/audio/sfx/"
const MAX_POLYPHONY := 8
const MUSIC_THEME := preload("res://assets/audio/music/menu.wav")

var _sfx: Dictionary = {}                       # name -> AudioStream
var _music_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []    # round-robin polyphony voices
var _sfx_cursor: int = 0


func _ready() -> void:
	_build_players()
	_load_sfx_registry()


## Play a sound by registry name. Unknown names are a no-op + push_warning.
## Uses a round-robin voice pool so overlapping calls each get their own
## player up to MAX_POLYPHONY (non-cutting).
func play_sfx(name: String) -> void:
	var stream: AudioStream = _sfx.get(name, null)
	if stream == null:
		push_warning("AudioManager: unknown sfx '%s'" % name)
		return
	var voice: AudioStreamPlayer = _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % MAX_POLYPHONY
	voice.stream = stream
	voice.play()


## Play a looping music stream. null stops current music (silence).
## WAV loop_mode is forced at runtime (import flags reset on reimport).
func play_music(stream: AudioStream) -> void:
	if stream == null:
		stop_music()
		return
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_music_player.stream = stream
	_music_player.play()


func stop_music() -> void:
	_music_player.stop()


## Stops music. Active short SFX voices (<1s) play out by design.
func stop_all() -> void:
	stop_music()


## Test/extension seam: register a stream at runtime (overrides on conflict).
func register_sfx(name: String, stream: AudioStream) -> void:
	_sfx[name] = stream


func _build_players() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	add_child(_music_player)
	for i in MAX_POLYPHONY:
		var voice := AudioStreamPlayer.new()
		voice.name = "SfxPlayer%d" % i
		add_child(voice)
		_sfx_pool.append(voice)


## Scan SFX_DIR, load every .wav keyed by filename without extension.
func _load_sfx_registry() -> void:
	var dir := DirAccess.open(SFX_DIR)
	if dir == null:
		push_warning("AudioManager: sfx dir not found: %s" % SFX_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.get_extension().to_lower() == "wav":
			var stream: AudioStream = load(SFX_DIR + fname)
			if stream != null:
				_sfx[fname.get_basename()] = stream
		fname = dir.get_next()
	dir.list_dir_end()
```

Notes:
- **Polyphony via round-robin pool:** `play_sfx` advances `_sfx_cursor` mod `MAX_POLYPHONY` (8), so up to 8 SFX overlap without cutting. A 9th simultaneous SFX reuses voice 0 (truncates that voice's tail) — an acceptable polyphony limit for this game's SFX density (voices are <1s, round-robin means a voice is reused only every 8th call).
- **Loop mode set at runtime, not `.import`:** `play_music` forces `AudioStreamWAV.loop_mode = LOOP_FORWARD` on the passed stream. Robust against Godot reimporting the `.import` file and resetting the flag (deviation from §4.2, which originally proposed editing `.import`). SFX do not loop; music does.
- `_load_sfx_registry` runs at autoload `_ready` (before the main scene). `load()` of imported `.wav` resources is cached by Godot, so per-call `play_sfx` does no disk IO.
- `MUSIC_THEME` is preloaded as a `const`; `main_menu` calls `AudioManager.play_music(AudioManager.MUSIC_THEME)`.

### 3.3 Trigger points

| name | File / location | Condition |
|---|---|---|
| `jump` | `player.gd` `_physics_process` | on the frame a grounded jump wind-up starts (`_buffer > 0 and _coyote > 0 and not _pogo and _windup <= 0`) |
| `pogo` | `player.gd` `_physics_process` | on each pogo floor bounce (`if _pogo and on_floor` branch). Toggle press is silent — the bounce is the faithful "boing". |
| `shoot` | `player.gd` `shoot()` | after the `ammo <= 0` early return, before projectile spawn |
| `hurt` | `player.gd` `take_damage()` | after `health_changed.emit` |
| `die` | `player.gd` `_die()` | at the top (after the `_dead` guard) |
| `pickup_score` | `collectible.gd` `_handle_player` | on `add_score` |
| `pickup_ammo` | `ammo_pickup.gd` `_handle_player` | on `add_ammo` |
| `enemy_hit` | `enemy.gd` `take_damage()` | when `health > 0` after damage applied |
| `enemy_die` | `enemy.gd` `take_damage()` | at the `health <= 0` branch, before award + free |
| `complete` | `level_runtime.gd` `_on_level_completed()` | when the overlay is shown |
| `menu_move` | `main_menu.gd`, `pack_select.gd` | on focus change / item highlight |
| `menu_select` | `main_menu.gd`, `pack_select.gd` | on button `pressed` (alongside existing handlers) |

**Music:**
| location | call |
|---|---|
| `level_runtime.gd` `build()` | `if level.music is AudioStream: play_music(level.music) else stop_music()` |
| `main_menu.gd` `_ready()` | `play_music(MUSIC_THEME)` |

**Butler:** overrides `take_damage` to a no-op (armored) — plays neither `enemy_hit` nor `enemy_die`. Correct by inheritance: the override never reaches the base-class call sites.

### 3.4 Why direct calls, not signals

The player already emits `score_changed`, `health_changed`, `ammo_changed`, `died`. These are ambiguous for audio:
- `ammo_changed` fires on both **shoot** (`ammo -= 1`) and **pickup** (`add_ammo`) — indistinguishable without extra state.
- `score_changed` could imply a pickup, but shoot/kill also award score via `add_score`.

A signal-driven design therefore still needs new dedicated signals (`shot_fired`, `picked_up_ammo`, `jump_fired`, …) plus entity-side signals and their connect/disconnect lifecycle. Direct calls at the unambiguous source (e.g. `shoot()` runs only on a successful shot) avoid all of this with zero new signals and one autoload reference — the common Godot pattern.

## 4. Assets (generated placeholders)

### 4.1 Layout

```
assets/audio/
├── LICENSE.txt                 # CC0 / public-domain, generated, free to replace
├── sfx/                        # 12 short .wav, 44.1kHz mono 16-bit
│   ├── jump.wav
│   ├── pogo.wav
│   ├── shoot.wav
│   ├── hurt.wav
│   ├── die.wav
│   ├── pickup_score.wav
│   ├── pickup_ammo.wav
│   ├── enemy_hit.wav
│   ├── enemy_die.wav
│   ├── complete.wav
│   ├── menu_move.wav
│   └── menu_select.wav
├── music/                      # 3 looping .wav
│   ├── menu.wav                # calm low drone (~8s loop)
│   ├── overworld.wav           # mid-tempo loop (~16s)
│   └── level.wav               # upbeat loop (~16s)
└── (generated by tools/gen_audio.gd — committed for regeneration only)
```

### 4.2 Import / loop settings

- SFX `.wav`: default import — **no loop**.
- Music `.wav`: **loop is forced at runtime** by `AudioManager.play_music()` (`AudioStreamWAV.loop_mode = LOOP_FORWARD`). *(Original draft proposed editing `loop = true` in each music `.import` file, but `.import` flags reset on reimport — setting loop_mode in code is more robust. See §3.2.)*
- Generator output must be valid RIFF/WAV so Godot's importer accepts them.

### 4.3 SFX character (so they're identifiable)

| sound | character |
|---|---|
| jump | short rising blip |
| pogo | short rising blip, higher pitch than jump |
| shoot | quick descending zap |
| hurt | low harsh buzz |
| die | descending sad tones |
| pickup_score | bright two-note up (reward) |
| pickup_ammo | metallic ping |
| enemy_hit | short mid click |
| enemy_die | descending squelch |
| complete | short triumphant arpeggio |
| menu_move | tiny tick |
| menu_select | soft confirm blip |

### 4.4 Generator

A one-off GDScript tool `tools/gen_audio.gd`, run via
`godot --headless --script res://tools/gen_audio.gd`, writes the WAV files via
direct byte synthesis (square/sine envelopes). GDScript is chosen over Python so
the generator needs no external runtime — only the documented Godot binary
(`make` targets already depend on it). It is committed for reproducibility but
is **not** a runtime dependency — the `.wav` files are the committed artifact.
Run once (re-run only to regenerate).

### 4.5 Bundled-level music assignment

After assets are imported:
- `assets/levels/keen1/overworld.tres` → `music` = `overworld.wav` resource (sub-resource path `res://assets/audio/music/overworld.wav`).
- `assets/levels/keen1/level1.tres` → `music` = `level.wav` resource.

Done via a committed deterministic script `tools/assign_music.gd` (run headless) rather than manual `make edit` / `.tres` hand-editing — reproducible and idempotent.

## 5. Data model & config

### 5.1 `LevelData` — no change

`music: Resource` already exists (`level_data.gd:40`). Runtime guards with `is AudioStream`. Editor already exposes the field under the Assets group; authors assign a music stream per level.

### 5.2 `project.godot` autoload

```
[autoload]

PackLoader="*res://src/core/pack_loader.gd"
GameManager="*res://src/core/game_manager.gd"
EntityRegistry="*res://src/core/entity_registry.gd"
TileSetRegistry="*res://src/core/tileset_registry.gd"
AudioManager="*res://src/core/audio_manager.gd"
```

`AudioManager` is last: it preloads nothing gameplay-critical and is only invoked after boot (autoloads run before the main scene, so any scene `_ready` can safely call it).

### 5.3 Buses

No `[audio]` bus-layout file this plan. Both players default to the `Master` bus. Volume / mute UI is deferred.

## 6. Testing (GUT, headless)

Audio output cannot be verified headless. Tests assert **state + wiring**, never audio amplitude. New file `tests/unit/test_audio_manager.gd`:

| Test | Asserts |
|---|---|
| `test_registry_has_known_sfx` | after autoload init, all 12 names (`jump`, `pogo`, `shoot`, `hurt`, `die`, `pickup_score`, `pickup_ammo`, `enemy_hit`, `enemy_die`, `complete`, `menu_move`, `menu_select`) present in `_sfx`; registry non-empty |
| `test_unknown_sfx_is_noop` | `play_sfx("nonexistent")` does not crash and does not pollute the registry. (GUT cannot capture `push_warning`; we assert the meaningful guarantees — no crash + registry unchanged — rather than the warning itself.) |
| `test_register_sfx_seam` | `register_sfx("fake", stream)` then `play_sfx("fake")` → no warning |
| `test_play_music_starts_player` | `play_music(stream)` → `_music_player.playing == true`; `_music_player.stream == stream` |
| `test_play_music_null_stops` | `play_music(null)` → `_music_player.playing == false` |
| `test_stop_music` | after playing, `stop_music()` → `_music_player.playing == false` |
| `test_stop_all` | after playing music, `stop_all()` → `_music_player.playing == false` (active short SFX voices play out by design) |

Extend existing tests (spot-wiring, light):
| Test | Asserts |
|---|---|
| `test_level_runtime.gd` | build a level whose `music` is a real/fixture `AudioStream` → `AudioManager._music_player.playing == true`; build with `music = null` → `playing == false` |
| `test_player.gd` / `test_runtime_entities.gd` | exercise `shoot()`, `take_damage()`, `enemy.take_damage()` → assert **no runtime errors** (real autoload present). No brittle call-count assertions. |

**Mocking note:** `AudioManager` is a real autoload in test runs, so tests call the genuine singleton — fine for state checks. We deliberately avoid asserting "player triggered sfx X" (brittle, adds no real coverage over code review). Manual verification covers the ears.

### 6.1 Test fixtures

`test_play_music_starts_player` needs a real `AudioStream`. Use one of the committed SFX streams (e.g. `load("res://assets/audio/sfx/jump.wav")`) as a throwaway music stream — its loop setting doesn't matter for a `playing == true` assertion. Avoids authoring a separate fixture.

## 7. Plan / phasing (for writing-plans)

Suggested task order (full breakdown deferred to the implementation plan):

1. **Generator + assets** — write `tools/gen_audio.*`, run it, commit `assets/audio/**` + `LICENSE.txt`; `make import` to produce `.import`; set `loop` on music imports.
2. **AudioManager autoload** — `src/core/audio_manager.gd` + `project.godot` entry; registry loads from `assets/audio/sfx/`; unit tests (registry, play/stop, unknown no-op).
3. **SFX trigger wiring** — player, enemy, collectible, ammo_pickup, level_runtime, main_menu, pack_select direct calls; spot-check tests assert no errors.
4. **Music wiring** — `LevelRuntime.build` music drive; `main_menu` theme; `test_level_runtime` music test.
5. **Bundled-level music** — assign overworld/level themes to the two `.tres` via `make edit`.
6. Full `./tests/run_all.sh` green; manual smoke via `make edit` / `make run-app`.

## 8. Complete-criteria

- [x] `AudioManager` autoload exists; `_sfx` registry holds all 12 names at boot — GUT.
- [x] `play_sfx` unknown name = no-op + warning; `register_sfx` seam works — GUT.
- [x] `play_music` / `stop_music` / `play_music(null)` / `stop_all` behave per spec — GUT.
- [x] `LevelRuntime.build` plays `level.music` when set, stops when null — GUT.
- [x] Player/enemy/pickup/completion/UI trigger calls do not cause runtime errors — GUT + manual.
- [x] `assets/audio/` holds 12 SFX + 3 music WAVs + `LICENSE.txt`; music loops (loop_mode forced at runtime).
- [x] Bundled `overworld.tres` and `level1.tres` carry assigned music — file check.
- [x] `./tests/run_all.sh` fully green (352/352); `make run-app` plays music + SFX audibly — confirmed via manual smoke.

## 9. Risk notes

- **Generated WAV validity:** if the generator emits malformed RIFF, Godot's importer rejects the files and `load()` returns null → registry ends empty, `play_sfx` becomes all-no-op. Mitigation: validate the generator output with a quick header parse; the registry-count GUT test fails loudly if `_sfx` is empty.
- **Polyphony approach (deviation resolved):** the original draft assumed `AudioStreamPlayerPolyphonic.play_stream(stream)` (Godot 4.2+) was available. **It is not present in Godot 4.7 stable** — `ClassDB.class_exists("AudioStreamPlayerPolyphonic") == false` (only `AudioStreamPlaybackPolyphonic` exists). Polyphony is realized via a round-robin voice pool of 8 `AudioStreamPlayer` nodes (§3.2). A 9th simultaneous SFX truncates voice 0's tail; acceptable for this game's SFX density. If a future SFX audibly self-cuts under rapid fire, raise `MAX_POLYPHONY` or add `pitch_scale` jitter.
- **WAV loop setting:** `AudioStreamWAV` loops only if `loop_mode`/`loop` import flag is set. If music does not loop audibly, fix the `.import` (not code).
- **Autoload `load()` in export:** `DirAccess` scan of `res://assets/audio/sfx/` and `load()` of `.wav` must survive PCK packaging. Imported resources are enumerated in export; verified at the `make build` gate. If stripped, fall back to a hardcoded preload list (documented escape hatch).
