class_name LevelEntrance
extends ProximityInteractable
## Overworld-only entity: a level door. Player presses `interact` while nearby to
## enter the linked level. When `blocks_until_completed` is set and the target
## level is not yet completed, a solid StaticBody2D blocks overworld passage.
##
## Does NOT own completion state — reads GameManager.is_level_completed(). Emits
## `enter_requested(target_level_id, tile)`; LevelRuntime wires it to
## GameManager.enter_level().

signal enter_requested(target_level_id: String, tile: Vector2i)

const BLOCKER_SIZE := 48

# Done-overlay sprite names + color column layout. The done sheet packs three
# color variants side by side; each column is `step` pixels wide.
const DONE_SMALL_NODE := "Small Done"
const DONE_LARGE_NODE := "Large Done"
const DONE_STEP_LARGE := 128
const DONE_STEP_SMALL := 64
const DONE_COLOR_ORDER := ["blue", "red", "yellow"]

var type_id: String = ""
var target_level_id: String = ""
var blocks_until_completed: bool = false
var tile: Vector2i = Vector2i(-1, -1)

var _blocker: StaticBody2D
var _blocker_shape: CollisionShape2D
# Cached the first time _apply_done_visual runs (after EntityVariant selects the
# variant in setup). Reused on later refreshes so a hidden variant is still
# found.
var _active_variant: Sprite2D = null
var _done_atlas_duplicated: bool = false


## Called by EntityRegistry.instantiate. Reads editor-set properties. Order-
## independent: refresh_blocking() reapplies solidity whether or not _ready has
## run yet (it null-guards the shape). Applies the "variant" enum to select which
## child Sprite2D is visible.
func setup(p_type_id: String, p_props: Dictionary) -> void:
	type_id = p_type_id
	target_level_id = String(p_props.get("target_level_id", ""))
	blocks_until_completed = bool(p_props.get("blocks_until_completed", false))
	EntityVariant.apply(type_id, p_props, self)
	refresh_blocking()


## Called by LevelRuntime after instantiate so the entrance knows its tile.
func set_tile(t: Vector2i) -> void:
	tile = t


func _ready() -> void:
	super._ready()
	_build_blocker()


func _build_blocker() -> void:
	_blocker = StaticBody2D.new()
	_blocker.name = "Blocker"
	_blocker.collision_layer = 4  # tiles bit -> blocks the player
	_blocker_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(BLOCKER_SIZE, BLOCKER_SIZE)
	_blocker_shape.shape = rect
	_blocker.add_child(_blocker_shape)
	_blocker.add_to_group("level_entrance_blocker")
	add_child(_blocker)
	# Offset the blocker to the visible sprite's center so collision aligns
	# with the art, which may be larger or offset from the entity origin.
	var sprite := _get_visible_sprite()
	if sprite != null:
		_blocker.position = sprite.position
	_apply_blocking()


func _get_visible_sprite() -> Sprite2D:
	for c in get_children():
		if c is Sprite2D and c.visible:
			return c
	return null


func _process(_delta: float) -> void:
	attempt_enter(Input.is_action_just_pressed("interact"))


## Returns true and emits enter_requested when a player is nearby and the
## interact control is pressed. `interact_pressed` is a parameter (not read from
## Input) so tests are deterministic.
func attempt_enter(interact_pressed: bool) -> bool:
	if not _nearby or not interact_pressed:
		return false
	if target_level_id == "":
		return false
	enter_requested.emit(target_level_id, tile)
	return true


func is_blocking() -> bool:
	return blocks_until_completed and target_level_id != "" and not GameManager.is_level_completed(target_level_id)


## Recompute the blocker's solidity from GameManager state. Called on build and
## after a level is completed. Also refreshes the done-overlay sprite so a
## completed level's entrance swaps to its Small/Large Done tile.
func refresh_blocking() -> void:
	_apply_blocking()
	_apply_done_visual()


func _apply_blocking() -> void:
	if _blocker_shape == null:
		return
	_blocker_shape.set_deferred("disabled", not is_blocking())


## When the target level is completed, hide the active variant sprite and show
## the matching done-overlay sprite (Small/Large per the variant's
## `useLargeDoneTile` metadata) with its atlas region shifted to the column for
## `doneVariant` (blue=0, red=1, yellow=2). Otherwise hide both done sprites and
## leave the variant sprite visible. The AtlasTexture is duplicated before its
## region is mutated so the shared tscn subresource is not corrupted across
## instances.
func _apply_done_visual() -> void:
	var small := get_node_or_null(DONE_SMALL_NODE)
	var large := get_node_or_null(DONE_LARGE_NODE)
	if small == null or large == null:
		return
	(small as CanvasItem).visible = false
	(large as CanvasItem).visible = false
	if _active_variant == null:
		_active_variant = _get_variant_sprite()
	var variant := _active_variant
	if variant == null:
		return
	var completed := target_level_id != "" and GameManager.is_level_completed(target_level_id)
	if not completed:
		variant.visible = true
		return
	variant.visible = false
	var use_large := bool(variant.get_meta("useLargeDoneTile", false))
	var done: Sprite2D = large if use_large else small
	var step := DONE_STEP_LARGE if use_large else DONE_STEP_SMALL
	var color := String(variant.get_meta("doneVariant", "blue")).to_lower()
	var idx := DONE_COLOR_ORDER.find(color)
	if idx < 0:
		idx = 0
	_set_atlas_column(done, idx * step)
	done.position = variant.position
	done.visible = true


## Mutates the done sprite's atlas region to start at column `x`. The
## AtlasTexture is duplicated once (on the first call for this instance) so the
## shared tscn subresource is not corrupted across instances; subsequent calls
## mutate the already-duplicated texture in place. Re-duplicating every call
## frees the previous duplicate while the renderer may still hold a reference,
## causing an intermittent SIGSEGV in exported builds.
func _set_atlas_column(sprite: Sprite2D, x: int) -> void:
	var base := sprite.texture as AtlasTexture
	if base == null:
		return
	if not _done_atlas_duplicated:
		var dup: AtlasTexture = base.duplicate()
		sprite.texture = dup
		base = dup
		_done_atlas_duplicated = true
	base.region.position.x = x


## Returns the active variant sprite (the visible non-done Sprite2D), or the
## first non-done Sprite2D if none is visible yet.
func _get_variant_sprite() -> Sprite2D:
	var fallback: Sprite2D = null
	for c in get_children():
		if not (c is Sprite2D):
			continue
		var nm := String(c.name)
		if nm == DONE_SMALL_NODE or nm == DONE_LARGE_NODE:
			continue
		var s := c as Sprite2D
		if s.visible:
			return s
		if fallback == null:
			fallback = s
	return fallback
