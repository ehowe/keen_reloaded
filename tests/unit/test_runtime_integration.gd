extends GutTest

func test_build_spawns_every_registered_entity_type():
	var by_kind: Dictionary = {}
	for entry in EntityRegistry.get_palette_entries():
		var kinds: Array = entry.get("map_kinds", [LevelData.MapKind.LEVEL])
		var key := int(kinds[0])
		if not by_kind.has(key):
			by_kind[key] = []
		by_kind[key].append(entry)
	for kind in by_kind:
		GameManager.pending_level = null
		var ld := LevelData.new()
		ld.map_kind = kind
		ld.width = 16
		ld.height = 8
		ld.tile_size = 16
		ld.fill_blank()
		ld.player_spawn = Vector2i(1, 1)
		var x := 2
		for entry in by_kind[kind]:
			ld.entities.append(EntityDef.new(String(entry["type_id"]), x, 1))
			x += 1
		var rt := LevelRuntime.new()
		add_child_autofree(rt)
		rt.build(ld)
		assert_eq(rt.entities_spawned.size(), ld.entities.size(),
			"every kind-%d map entity spawned" % kind)
		for node in rt.entities_spawned:
			assert_true(node is Entity or node is SpriteEntity or node is LevelEntrance)
			assert_true(node.is_inside_tree())
