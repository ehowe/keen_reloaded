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
