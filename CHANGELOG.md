## v2026.07.21 — 2026-07-21

### Added
- randomize green dangly stuff anim start frame
- green dangly stuff ceiling hazard
- register keen1.green_dangly_stuff hazard
- replace green dangly placeholder with real scene
- add GreenDanglyStuff hazard script + tests
- add keen1 tank robot
- add LAYER_FRONT tile layer

### Documentation
- plan green dangly stuff hazard implementation
- spec green dangly stuff ceiling hazard

## v2026.07.19 — 2026-07-19

### Added
- add everclear/vacuum/joystick collectibles

## v2026.07.18 — 2026-07-18

### Added
- rework butler + vorticon AI, sprite atlases
- add keen1.battery collectible
- raygun grants blaster inventory item on first contact
- blaster is find-to-own, not auto-granted
- add color-locked Door entity
- add Keycard pickup entity
- add per-level keycard state

### Fixed
- disable collision via set_deferred during anim
- widen contact sensor beyond solid collision
- drop half-applied guard, add non-default variant test

### Documentation
- refresh blaster docstrings to reflect find-to-own
- blaster find-to-own implementation plan
- blaster as find-to-own global inventory
- door + keycard entities implementation plan
- door + keycard entities design spec

### Refactored
- extract _build_contact_area helper

## v2026.07.17 — 2026-07-17

### Refactored
- Tier 3 nits (wall-check, restore_tiles, ammo sync, proximity type_id)
- Tier 2 cleanup (Constants, ItemIDs, Player.find, data-driven pickups)
- extract shared entity helpers (SpriteUtil, ShapeUtil, ProximityInteractable, instakill)

## v2026.07.16 — 2026-07-16

### Added
- Message entity uses Base/Unread/Read sprites with animation control
- editor grid syncs to selected atlas source tile size
- wire MessageEntity signal to LevelRuntime overlay builder
- register keen1.message entity type
- add MessageEntity with read/unread sprite states
- add MessageOverlay scene + dismiss-on-input
- add Message option to editor MapKindPicker
- Episode.load_levels includes MESSAGE-kind levels
- add MapKind.MESSAGE to LevelData enum

### Fixed
- stage only .app for DMG, clean stale create-dmg volumes
- output macOS DMG to build/dist to avoid recursive self-inclusion
- message overlay renders via TileCanvas to avoid tile gaps
- message overlay scales tiles to fit viewport using TileSet size
- editor Test ▶ registers sibling levels so cross-level refs resolve

### Documentation
- add message entity design spec + implementation plan

## v2026.07.15 — 2026-07-15

### Added
- add level5, fire hazard entity, Backgrounds tileset, DMG builds
- persistent ammo/lives + overworld inventory HUD
- add Garg charging hazard
- rewrite pogo physics, animation, bounce hold
- add pogo stick pickup + persistent inventory

### Documentation
- add ASCII art header

# Changelog

## v2026.07.14 — 2026-07-14

### Added
- CalVer versioning pipeline
- route custom pack start through slot-select
- pause menu (Esc) with save/load/quit
- New Game + Continue buttons wired to slot-select
- slot-select screen with status-aware card labels
- resume_overworld + start_pack clear refactor + auto-save hooks
- list_slots with status classification + delete_slot
- load_slot with validation + .bak fallback
- SaveSystem autoload with atomic save_slot + .bak rotate
- add current_scope_kind + extend serialize/deserialize
- done overlays + binary leveldata pipeline
- level_id dropdown + rename overworld from placeholder
- animate both ends of teleport, hide/freeze player in transit
- wire Teleporter.teleport_requested to GameManager.teleport
- GameManager.teleport resolves cross-map teleporter destination
- register keen1.teleporter (SPECIAL, level+overworld)
- add Teleporter node (proximity+interact, emits teleport_requested)
- toggle Level/Overworld collision by mode
- instantiate icon Hud + overworld cleared label; raise overlay layer
- default gamepad bindings (d-pad + stick + A/B/X/Y)
- icon-based Hud scene (hearts/ammo/score + overworld cleared)
- add max_health export (default 3)
- generated CC0 placeholder HUD icons (heart + ammo)
- assign placeholder music to bundled keen1 levels
- menu music + navigate/select SFX on menus
- drive music from LevelData + completion SFX
- SFX for enemy hit/die + score/ammo pickups
- SFX for jump/pogo/shoot/hurt/die
- AudioManager autoload — SFX registry + music/SFX players
- generated CC0 placeholder audio (12 SFX + 3 music)
- pack-select menu + main-menu entry for custom packs
- start_pack entry point for custom level packs
- hardened zip import (traversal + type allowlist)
- scan user levelpacks + manifest/overworld resolution
- death sequence prep — Death sprite node + plan + art
- spike is a clapper-like instakill hazard with facing variant
- canvas label appends enum variant value
- register spike entity with facing variant schema
- inspector renders enum OptionButton, schema-first w/ fallback
- placement seeds schema defaults into EntityDef
- SpriteEntity applies enum variant to child visibility
- entity property schema retrieval + enum validation
- death flies player off-screen, transitions to overworld
- GameManager.fail_level returns to overworld w/o completing
- dead physics holds launch velocity (no gravity)
- death visual sync shows Death sprite, feet aligned
- death launches Keen up-left at 60 deg, collision off
- _dead flag + idempotent take_damage routes to _die()
- overworld spawns player in OVERWORLD mode + suppresses HUD
- overworld visual sync — 4 sprites, idle on frame 0, no flip
- overworld physics — 4-directional top-down movement, no gravity
- add Mode/Direction enums + set_mode() plumbing
- register move_up/move_down input actions for overworld
- boot flow — start_episode + Episode.load_overworld + Play button
- wire enter/return overworld loop through GameManager
- edit String/Bool entity properties in inspector
- filter entity palette by map kind; register Level Entrance
- LevelEntrance entity — door + proximity + gate blocker
- GameManager loop state, completion set, save hooks
- register interact input action (Up arrow)
- map kind dropdown in inspector
- overworld maps disable the bottom kill zone
- add MapKind enum to LevelData (LEVEL default)
- support multiple atlas sources per TileSet
- register Clapper as keen1.clapper hazard
- add Clapper hazard — stationary invincible instakill
- register Exit Sign sprite as decor entity
- wrap sprite scenes in SpriteEntity at instantiate
- add register_sprite + CATEGORY_DECOR to EntityRegistry
- add SpriteEntity wrapper for decor sprites
- exit door walk-out animation
- sprite pickups + exit door
- running leap + slow air steer
- auto-reopen last level on fresh editor open
- persist last level path to user config
- entity category filter + score pickups
- player movement feel + enemy AI polish
- cell-center spawns, ammo-from-zero, sprite art
- wire Walking/Idle/Stunned/Shot sprites into scene
- shot death animation (immediate when no art)
- stun + stomp-to-stun + contact routing
- wander pacing (walk/idle phases)
- state enum + sprite cache/visual sync
- minimal in-play HUD (score/ammo/health)
- exit door + level completion overlay (score/time, pause, return)
- Candy + Raygun ammo pickups + scenes
- ammo-limited raygun shoot + facing tracking + Muzzle
- raygun projectile (kill enemies, despawn on wall/lifetime)
- Vorticon/Yorp/Butler concrete enemies + scenes
- Enemy physics base — gravity, patrol, turn-at-walls/ledges, score award
- per-episode union catalog + shoot input (keen1 registers namespaced types)
- level resize preserves existing tiles
- current-tile preview + auto-scroll palette
- tile box-move, eyedropper, flood-erase
- confine player to map via walls + bottom kill zone
- palette tile grid scrolls vertically for large tilesets
- inspector TileSet picker (assigns level.tileset_ref)
- editor palette shows real tile thumbnails when tileset_ref is set
- editor canvas renders real tile art when tileset_ref is set
- LevelRuntime renders+collides from level.tileset_ref (procedural fallback)
- add TileAtlas helper (row-major tile-id to atlas-coords mapping)
- wire editor Test ▶ to runtime + restore level on return
- add LevelRuntime scene root
- add LevelRuntime.build (assembles tile world, player, entities)
- add GameManager pending_level/return_scene + input actions
- add Player (run/jump/pogo) with score + health API
- add EntityRegistry.instantiate + scene binding
- add base entity classes (Entity/Collectible/Hazard/Enemy/Special)
- add ProceduralTileSet builder (no-art render + collision)
- add main-menu entry to open the level editor
- add editor inspector panel (metadata, spawn, entity props)
- add editor palette panel (tiles, layers, tools, entities)
- add editor canvas with tile drawing, painting, zoom
- add LevelEditor controller + 3-panel layout scaffold
- add EditorColors helper for tile id -> color mapping
- add EntityRegistry data layer for editor palette
- add entity + player-spawn editor commands
- add FloodFillCmd for editor fill tool
- add EditorCommand base, PaintCellsCmd, and UndoStack
- add generic layer-name tile accessors to LevelData
- add placeholder main_menu scene (replaced in Plan 2)
- add LevelPack manifest parser with validation + sorting
- add LevelData tile accessors + serialization round-trip
- add LevelData resource with metadata, dimensions, tile helpers
- add EntityDef resource with serialization

### Fixed
- purge stale level registrations on quit + register on test_run
- hide pause overlay on quit + free load slot-select
- wire SFX for dynamic slot-select buttons
- _slot_status rejects non-dict data as corrupt
- defer complete_level scene swap + overworld content
- guard proximity with player-group check
- restore player when destination dangles (no soft-lock)
- validate manifest pack_id (traversal), atomic rename, case-insensitive scheme checks
- set autoplay on variant AnimatedSprite2D children
- defer collision disable on death
- dead check precedes overworld mode (defense-in-depth)
- kill zone routes lethal falls through death, respawns only if alive
- make yorp solid to keen with bouncy knockback
- pass bolts through one-way platforms
- hide inactive sprite set in visual sync
- review follow-ups — clear_progress hygiene, play button fallback, stale docstring
- per-kind entity spawn test + palette selection reset + registry helper
- setup reapplies blocking + guard against empty-target gates
- clear_progress also resets pending_player_spawn + registry assertion
- drop contact damage on bump
- match collision box height to 96px sprite
- let yorp walk off ledges
- skip bounce on re-stomp of stunned enemy
- disable camera position smoothing
- reparent sprite visual so it renders at wrapper position
- clear EntityRegistry in after_each + lock sprite properties default
- completion overlay ignores mouse so click-to-dismiss works
- wire projectile_speed onto spawned bolt
- at most one patrol flip per frame (wall elif ledge)
- clamp camera to map bounds
- TileSet picker uses an export-safe registry instead of DirAccess
- bind entity properties to behavior vars + consume Test stash on restore + silence test node leaks
- stop tests leaking empty EntityRegistry into later scripts
- attach main_menu script to root node
- enable ETC2 ASTC texture compression for macOS export
- track .uid files, add fg/bg tile tests, gitignore .serena
- track .import files (godot 4 import config is source-controlled)

### Documentation
- add README, LICENSE (MIT code), and CONTRIBUTING
- release versioning design spec
- mark Plan 6c (persistence) done
- Plan 6c persistence design spec + implementation plan
- document animation sequence + arrival-id flag
- design spec + implementation plan
- mark Plan 6b (Feel/Feedback) done in build-phases + spec status
- feel & feedback implementation plan (6 TDD tasks)
- feel & feedback design spec — icon HUD + gamepad bindings
- mark audible smoke confirmed — 6a fully complete
- mark Plan 6a (Audio) done in build-phases table
- sync spec with implemented voice-pool audio + deviations
- audio implementation plan (8 TDD tasks)
- audio design spec — AudioManager + music/SFX + generated assets
- mark Plan 5 (pack loading) done in build-phases table
- pack loading implementation plan (5 TDD tasks)
- pack loading design spec — PackLoader + zip import + start_pack
- SpriteEntity variant caveat + warn on unmatched value
- entity variant properties — 6-task TDD implementation plan
- variant selector walks descendants, not direct children
- entity variant properties — enum schema for spike facing
- keen death sequence — anim, up-left launch, overworld return
- note OVERWORLD mode in class docstring
- overworld player behavior — 6-task TDD implementation plan
- overworld player behavior — top-down 4-dir walk, mode flag, HUD off
- add map-kind + overworld loop implementation plan
- add map-kind + overworld loop design spec
- correct Clapper.png sheet dimensions to 256x64
- clapper enemy implementation plan
- clapper enemy design — stationary invincible instakill hazard
- implementation plan for sprite-backed entities
- spec for sprite-backed entities
- remember-last-level spec + plan
- implementation plan for enemy state-driven sprites
- spec for enemy state-driven sprites (walk/idle/stunned/shot)
- Plan 4 implementation plan — gameplay content (12 tasks)
- Plan 4 design spec — gameplay content (entities, shoot, exits)
- add future-work list (tile palette search/filter)
- Plan 4 implementation plan — tile-art import pipeline
- correct Godot 4.7 API in Plan 4 spec (margins/get_tiles_count) + add verified-API note
- Plan 4 design spec — tile-art import pipeline
- mark Plan 3 runtime-core criteria complete
- Plan 3 runtime-core design + master-plan descopes (content/shoot -> Plan 4)
- add AGENTS.md with build/test commands

### Refactored
- path_join consistency + assert ResourceSaver in tests
- type-hint ResourceLoader.exists as PackedScene
- extract _load_from_path, remember on save/load
- inherit contact/stun/shot behaviour from Enemy base
- migrate entity type ids to namespaced keen1.*
- rebuild episodes metadata each scan + cover disk-scan discovery
- Entity base becomes CharacterBody2D (contact via child Area2D)
- simplify registry scene branch + free test entity nodes
- name collision-bit constants + lock them in test
- allow GODOT path override via env var
