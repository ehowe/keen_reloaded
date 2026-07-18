# Blaster Find-to-Own Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop auto-granting the blaster inventory item on every `Player._ready()`; instead, the existing `keen1.raygun` pickup entity grants the item on first contact (alongside ammo), so the weapon is find-to-own and persists across levels + save/load via the existing `Inventory` autoload.

**Architecture:** Two-line source change spread across `player.gd` (delete auto-grant) and `ammo_pickup.gd` (add `Inventory.add_item(ItemIDs.BLASTER)` in the contact hook). All persistence, serialization, and reset paths already work via existing `Inventory` autoload wiring. Test suites are updated first to lock in the new contract, then source follows.

**Tech Stack:** Godot 4.7, GDScript, GUT test framework (`addons/gut/`), vendored. Tests run via `./tests/run_all.sh` (headless).

**Spec:** `docs/superpowers/specs/2026-07-18-blaster-global-inventory-design.md`

**Reference files (read once before starting):**
- `src/runtime/player/player.gd` — `_ready()` (lines 91-99), `shoot()` (lines 255-272)
- `src/runtime/entities/ammo_pickup.gd` — full file (13 lines)
- `src/core/inventory.gd` — full file (35 lines; `add_item` is idempotent)
- `src/core/item_ids.gd` — full file (13 lines)
- `tests/unit/test_player_shoot.gd` — full file (131 lines)
- `tests/unit/test_pickups.gd` — full file (61 lines)

---

## Task 1: Lock the no-auto-grant contract in `test_player_shoot.gd`

Updates the shoot test suite to (a) assert the blaster is NOT auto-granted on spawn, and (b) explicitly grant the blaster in every test that actually fires a projectile. After this task the suite is run and **expected to fail** on the new assertion (because the source still auto-grants). Task 2 then flips the source.

**Files:**
- Modify: `tests/unit/test_player_shoot.gd`

- [ ] **Step 1: Replace the `before_each` comment + body**

The current comment is stale after this plan lands. Update the comment and leave `Inventory.clear()` so each test starts clean.

In `tests/unit/test_player_shoot.gd`, find:

```gdscript
func before_each() -> void:
	# Each player spawn re-grants the blaster; start every test clean so the
	# grant is exercised by _ready, and mirror store is predictable.
	Inventory.clear()
	GameManager.ammo = 0
```

Replace with:

```gdscript
func before_each() -> void:
	# Blaster is find-to-own (granted by the keen1.raygun pickup, not by
	# Player._ready). Start every test clean so each must grant it explicitly.
	Inventory.clear()
	GameManager.ammo = 0
```

- [ ] **Step 2: Replace `test_ready_grants_blaster` with the inverse assertion**

The current test asserts the auto-grant exists. After this plan, the auto-grant is gone. Rename and flip the assertion.

In `tests/unit/test_player_shoot.gd`, find:

```gdscript
# ---- Blaster (permanent inventory item, like pogo) ----

func test_ready_grants_blaster():
	var p := _new_player()
	assert_true(Inventory.has_item(BLASTER), "player always owns the blaster on spawn")
```

Replace with:

```gdscript
# ---- Blaster (find-to-own: granted by keen1.raygun pickup, not Player._ready) ----

func test_ready_does_not_grant_blaster():
	# Player._ready must NOT auto-grant the blaster. Acquisition is via the
	# keen1.raygun pickup (see test_pickups.gd). Spawn-and-check is the contract.
	var p := _new_player()
	assert_false(Inventory.has_item(BLASTER), "spawn does not auto-grant blaster")
```

- [ ] **Step 3: Grant blaster in `test_shoot_spawns_projectile_and_decrements`**

Find:

```gdscript
func test_shoot_spawns_projectile_and_decrements():
	var host := Node2D.new()
	add_child_autofree(host)
	var p := Player.new()
	host.add_child(p)  # parent = host so the projectile lands as a sibling
	p.projectile_speed = 999.0
	p.ammo = p.max_ammo
	var before := host.get_child_count()
	p.shoot()
	assert_eq(p.ammo, p.max_ammo - 1, "ammo decremented")
	assert_eq(host.get_child_count(), before + 1, "projectile spawned as sibling")
	var proj := host.get_child(host.get_child_count() - 1) as Projectile
	assert_true(proj is Projectile, "spawned node is a Projectile")
	assert_eq(proj.speed, 999.0, "player projectile_speed wired to bolt")
```

Replace with (add one `Inventory.add_item` line after `host.add_child(p)`):

```gdscript
func test_shoot_spawns_projectile_and_decrements():
	var host := Node2D.new()
	add_child_autofree(host)
	var p := Player.new()
	host.add_child(p)  # parent = host so the projectile lands as a sibling
	Inventory.add_item(BLASTER)
	p.projectile_speed = 999.0
	p.ammo = p.max_ammo
	var before := host.get_child_count()
	p.shoot()
	assert_eq(p.ammo, p.max_ammo - 1, "ammo decremented")
	assert_eq(host.get_child_count(), before + 1, "projectile spawned as sibling")
	var proj := host.get_child(host.get_child_count() - 1) as Projectile
	assert_true(proj is Projectile, "spawned node is a Projectile")
	assert_eq(proj.speed, 999.0, "player projectile_speed wired to bolt")
```

- [ ] **Step 4: Grant blaster in `test_shoot_uses_facing`**

Find:

```gdscript
func test_shoot_uses_facing():
	var host := Node2D.new()
	add_child_autofree(host)
	var p := Player.new()
	host.add_child(p)
	p._facing = -1
	p.ammo = p.max_ammo
	p.shoot()
	var proj := host.get_child(host.get_child_count() - 1) as Projectile
	assert_lt(proj.velocity.x, 0, "left-facing shot moves left")
```

Replace with:

```gdscript
func test_shoot_uses_facing():
	var host := Node2D.new()
	add_child_autofree(host)
	var p := Player.new()
	host.add_child(p)
	Inventory.add_item(BLASTER)
	p._facing = -1
	p.ammo = p.max_ammo
	p.shoot()
	var proj := host.get_child(host.get_child_count() - 1) as Projectile
	assert_lt(proj.velocity.x, 0, "left-facing shot moves left")
```

- [ ] **Step 5: Grant blaster in `test_shoot_spawn_flips_with_facing`**

Find:

```gdscript
func test_shoot_spawn_flips_with_facing():
	var scene := load("res://src/runtime/player/player.tscn") as PackedScene
	var host := Node2D.new()
	add_child_autofree(host)
	var p := scene.instantiate() as Player
	host.add_child(p)
	p.global_position = Vector2(1000, 500)
	p.ammo = p.max_ammo
	p._facing = 1
	p.shoot()
	var pr := host.get_child(host.get_child_count() - 1) as Projectile
	assert_gt(pr.global_position.x, p.global_position.x, "right-facing spawns right of player")
	p._facing = -1
	p.shoot()
	var pl := host.get_child(host.get_child_count() - 1) as Projectile
	assert_lt(pl.global_position.x, p.global_position.x, "left-facing spawns left of player")
```

Replace with (add `Inventory.add_item(BLASTER)` once, right after `host.add_child(p)`):

```gdscript
func test_shoot_spawn_flips_with_facing():
	var scene := load("res://src/runtime/player/player.tscn") as PackedScene
	var host := Node2D.new()
	add_child_autofree(host)
	var p := scene.instantiate() as Player
	host.add_child(p)
	Inventory.add_item(BLASTER)
	p.global_position = Vector2(1000, 500)
	p.ammo = p.max_ammo
	p._facing = 1
	p.shoot()
	var pr := host.get_child(host.get_child_count() - 1) as Projectile
	assert_gt(pr.global_position.x, p.global_position.x, "right-facing spawns right of player")
	p._facing = -1
	p.shoot()
	var pl := host.get_child(host.get_child_count() - 1) as Projectile
	assert_lt(pl.global_position.x, p.global_position.x, "left-facing spawns left of player")
```

- [ ] **Step 6: Grant blaster in `test_shoot_mirrors_game_manager`**

Find:

```gdscript
func test_shoot_mirrors_game_manager():
	var host := Node2D.new()
	add_child_autofree(host)
	var p := Player.new()
	host.add_child(p)
	p.ammo = p.max_ammo
	GameManager.ammo = p.max_ammo
	p.shoot()
	assert_eq(GameManager.ammo, p.max_ammo - 1, "shot decremented persistent store")
```

Replace with:

```gdscript
func test_shoot_mirrors_game_manager():
	var host := Node2D.new()
	add_child_autofree(host)
	var p := Player.new()
	host.add_child(p)
	Inventory.add_item(BLASTER)
	p.ammo = p.max_ammo
	GameManager.ammo = p.max_ammo
	p.shoot()
	assert_eq(GameManager.ammo, p.max_ammo - 1, "shot decremented persistent store")
```

- [ ] **Step 7: Run the suite — expect one new failure**

Run:

```bash
./tests/run_all.sh 2>&1 | grep -E "(test_ready_does_not_grant_blaster|PASS|FAIL|Asserting)" | head -40
```

Expected: `test_ready_does_not_grant_blaster` **FAILS** ("spawn does not auto-grant blaster"). All other shoot tests still PASS (they now grant the blaster explicitly). This is the correct state: the test suite enforces the new contract, but the source still auto-grants. Task 2 fixes the source.

(If a *different* test fails, stop and investigate — something else regressed.)

Do not commit yet; commit together with Task 2 so the tree stays green on each commit.

---

## Task 2: Remove the auto-grant from `Player._ready()`

Delete the `Inventory.add_item(BLASTER)` line in `Player._ready()`. After this, the assertion added in Task 1 passes, and the shoot gate (`if not Inventory.has_item(BLASTER): return`) does real work.

**Files:**
- Modify: `src/runtime/player/player.gd:20-22` (comment block) and `src/runtime/player/player.gd:91-99` (`_ready` body)

- [ ] **Step 1: Update the `BLASTER` constant comment**

The comment currently says "Always owned (granted in _ready)". After this task it's wrong. Find in `src/runtime/player/player.gd`:

```gdscript
## Permanent inventory item representing Keen's raygun/blaster. Always owned
## (granted in _ready), so shooting is always available given ammo — kept as an
## inventory item so it persists in saves like keen1.pogo.
const BLASTER := ItemIDs.BLASTER
```

Replace with:

```gdscript
## Raygun/blaster inventory item. Find-to-own: granted by the keen1.raygun
## ammo pickup on first contact (see ammo_pickup.gd). Gates shooting — see
## shoot(). Persists across levels + save/load via the Inventory autoload
## (like keen1.pogo).
const BLASTER := ItemIDs.BLASTER
```

- [ ] **Step 2: Delete the auto-grant line in `_ready()`**

Find in `src/runtime/player/player.gd`:

```gdscript
func _ready() -> void:
	add_to_group("player")
	# Keen always carries the blaster (permanent inventory item, like the pogo).
	# Idempotent: covers episode, pack, and editor-Test entry paths alike.
	Inventory.add_item(BLASTER)
	ammo = 0
	ammo_changed.emit(ammo)
	_apply_collision_for_mode()
	_align_sprite_feet()
```

Replace with:

```gdscript
func _ready() -> void:
	add_to_group("player")
	ammo = 0
	ammo_changed.emit(ammo)
	_apply_collision_for_mode()
	_align_sprite_feet()
```

- [ ] **Step 3: Run the full test suite — expect all-pass**

Run:

```bash
./tests/run_all.sh
```

Expected: **all tests pass**, including:
- `test_ready_does_not_grant_blaster` (was failing after Task 1; now passes)
- `test_shoot_requires_blaster` (still passes — already disarms via `Inventory.remove_item`)
- All other shoot tests (now grant blaster explicitly via Task 1)
- All inventory, pogo, pickup, keycard, door, game_manager, level_runtime tests (unchanged behavior)

If any test other than the auto-grant assertion is failing, stop and investigate.

- [ ] **Step 4: Commit**

```bash
git add tests/unit/test_player_shoot.gd src/runtime/player/player.gd
git commit -m "feat(player): blaster is find-to-own, not auto-granted

Player._ready no longer auto-grants the keen1.blaster inventory item.
Shooting now requires acquiring the blaster via the keen1.raygun pickup
(wired in a follow-up task) — matches the pogo acquisition pattern.
Test suite updated: shoot tests grant the blaster explicitly; new
test_ready_does_not_grant_blaster locks the contract."
```

---

## Task 3: Lock the raygun-grants-blaster contract in `test_pickups.gd`

Adds an assertion that the existing `keen1.raygun` pickup grants the blaster inventory item on contact. Also adds a `before_each` that clears the Inventory so the assertion is not tainted by prior tests. After this task the suite is run and **expected to fail** on the new assertion (because the source change is in Task 4).

**Files:**
- Modify: `tests/unit/test_pickups.gd`

- [ ] **Step 1: Add a `before_each` that clears Inventory**

`test_pickups.gd` currently has no `before_each` (only an `after_each` that re-registers episodes). The new blaster assertion will be tainted if a prior test left the blaster in Inventory. Add `before_each` right after the `FakePlayer` class definition (before `test_lollipop_awards_score`).

Find:

```gdscript
func after_each():
	GameManager.register_episodes()


func test_lollipop_awards_score():
```

Replace with:

```gdscript
func before_each():
	Inventory.clear()


func after_each():
	GameManager.register_episodes()


func test_lollipop_awards_score():
```

- [ ] **Step 2: Extend `test_raygun_grants_ammo` to assert blaster ownership**

Find:

```gdscript
func test_raygun_grants_ammo():
	var r: AmmoPickup = add_child_autofree(load("res://src/runtime/entities/ammo_pickup.tscn").instantiate())
	assert_eq(r.ammo_value, 5)
	var p := FakePlayer.new()
	p.ammo = 1
	add_child_autofree(p)
	r._on_body_entered(p)
	assert_eq(p.ammo, 5, "ammo granted and clamped to max")
	assert_true(r.is_queued_for_deletion(), "pickup frees after use")
```

Replace with:

```gdscript
func test_raygun_grants_ammo_and_blaster():
	var r: AmmoPickup = add_child_autofree(load("res://src/runtime/entities/ammo_pickup.tscn").instantiate())
	assert_eq(r.ammo_value, 5)
	var p := FakePlayer.new()
	p.ammo = 1
	add_child_autofree(p)
	assert_false(Inventory.has_item(ItemIDs.BLASTER), "blaster not owned before pickup")
	r._on_body_entered(p)
	assert_eq(p.ammo, 5, "ammo granted and clamped to max")
	assert_true(Inventory.has_item(ItemIDs.BLASTER), "blaster granted on first pickup")
	assert_true(r.is_queued_for_deletion(), "pickup frees after use")
```

(The test name changes from `test_raygun_grants_ammo` to `test_raygun_grants_ammo_and_blaster` so the name reflects the dual grant.)

- [ ] **Step 3: Add an idempotency test for the blaster grant**

A second raygun pickup (in a later level, after re-load, etc.) must not re-emit `item_collected` for the blaster — but it must still grant ammo. Add this new test right after `test_raygun_grants_ammo_and_blaster`:

```gdscript
## Second+ raygun pickups still grant ammo but do not re-emit item_collected
## for the blaster (Inventory.add_item is idempotent).
func test_raygun_blaster_grant_is_idempotent():
	# Pre-grant the blaster as if a prior pickup already gave it.
	Inventory.add_item(ItemIDs.BLASTER)
	watch_signals(Inventory)
	var r: AmmoPickup = add_child_autofree(load("res://src/runtime/entities/ammo_pickup.tscn").instantiate())
	var p := FakePlayer.new()
	p.ammo = 0
	add_child_autofree(p)
	r._on_body_entered(p)
	assert_eq(p.ammo, 5, "ammo still granted on subsequent pickups")
	assert_true(Inventory.has_item(ItemIDs.BLASTER), "blaster still owned")
	assert_signal_not_emitted(Inventory, "item_collected", "no re-emit on duplicate blaster grant")
```

- [ ] **Step 4: Run the suite — expect one new failure**

Run:

```bash
./tests/run_all.sh 2>&1 | grep -E "(test_raygun|PASS|FAIL|Asserting)" | head -40
```

Expected:
- `test_raygun_grants_ammo_and_blaster` **FAILS** ("blaster granted on first pickup" — `Inventory.has_item(ItemIDs.BLASTER)` is false because `ammo_pickup.gd` doesn't grant it yet).
- `test_raygun_blaster_grant_is_idempotent` **PASSES** (the pre-grant + signal-not-emitted assertion holds regardless of source — it pre-grants manually).
- The existing `test_lollipop_awards_score`, `test_score_pickups_award_expected_values` still pass (unrelated).

Do not commit yet; commit together with Task 4.

---

## Task 4: Grant blaster in `ammo_pickup.gd`

Add one line — `Inventory.add_item(ItemIDs.BLASTER)` — to the top of `AmmoPickup._handle_player`. `add_item` is idempotent and only emits `item_collected` on first acquisition, so subsequent raygun pickups stay quiet on the inventory side but still grant ammo.

**Files:**
- Modify: `src/runtime/entities/ammo_pickup.gd`

- [ ] **Step 1: Update the class docstring**

The class docstring currently says "Grants ammo_value to the player on contact, then frees." Update to reflect the dual grant. Find in `src/runtime/entities/ammo_pickup.gd`:

```gdscript
class_name AmmoPickup
extends Collectible
## Raygun ammo pickup. Grants ammo_value to the player on contact, then frees.
```

Replace with:

```gdscript
class_name AmmoPickup
extends Collectible
## Raygun pickup. On first contact, grants the keen1.blaster inventory item
## (the weapon); every contact grants ammo_value ammo. Idempotent: subsequent
## pickups silently no-op the inventory write (Inventory.add_item guards on
## first acquisition) and still grant ammo. Registered as keen1.raygun.
```

- [ ] **Step 2: Add the blaster grant to `_handle_player`**

Find:

```gdscript
func _handle_player(player: Node) -> void:
	if player.has_method("add_ammo"):
		player.add_ammo(ammo_value)
	AudioManager.play_sfx("pickup_ammo")
	queue_free()
```

Replace with:

```gdscript
func _handle_player(player: Node) -> void:
	Inventory.add_item(ItemIDs.BLASTER)
	if player.has_method("add_ammo"):
		player.add_ammo(ammo_value)
	AudioManager.play_sfx("pickup_ammo")
	queue_free()
```

- [ ] **Step 3: Run the full test suite — expect all-pass**

Run:

```bash
./tests/run_all.sh
```

Expected: **all tests pass**, including:
- `test_raygun_grants_ammo_and_blaster` (was failing after Task 3; now passes)
- `test_raygun_blaster_grant_is_idempotent` (still passes)
- All pickup, inventory, pogo, keycard, door, game_manager, level_runtime, player_shoot, player tests unchanged.

- [ ] **Step 4: Commit**

```bash
git add tests/unit/test_pickups.gd src/runtime/entities/ammo_pickup.gd
git commit -m "feat(pickup): raygun grants blaster inventory item on first contact

AmmoPickup._handle_player now calls Inventory.add_item(ItemIDs.BLASTER)
before granting ammo. Idempotent: first pickup gives weapon + ammo;
later pickups give ammo only. Shooting was already gated by
Inventory.has_item(BLASTER) — combined with Task 2 (removed auto-grant),
the blaster is now find-to-own via the keen1.raygun pickup, persisting
across levels and save/load."
```

---

## Task 5: Update stale docstrings in `item_ids.gd` and `test_ammo_persistence.gd`

Two remaining doc-only updates so future readers aren't misled. No behavior change, no new tests.

**Files:**
- Modify: `src/core/item_ids.gd:12-13`
- Modify: `tests/unit/test_ammo_persistence.gd:1-4`

- [ ] **Step 1: Update `ItemIDs.BLASTER` docstring**

Find in `src/core/item_ids.gd`:

```gdscript
## Raygun/blaster. Always owned (granted in Player._ready); gates shooting.
const BLASTER := "keen1.blaster"
```

Replace with:

```gdscript
## Raygun/blaster. Find-to-own: granted by the keen1.raygun ammo pickup entity
## on first contact; gates shooting. Persists across levels + save/load via the
## Inventory autoload (like POGO). Cleared on new game by clear_progress().
const BLASTER := "keen1.blaster"
```

- [ ] **Step 2: Update `test_ammo_persistence.gd` header comment**

Find in `tests/unit/test_ammo_persistence.gd`:

```gdscript
extends GutTest
## Ammo is a persistent GameManager field (source of truth across levels). It
## serializes with the session, deserializes back, and resets on clear_progress
## (new game). The blaster is a permanent inventory item Keen always owns.
```

Replace with:

```gdscript
extends GutTest
## Ammo is a persistent GameManager field (source of truth across levels). It
## serializes with the session, deserializes back, and resets on clear_progress
## (new game). The blaster is a find-to-own inventory item (granted by the
## keen1.raygun pickup) tracked separately via the Inventory autoload; its
## persistence is covered by test_inventory.gd and test_pickups.gd.
```

- [ ] **Step 3: Run the full test suite — confirm no regressions**

Run:

```bash
./tests/run_all.sh
```

Expected: **all tests pass** (comment-only changes; nothing can break).

- [ ] **Step 4: Commit**

```bash
git add src/core/item_ids.gd tests/unit/test_ammo_persistence.gd
git commit -m "docs: refresh blaster docstrings to reflect find-to-own

item_ids.gd and test_ammo_persistence.gd header comments still described
the blaster as always-owned. Update both to point at the keen1.raygun
pickup as the acquisition source."
```

---

## Task 6: Manual verification

Confirm the change works end-to-end in the running game. No code changes; this is a sanity check that the level 1 raygun placement is reachable and the new gating is felt in play.

**Files:** (none)

- [ ] **Step 1: Launch the game**

Run:

```bash
make run-app
```

(If a build is required first, `make build` then run the produced bundle. See `AGENTS.md`.)

- [ ] **Step 2: Start a new episode and enter level 1**

From the title screen, start a new keen1 episode, walk to level 1's entrance on the overworld, and enter.

- [ ] **Step 3: Confirm shooting is disabled before pickup**

Press the `shoot` key (`X` on keyboard, `X` button on gamepad). Expected: **no projectile fires, no ammo decrement, no `shoot` SFX**. (The shoot gate returns early because `Inventory` does not have `keen1.blaster`.)

- [ ] **Step 4: Walk to the raygun pickup, confirm acquisition**

The `keen1.raygun` entity is placed in `level1.tres`. Walk Keen into it. Expected: `pickup_ammo` SFX plays; ammo counter on the HUD increases by 5.

- [ ] **Step 5: Confirm shooting is now enabled**

Press `shoot`. Expected: `shoot` SFX plays; projectile spawns from the muzzle in the facing direction; ammo decrements by 1.

- [ ] **Step 6: Confirm persistence across death**

Find a hazard or enemy, let Keen die. After the overworld respawn, re-enter level 1 (or any other level). Press `shoot`. Expected: shooting still works (blaster persisted via global Inventory, not per-level state).

- [ ] **Step 7: Confirm persistence across save/load**

If save/load is reachable in the current build: save the game, quit to title, load the save, enter a level, press `shoot`. Expected: shooting still works.

If save/load UI is not reachable in this build, skip this step and note it in the task summary.

- [ ] **Step 8: Confirm new-game reset**

From a state where the blaster is owned, quit to title and start a fresh episode (new game, not continue). Enter level 1. Press `shoot` before touching any raygun pickup. Expected: **no projectile** — `clear_progress()` cleared Inventory on new-game start, so the blaster must be re-acquired.

- [ ] **Step 9: No commit needed**

This task is verification only. If any step failed, file the finding as a follow-up bug; do not commit a regression.

---

## Self-Review

**Spec coverage:**

| Spec goal | Task |
|---|---|
| Goal 1 — `Player._ready()` no longer auto-grants | Task 2 |
| Goal 2 — `keen1.raygun` grants blaster on first contact | Task 4 |
| Goal 3 — Shooting still gated by `Inventory.has_item(BLASTER)` | (No change needed; gate already exists at `player.gd:256`) |
| Goal 4 — Persists across levels + save/load | (No change needed; existing Inventory autoload wiring) |
| Goal 5 — `clear_progress()` clears blaster on new game | (No change needed; existing behavior) |
| Goal 6 — All shooting tests updated to grant blaster | Task 1 |
| Spec §4.3 — `item_ids.gd` docstring update | Task 5 |
| Spec §5.1 — `test_pickups.gd` blaster assertion + idempotency test | Task 3 |
| Spec §5.3 — Manual verification checklist | Task 6 |

No spec gaps.

**Placeholder scan:** No "TBD"/"TODO"/"implement later". Every code step contains complete code.

**Type/name consistency:**
- `ItemIDs.BLASTER` — used consistently across `player.gd`, `ammo_pickup.gd`, `test_pickups.gd`, `item_ids.gd`.
- `BLASTER` local const in `test_player_shoot.gd` (= `"keen1.blaster"`) — unchanged, matches `ItemIDs.BLASTER`.
- `_handle_player(player: Node)` signature — unchanged; new code uses it as-is.
- `_on_body_entered(p)` — pickup test entry point, unchanged.

No drift.
