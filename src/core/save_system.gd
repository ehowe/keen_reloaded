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


## Read metadata for every slot 1..SLOT_COUNT. Each entry is a Dictionary:
##   {"slot": N, "status": "empty"|"occupied"|"corrupt"|"missing_pack"|
##                       "unsupported_version", ...metadata}
## Does NOT touch GameManager. Resolves pack validity via PackLoader.
func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in range(1, SLOT_COUNT + 1):
		out.append(_slot_status(slot))
	return out


func _slot_status(slot: int) -> Dictionary:
	var base := saves_dir + "slot_%d.json" % slot
	var entry := {"slot": slot}
	if not FileAccess.file_exists(base):
		entry["status"] = "empty"
		return entry
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(base)) != OK:
		entry["status"] = "corrupt"
		return entry
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		entry["status"] = "corrupt"
		return entry
	var d: Dictionary = parsed
	if not d.has("version") or not d.has("data"):
		entry["status"] = "corrupt"
		return entry
	var ver: int = int(d["version"])
	if ver != CURRENT_VERSION:
		entry["status"] = "unsupported_version"
		entry["version"] = ver
		return entry
	var kind: String = String(d.get("kind", ""))
	var scope_id: String = String(d.get("scope_id", ""))
	if kind == "pack" and PackLoader.get_overworld(scope_id) == null:
		entry["status"] = "missing_pack"
	else:
		entry["status"] = "occupied"
	entry["kind"] = kind
	entry["scope_id"] = scope_id
	entry["scope_title"] = String(d.get("scope_title", scope_id))
	entry["saved_at"] = int(d.get("saved_at", 0))
	entry["completed_count"] = int(d.get("completed_count", 0))
	return entry


## Remove a slot file and its .bak. Used by corrupt/missing-pack cleanup and
## explicit user "clear slot" actions.
func delete_slot(slot: int) -> void:
	if slot < 1 or slot > SLOT_COUNT:
		return
	var base := saves_dir + "slot_%d.json" % slot
	if FileAccess.file_exists(base):
		DirAccess.remove_absolute(base)
	var bak := base + ".bak"
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(bak)
	if active_slot == slot:
		active_slot = 0


## Read a slot, validate, apply to GameManager via deserialize(), set active_slot.
## Falls back to <slot>.bak if the primary file fails validation. Returns true
## on success; on any failure GameManager is left untouched and active_slot
## is unchanged.
func load_slot(slot: int) -> bool:
	if slot < 1 or slot > SLOT_COUNT:
		push_warning("SaveSystem: invalid slot %d" % slot)
		return false
	var base := saves_dir + "slot_%d.json" % slot
	var payload: Variant = _read_and_validate(base)
	if payload == null:
		var bak := base + ".bak"
		if FileAccess.file_exists(bak):
			payload = _read_and_validate(bak)
			if payload == null:
				return false
			push_warning("SaveSystem: slot %d primary corrupt, loaded .bak" % slot)
		else:
			return false
	GameManager.deserialize(payload["data"])
	active_slot = slot
	return true


## Read + JSON-parse + validate a slot file. Returns the validated Dictionary
## (the full envelope including "data"), or null on any failure.
func _read_and_validate(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = parsed
	if not d.has("version") or not d.has("data"):
		return null
	var ver: int = int(d["version"])
	if ver != CURRENT_VERSION:
		return null  # forward-incompatible or pre-migration; no converters yet
	if typeof(d["data"]) != TYPE_DICTIONARY:
		return null
	return d


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
