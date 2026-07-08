class_name EntityVariant
extends RefCounted
## Applies schema-driven enum "variant" child visibility to a node tree. Shared by
## SpriteEntity (decor) and scripted Hazard/scripted entities (e.g. Spike) that carry
## multiple visual variants selected by an enum property. Reads the type's schema from
## EntityRegistry; for each enum, shows the descendant CanvasItem whose name contains
## the chosen value (case-insensitive) and hides sibling variants.
##
## Note: the first option whose substring appears in a child name wins. Avoid option
## values that are substrings of each other (e.g. ["right","topright"]), or name
## variant children exactly their option value.


static func apply(type_id: String, props: Dictionary, root: Node) -> void:
	for s in EntityRegistry.get_properties_schema(type_id):
		if String(s.get("type", "")) != "enum":
			continue
		var options: Array = s.get("options", [])
		if options.is_empty():
			continue
		var key: String = String(s.get("name", ""))
		var val := String(props.get(key, s.get("default", "")))
		_select(options, val, root)


## Variant group = descendant CanvasItems whose node names contain an enum option
## (case-insensitive). Show the one whose option == val; hide the rest. Descendants
## not matching any option are left untouched. Descendant walk handles sprites nested
## under a wrapper (e.g. a "Visual" node).
static func _select(options: Array, val: String, root: Node) -> void:
	var want := val.to_lower()
	var matched: CanvasItem = null
	var to_hide: Array[CanvasItem] = []
	for c in _descendants(root):
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
	elif not to_hide.is_empty():
		push_warning("EntityVariant: variant value '%s' matched no child of '%s'" % [val, root.name])


static func _descendants(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_descendants(c))
	return out
