extends SceneTree

## Converts all .tres LevelData files in res://assets/levels/ to .res (binary)
## preserving PackedInt32Array data that the Godot 4.7 export converter strips.
## Output .res files sit alongside .tres sources; episode.gd prefers .res.

func _init() -> void:
	var dirs := ["res://assets/levels/"]
	var converted := 0
	for d in dirs:
		converted += _convert_dir(d)
	print("converted=", converted)
	quit()


func _convert_dir(dir_path: String) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	var count := 0
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if dir.dir_exists(fname) and not fname.begins_with("."):
			count += _convert_dir(dir_path + fname + "/")
		elif fname.get_extension().to_lower() == "tres":
			var src := dir_path + fname
			var dst := dir_path + fname.get_basename() + ".res"
			if _convert_one(src, dst):
				count += 1
		fname = dir.get_next()
	dir.list_dir_end()
	return count


func _convert_one(src_path: String, dst_path: String) -> bool:
	var res := load(src_path)
	if res == null or not (res is LevelData):
		return false
	var ld := res as LevelData
	var err := ResourceSaver.save(ld, dst_path)
	if err != OK:
		push_warning("convert_levels: save failed %s -> %s (err=%d)" % [src_path, dst_path, err])
		return false
	print("  ", src_path, " -> ", dst_path, " (geom=", ld.geometry_tiles.size(), ")")
	return true
