class_name SpriteEntity
extends Node2D
## Wrapper that gives a pure-visual sprite scene (bare Node root, no script) the
## entity contract: a Node2D transform + setup(type_id, props). Built by
## EntityRegistry.instantiate around a .tscn loaded from assets/sprites/.
## Deliberately has no collision, no AI, no signals — it is a positioned
## container; the wrapped sprite scene's children (e.g. AnimatedSprite2D) render
## and animate on their own.

@export var type_id: String = ""
@export var properties: Dictionary = {}


## Called by EntityRegistry.instantiate after constructing the wrapper.
func setup(p_type_id: String, p_props: Dictionary = {}) -> void:
	type_id = p_type_id
	properties = p_props
