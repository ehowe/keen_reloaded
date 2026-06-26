class_name LevelPack
extends RefCounted
## Parsed representation of a level pack's manifest.json. Pure data — does
## not load the .tres level files (that's PackLoader's job).

var pack_id: String = ""
var pack_name: String = ""
var author: String = ""
var version: String = ""
var episode: String = ""
var levels: Array[Dictionary] = []  # each: {level_id, file, name, order}


## Parses manifest JSON text. Returns null if invalid or missing required fields.
## Uses JSON.new().parse() (instance method) so invalid JSON returns an error
## code silently, instead of JSON.parse_string() which pushes an engine error.
## NOTE: manifest key "name" maps to field pack_name (avoid Node.name clashes).
static func from_json(json_text: String) -> LevelPack:
	var parser := JSON.new()
	if parser.parse(json_text) != OK:
		return null
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = parsed
	for key in ["pack_id", "name", "author", "version", "levels"]:
		if not d.has(key):
			return null
	var raw_levels: Variant = d["levels"]
	if typeof(raw_levels) != TYPE_ARRAY:
		return null

	var pack := LevelPack.new()
	pack.pack_id = d["pack_id"]
	pack.pack_name = d["name"]
	pack.author = d["author"]
	pack.version = d["version"]
	pack.episode = d.get("episode", "")

	for entry: Variant in raw_levels:
		if typeof(entry) == TYPE_DICTIONARY:
			pack.levels.append(entry)

	pack.levels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("order", 0)) < int(b.get("order", 0)))
	return pack
