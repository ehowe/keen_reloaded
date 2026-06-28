class_name InspectorPanel
extends VBoxContainer
## Right panel: level metadata, player spawn, and selected-entity properties.

var _e: LevelEditor
var _id_edit: LineEdit
var _name_edit: LineEdit
var _episode_edit: LineEdit
var _order_spin: SpinBox
var _width_spin: SpinBox
var _height_spin: SpinBox
var _spawn_x: SpinBox
var _spawn_y: SpinBox
var _entity_box: VBoxContainer
var _tileset_picker: OptionButton


func build(e: LevelEditor) -> void:
	_e = e
	custom_minimum_size = Vector2(250, 0)

	add_child(_section_label("Level"))
	_id_edit = _line(_on_id_changed)
	add_child(_labeled("ID", _id_edit))
	_name_edit = _line(_on_name_changed)
	add_child(_labeled("Name", _name_edit))
	_episode_edit = _line(_on_episode_changed)
	add_child(_labeled("Episode", _episode_edit))
	_order_spin = _spin(0, 9999, _on_order_changed)
	add_child(_labeled("Order", _order_spin))

	_width_spin = _spin(1, 512, _on_dims_changed)
	_height_spin = _spin(1, 512, _on_dims_changed)
	add_child(_labeled("Width", _width_spin))
	add_child(_labeled("Height", _height_spin))

	add_child(_section_label("Player Spawn"))
	_spawn_x = _spin(0, 511, _on_spawn_changed)
	_spawn_y = _spin(0, 511, _on_spawn_changed)
	add_child(_labeled("Spawn X", _spawn_x))
	add_child(_labeled("Spawn Y", _spawn_y))

	add_child(_section_label("TileSet"))
	_tileset_picker = OptionButton.new()
	_populate_tileset_picker()
	_tileset_picker.item_selected.connect(_on_tileset_selected)
	add_child(_labeled("File", _tileset_picker))

	add_child(_section_label("Selected Entity"))
	_entity_box = VBoxContainer.new()
	add_child(_entity_box)


func refresh(e: LevelEditor) -> void:
	_e = e
	_set_if_focused(_id_edit, e.level.level_id)
	_set_if_focused(_name_edit, e.level.level_name)
	_set_if_focused(_episode_edit, e.level.episode)
	_order_spin.set_value_no_signal(e.level.order)
	_width_spin.set_value_no_signal(e.level.width)
	_height_spin.set_value_no_signal(e.level.height)
	_spawn_x.set_value_no_signal(e.level.player_spawn.x)
	_spawn_y.set_value_no_signal(e.level.player_spawn.y)
	_sync_tileset_picker(e.level.tileset_ref)
	_rebuild_entity_box(e)


func _rebuild_entity_box(e: LevelEditor) -> void:
	for c in _entity_box.get_children():
		c.queue_free()
	if e.selected_entity_index < 0 or e.selected_entity_index >= e.level.entities.size():
		var l := Label.new()
		l.text = "(none — use Select/Entity tool)"
		l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_entity_box.add_child(l)
		return
	var ent: EntityDef = e.level.entities[e.selected_entity_index]
	_entity_box.add_child(_kv_label("type", ent.type))

	# Each SpinBox writes straight to the entity via a closure capturing itself,
	# so we avoid fragile get_node() lookups (and node-name collisions).
	var xs := SpinBox.new()
	xs.min_value = 0
	xs.max_value = 511
	xs.set_value_no_signal(ent.x)
	xs.value_changed.connect(func(_v: float) -> void: ent.x = int(xs.value))
	_entity_box.add_child(_labeled("X", xs))

	var ys := SpinBox.new()
	ys.min_value = 0
	ys.max_value = 511
	ys.set_value_no_signal(ent.y)
	ys.value_changed.connect(func(_v: float) -> void: ent.y = int(ys.value))
	_entity_box.add_child(_labeled("Y", ys))

	# numeric properties only (int-valued) for MVP
	for key in ent.properties.keys():
		var val = ent.properties[key]
		if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
			var ps := SpinBox.new()
			ps.min_value = -9999
			ps.max_value = 9999
			ps.set_value_no_signal(val)
			var k: Variant = key
			ps.value_changed.connect(func(_v: float) -> void: ent.properties[k] = int(ps.value))
			_entity_box.add_child(_labeled(str(key), ps))

	var del := Button.new()
	del.text = "Delete entity"
	del.pressed.connect(e.remove_selected_entity)
	_entity_box.add_child(del)


# ---------------------------------------------------------------- handlers

func _on_id_changed(t: String) -> void: _e.level.level_id = t
func _on_name_changed(t: String) -> void: _e.level.level_name = t
func _on_episode_changed(t: String) -> void: _e.level.episode = t
func _on_order_changed(_v: float) -> void: _e.level.order = int(_order_spin.value)

func _on_dims_changed(_v: float) -> void:
	_e.level.width = int(_width_spin.value)
	_e.level.height = int(_height_spin.value)
	_e.level.fill_blank()
	_e._broadcast()

func _on_spawn_changed(_v: float) -> void:
	_e.level.player_spawn = Vector2i(int(_spawn_x.value), int(_spawn_y.value))
	_e._broadcast()


func _populate_tileset_picker() -> void:
	_tileset_picker.clear()
	_tileset_picker.add_item("None (procedural)", 0)
	_tileset_picker.set_item_metadata(0, "")
	var dir := DirAccess.open("res://assets/tilesets")
	if dir == null:
		return
	var entries: Array[String] = []
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".tres"):
			entries.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	entries.sort()
	for name in entries:
		_tileset_picker.add_item(name)
		_tileset_picker.set_item_metadata(_tileset_picker.item_count - 1, "res://assets/tilesets/%s" % name)


func _sync_tileset_picker(ts: TileSet) -> void:
	var want := ""
	if ts != null and ts.resource_path != "":
		want = ts.resource_path
	for i in range(_tileset_picker.item_count):
		if String(_tileset_picker.get_item_metadata(i)) == want:
			_tileset_picker.select(i)
			return
	_tileset_picker.select(0)


func _on_tileset_selected(index: int) -> void:
	var path := String(_tileset_picker.get_item_metadata(index))
	if path == "":
		_e.level.tileset_ref = null
	else:
		var loaded := load(path)
		if loaded == null:
			push_warning("TileSet load failed: %s" % path)
		_e.level.tileset_ref = loaded
	_e._broadcast()


# ---------------------------------------------------------------- helpers

func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	return l

func _line(on_changed: Callable) -> LineEdit:
	var le := LineEdit.new()
	le.text_changed.connect(on_changed)
	return le

func _spin(minv: int, maxv: int, on_changed: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = minv
	s.max_value = maxv
	s.value_changed.connect(on_changed)
	return s

func _labeled(text: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(70, 0)
	h.add_child(l)
	h.add_child(control)
	return h

func _kv_label(k: String, v: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = "%s: %s" % [k, v]
	h.add_child(l)
	return h

func _set_if_focused(le: LineEdit, value: String) -> void:
	if not le.has_focus():
		le.text = value
