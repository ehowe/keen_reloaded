class_name SurfacePhysics
extends RefCounted
## Pure (vx, ...) -> float ground-movement helpers. No Godot nodes, no side
## effects — fully unit-testable. The Player's physics loop reads the surface
## under its feet and delegates velocity math here.

## Normal ground: accelerate toward dir*run_speed*speed_scale when input is
## held, decelerate toward 0 when released. A single move_toward covers
## speed-up, slow-down, and turn-through-zero.
static func step_ground(vx: float, dir: float, run_speed: float, speed_scale: float, accel: float, decel: float, delta: float) -> float:
	var target := dir * run_speed * speed_scale
	if dir != 0.0:
		return move_toward(vx, target, accel * delta)
	return move_toward(vx, 0.0, decel * delta)


## Ice1 entry: clamp |vx| to `cap`, preserving direction. Called once on the
## first grounded ICE1 frame after a non-ICE1 surface.
static func step_ice1_entry(vx: float, cap: float) -> float:
	if absf(vx) > cap:
		return signf(vx) * cap
	return vx


## Ice1 surface: accelerate toward dir*cap when input is held; ZERO friction
## (velocity unchanged) when no input. Same move_toward shape as step_ground.
static func step_ice1(vx: float, dir: float, cap: float, accel: float, delta: float) -> float:
	if dir != 0.0:
		return move_toward(vx, dir * cap, accel * delta)
	return vx


## Ice2 surface: pin horizontal velocity to entry_dir * slide_speed. The
## Player manages entry_dir, the lock flag, and the wall-stop (which zeroes
## vx and clears the lock after move_and_slide); this helper just pins.
static func step_ice2(entry_dir: float, slide_speed: float) -> float:
	return entry_dir * slide_speed


## Constant deceleration that stops a body moving at speed |vx| in exactly
## `distance` pixels: a = v0^2 / (2*distance). Returns a positive rate to
## pass to step_coast. Zero when distance<=0 or the body is already stopped.
static func coast_decel_for(vx: float, distance: float) -> float:
	var v0 := absf(vx)
	if distance <= 0.0 or v0 <= 0.0:
		return 0.0
	return (v0 * v0) / (2.0 * distance)


## Coast: decelerate toward 0 at a constant rate (computed by coast_decel_for
## for a fixed stop distance). The Player suspends this while steering and
## recomputes coast_decel_for on release.
static func step_coast(vx: float, coast_decel: float, delta: float) -> float:
	return move_toward(vx, 0.0, coast_decel * delta)
