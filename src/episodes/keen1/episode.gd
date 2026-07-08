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
	var lollipop := preload("res://src/runtime/entities/lollipop.tscn")
	var soda := preload("res://src/runtime/entities/soda.tscn")
	var pizza := preload("res://src/runtime/entities/pizza.tscn")
	var book := preload("res://src/runtime/entities/book.tscn")
	var teddy := preload("res://src/runtime/entities/teddy.tscn")
	var raygun := preload("res://src/runtime/entities/ammo_pickup.tscn")
	var exit_door := preload("res://src/runtime/entities/exit_door.tscn")
	var clapper := preload("res://src/runtime/entities/clapper.tscn")
	registry.register("keen1.vorticon", registry.CATEGORY_ENEMY, "Vorticon", [], vorticon)
	registry.register("keen1.yorp", registry.CATEGORY_ENEMY, "Yorp", [], yorp)
	registry.register("keen1.butler", registry.CATEGORY_HAZARD, "Butler Robot", [], butler)
	registry.register("keen1.clapper", registry.CATEGORY_HAZARD, "Clapper", [], clapper)
	registry.register("keen1.lollipop", registry.CATEGORY_ITEM, "Lollipop", [], lollipop)
	registry.register("keen1.soda", registry.CATEGORY_ITEM, "Soda", [], soda)
	registry.register("keen1.pizza", registry.CATEGORY_ITEM, "Pizza", [], pizza)
	registry.register("keen1.book", registry.CATEGORY_ITEM, "Book", [], book)
	registry.register("keen1.teddy", registry.CATEGORY_ITEM, "Teddy Bear", [], teddy)
	registry.register("keen1.raygun", registry.CATEGORY_ITEM, "Raygun Ammo", [], raygun)
	registry.register("keen1.exit_door", registry.CATEGORY_SPECIAL, "Exit Door", [], exit_door)
	var all_kinds: Array[int] = [LevelData.MapKind.LEVEL, LevelData.MapKind.OVERWORLD]
	registry.register("keen1.player_spawn", registry.CATEGORY_SPECIAL, "Player Spawn", [], null, all_kinds)
	registry.register_sprite("keen1.exit_sign", registry.CATEGORY_DECOR, "Exit Sign",
		"res://assets/sprites/Exit Sign.tscn")
	registry.register_sprite("keen1.spike", registry.CATEGORY_HAZARD, "Spike",
		"res://assets/sprites/Spike.tscn",
		[{name = "facing", default = "right", type = "enum", options = ["right", "left"]}])
	var level_entrance := preload("res://src/runtime/entities/level_entrance.tscn")
	var overworld_only: Array[int] = [LevelData.MapKind.OVERWORLD]
	registry.register("keen1.level_entrance", registry.CATEGORY_SPECIAL, "Level Entrance",
		[], level_entrance, overworld_only)
