class_name EntityDef
extends Resource
## A single placed entity inside a LevelData. Type ID is resolved at runtime
## by EntityRegistry. Extensible: episodes add types without changing this class.

@export var type: String = ""
@export var x: int = 0
@export var y: int = 0
@export var properties: Dictionary = {}

func _init(p_type := "", p_x := 0, p_y := 0, p_props: Dictionary = {}) -> void:
	type = p_type
	x = p_x
	y = p_y
	properties = p_props
