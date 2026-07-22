class_name Keen1Episode
extends Episode
## Registers the Keen 1 ("Marooned on Mars") entity roster into the global
## catalog. type_ids are namespaced "keen1.*". Scenes are bound as they are
## authored (enemy/item/exit tasks update the preload lines below).

func _init() -> void:
	id = "keen1"
	title = "Marooned on Mars"
	overworld_path = "res://assets/levels/keen1/overworld.tres"


func register_entities(registry: Node) -> void:
	var vorticon := preload("res://src/runtime/entities/vorticon.tscn")
	var yorp := preload("res://src/runtime/entities/yorp.tscn")
	var garg := preload("res://src/runtime/entities/garg.tscn")
	var butler := preload("res://src/runtime/entities/butler.tscn")
	var tank_robot := preload("res://src/runtime/entities/tank_robot.tscn")
	var lollipop := preload("res://src/runtime/entities/lollipop.tscn")
	var soda := preload("res://src/runtime/entities/soda.tscn")
	var pizza := preload("res://src/runtime/entities/pizza.tscn")
	var book := preload("res://src/runtime/entities/book.tscn")
	var teddy := preload("res://src/runtime/entities/teddy.tscn")
	var raygun := preload("res://src/runtime/entities/ammo_pickup.tscn")
	var pogo_stick := preload("res://src/runtime/entities/pogo_stick.tscn")
	var battery := preload("res://src/runtime/entities/battery_pickup.tscn")
	var everclear := preload("res://src/runtime/entities/everclear_pickup.tscn")
	var vacuum := preload("res://src/runtime/entities/vacuum_pickup.tscn")
	var joystick := preload("res://src/runtime/entities/joystick_pickup.tscn")
	var exit_door := preload("res://src/runtime/entities/exit_door.tscn")
	var clapper := preload("res://src/runtime/entities/clapper.tscn")
	var spike := preload("res://src/runtime/entities/spike.tscn")
	var fire := preload("res://src/runtime/entities/fire.tscn")
	var green_dangly := preload("res://src/runtime/entities/green_dangly_stuff.tscn")
	registry.register("keen1.vorticon", registry.CATEGORY_ENEMY, "Vorticon", [], vorticon)
	registry.register("keen1.yorp", registry.CATEGORY_ENEMY, "Yorp", [], yorp)
	registry.register("keen1.garg", registry.CATEGORY_HAZARD, "Garg", [], garg)
	registry.register("keen1.butler", registry.CATEGORY_HAZARD, "Butler Robot", [], butler)
	registry.register("keen1.tank_robot", registry.CATEGORY_HAZARD, "Tank Robot", [], tank_robot)
	registry.register("keen1.clapper", registry.CATEGORY_HAZARD, "Clapper", [], clapper)
	registry.register("keen1.fire", registry.CATEGORY_HAZARD, "Fire", [], fire)
	registry.register("keen1.green_dangly_stuff", registry.CATEGORY_HAZARD, "Green Dangly Stuff",
		[{name = "variant", default = "Normal", type = "enum",
			options = ["Left Edge", "Normal", "Right Edge"]}],
		green_dangly)
	registry.register("keen1.lollipop", registry.CATEGORY_ITEM, "Lollipop", [], lollipop)
	registry.register("keen1.soda", registry.CATEGORY_ITEM, "Soda", [], soda)
	registry.register("keen1.pizza", registry.CATEGORY_ITEM, "Pizza", [], pizza)
	registry.register("keen1.book", registry.CATEGORY_ITEM, "Book", [], book)
	registry.register("keen1.teddy", registry.CATEGORY_ITEM, "Teddy Bear", [], teddy)
	registry.register("keen1.raygun", registry.CATEGORY_ITEM, "Raygun Ammo", [], raygun)
	registry.register("keen1.pogo_stick", registry.CATEGORY_ITEM, "Pogo Stick", [], pogo_stick)
	registry.register("keen1.battery", registry.CATEGORY_ITEM, "Battery", [], battery)
	registry.register("keen1.everclear", registry.CATEGORY_ITEM, "Everclear", [], everclear)
	registry.register("keen1.vacuum", registry.CATEGORY_ITEM, "Vacuum Cleaner", [], vacuum)
	registry.register("keen1.joystick", registry.CATEGORY_ITEM, "Joystick", [], joystick)
	registry.register("keen1.exit_door", registry.CATEGORY_SPECIAL, "Exit Door", [], exit_door)
	var all_kinds: Array[int] = [LevelData.MapKind.LEVEL, LevelData.MapKind.OVERWORLD]
	registry.register("keen1.player_spawn", registry.CATEGORY_SPECIAL, "Player Spawn", [], null, all_kinds)
	registry.register_sprite("keen1.exit_sign", registry.CATEGORY_DECOR, "Exit Sign",
		"res://assets/sprites/Exit Sign.tscn")
	registry.register("keen1.spike", registry.CATEGORY_HAZARD, "Spike",
		[{name = "facing", default = "right", type = "enum", options = ["right", "left"]}],
		spike)
	var level_entrance := preload("res://src/runtime/entities/level_entrance.tscn")
	var overworld_only: Array[int] = [LevelData.MapKind.OVERWORLD]
	registry.register("keen1.level_entrance", registry.CATEGORY_SPECIAL, "Level Entrance",
		[
			{name = "target_level_id", default = "", type = "level_id"},
			{name = "blocks_until_completed", default = false, type = "bool"},
			{name = "variant", default = "City", type = "enum",
				options = ["City", "Blue Shrine", "Emerald", "Gray Shrine", "Crystal", "Castle", "Treasury"]},
		],
		level_entrance, overworld_only)
	var ship := preload("res://src/runtime/entities/ship.tscn")
	registry.register("keen1.ship", registry.CATEGORY_SPECIAL, "Ship",
		[], ship, overworld_only)
	var teleporter := preload("res://src/runtime/entities/teleporter.tscn")
	registry.register("keen1.teleporter", registry.CATEGORY_SPECIAL, "Teleporter",
		[
			{name = "teleporter_id", default = "", type = "string"},
			{name = "destination_level_id", default = "", type = "level_id"},
			{name = "destination_teleporter_id", default = "", type = "string"},
		],
		teleporter, all_kinds)
	var message := preload("res://src/runtime/entities/message.tscn")
	registry.register("keen1.message", registry.CATEGORY_SPECIAL, "Message Sign",
		[
			{name = "target_level_id", default = "", type = "level_id"},
			{name = "repeat", default = false, type = "bool"},
		],
		message)
	var keycard := preload("res://src/runtime/entities/Keycard.tscn")
	registry.register("keen1.keycard", registry.CATEGORY_ITEM, "Keycard",
		[{name = "variant", default = "red", type = "enum",
			options = ["red", "blue", "yellow", "green"]}],
		keycard)
	var door := preload("res://src/runtime/entities/Door.tscn")
	registry.register("keen1.door", registry.CATEGORY_SPECIAL, "Door",
		[{name = "variant", default = "red", type = "enum",
			options = ["red", "blue", "yellow", "green"]}],
		door)
