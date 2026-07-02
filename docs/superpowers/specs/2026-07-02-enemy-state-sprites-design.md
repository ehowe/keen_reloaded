# Enemy State-Driven Sprites — Design Spec

**Date:** 2026-07-02
**Status:** Draft
**Engine:** Godot 4.7 (stable)
**Language:** GDScript
**Scope:** `src/runtime/entities/enemy.gd`, `src/runtime/entities/entity.gd`, concrete enemies (Yorp first), tests.

## 1. Overview

Give enemies multi-state animated visuals driven by behaviour. Every enemy shares the same four visual states — **Walking, Idle, Stunned, Shot** — so the entire state machine (behaviour **and** visual switching) lives in the `Enemy` base class. Concrete enemies (Yorp, Garg, …) become drop-in: they provide a scene with four named `AnimatedSprite2D` nodes plus tuning, and override hooks only for unique flavour.

### Goals

| # | Goal |
|---|------|
| 1 | Universal visual states (Walking/Idle/Stunned/Shot) for all enemies, from one base implementation |
| 2 | Stomp mechanic: Keen landing on an enemy from above **stuns** it (temporary, harmless, recoverable); only the blaster kills |
| 3 | Reusable, hook-driven base so concrete enemies need ~zero code for the common case |
| 4 | No breakage to existing enemies/tests; placeholders remain until art ships |

### Out of Scope

- Per-enemy bespoke AI (charging, flying) — hooks exist for it but specific behaviours are separate specs.
- Particle/audio feedback on stomp/shot (placeholder for a later juice pass).
- New enemy classes beyond wiring up the already-built Yorp sprites.

## 2. Background & Current State

- `Enemy` (`enemy.gd`) extends `Entity`, applies gravity, patrols at `patrol_speed`, turns at walls/ledges, deals contact damage, dies on HP ≤ 0 and awards score.
- `_handle_player(player)` is called by `Entity`'s contact `Area2D` on `body_entered`. Currently a flat override per enemy (Yorp: knockback + damage).
- `take_damage(amount)` decrements HP; the player's `Projectile` calls `take_damage(1)` on hit → instant death for a 1-HP Yorp.
- **There is no stomp/jump-on detection anywhere.** Contact from any direction is treated identically.
- Enemies always patrol (`velocity.x = _dir * patrol_speed` every frame), so there is no natural "Idle" moment today.
- Visuals today are placeholder `ColorRect` fallbacks built by `Entity._build_contact()` when no `"Visual"` child exists.

### Confirmed behaviour decisions (from design session)

- **State set:** Walking (mirrored via `flip_h`), Idle, Stunned, Shot. (User-built Yorp already has four `AnimatedSprite2D` nodes for these.)
- **Stomp:** Keen lands from above → enemy enters **Stunned** for a duration, then **recovers** and resumes wandering. Re-stomping while stunned resets the timer.
- **Stun never kills.** Only the blaster (`take_damage`) kills, triggering the **Shot** death state.
- **Idle trigger:** periodic wandering — walk a stretch, pause (Idle) for a beat, walk the other way.
- **Logic location:** stun/stomp/state-machine/visuals all live in the `Enemy` base (reusable by Vorticon/Butler/Garg/…).

## 3. Architecture

The `Enemy` base becomes a small, hook-driven **state machine** that also owns visual synchronisation. Concrete enemies are data: a scene with four conventionally-named sprite nodes plus `@export` tuning.

### 3.1 State machine (Enemy base)

```
enum State { WALK, IDLE, STUNNED, SHOT }

var _state: State = State.WALK
var _stunned: bool = false        # true while stunned (drives STUNNED visual + harmless contact)
var _stun_timer: float = 0.0
var _dying: bool = false          # true during SHOT death animation, before queue_free
var _phase_timer: float = 0.0     # wander pacing (walk/idle)
```

**State transitions**

```
WALK  --walk_time elapsed-->            IDLE
IDLE  --idle_time elapsed--> flip _dir; WALK
any(non-SHOT) --stomped from above-->   STUNNED (sets _stunned, _stun_timer)
STUNNED --_stun_timer elapsed-->        _on_recover() -> WALK (or prior wander phase)
any --take_damage to HP<=0-->           SHOT (sets _dying) -> score + queue_free()
```

### 3.2 Physics & contact routing

`_physics_process(delta)`:

```
velocity.y = min(velocity.y + gravity*delta, max_fall)
if _dying:
    velocity.x = 0                      # frozen during death anim
elif _stunned:
    velocity.x = 0
    _stun_timer -= delta
    if _stun_timer <= 0.0:
        _stunned = false
        _on_recover()
else:
    _tick_wander(delta)                 # sets WALK vs IDLE + velocity.x; wall/ledge turns
    _ai_tick(delta)                     # subclass hook (default no-op)
move_and_slide()
_sync_visual()
```

`_tick_wander(delta)` (base, generic):

```
_phase_timer -= delta
match _state:
    State.WALK:
        velocity.x = _dir * patrol_speed
        # existing wall/ledge turn logic (turns_at_walls / turns_at_ledges)
        if _phase_timer <= 0.0:
            _enter(State.IDLE); velocity.x = 0; _phase_timer = idle_time
    State.IDLE:
        velocity.x = 0
        if _phase_timer <= 0.0:
            _dir = -_dir                # about-face after a pause
            _enter(State.WALK); _phase_timer = walk_time
```

`_handle_player(player)` becomes a **router** (replaces flat override):

```
if _dying or _stunned:
    return                              # harmless while stunned/dying (no knockback, no damage)
if _is_stomp(player):
    _on_stomped(player)
else:
    _on_side_contact(player)
```

### 3.3 Hooks (overridable, with sensible defaults)

| Hook | Default | Concrete override use |
|------|---------|------------------------|
| `_on_stomped(player)` | `stun(stun_duration)` + bounce player (`velocity.y = -stomp_bounce`) | Butler → no-op (armored) |
| `_on_side_contact(player)` | knockback *away from enemy* (`d = signi(player.global_position.x - global_position.x)`; `player.velocity = Vector2(d*knockback_x, -knockback_y)`) + `player.take_damage(contact_damage)` | enemy that shouldn't knock back |
| `_on_recover()` | resume wander phase (`_state = WALK`) | custom wake-up behaviour |
| `_ai_tick(delta)` | no-op | Garg charging, patrolling variants |
| `_die()` | award `score_value` to player + `queue_free()` | custom death SFX/anim |

`stun(duration)`:

```
_stunned = true; _stun_timer = duration; velocity.x = 0; _state = State.STUNNED
```

`take_damage(amount)` is overridden to route death through the SHOT visual:

```
if _dying: return                       # ignore further hits mid-death
health -= amount
if health <= 0:
    _enter_shot_death()                 # _state=SHOT, _dying=true, freeze, play "Shot" once
```

`_enter_shot_death()`:

```
_dying = true; _state = State.SHOT; velocity = Vector2.ZERO
# play Shot animation; on animation_finished (or a guard timer) -> _die()
```

**Invariant:** stomp calls `stun()`, never `take_damage()`. Therefore only the blaster can reduce HP / kill.

### 3.4 Stomp detection

`_is_stomp(player) -> bool` — heuristic, evaluated at the moment the contact `Area2D` fires `body_entered`:

```
player is CharacterBody2D
and player.velocity.y > 0.0                                  # falling
and player.global_position.y < global_position.y - TILE*0.25 # player centre clearly above enemy centre
```

`TILE` is the existing `Entity.TILE` constant (64). The threshold (¼ tile) tolerates the small overlap present when `body_entered` first fires while still distinguishing a top-down landing from a side collision. Tunable if needed.

### 3.5 Visual synchronisation (Enemy base)

`_ready()` (after `super._ready()`):

```
_cache_sprites()           # find children named Walking/Idle/Stunned/Shot
if _sprites not empty and has_node("Visual"):
    get_node("Visual").queue_free()     # drop Entity's fallback ColorRect
```

`_sync_visual()` — called at end of each `_physics_process`:

```
var active := _state_name_for(_state)          # WALK->"Walking", IDLE->"Idle", ...
for name in _sprites:
    var node = _sprites[name]
    var show := (name == active)
    node.visible = show
    if show:
        # Guard: don't restart an already-playing (esp. one-shot SHOT) animation.
        if not node.is_playing():
            node.play()
        if name == "Walking":
            node.flip_h = (_dir > 0)          # directional art faces movement
    elif node.is_playing():
        node.stop()
```

**Node-name convention** (required, case-sensitive):

| State | AnimatedSprite2D child name | Loop |
|-------|------------------------------|------|
| WALK | `Walking` | yes |
| IDLE | `Idle` | yes |
| STUNNED | `Stunned` | yes |
| SHOT | `Shot` | **no** (one-shot; `_die()` fires on `animation_finished`) |

The `is_playing()` guard means `_sync_visual` never restarts the one-shot Shot animation mid-play.

Only `Walking` is flipped; Idle/Stunned/Shot are assumed forward-facing (symmetric) art. Missing nodes are tolerated — that state simply renders nothing, so a half-built enemy still runs.

### 3.6 Concrete enemy contract

A concrete enemy (e.g. Yorp) contributes:

1. A scene (`.tscn`) whose root extends the enemy script, with four `AnimatedSprite2D` children named per the convention above, each holding its own `SpriteFrames`.
2. `@export` tuning on the base for per-enemy feel.
3. Optional hook overrides for unique behaviour.

**Yorp specifically** needs **no code** beyond the existing class — its knockback/damage now comes free from the base `_on_side_contact` default (same `knockback_x`/`knockback_y`/`contact_damage` values it already declares). The current Yorp `_handle_player` override is removed.

### 3.7 `@export` knobs (Enemy base, with defaults)

| Knob | Default | Purpose |
|------|---------|---------|
| `stun_duration` | `4.0` | seconds stunned after a stomp |
| `walk_time` | `2.5` | seconds of WALK before an IDLE pause |
| `idle_time` | `1.2` | seconds of IDLE before walking again |
| `stomp_bounce` | `520.0` | upward velocity given to player on stomp (`0` = classic no-bounce) |
| `knockback_x` | `400.0` | side-contact knockback X |
| `knockback_y` | `300.0` | side-contact knockback Y |

Existing knobs (`gravity`, `patrol_speed`, `max_fall`, `turns_at_walls`, `turns_at_ledges`, `health`, `contact_damage`, `score_value`) are unchanged.

## 4. Component Changes

### 4.1 `enemy.gd` (major)
- Add `State` enum, state/stun/dying/phase vars.
- Add wander pacing (`_tick_wander`), stun (`stun`), stomp detect (`_is_stomp`), contact router in `_handle_player`, hook defaults (`_on_stomped`/`_on_side_contact`/`_on_recover`/`_ai_tick`/`_die`), shot-death (`_enter_shot_death`), visual cache+sync (`_cache_sprites`/`_sync_visual`), fallback-Visual removal.
- Preserve existing wall/ledge turn logic inside the WALK branch.
- `take_damage` gains the `_dying` guard and SHOT routing; score award moves into `_die()`.

### 4.2 `entity.gd` (no behavioural change)
- Unchanged. Its fallback `ColorRect` "Visual" is still built when no `"Visual"` child exists; `Enemy._ready()` removes it once sprite nodes are present.

### 4.3 `yorp.gd` (shrink)
- Remove the `_handle_player` override (base default covers knockback+damage).
- Keep `class_name`, `extends Enemy`, and the `@export` tuning knobs (`knockback_x/y` already match defaults; `health=1`, `score_value=100`, `patrol_speed=70.0`, `contact_damage=1` set in `_ready`).

### 4.4 `yorp.tscn` (rebuild Visual)
- Replace the `ColorRect` "Visual" child with four `AnimatedSprite2D` nodes named `Walking`, `Idle`, `Stunned`, `Shot`, each wired to its `SpriteFrames` (sourced from `assets/sprites/Yorp 64x96.*`).

## 5. Testing

New `tests/unit/test_enemy_states.gd` (GUT), plus updates as needed:

| Test | Asserts |
|------|---------|
| `test_wander_cycles_walk_idle` | `_phase_timer` expiry flips WALK↔IDLE; `_dir` flips on IDLE→WALK |
| `test_stomp_stuns_and_is_harmless` | falling player from above → `_stunned` true, `_state==STUNNED`; subsequent contact deals no damage |
| `test_stun_recovers` | after `stun_duration`, `_stunned` false and `_on_recover` resumed wander |
| `test_restomp_resets_timer` | stomping while stunned resets `_stun_timer` to full duration |
| `test_stomp_does_not_damage_enemy` | HP unchanged after stomp (only blaster kills) |
| `test_shot_kills_with_shot_state` | `take_damage` to 0 → `_state==SHOT`, `_dying==true`, freed after anim |
| `test_side_contact_knockback_and_damage` | side contact → player knocked back + takes `contact_damage` (replaces old Yorp test) |
| `test_visual_active_node_matches_state` | for each state, only the matching named node is `visible`+playing; `Walking.flip_h` follows `_dir` |

Existing `test_concrete_enemies.gd`:
- `test_yorp_knockback_and_damage` is reframed to side-contact (base `_on_side_contact`) — same assertions (knocked right, 1 contact damage) still hold, now via `_handle_player` with a side-positioned non-falling player.
- Vorticon/Butler tests unchanged (HP/score/armored).

## 6. Sequencing / Fallout

- Base changes land first (state machine + visuals + stun + stomp + shot-death), behind the existing placeholder look — all current enemies keep working via the `ColorRect` fallback until they ship sprites.
- Yorp is the first concrete wiring (its sprites already exist).
- Vorticon/Butler gain Walking/Idle/Stunned/Shot automatically once their four sprite nodes are added (no code).
- Future enemies (Garg, etc.) follow the same contract: scene + tuning + optional hooks.

## 7. Open Questions

- **Stomp bounce feel:** default `stomp_bounce=520` is a guess; tune during playtest (classic Keen has no bounce → set `0`).
- **Shot animation length:** death is gated on the Shot animation's `animation_finished` signal; if a Shot `SpriteFrames` is missing/empty, fall back to a short guard timer (~0.3s) before `_die()`.
- **Stunned-enemy solidity:** stunned Yorp keeps its physics body (stands on floor via gravity) but contact is a no-op. If standing on top re-triggers stomp each frame, the re-stomp simply resets the timer (acceptable, matches "re-stompable").
