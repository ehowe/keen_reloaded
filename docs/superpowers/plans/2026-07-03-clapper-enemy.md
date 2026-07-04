# Clapper Enemy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a stationary, invincible Clapper enemy whose contact (side or stomp) instantly kills Keen; register it as a Keen 1 hazard.

**Architecture:** New `Clapper` class extends `Hazard` (which extends `Entity`). Overrides only `_handle_player()` to drain the player's current health to 0 via the existing `take_damage()` path (→ `died` signal). No `take_damage` method on the Clapper → `projectile.gd`'s `has_method` guard makes blaster bolts pass through harmlessly (invincible, no code needed). A runtime scene `clapper.tscn` carries an `AnimatedSprite2D` named `Visual` (the seam `Entity._build_contact()` checks to skip the procedural fallback), wired to the existing `Clapper.png` (4 frames × 64×64, clap loop). Registered as `keen1.clapper` under `CATEGORY_HAZARD`.

**Tech Stack:** Godot 4.7, GDScript, GUT test framework (vendored at `addons/gut/`).

**Spec:** `docs/superpowers/specs/2026-07-03-clapper-enemy-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `src/runtime/entities/clapper.gd` | Create | `Clapper extends Hazard`; instakill on contact |
| `src/runtime/entities/clapper.tscn` | Create | CharacterBody2D root + script + `Visual` AnimatedSprite2D (clap loop) |
| `src/episodes/keen1/episode.gd` | Modify | Register `keen1.clapper` as `CATEGORY_HAZARD` |
| `tests/unit/test_concrete_enemies.gd` | Modify | Behavior tests: instakill + invincibility |
| `tests/unit/test_episode.gd` | Modify | Assert `keen1.clapper` registered + category |

**Established patterns this plan follows:**
- Per-enemy script + scene live in `src/runtime/entities/` (mirrors `yorp.gd`/`yorp.tscn`, `butler.gd`/`butler.tscn`).
- Runtime entity scene duplicates the sprite slice definitions rather than inheriting from the decor scene in `assets/sprites/` (mirrors `yorp.tscn` slicing `Yorp 64x96.png` even though no shared SpriteFrames resource exists).
- `Entity._build_contact()` (`src/runtime/entities/entity.gd:52`) skips the procedural `ColorRect` when the scene already has a child named `Visual`. No `Enemy._cache_sprites()` runs (Clapper is not an `Enemy`), so a single looping `AnimatedSprite2D` named `Visual` is correct.
- `projectile.gd:31` only calls `body.take_damage(1)` when `body.has_method("take_damage")`. Omitting that method makes bolts pass through — the documented shoot-through contract.

---

## Task 1: Failing behavior test

**Files:**
- Modify: `tests/unit/test_concrete_enemies.gd` (append three test functions before `after_each`)

The existing `FakeKinematicPlayer` inner class (lines 3–11) already has `health: int = 3` and a `take_damage(amount)` that subtracts. Reuse it via the existing `_fake_player()` helper.

- [ ] **Step 1: Add the three failing tests**

In `tests/unit/test_concrete_enemies.gd`, insert these three functions immediately before the final `func after_each():` block:

```gdscript
func test_clapper_instakills_on_contact():
	var c: Clapper = add_child_autofree(load("res://src/runtime/entities/clapper.tscn").instantiate())
	var p := _fake_player()
	assert_eq(p.health, 3, "fake player starts at 3 hp")
	c._handle_player(p)
	assert_eq(p.health, 0, "clapper drains all health on contact (instakill)")


func test_clapper_instakills_on_stomp_from_above():
	# No stomp branch exists today (contact is uniformly lethal), but Enemy has a
	# stomp-vs-side distinction. This pins the intent: landing on the Clapper must
	# stay lethal even if such branching is ever introduced.
	var c: Clapper = add_child_autofree(load("res://src/runtime/entities/clapper.tscn").instantiate())
	c.global_position = Vector2(0, 0)
	var p := _fake_player()
	p.global_position = Vector2(0, -100)  # player above the Clapper (stomp geometry)
	c._handle_player(p)
	assert_eq(p.health, 0, "stomping the Clapper is lethal")


func test_clapper_invincible_to_shots():
	# projectile.gd only damages bodies with a take_damage method. The Clapper
	# must NOT implement it, so blaster bolts pass straight through.
	var c: Clapper = add_child_autofree(load("res://src/runtime/entities/clapper.tscn").instantiate())
	assert_false(c.has_method("take_damage"), "clapper has no take_damage -> projectiles pass through")
```

- [ ] **Step 2: Run the suite to confirm the new tests fail**

Run: `./tests/run_all.sh`
Expected: FAIL — errors referencing `Clapper` (unknown class) and/or missing `res://src/runtime/entities/clapper.tscn` (parse/load error). `test_clapper_instakills_on_contact`, `test_clapper_instakills_on_stomp_from_above`, and `test_clapper_invincible_to_shots` fail/error.

- [ ] **Step 3: Do NOT commit yet**

The tests are red by design (TDD). Implementation lands in Tasks 2–3 before the commit.

---

## Task 2: Clapper script

**Files:**
- Create: `src/runtime/entities/clapper.gd`

- [ ] **Step 1: Create the script**

Create `src/runtime/entities/clapper.gd` with this exact content:

```gdscript
class_name Clapper
extends Hazard
## Stationary, invincible obstacle. Any contact with the player — from the side
## or by jumping on top — instantly kills Keen (drains current health to 0,
## triggering Player.died). Cannot be destroyed: it has no take_damage method,
## so blaster bolts pass through harmlessly (see projectile.gd's has_method guard)
## and stomping deals no damage to it, only to Keen.

func _handle_player(player: Node) -> void:
	if player.has_method("take_damage") and "health" in player:
		player.take_damage(player.health)
```

- [ ] **Step 2: Do NOT run yet**

The behavior test loads the scene (`clapper.tscn`), which doesn't exist. The suite will still fail until Task 3 completes. No intermediate run needed.

---

## Task 3: Clapper scene — make the behavior tests pass

**Files:**
- Create: `src/runtime/entities/clapper.tscn`

The Clapper.png (256×64) is a horizontal strip of **4 frames × 64×64** (verified against `assets/sprites/Clapper.tscn`: regions `Rect2(0,0,64,64)`, `Rect2(64,0,64,64)`, `Rect2(128,0,64,64)`, `Rect2(192,0,64,64)` — exactly fills the sheet). The clap animation plays frames 0→1→2→3→2→1 at 5 FPS, looping (open-clap-open).

- [ ] **Step 1: Create the scene file**

Create `src/runtime/entities/clapper.tscn` with this exact content (no `unique_id` — Godot assigns on save; mirrors `yorp.tscn`/`vorticon.tscn` hand-authoring):

```ini
[gd_scene load_steps=8 format=3]

[ext_resource type="Script" path="res://src/runtime/entities/clapper.gd" id="1_clap"]
[ext_resource type="Texture2D" uid="uid://bc7m7hpu1ssvg" path="res://assets/sprites/Clapper.png" id="2_tex"]

[sub_resource type="AtlasTexture" id="AtlasTexture_f0"]
atlas = ExtResource("2_tex")
region = Rect2(0, 0, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_f1"]
atlas = ExtResource("2_tex")
region = Rect2(64, 0, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_f2"]
atlas = ExtResource("2_tex")
region = Rect2(128, 0, 64, 64)

[sub_resource type="AtlasTexture" id="AtlasTexture_f3"]
atlas = ExtResource("2_tex")
region = Rect2(192, 0, 64, 64)

[sub_resource type="SpriteFrames" id="SpriteFrames_clap"]
animations = [{
"frames": [{
"duration": 1.0,
"texture": SubResource("AtlasTexture_f0")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_f1")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_f2")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_f3")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_f2")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_f1")
}],
"loop": 1,
"name": &"default",
"speed": 5.0
}]

[node name="Clapper" type="CharacterBody2D"]
script = ExtResource("1_clap")

[node name="Visual" type="AnimatedSprite2D" parent="."]
sprite_frames = SubResource("SpriteFrames_clap")
autoplay = "default"
```

`load_steps=8` = 2 ext + 5 sub + 1. The `Visual` child name is the seam `Entity._build_contact()` checks (`src/runtime/entities/entity.gd:52` → skips the `ColorRect` fallback). The `AnimatedSprite2D` is centered at the body origin by default; the runtime-built contact `Area2D` uses a 64×64 `RectangleShape2D` centered at origin (`entity.gd:45-48`), so sprite and hitbox align without offset.

- [ ] **Step 2: Run the suite to confirm the behavior tests pass**

Run: `./tests/run_all.sh`
Expected: `test_clapper_instakills_on_contact`, `test_clapper_instakills_on_stomp_from_above`, and `test_clapper_invincible_to_shots` PASS. No regressions in other tests. (`test_runtime_integration.gd` spawns every registered entity — but `keen1.clapper` is not registered yet, so it is not yet spawned there; still green.)

- [ ] **Step 3: Commit**

```bash
git add src/runtime/entities/clapper.gd src/runtime/entities/clapper.tscn tests/unit/test_concrete_enemies.gd
git commit -m "feat(keen1): add Clapper hazard — stationary invincible instakill

Clapper extends Hazard. Any contact (side or stomp) drains Keen's
current health to 0 via take_damage -> died. No take_damage method on
the Clapper, so blaster bolts pass through (projectile.gd guard).
Visual = 4-frame 64x64 clap loop from Clapper.png."
```

---

## Task 4: Register in episode + registration test

**Files:**
- Modify: `src/episodes/keen1/episode.gd` (preload + register line)
- Modify: `tests/unit/test_episode.gd` (expected types list + category assertion)

- [ ] **Step 1: Add the failing registration test**

In `tests/unit/test_episode.gd`, edit the `test_keen1_registers_expected_types` types list (lines 6–8) to include `"keen1.clapper"`:

```gdscript
	for tid in ["keen1.vorticon", "keen1.yorp", "keen1.butler", "keen1.clapper",
			"keen1.lollipop", "keen1.soda", "keen1.pizza", "keen1.book",
			"keen1.teddy", "keen1.raygun", "keen1.exit_door", "keen1.player_spawn"]:
```

Then in `test_keen1_categories` (lines 11–17), add a Clapper category assertion after the butler line:

```gdscript
	assert_eq(EntityRegistry.get_entry("keen1.clapper")["category"], EntityRegistry.CATEGORY_HAZARD)
```

- [ ] **Step 2: Run the suite to confirm the registration tests fail**

Run: `./tests/run_all.sh`
Expected: `test_keen1_registers_expected_types` and `test_keen1_categories` FAIL — `keen1.clapper` not yet registered.

- [ ] **Step 3: Register the Clapper**

In `src/episodes/keen1/episode.gd` `register_entities()`, add a preload alongside the others (after the `exit_door` preload line, line 22):

```gdscript
	var clapper := preload("res://src/runtime/entities/clapper.tscn")
```

Then add a register call after the butler register line (line 25):

```gdscript
	registry.register("keen1.clapper", registry.CATEGORY_HAZARD, "Clapper", [], clapper)
```

- [ ] **Step 4: Run the full suite — everything green**

Run: `./tests/run_all.sh`
Expected: ALL tests PASS, including:
- `test_clapper_instakills_on_contact`, `test_clapper_instakills_on_stomp_from_above`, `test_clapper_invincible_to_shots` (Task 1)
- `test_keen1_registers_expected_types`, `test_keen1_categories` (Task 4 Step 1)
- `test_register_episodes_populates_catalog_via_disk_scan` (now also finds `keen1.clapper`)
- `test_build_spawns_every_registered_entity_type` in `test_runtime_integration.gd` — now spawns a Clapper; it extends `Hazard extends Entity`, so the `node is Entity` assertion holds and `build()` succeeds without errors.

- [ ] **Step 5: Commit**

```bash
git add src/episodes/keen1/episode.gd tests/unit/test_episode.gd
git commit -m "feat(keen1): register Clapper as keen1.clapper hazard

Adds keen1.clapper to EntityRegistry under CATEGORY_HAZARD so it
appears in the editor palette and spawns in levels. Updates episode
registration tests for the new type."
```

---

## Verification (final)

After all tasks:

- [ ] `./tests/run_all.sh` exits 0 with every test green.
- [ ] `git log --oneline -3` shows two Clapper commits (scene/script/tests, then registration).
- [ ] Optional manual check: open the project editor, confirm `Clapper` appears under the HAZARD palette group in the level editor, place one in a level, run Test ▶, walk into it and jump on it — both kill Keen instantly; shoot it — bolt passes through.

## Out of scope (per spec §6)

- Tile collision for the Clapper (floats at placed position).
- Stun/knockback states (pure hazard, no state machine).
- Death SFX (handled globally elsewhere).
