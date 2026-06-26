extends GutTest

const VALID_MANIFEST := """{
	"pack_id": "keen1",
	"name": "Keen 1: Marooned on Mars",
	"author": "keen_reloaded",
	"version": "1.0.0",
	"episode": "keen1",
	"levels": [
		{"level_id": "keen1_01", "file": "01.tres", "name": "Border Village", "order": 1},
		{"level_id": "keen1_02", "file": "02.tres", "name": "Ice Shrine", "order": 2}
	]
}"""

func test_parse_valid_manifest():
	var pack := LevelPack.from_json(VALID_MANIFEST)
	assert_not_null(pack, "from_json should return a pack for valid JSON")
	assert_eq(pack.pack_id, "keen1")
	assert_eq(pack.pack_name, "Keen 1: Marooned on Mars")
	assert_eq(pack.author, "keen_reloaded")
	assert_eq(pack.version, "1.0.0")
	assert_eq(pack.episode, "keen1")
	assert_eq(pack.levels.size(), 2)
	assert_eq(pack.levels[0]["level_id"], "keen1_01")
	assert_eq(pack.levels[0]["file"], "01.tres")
	assert_eq(pack.levels[1]["order"], 2)

func test_parse_invalid_json_returns_null():
	var pack := LevelPack.from_json("{ this is not valid json")
	assert_null(pack, "invalid JSON should return null")

func test_manifest_missing_required_field():
	var bad := """{"pack_id": "x", "name": "No levels key here"}"""
	var pack := LevelPack.from_json(bad)
	assert_null(pack, "missing 'levels' should return null")

func test_levels_sorted_by_order():
	var unordered := """{
		"pack_id": "p", "name": "n", "author": "a", "version": "1",
		"levels": [
			{"level_id": "c", "file": "c.tres", "name": "C", "order": 3},
			{"level_id": "a", "file": "a.tres", "name": "A", "order": 1},
			{"level_id": "b", "file": "b.tres", "name": "B", "order": 2}
		]
	}"""
	var pack := LevelPack.from_json(unordered)
	assert_eq(pack.levels[0]["level_id"], "a")
	assert_eq(pack.levels[1]["level_id"], "b")
	assert_eq(pack.levels[2]["level_id"], "c")
