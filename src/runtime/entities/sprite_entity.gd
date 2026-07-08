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


## Called by EntityRegistry.instantiate after constructing the wrapper and
## attaching the sprite scene. Applies enum "variant" properties: for each
## enum in the type's schema, the descendant CanvasItem whose name contains
## the property value (case-insensitive) is shown; sibling variants hidden.
func setup(p_type_id: String, p_props: Dictionary = {}) -> void:
	type_id = p_type_id
	properties = p_props
	_apply_variant_properties()


func _apply_variant_properties() -> void:
	for s in EntityRegistry.get_properties_schema(type_id):
		if String(s.get("type", "")) != "enum":
			continue
		var options: Array = s.get("options", [])
		if options.is_empty():
			continue
		var key: String = String(s.get("name", ""))
		var val := String(properties.get(key, s.get("default", "")))
		_select_variant_child(options, val)


## Variant group = descendant CanvasItems whose node names contain an enum
## option (case-insensitive). Show the one whose option == val; hide the rest.
## Descendants not matching any option are left untouched. Descendant walk is
## required because attach_sprite() adds the scene root as the wrapper's only
## child, so variant sprites are typically grandchildren of the wrapper.
func _select_variant_child(options: Array, val: String) -> void:
	var want := val.to_lower()
	var matched: CanvasItem = null
	var to_hide: Array[CanvasItem] = []
	for c in _descendants(self):
		if not (c is CanvasItem):
			continue
		var nm := String(c.name).to_lower()
		for o in options:
			if nm.contains(String(o).to_lower()):
				if String(o).to_lower() == want:
					matched = c
				else:
					to_hide.append(c)
				break
	for c in to_hide:
		c.visible = false
	if matched != null:
		matched.visible = true


func _descendants(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_descendants(c))
	return out


## Attach an instantiated sprite scene as this wrapper's visual content. The
## scene's root is usually a Node2D/Sprite2D and is added directly, so its
## transform inherits this wrapper's position. If the root is a non-CanvasItem
## (e.g. a plain organizational Node — see assets/sprites/Exit Sign.tscn), a
## non-CanvasItem between two CanvasItems severs the canvas transform chain and
## the sprite would render at the world origin instead of at this wrapper; in
## that case the root's direct CanvasItem children are reparented into the
## wrapper (artist-authored local offsets preserved) and the bare root is freed.
func attach_sprite(root: Node) -> void:
	if root is CanvasItem:
		add_child(root)
		return
	var canvas_kids: Array[Node] = []
	for c in root.get_children():
		if c is CanvasItem:
			canvas_kids.append(c)
	for c in canvas_kids:
		root.remove_child(c)
		c.owner = null
		add_child(c)
	root.free()
