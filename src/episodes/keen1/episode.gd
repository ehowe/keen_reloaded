class_name Keen1Episode
extends Episode
## Registers the Keen 1 ("Marooned on Mars") entity roster into the global
## catalog. type_ids are namespaced "keen1.*". Scenes are bound as they are
## authored (enemy/item/exit tasks update the preload lines below).

func _init() -> void:
	id = "keen1"
	title = "Marooned on Mars"


func register_entities(registry: Node) -> void:
	var vorticon := preload("res://src/runtime/entities/vorticon.tscn")
	var yorp := preload("res://src/runtime/entities/yorp.tscn")
	var butler := preload("res://src/runtime/entities/butler.tscn")
	registry.register("keen1.vorticon", registry.CATEGORY_ENEMY, "Vorticon", [], vorticon)
	registry.register("keen1.yorp", registry.CATEGORY_ENEMY, "Yorp", [], yorp)
	registry.register("keen1.butler", registry.CATEGORY_HAZARD, "Butler Robot", [], butler)
	registry.register("keen1.candy", registry.CATEGORY_ITEM, "Candy")
	registry.register("keen1.raygun", registry.CATEGORY_ITEM, "Raygun Ammo")
	registry.register("keen1.exit_door", registry.CATEGORY_SPECIAL, "Exit Door")
	registry.register("keen1.player_spawn", registry.CATEGORY_SPECIAL, "Player Spawn")
