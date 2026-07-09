extends SceneTree
## One-off HUD icon generator. Writes 16x16 placeholder PNGs into
## assets/sprites/hud/. Run headless:
##   godot --headless --path . --script res://tools/gen_hud_icons.gd
## Output is committed; re-run only to regenerate. CC0 / public domain.
## All output is original/programmatically drawn — free to replace later.

const SIZE := 16
const DIR := "res://assets/sprites/hud/"

const HEART := [
	"................",
	"...##....##.....",
	"..####..####....",
	".############...",
	".############...",
	".############...",
	".############...",
	"..##########....",
	"...########.....",
	"....######......",
	".....####.......",
	"......##........",
	"................",
	"................",
	"................",
	"................",
]

const BOLT := [
	"................",
	"......####......",
	".....####.......",
	"....####........",
	"...############.",
	"...##########...",
	"....######......",
	"....######......",
	"....######......",
	".....####.......",
	"....####........",
	"...####.........",
	"..####..........",
	"................",
	"................",
	"................",
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_write("heart_full.png",  HEART, Color(0.86, 0.12, 0.16))
	_write("heart_empty.png", HEART, Color(0.30, 0.12, 0.14))
	_write("ammo_full.png",   BOLT,  Color(1.0, 0.82, 0.16))
	_write("ammo_empty.png",  BOLT,  Color(0.28, 0.23, 0.10))
	print("gen_hud_icons: wrote assets/sprites/hud")
	quit()


func _write(name: String, pattern: Array, color: Color) -> void:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in SIZE:
		var row: String = pattern[y]
		for x in SIZE:
			if row[x] == '#':
				img.set_pixel(x, y, color)
	var err := img.save_png(DIR + name)
	if err != OK:
		push_error("gen_hud_icons: cannot write %s%s (err=%d)" % [DIR, name, err])
