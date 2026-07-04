# Clapper Enemy — Design Spec

**Date:** 2026-07-03
**Status:** Approved (pending spec review)
**Engine:** Godot 4.7 (stable)
**Language:** GDScript

## 1. Overview

Add a new Keen 1 enemy, the **Clapper**: a stationary, invincible obstacle. Any
contact with the player — from the side or by jumping on top — instantly kills
Keen. It cannot be destroyed by shooting or stomping.

Mechanically it behaves like a deadly hazard; it is registered under the
`HAZARD` palette category. The art asset already exists at
`assets/sprites/Clapper.png` + `Clapper.aseprite` (1024×256 sprite sheet).

## 2. Behavior

| Property | Value |
|----------|-------|
| Movement | None — stationary for its entire lifetime |
| Gravity / physics | None — does not collide with tiles (uses `Hazard`/`Entity` static-item collision defaults: `layer=items`, `mask=0`) |
| Shootable | No — projectiles pass through harmlessly |
| Stompable | No — landing on it kills Keen (does not stun/bounce the Clapper) |
| Health / death | Invincible — no `take_damage` method |
| Contact effect | Keen dies instantly (health drained to 0) |
| Palette category | `CATEGORY_HAZARD` |

### Contact detection

Reuses the inherited `Entity._build_contact()` Area2D (`collision_mask = player
bit`). `Area2D.body_entered` → `Entity._on_body_entered` → `_handle_player()`.
The Clapper overrides only `_handle_player`. No distinction between side contact
and stomp — both are lethal.

### Projectile interaction

`src/runtime/player/projectile.gd` calls `body.take_damage(1)` only when the
body `has_method("take_damage")`. The Clapper does not implement that method, so
blaster bolts pass straight through with no effect and no crash. No code needed
on the Clapper side for this.

## 3. Instakill mechanism

Player (`src/runtime/player/player.gd`) exposes:

```gdscript
var health: int = 3
signal died

func take_damage(amount: int) -> void:
    health -= amount
    health_changed.emit(health)
    if health <= 0:
        died.emit()
```

The Clapper drains the player's *current* health in one call:

```gdscript
player.take_damage(player.health)
```

This zeroes health regardless of upgrades/max-health changes, then emits the
existing `died` signal. No new player API is introduced.

## 4. Code structure

### 4.1 Script — `src/runtime/entities/clapper.gd`

```gdscript
class_name Clapper
extends Hazard
## Stationary, invincible obstacle. Any contact with the player (side or stomp
## from above) instantly kills Keen. Cannot be destroyed by shooting or
## stomping — projectiles pass through (no take_damage method).

func _handle_player(player: Node) -> void:
    if player.has_method("take_damage") and "health" in player:
        player.take_damage(player.health)
```

`Hazard` already extends `Entity` and provides the red-tinted fallback color;
the real sprite comes from the scene (see 4.2), which suppresses the fallback.

### 4.2 Scene — `src/runtime/entities/clapper.tscn`

- Root: `CharacterBody2D` named `Clapper`, script = `clapper.gd`.
- Child: `AnimatedSprite2D` named `Visual` (the seam name `Entity._build_contact`
  checks — when present, the procedural `ColorRect` fallback is skipped).
  - `sprite_frames`: built from `res://assets/sprites/Clapper.png` regions.
  - Animation: single looping animation (the clapping cycle). Exact frame count,
    region rects, and FPS are confirmed from `Clapper.aseprite` at implementation
    time; the sheet is 1024×256.
- No additional collision children — `Entity._build_contact()` adds the
  `Area2D` + `CollisionShape2D` (64×64 `RectangleShape2D`) at runtime.

### 4.3 Registration — `src/episodes/keen1/episode.gd`

Add to `register_entities()`:

```gdscript
var clapper := preload("res://src/runtime/entities/clapper.tscn")
...
registry.register("keen1.clapper", registry.CATEGORY_HAZARD, "Clapper", [], clapper)
```

Type ID `keen1.clapper` follows the existing `keen1.*` namespacing convention.

## 5. Testing

GUT unit test under `tests/unit/` (extends `GutTest`), following existing enemy
test conventions:

1. **Instakill on contact** — register the Clapper, instantiate it, fake a
   player node entering its contact `Area2D`, assert the player's `died` signal
   fired and `health == 0`.
2. **Invincibility** — assert the Clapper instance has **no** `take_damage`
   method (`not has_method("take_damage")`), mirroring the condition
   `projectile.gd` checks. This documents the shoot-through contract without
   needing to spin up a real projectile.
3. **Stomp is lethal** — simulate a player entering from above (player above
   the Clapper) and assert the same instakill result (no special-case branch in
   the code, but the test pins the behavior against future refactors).

Run `./tests/run_all.sh` — must pass before commit.

## 6. Out of scope

- Tile collision for the Clapper (it floats at its placed position; level
  designer places it precisely). Can revisit if it needs to rest on floors.
- Stun/knockback states — it's a pure hazard, no state machine.
- Sound effects / death SFX (handled by the global plan, not this spec).
