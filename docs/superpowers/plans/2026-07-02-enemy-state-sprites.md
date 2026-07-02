# Enemy State-Driven Sprites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give all enemies four shared animated states (Walking/Idle/Stunned/Shot) driven by a state machine + stomp-to-stun mechanic that live in the `Enemy` base, so concrete enemies (Yorp first) are scene + tuning only.

**Architecture:** `Enemy` base owns: a `State` enum, wander pacing (walk↔idle), stun timer, stomp detection + contact routing, and visual sync that toggles four conventionally-named `AnimatedSprite2D` children. Concrete enemies supply those nodes and tune `@export`s; they override hooks only for unique flavour.

**Tech Stack:** Godot 4.7, GDScript, GUT (vendored in `addons/gut/`).

**Spec:** `docs/superpowers/specs/2026-07-02-enemy-state-sprites-design.md`

**Commands:**
- Full test suite: `make test` (or `./tests/run_all.sh`)
- Single test file: `GODOT="/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot"; "$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gselect=res://tests/unit/TESTFILE.gd -gexit -gdisable_colors`
- Godot binary: `/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot`

**Convention (critical):** AnimatedSprite2D children must be named exactly `Walking`, `Idle`, `Stunned`, `Shot` (case-sensitive). The base looks them up by name.

**Important resolution vs. spec pseudocode:** The spec's `_handle_player` sketch (`if _dying or _stunned: return`) contradicted its "re-stomp resets timer" rule. This plan implements the intent: a **stomp is always allowed** (refreshes/starts stun even if already stunned); only a **side contact is ignored** while stunned. Also: an enemy with **no Shot art dies immediately** (keeps Vorticon/Butler behaviour and their tests green); only enemies with a `Shot` sprite defer death for the animation.

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `src/runtime/entities/enemy.gd` | Modify (major) | State machine, wander, stun, stomp, shot-death, visual sync |
| `src/runtime/entities/yorp.gd` | Modify (shrink) | Remove `_handle_player` override + duplicate `knockback_*` exports |
| `src/runtime/entities/yorp.tscn` | Modify | Replace `ColorRect` with 4 `AnimatedSprite2D` children (merge from `assets/sprites/Yorp.tscn`) |
| `tests/unit/test_enemy_states.gd` | Create | New GUT tests for the base behaviour + visuals |

`entity.gd`, `vorticon.gd`, `butler.gd` are **not modified**.

---

## Reference: final `enemy.gd` (target after Tasks 1–4)

> This is the complete target file. Tasks 1–4 build it incrementally with tests; each task shows the exact code it adds. If you prefer, you may write this whole file once and then add the tests — but the tasks below follow strict TDD ordering.

```gdscript
class_name Enemy
extends Entity
## Physics-enabled enemy base with state-driven animated visuals. Applies
## gravity + a wander patrol (walk stretch / idle pause), turns at walls and
## (optionally) ledges, deals contact damage, can be stunned by a stomp from
## above (harmless + recoverable), and dies via a Shot animation when its HP
## hits 0. Concrete enemies supply four AnimatedSprite2D children named
## Walking/Idle/Stunned/Shot and tune the @export knobs; they override the hook
## methods only for unique flavour (e.g. Butler._on_stomped = no-op).

enum State { WALK, IDLE, STUNNED, SHOT }

const SPRITE_NAMES := {
	State.WALK: "Walking",
	State.IDLE: "Idle",
	State.STUNNED: "Stunned",
	State.SHOT: "Shot",
}

@export var gravity: float = 3920.0
@export var patrol_speed: float = 120.0
@export var max_fall: float = 1920.0
@export var turns_at_walls: bool = true
@export var turns_at_ledges: bool = true
@export var stun_duration: float = 4.0
@export var walk_time: float = 2.5
@export var idle_time: float = 1.2
@export var stomp_bounce: float = 520.0
@export var knockback_x: float = 400.0
@export var knockback_y: float = 300.0

var health: int = 1
var contact_damage: int = 1
var score_value: int = 100

var _dir: int = -1
var _state: State = State.WALK
var _phase_timer: float = 0.0
var _stunned: bool = false
var _stun_timer: float = 0.0
var _dying: bool = false
var _dead: bool = false
var _sprites: Dictionary = {}


func _ready() -> void:
	super._ready()
	collision_layer = 2  # enemies
	collision_mask = 4   # tiles
	if not has_node("BodyShape"):
		var s := CollisionShape2D.new()
		s.name = "BodyShape"
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE * 0.8, TILE * 0.9)
		s.shape = rect
		add_child(s)
	if not has_node("LedgeProbe"):
		var rc := RayCast2D.new()
		rc.name = "LedgeProbe"
		rc.enabled = true
		rc.target_position = Vector2(_dir * TILE * 0.5, TILE * 0.6)
		add_child(rc)
	_phase_timer = walk_time
	_cache_sprites()


func _cache_sprites() -> void:
	_sprites.clear()
	for state in SPRITE_NAMES:
		var n := get_node_or_null(SPRITE_NAMES[state]) as AnimatedSprite2D
		if n != null:
			_sprites[SPRITE_NAMES[state]] = n
			n.stop()
	# Drop Entity's placeholder ColorRect once real art is present.
	if _sprites.size() > 0 and has_node("Visual"):
		get_node("Visual").queue_free()


func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta
	if velocity.y > max_fall:
		velocity.y = max_fall
	if _dying:
		velocity.x = 0.0
	elif _stunned:
		velocity.x = 0.0
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_stunned = false
			_on_recover()
	else:
		_tick_wander(delta)
		_ai_tick(delta)
	move_and_slide()
	_sync_visual()


func _tick_wander(delta: float) -> void:
	_phase_timer -= delta
	match _state:
		State.WALK:
			velocity.x = _dir * patrol_speed
			_turn_if_blocked()
			if _phase_timer <= 0.0:
				_state = State.IDLE
				velocity.x = 0.0
				_phase_timer = idle_time
		State.IDLE:
			velocity.x = 0.0
			if _phase_timer <= 0.0:
				_dir = -_dir
				_state = State.WALK
				_phase_timer = walk_time


func _turn_if_blocked() -> void:
	if turns_at_walls and is_on_wall():
		_dir = -_dir
	elif turns_at_ledges:
		var rc := get_node_or_null("LedgeProbe") as RayCast2D
		if rc != null:
			rc.target_position = Vector2(_dir * TILE * 0.5, TILE * 0.6)
			rc.force_raycast_update()
			if is_on_floor() and not rc.is_colliding():
				_dir = -_dir


func _sync_visual() -> void:
	var active: String = SPRITE_NAMES.get(_state, "")
	for name in _sprites:
		var n: AnimatedSprite2D = _sprites[name]
		var show: bool = (name == active)
		n.visible = show
		if show:
			if _state != State.SHOT and not n.is_playing() and n.sprite_frames != null:
				n.play()
			if name == "Walking":
				n.flip_h = _dir > 0
		elif n.is_playing():
			n.stop()


## Hook: per-frame AI tick while wandering (default no-op). Override for charging, etc.
func _ai_tick(_delta: float) -> void:
	pass


## Stun this enemy for `duration` seconds (harmless + frozen, then recovers).
func stun(duration: float) -> void:
	_stunned = true
	_stun_timer = duration
	velocity.x = 0.0
	_state = State.STUNNED


func _is_stomp(player: Node) -> bool:
	if player is CharacterBody2D:
		var cb := player as CharacterBody2D
		return cb.velocity.y > 0.0 and cb.global_position.y < global_position.y - TILE * 0.25
	return false


func _handle_player(player: Node) -> void:
	if _dying:
		return
	if _is_stomp(player):
		_on_stomped(player)
	elif not _stunned:
		_on_side_contact(player)
	# else: side contact while stunned -> harmless (ignored)


## Hook: landed on from above. Default = stun + bounce the player up.
func _on_stomped(player: Node) -> void:
	stun(stun_duration)
	if player is CharacterBody2D and stomp_bounce > 0.0:
		(player as CharacterBody2D).velocity.y = -stomp_bounce


## Hook: touched from the side. Default = knockback away + contact damage.
func _on_side_contact(player: Node) -> void:
	if player is CharacterBody2D:
		var d := signi(player.global_position.x - global_position.x)
		(player as CharacterBody2D).velocity = Vector2(d * knockback_x, -knockback_y)
	if player.has_method("take_damage"):
		player.take_damage(contact_damage)


## Hook: just recovered from being stunned. Default = resume walking.
func _on_recover() -> void:
	_state = State.WALK
	_phase_timer = walk_time


func take_damage(amount: int) -> void:
	if _dying or _dead:
		return
	health -= amount
	if health <= 0:
		_enter_shot_death()


func _enter_shot_death() -> void:
	_dying = true
	velocity = Vector2.ZERO
	_state = State.SHOT
	var shot := _sprites.get("Shot") as AnimatedSprite2D
	if shot != null and shot.sprite_frames != null and shot.sprite_frames.get_animation_count() > 0:
		shot.visible = true
		if not shot.is_playing():
			shot.play()
		if not shot.animation_finished.is_connected(_on_shot_finished):
			shot.animation_finished.connect(_on_shot_finished)
		# Fallback in case the one-shot animation never signals completion.
		get_tree().create_timer(0.6).timeout.connect(_die)
	else:
		_die()  # no death art -> die immediately (keeps Vorticon/Butler behaviour)


func _on_shot_finished() -> void:
	_die()


## Idempotent death: awards score once, then frees the node.
func _die() -> void:
	if _dead:
		return
	_dead = true
	var tree := get_tree()
	if tree != null:
		var p := tree.get_first_node_in_group("player")
		if p != null and p.has_method("add_score"):
			p.add_score(score_value)
	queue_free()


func _color() -> Color:
	return Color(0.9, 0.4, 0.6, 1)
```

---

## Task 1: Visual state machine (enum, sprite cache, sync)

Add the `State` enum, sprite-name map, sprite caching (with placeholder-ColorRect removal), and `_sync_visual()`. Wire `_sync_visual()` into `_physics_process`. No behaviour change yet — the enemy still always patrols; `_state` stays `WALK`.

**Files:**
- Modify: `src/runtime/entities/enemy.gd`
- Create: `tests/unit/test_enemy_states.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_enemy_states.gd`:

```gdscript
extends GutTest


class FakePlayer extends CharacterBody2D:
	var health: int = 3
	var score: int = 0
	func _ready() -> void:
		add_to_group("player")
	func take_damage(amount: int) -> void:
		health -= amount
	func add_score(amount: int) -> void:
		score += amount


func _new_enemy() -> Enemy:
	var e := Enemy.new()
	add_child_autofree(e)
	return e


func _add_sprite(enemy: Node, pname: String) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.name = pname
	enemy.add_child(s)
	return s


func test_visual_active_node_matches_state():
	var e := _new_enemy()
	var walk := _add_sprite(e, "Walking")
	var idle := _add_sprite(e, "Idle")
	var stunned := _add_sprite(e, "Stunned")
	var shot := _add_sprite(e, "Shot")
	e._cache_sprites()

	e._dir = 1
	e._state = Enemy.State.WALK
	e._sync_visual()
	assert_true(walk.visible, "Walking visible in WALK")
	assert_false(idle.visible, "Idle hidden in WALK")
	assert_true(walk.flip_h, "Walking flips when _dir>0")

	e._state = Enemy.State.IDLE
	e._sync_visual()
	assert_true(idle.visible, "Idle visible in IDLE")
	assert_false(walk.visible, "Walking hidden in IDLE")

	e._state = Enemy.State.STUNNED
	e._sync_visual()
	assert_true(stunned.visible, "Stunned visible in STUNNED")

	e._state = Enemy.State.SHOT
	e._sync_visual()
	assert_true(shot.visible, "Shot visible in SHOT")


func test_cache_sprites_drops_placeholder_visual():
	var e := _new_enemy()
	# Entity._ready built a fallback ColorRect named "Visual".
	assert_true(e.has_node("Visual"), "placeholder Visual exists")
	_add_sprite(e, "Walking")
	_add_sprite(e, "Idle")
	_add_sprite(e, "Stunned")
	_add_sprite(e, "Shot")
	e._cache_sprites()
	await get_tree().process_frame  # let queue_free take effect
	assert_false(e.has_node("Visual"), "placeholder Visual removed once sprites exist")
```

- [ ] **Step 2: Run test to verify it fails**

```
GODOT="/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gselect=res://tests/unit/test_enemy_states.gd -gexit -gdisable_colors
```
Expected: FAIL — `Enemy.State` / `_cache_sprites` / `_sync_visual` do not exist.

- [ ] **Step 3: Implement the visual layer**

In `src/runtime/entities/enemy.gd`:

1. After the existing `@export`/`var` block, add the enum, the sprite-name map, and the new state vars:

```gdscript
enum State { WALK, IDLE, STUNNED, SHOT }

const SPRITE_NAMES := {
	State.WALK: "Walking",
	State.IDLE: "Idle",
	State.STUNNED: "Stunned",
	State.SHOT: "Shot",
}
```

Add these vars (alongside the existing `_dir`):

```gdscript
var _state: State = State.WALK
var _phase_timer: float = 0.0
var _stunned: bool = false
var _stun_timer: float = 0.0
var _dying: bool = false
var _dead: bool = false
var _sprites: Dictionary = {}
```

2. At the end of `_ready()`, append:

```gdscript
	_phase_timer = walk_time
	_cache_sprites()
```

3. Add the `_cache_sprites()` and `_sync_visual()` methods (e.g. after `_ready`):

```gdscript
func _cache_sprites() -> void:
	_sprites.clear()
	for state in SPRITE_NAMES:
		var n := get_node_or_null(SPRITE_NAMES[state]) as AnimatedSprite2D
		if n != null:
			_sprites[SPRITE_NAMES[state]] = n
			n.stop()
	if _sprites.size() > 0 and has_node("Visual"):
		get_node("Visual").queue_free()


func _sync_visual() -> void:
	var active: String = SPRITE_NAMES.get(_state, "")
	for name in _sprites:
		var n: AnimatedSprite2D = _sprites[name]
		var show: bool = (name == active)
		n.visible = show
		if show:
			if _state != State.SHOT and not n.is_playing() and n.sprite_frames != null:
				n.play()
			if name == "Walking":
				n.flip_h = _dir > 0
		elif n.is_playing():
			n.stop()
```

4. At the end of the existing `_physics_process`, add one line (keep all current patrol logic for now):

```gdscript
	_sync_visual()
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: PASS (2 tests).

- [ ] **Step 5: Run full suite**

`make test` — Expected: all green (no behaviour changed).

- [ ] **Step 6: Commit**

```bash
git add src/runtime/entities/enemy.gd tests/unit/test_enemy_states.gd
git commit -m "feat(enemy): state enum + sprite cache/visual sync"
```

---

## Task 2: Wander pacing (walk ↔ idle)

Replace always-on patrol with periodic walk/idle phases. Extract turning into `_turn_if_blocked()`.

**Files:**
- Modify: `src/runtime/entities/enemy.gd`
- Modify: `tests/unit/test_enemy_states.gd` (append)

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_enemy_states.gd`:

```gdscript
func test_wander_cycles_walk_then_idle():
	var e := _new_enemy()
	e.walk_time = 0.2
	e.idle_time = 0.1
	e._phase_timer = e.walk_time
	e._state = Enemy.State.WALK
	assert_eq(e._dir, -1, "starts facing left")

	e._tick_wander(0.3)  # walk_time elapsed -> IDLE
	assert_eq(e._state, Enemy.State.IDLE, "enters IDLE after walk_time")
	assert_eq(e.velocity.x, 0.0, "stopped while idle")

	e._tick_wander(0.1)  # idle_time elapsed -> WALK, about-face
	assert_eq(e._state, Enemy.State.WALK, "back to WALK after idle_time")
	assert_eq(e._dir, 1, "reversed facing after idle")


func test_walk_phase_moves_at_patrol_speed():
	var e := _new_enemy()
	e.patrol_speed = 200.0
	e._state = Enemy.State.WALK
	e._phase_timer = 1.0
	e._dir = 1
	e._tick_wander(0.05)
	assert_eq(e.velocity.x, 200.0, "walks right at patrol_speed")
```

- [ ] **Step 2: Run tests to verify they fail**

Same `-gselect` command. Expected: FAIL — `_tick_wander` does not exist.

- [ ] **Step 3: Implement wander**

In `src/runtime/entities/enemy.gd`:

1. Replace the patrol block inside `_physics_process`. The current body is:

```gdscript
	velocity.x = _dir * patrol_speed
	if turns_at_walls and is_on_wall():
		_dir = -_dir
	elif turns_at_ledges:
		var rc := get_node_or_null("LedgeProbe") as RayCast2D
		if rc != null:
			rc.target_position = Vector2(_dir * TILE * 0.5, TILE * 0.6)
			rc.force_raycast_update()
			if is_on_floor() and not rc.is_colliding():
				_dir = -_dir
	_ai_tick(delta)
```

Replace it with:

```gdscript
	_tick_wander(delta)
	_ai_tick(delta)
```

2. Add `_tick_wander()` and `_turn_if_blocked()` (the turn logic moves here verbatim from the old block):

```gdscript
func _tick_wander(delta: float) -> void:
	_phase_timer -= delta
	match _state:
		State.WALK:
			velocity.x = _dir * patrol_speed
			_turn_if_blocked()
			if _phase_timer <= 0.0:
				_state = State.IDLE
				velocity.x = 0.0
				_phase_timer = idle_time
		State.IDLE:
			velocity.x = 0.0
			if _phase_timer <= 0.0:
				_dir = -_dir
				_state = State.WALK
				_phase_timer = walk_time


func _turn_if_blocked() -> void:
	if turns_at_walls and is_on_wall():
		_dir = -_dir
	elif turns_at_ledges:
		var rc := get_node_or_null("LedgeProbe") as RayCast2D
		if rc != null:
			rc.target_position = Vector2(_dir * TILE * 0.5, TILE * 0.6)
			rc.force_raycast_update()
			if is_on_floor() and not rc.is_colliding():
				_dir = -_dir
```

- [ ] **Step 4: Run tests to verify they pass**

Same command. Expected: PASS (4 tests total).

- [ ] **Step 5: Run full suite**

`make test` — Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add src/runtime/entities/enemy.gd tests/unit/test_enemy_states.gd
git commit -m "feat(enemy): wander pacing (walk/idle phases)"
```

---

## Task 3: Stun + stomp routing + contact hooks

Add the stun mechanism, stomp detection, the `_handle_player` router, and the default hooks (`_on_stomped`, `_on_side_contact`, `_on_recover`). Add the stunned branch to `_physics_process`.

**Files:**
- Modify: `src/runtime/entities/enemy.gd`
- Modify: `tests/unit/test_enemy_states.gd` (append)

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_enemy_states.gd`:

```gdscript
func _fake_player() -> FakePlayer:
	var p := FakePlayer.new()
	add_child_autofree(p)
	return p


func test_stun_freezes_and_marks_state():
	var e := _new_enemy()
	e.velocity.x = 123.0
	e.stun(4.0)
	assert_true(e._stunned, "stunned flag set")
	assert_eq(e._state, Enemy.State.STUNNED, "state STUNNED")
	assert_eq(e._stun_timer, 4.0, "timer set")
	assert_eq(e.velocity.x, 0.0, "frozen")


func test_stun_recovers_after_duration():
	var e := _new_enemy()
	e.stun(0.2)
	assert_true(e._stunned)
	e._physics_process(0.3)  # stun timer elapses
	assert_false(e._stunned, "no longer stunned")
	assert_eq(e._state, Enemy.State.WALK, "resumed walking")


func test_stomp_from_above_stuns_without_damage():
	var e := _new_enemy()
	e.global_position = Vector2(0, 0)
	var p := _fake_player()
	p.global_position = Vector2(0, -40)  # above
	p.velocity = Vector2(0, 500)         # falling
	e._handle_player(p)
	assert_true(e._stunned, "stomped -> stunned")
	assert_eq(e.health, 1, "stomp does not damage enemy")
	assert_eq(p.health, 3, "stomp does not damage player")
	assert_lt(p.velocity.y, 0.0, "player bounced up")


func test_restomp_refreshes_timer():
	var e := _new_enemy()
	e.stun(4.0)
	e._physics_process(1.0)            # timer 4.0 -> 3.0
	var p := _fake_player()
	p.global_position = Vector2(0, -40)
	p.velocity = Vector2(0, 500)
	e._handle_player(p)                # restomp
	assert_approx(e._stun_timer, 4.0, 0.001, "timer refreshed to full")


func test_side_contact_knockback_and_damage():
	var e := _new_enemy()
	e.global_position = Vector2(100, 0)
	var p := _fake_player()
	p.global_position = Vector2(200, 0)  # to the right
	p.velocity = Vector2(0, 0)           # not falling
	e._handle_player(p)
	assert_gt(p.velocity.x, 0.0, "knocked right (away from enemy)")
	assert_eq(p.health, 2, "took 1 contact damage")


func test_side_contact_ignored_while_stunned():
	var e := _new_enemy()
	e.global_position = Vector2(100, 0)
	e.stun(4.0)
	var p := _fake_player()
	p.global_position = Vector2(200, 0)
	p.velocity = Vector2(0, 0)
	e._handle_player(p)
	assert_eq(p.health, 3, "harmless while stunned")
	assert_eq(p.velocity.x, 0.0, "no knockback while stunned")
```

- [ ] **Step 2: Run tests to verify they fail**

Same command. Expected: FAIL — `stun`, `_is_stomp`, `_on_stomped`, `_on_side_contact`, `_on_recover` do not exist; `_handle_player` still does old behaviour.

- [ ] **Step 3: Implement stun + routing**

In `src/runtime/entities/enemy.gd`:

1. Add the stunned branch to `_physics_process`, immediately after the `if _dying:` block (the `_dying` branch is added in Task 4; if it doesn't exist yet, just add the `_elif _stunned:` shown here after the gravity/clamp lines and before the `else:` that calls `_tick_wander`). Insert before the existing `else:` wander branch:

```gdscript
	elif _stunned:
		velocity.x = 0.0
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_stunned = false
			_on_recover()
```

So the dispatch reads (after Task 4 it will also include `if _dying:`):

```gdscript
	if _stunned:
		velocity.x = 0.0
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_stunned = false
			_on_recover()
	else:
		_tick_wander(delta)
		_ai_tick(delta)
```

2. **Replace** the existing `_handle_player` method entirely with the router + hooks:

```gdscript
func stun(duration: float) -> void:
	_stunned = true
	_stun_timer = duration
	velocity.x = 0.0
	_state = State.STUNNED


func _is_stomp(player: Node) -> bool:
	if player is CharacterBody2D:
		var cb := player as CharacterBody2D
		return cb.velocity.y > 0.0 and cb.global_position.y < global_position.y - TILE * 0.25
	return false


func _handle_player(player: Node) -> void:
	if _dying:
		return
	if _is_stomp(player):
		_on_stomped(player)
	elif not _stunned:
		_on_side_contact(player)
	# else: side contact while stunned -> harmless (ignored)


## Hook: landed on from above. Default = stun + bounce the player up.
func _on_stomped(player: Node) -> void:
	stun(stun_duration)
	if player is CharacterBody2D and stomp_bounce > 0.0:
		(player as CharacterBody2D).velocity.y = -stomp_bounce


## Hook: touched from the side. Default = knockback away + contact damage.
func _on_side_contact(player: Node) -> void:
	if player is CharacterBody2D:
		var d := signi(player.global_position.x - global_position.x)
		(player as CharacterBody2D).velocity = Vector2(d * knockback_x, -knockback_y)
	if player.has_method("take_damage"):
		player.take_damage(contact_damage)


## Hook: just recovered from being stunned. Default = resume walking.
func _on_recover() -> void:
	_state = State.WALK
	_phase_timer = walk_time
```

- [ ] **Step 4: Run tests to verify they pass**

Same command. Expected: PASS (10 tests total).

- [ ] **Step 5: Run full suite**

`make test` — Expected: all green. (The existing `test_yorp_knockback_and_damage` still passes because Yorp still has its own `_handle_player` override at this point — Task 5 removes it.)

- [ ] **Step 6: Commit**

```bash
git add src/runtime/entities/enemy.gd tests/unit/test_enemy_states.gd
git commit -m "feat(enemy): stun + stomp-to-stun + contact routing"
```

---

## Task 4: Shot death (take_damage → SHOT → die)

Override `take_damage` to route lethal hits through the SHOT animation, with immediate death when there is no `Shot` art (preserves Vorticon/Butler behaviour and tests).

**Files:**
- Modify: `src/runtime/entities/enemy.gd`
- Modify: `tests/unit/test_enemy_states.gd` (append)

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_enemy_states.gd`:

```gdscript
func test_no_shot_art_dies_immediately():
	var e := _new_enemy()  # no Shot sprite
	e.score_value = 100
	var p := _fake_player()
	e.take_damage(1)
	assert_true(e.is_queued_for_deletion(), "freed immediately with no death art")
	assert_eq(p.score, 100, "score awarded")


func test_shot_art_defers_death_and_marks_dying():
	var e := _new_enemy()
	var shot := _add_sprite(e, "Shot")
	var frames := SpriteFrames.new()
	frames.add_animation(&"default")
	frames.add_frame(&"default", load("res://assets/sprites/Yorp 64x96.png"))
	shot.sprite_frames = frames
	e._cache_sprites()
	e.take_damage(1)
	assert_true(e._dying, "dying flag set")
	assert_eq(e._state, Enemy.State.SHOT, "state SHOT")
	assert_false(e.is_queued_for_deletion(), "not freed until anim/timer completes")


func test_take_damage_ignored_once_dying():
	var e := _new_enemy()
	e.score_value = 50
	var p := _fake_player()
	e.take_damage(1)   # dies immediately (no art)
	var score_before := p.score
	e.take_damage(1)   # ignored
	assert_eq(p.score, score_before, "no double score on repeat hit")


func test_die_is_idempotent():
	var e := _new_enemy()
	e.score_value = 100
	var p := _fake_player()
	e._die()
	e._die()
	assert_true(e.is_queued_for_deletion(), "freed once")
	assert_eq(p.score, 100, "score awarded exactly once")
```

- [ ] **Step 2: Run tests to verify they fail**

Same command. Expected: FAIL — `_dying`/`_dead` not used by `take_damage`; `_enter_shot_death`/`_die` don't exist.

- [ ] **Step 3: Implement shot death**

In `src/runtime/entities/enemy.gd`:

1. Add the `_dying` branch to the top of `_physics_process`'s dispatch (before `if _stunned:`):

```gdscript
	if _dying:
		velocity.x = 0.0
	elif _stunned:
```

2. **Replace** the existing `take_damage` method with:

```gdscript
func take_damage(amount: int) -> void:
	if _dying or _dead:
		return
	health -= amount
	if health <= 0:
		_enter_shot_death()


func _enter_shot_death() -> void:
	_dying = true
	velocity = Vector2.ZERO
	_state = State.SHOT
	var shot := _sprites.get("Shot") as AnimatedSprite2D
	if shot != null and shot.sprite_frames != null and shot.sprite_frames.get_animation_count() > 0:
		shot.visible = true
		if not shot.is_playing():
			shot.play()
		if not shot.animation_finished.is_connected(_on_shot_finished):
			shot.animation_finished.connect(_on_shot_finished)
		get_tree().create_timer(0.6).timeout.connect(_die)
	else:
		_die()  # no death art -> die immediately


func _on_shot_finished() -> void:
	_die()


## Idempotent death: awards score once, then frees the node.
func _die() -> void:
	if _dead:
		return
	_dead = true
	var tree := get_tree()
	if tree != null:
		var p := tree.get_first_node_in_group("player")
		if p != null and p.has_method("add_score"):
			p.add_score(score_value)
	queue_free()
```

- [ ] **Step 4: Run tests to verify they pass**

Same command. Expected: PASS (14 tests total).

- [ ] **Step 5: Run full suite**

`make test` — Expected: all green. `test_vorticon_has_three_hp_and_awards_score` still passes (Vorticon has no Shot art ⇒ immediate `_die()` ⇒ score awarded + queued, exactly as before).

- [ ] **Step 6: Commit**

```bash
git add src/runtime/entities/enemy.gd tests/unit/test_enemy_states.gd
git commit -m "feat(enemy): shot death animation (immediate when no art)"
```

---

## Task 5: Yorp cleanup (use base behaviour)

Remove Yorp's `_handle_player` override and its duplicate `knockback_*` exports so it inherits the base contact routing (knockback + damage) for free. Yorp becomes scene + tuning only.

**Files:**
- Modify: `src/runtime/entities/yorp.gd`
- Modify: `tests/unit/test_concrete_enemies.gd` (no code change expected — verify it still passes)

- [ ] **Step 1: Verify the existing Yorp test still encodes the contract**

Read `tests/unit/test_concrete_enemies.gd:41` — `test_yorp_knockback_and_damage` calls `y._handle_player(p)` with a non-falling player to the right and asserts knockback-right + 1 contact damage. After removing the override, the base `_on_side_contact` must satisfy the same assertions. No edit needed; this is the guard.

- [ ] **Step 2: Shrink `yorp.gd`**

Replace the entire contents of `src/runtime/entities/yorp.gd` with:

```gdscript
class_name Yorp
extends Enemy
## Keen 1 Yorp: slow patrol; on side contact knocks the player back and deals
## minor damage; a stomp from above stuns it (recoverable); 1 blaster hit to
## defeat. All behaviour comes from the Enemy base; this class only tunes knobs.


func _ready() -> void:
	super._ready()
	health = 1
	score_value = 100
	patrol_speed = 70.0
	contact_damage = 1
```

(This drops the `@export var knockback_x/knockback_y` and the `_handle_player` override — the base now provides both with identical defaults: knockback 400/300, contact damage 1.)

- [ ] **Step 3: Run the concrete-enemy tests**

```
GODOT="/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gselect=res://tests/unit/test_concrete_enemies.gd -gexit -gdisable_colors
```
Expected: PASS — `test_yorp_knockback_and_damage` passes via the base router (player not falling ⇒ side contact).

- [ ] **Step 4: Run full suite**

`make test` — Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add src/runtime/entities/yorp.gd
git commit -m "refactor(yorp): inherit contact/stun/shot behaviour from Enemy base"
```

---

## Task 6: Wire the Yorp sprites into the runtime scene

Replace the `ColorRect` placeholder in the runtime `yorp.tscn` with the four `AnimatedSprite2D` nodes (merged from `assets/sprites/Yorp.tscn`), renaming `Standing still` → `Idle`. Guarded by a scene-instantiation test.

**Files:**
- Modify: `src/runtime/entities/yorp.tscn`
- Create: `tests/unit/test_yorp_scene.gd`

- [ ] **Step 1: Write the failing scene test**

Create `tests/unit/test_yorp_scene.gd`:

```gdscript
extends GutTest


func test_yorp_scene_has_four_named_sprites_no_placeholder():
	var y: Yorp = add_child_autofree(load("res://src/runtime/entities/yorp.tscn").instantiate())
	assert_false(y.has_node("Visual"), "no ColorRect placeholder")
	for pname in ["Walking", "Idle", "Stunned", "Shot"]:
		var n := y.get_node_or_null(pname)
		assert_not_null(n, "%s node present" % pname)
		assert_true(n is AnimatedSprite2D, "%s is AnimatedSprite2D" % pname)


func test_yorp_shot_animation_is_one_shot():
	var y: Yorp = add_child_autofree(load("res://src/runtime/entities/yorp.tscn").instantiate())
	var shot := y.get_node("Shot") as AnimatedSprite2D
	assert_not_null(shot.sprite_frames, "Shot has SpriteFrames")
	var loop: bool = shot.sprite_frames.get_animation_loop(&"default")
	assert_false(loop, "Shot must be non-looping (one-shot)")
```

- [ ] **Step 2: Run test to verify it fails**

```
GODOT="/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gselect=res://tests/unit/test_yorp_scene.gd -gexit -gdisable_colors
```
Expected: FAIL — runtime `yorp.tscn` still has `Visual` ColorRect and no sprite children.

- [ ] **Step 3: Rewrite the runtime scene**

Replace the entire contents of `src/runtime/entities/yorp.tscn` with (merges the `CharacterBody2D`+script root with the four sprite subtrees from `assets/sprites/Yorp.tscn`, with `Standing still` renamed to `Idle`):

```
[gd_scene load_steps=15 format=3]

[ext_resource type="Script" path="res://src/runtime/entities/yorp.gd" id="1_yorp"]
[ext_resource type="Texture2D" uid="uid://c5ahtje68vwpw" path="res://assets/sprites/Yorp 64x96.png" id="2_tex"]

[sub_resource type="AtlasTexture" id="AtlasTexture_82yae"]
atlas = ExtResource("2_tex")
region = Rect2(136, 0, 64, 96)

[sub_resource type="AtlasTexture" id="AtlasTexture_yf8by"]
atlas = ExtResource("2_tex")
region = Rect2(204, 0, 64, 96)

[sub_resource type="AtlasTexture" id="AtlasTexture_t6m28"]
atlas = ExtResource("2_tex")
region = Rect2(272, 0, 64, 96)

[sub_resource type="AtlasTexture" id="AtlasTexture_6ugff"]
atlas = ExtResource("2_tex")
region = Rect2(340, 0, 64, 96)

[sub_resource type="SpriteFrames" id="SpriteFrames_x4u6v"]
animations = [{
"frames": [{
"duration": 1.0,
"texture": SubResource("AtlasTexture_82yae")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_yf8by")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_t6m28")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_6ugff")
}],
"loop": true,
"name": &"default",
"speed": 5.0
}]

[sub_resource type="AtlasTexture" id="AtlasTexture_vb0e6"]
atlas = ExtResource("2_tex")
region = Rect2(0, 0, 64, 96)

[sub_resource type="AtlasTexture" id="AtlasTexture_tki2i"]
atlas = ExtResource("2_tex")
region = Rect2(68, 0, 64, 96)

[sub_resource type="SpriteFrames" id="SpriteFrames_07erc"]
animations = [{
"frames": [{
"duration": 1.0,
"texture": SubResource("AtlasTexture_vb0e6")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_tki2i")
}],
"loop": true,
"name": &"default",
"speed": 5.0
}]

[sub_resource type="AtlasTexture" id="AtlasTexture_b4o2e"]
atlas = ExtResource("2_tex")
region = Rect2(408, 0, 64, 96)

[sub_resource type="AtlasTexture" id="AtlasTexture_los54"]
atlas = ExtResource("2_tex")
region = Rect2(476, 0, 64, 96)

[sub_resource type="SpriteFrames" id="SpriteFrames_qccdw"]
animations = [{
"frames": [{
"duration": 1.0,
"texture": SubResource("AtlasTexture_b4o2e")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_los54")
}],
"loop": true,
"name": &"default",
"speed": 5.0
}]

[sub_resource type="AtlasTexture" id="AtlasTexture_ln05h"]
atlas = ExtResource("2_tex")
region = Rect2(544, 0, 64, 96)

[sub_resource type="AtlasTexture" id="AtlasTexture_b38o3"]
atlas = ExtResource("2_tex")
region = Rect2(612, 0, 64, 96)

[sub_resource type="SpriteFrames" id="SpriteFrames_f7soo"]
animations = [{
"frames": [{
"duration": 1.0,
"texture": SubResource("AtlasTexture_ln05h")
}, {
"duration": 1.0,
"texture": SubResource("AtlasTexture_b38o3")
}],
"loop": false,
"name": &"default",
"speed": 5.0
}]

[node name="Yorp" type="CharacterBody2D"]
script = ExtResource("1_yorp")

[node name="Idle" type="AnimatedSprite2D" parent="."]
visible = false
sprite_frames = SubResource("SpriteFrames_x4u6v")

[node name="Walking" type="AnimatedSprite2D" parent="."]
visible = false
sprite_frames = SubResource("SpriteFrames_07erc")

[node name="Stunned" type="AnimatedSprite2D" parent="."]
visible = false
sprite_frames = SubResource("SpriteFrames_qccdw")

[node name="Shot" type="AnimatedSprite2D" parent="."]
visible = false
sprite_frames = SubResource("SpriteFrames_f7soo")
```

> The `unique_id=` fields present in `assets/sprites/Yorp.tscn` are intentionally omitted here — they are non-standard for the runtime scene (the original runtime `yorp.tscn` never had them) and Godot loads the scene fine without them.

- [ ] **Step 4: Import + run the scene test**

```
make import
GODOT="/Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gselect=res://tests/unit/test_yorp_scene.gd -gexit -gdisable_colors
```
Expected: PASS. If `make import` reports a parse error in `yorp.tscn`, open the Godot editor (`make edit`), delete the `Visual` ColorRect, and instance the four `AnimatedSprite2D` nodes from `assets/sprites/Yorp.tscn` manually (renaming `Standing still` → `Idle`), then re-run.

- [ ] **Step 5: Run full suite + a headless visual sanity check**

```
make test
```
Expected: all green (16 new tests + existing).

- [ ] **Step 6: Commit**

```bash
git add src/runtime/entities/yorp.tscn tests/unit/test_yorp_scene.gd
git commit -m "feat(yorp): wire Walking/Idle/Stunned/Shot sprites into scene"
```

---

## Self-Review (completed during authoring)

**Spec coverage:** Every spec section maps to a task — state enum + visual sync (Task 1, §3.1/3.5), wander (Task 2, §3.2), stun/stomp/hooks (Task 3, §3.2–3.4), shot death (Task 4, §3.3), concrete-enemy contract (Task 5, §3.6), scene + node-name convention (Task 6, §3.5/4.4). Stomp-detection heuristic (§3.4) is in Task 3. Knockback-away direction (§3.3) is in `_on_side_contact`.

**Placeholder scan:** None. All code blocks are complete; no "TODO"/"similar to".

**Type consistency:** `SPRITE_NAMES`, `State`, `stun()`, `_is_stomp()`, `_handle_player()`, `_on_stomped/_on_side_contact/_on_recover`, `take_damage()`, `_enter_shot_death()`, `_die()`, `_tick_wander()`, `_turn_if_blocked()`, `_cache_sprites()`, `_sync_visual()` are used identically across tasks and tests.

**Two spec issues fixed inline:** (1) re-stomp-vs-stunned contradiction → stomp always allowed, only side-contact ignored while stunned; (2) deferred death would break the Vorticon test → immediate `_die()` when no `Shot` art.
