extends Node
## Disk persistence for GameManager session state. Owns slot file I/O and the
## active-slot concept. Calls GameManager.serialize()/deserialize() — does not
## own session state itself.
##
## Slot files live at <saves_dir>/slot_<N>.json (N = 1..SLOT_COUNT). Writes are
## atomic: payload is written to .tmp, the previous good save is copied to .bak,
## then .tmp is renamed over the slot file. load_slot falls back to .bak if the
## primary file fails validation.

const SLOT_COUNT := 6
const CURRENT_VERSION := 1
const DEFAULT_SAVES_DIR := "user://saves/"

# Overridable in tests (mirrors PackLoader.root_dir pattern).
var saves_dir: String = DEFAULT_SAVES_DIR

# Active slot for this session. 0 = none (save_active is a no-op). In-memory
# only; never persisted as its own field.
var active_slot: int = 0


## Persist GameManager.serialize() to the slot file. Atomic write + .bak rotate.
## Sets active_slot. Returns true on success, false on disk/arg failure.
func save_slot(slot: int) -> bool:
	if slot < 1 or slot > SLOT_COUNT:
		push_warning("SaveSystem: invalid slot %d" % slot)
		return false
	var data := GameManager.serialize()
	var kind: String = data.get("current_scope_kind", "episode")
	var scope_id: String = data.get("current_episode_id", "")
	var completed: Array = data.get("completed_levels", [])
	var payload := {
		"version": CURRENT_VERSION,
		"kind": kind,
		"scope_id": scope_id,
		"scope_title": _resolve_scope_title(kind, scope_id),
		"saved_at": int(Time.get_unix_time_from_system()),
		"completed_count": completed.size(),
		"data": data,
	}
	_ensure_dir()
	var base := saves_dir + "slot_%d.json" % slot
	var tmp := base + ".tmp"
	var bak := base + ".bak"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: cannot open %s for write" % tmp)
		return false
	f.store_string(JSON.stringify(payload, "  "))
	f.close()
	# Rotate backup from the previous good save (if any). Best-effort.
	if FileAccess.file_exists(base):
		if DirAccess.copy_absolute(base, bak) != OK:
			push_warning("SaveSystem: could not rotate .bak for slot %d" % slot)
	if DirAccess.rename_absolute(tmp, base) != OK:
		push_error("SaveSystem: cannot rename tmp to %s" % base)
		DirAccess.remove_absolute(tmp)
		return false
	active_slot = slot
	return true


## Save to the active slot. No-op (returns true) when active_slot == 0.
func save_active() -> bool:
	if active_slot == 0:
		return true
	return save_slot(active_slot)


func clear_active() -> void:
	active_slot = 0


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(saves_dir):
		DirAccess.make_dir_recursive_absolute(saves_dir)


## Resolve a human-readable scope title for the cached slot metadata. Falls
## back to scope_id when the source is unavailable (e.g. pack uninstalled).
func _resolve_scope_title(kind: String, scope_id: String) -> String:
	if kind == "pack":
		var p := PackLoader.get_pack(scope_id)
		if p != null:
			return p.pack_name
		return scope_id
	for ep in GameManager.episodes:
		if String(ep.get("id", "")) == scope_id:
			return String(ep.get("title", scope_id))
	return scope_id
