extends MaskDisplay
class_name CustomLevel
## Builds its AnimatedSprite2D children at runtime from user-made PNGs named
## output_<i>_<n>.png (i = animation frame, n = level, both starting at 0), then hands off to MaskDisplay.
## Level 0 is the most broken, the last level is the full painting.
## Set folder / levels / animation_frames (or use CustomLevel.create) BEFORE add_child().
## Images can be produced with CustomLevel.generate(), which runs fogleman/primitive.

const USER_TEXTURES := "user://"
const ZOOM_LEVEL := 8.0          ## scale applied on top of the image's native size
const FPS := 8.0

var folder := ""                 ## subfolder inside user://, e.g. "levels/my_level"
var levels := 0                  ## 0 = auto-detect from files
var animation_frames := 0        ## 0 = auto-detect from files


# ---------------------------------------------------------------------------
# Creation
# ---------------------------------------------------------------------------

## Create and configure in one step. Add the result to the tree afterwards.
static func create(p_folder: String, p_levels := 0, p_frames := 0) -> CustomLevel:
	var lvl := CustomLevel.new()
	lvl.folder = p_folder
	lvl.levels = p_levels
	lvl.animation_frames = p_frames
	return lvl


func _ready() -> void:
	if levels <= 0:
		levels = _count_levels()
	if animation_frames <= 0:
		animation_frames = _count_frames()

	if levels < 2 or animation_frames < 1:
		push_warning("CustomLevel: no valid output_i_n.png files in %s" % USER_TEXTURES.path_join(folder))
		return
	if levels > MAX_LEVELS:
		push_warning("CustomLevel: %d levels found, using only the first %d" % [levels, MAX_LEVELS])
		levels = MAX_LEVELS

	if not _build_sprites():
		return

	super._ready()           # MaskDisplay now finds the sprites we just added
	if full:
		full.play("default")


# ---------------------------------------------------------------------------
# Loading images
# ---------------------------------------------------------------------------

static func _file_path(p_folder: String, i: int, n: int) -> String:
	return USER_TEXTURES.path_join(p_folder).path_join("output_%d_%d.png" % [i, n])


## Number of consecutive levels (n), checked on the first frame.
func _count_levels() -> int:
	var k := 0
	while FileAccess.file_exists(_file_path(folder, 0, k)):
		k += 1
	return k


## Number of consecutive animation frames (i), checked on the first level.
func _count_frames() -> int:
	var k := 0
	while FileAccess.file_exists(_file_path(folder, k, 0)):
		k += 1
	return k


func _build_sprites() -> bool:
	var level_sprites: Array[AnimatedSprite2D] = []

	for n in levels:
		var sf := SpriteFrames.new()   # comes with a "default" animation
		sf.set_animation_speed("default", FPS)
		sf.set_animation_loop("default", true)

		for i in animation_frames:
			var path := _file_path(folder, i, n)
			if not FileAccess.file_exists(path):
				push_warning("CustomLevel: missing file %s" % path)
				return false
			var img := Image.load_from_file(path)
			if img == null or img.is_empty():
				push_warning("CustomLevel: could not load %s" % path)
				return false
			sf.add_frame("default", ImageTexture.create_from_image(img))

		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = sf
		spr.animation = "default"
		spr.scale = Vector2.ONE * ZOOM_LEVEL
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		level_sprites.append(spr)

	# Remove any placeholder sprites immediately so MaskDisplay doesn't see them
	for c in get_children():
		if c is AnimatedSprite2D:
			remove_child(c)
			c.queue_free()

	# Order matters: MOST BROKEN first, FULL PAINTING last
	for s in level_sprites:
		add_child(s)
	return true


# ---------------------------------------------------------------------------
# Generating images with fogleman/primitive
# ---------------------------------------------------------------------------

## Name of the bundled binary for the current OS + CPU, or "" if unsupported.
## Must match the file names produced by build_primitive.sh.
static func _binary_name() -> String:
	var arch := Engine.get_architecture_name()   # "x86_64", "arm64", ...
	match OS.get_name():
		"Windows":
			return "primitive_windows_%s.exe" % arch
		"Linux":
			return "primitive_linux_%s" % arch
		"macOS":
			return "primitive_macos_%s" % arch
	return ""   # Android, iOS and Web cannot spawn subprocesses


## Copies the bundled binary from res://bin to user://bin and returns its absolute
## path, or "" on failure. Re-copies if the bundled file's size changed.
static func _prepare_binary() -> String:
	var bin_name := _binary_name()
	if bin_name == "":
		push_warning("CustomLevel: subprocesses are not supported on %s" % OS.get_name())
		return ""

	var src := "res://bin/".path_join(bin_name)
	var dst := "user://bin/".path_join(bin_name)
	if not FileAccess.file_exists(src):
		push_warning("CustomLevel: no bundled binary for this platform: %s" % bin_name)
		return ""

	var src_file := FileAccess.open(src, FileAccess.READ)
	if src_file == null:
		return ""

	var needs_copy := true
	if FileAccess.file_exists(dst):
		var dst_file := FileAccess.open(dst, FileAccess.READ)
		needs_copy = dst_file == null or dst_file.get_length() != src_file.get_length()

	if needs_copy:
		DirAccess.make_dir_recursive_absolute("user://bin")
		var out := FileAccess.open(dst, FileAccess.WRITE)
		if out == null:
			push_warning("CustomLevel: cannot write %s" % dst)
			return ""
		out.store_buffer(src_file.get_buffer(src_file.get_length()))
		out.close()

	var abs_path := ProjectSettings.globalize_path(dst)
	if OS.get_name() != "Windows":
		OS.execute("chmod", ["+x", abs_path])
	return abs_path


static func _gcd(a: int, b: int) -> int:
	var x := a
	var y := b
	while y != 0:
		var t := y
		y = x % y
		x = t
	return x


## Generates output_<i>_<n>.png (indices from 0) into user://<out_folder>/ using fogleman/primitive.
## shape_counts: total shapes for each level, strictly increasing, e.g. [10, 30, 80, 200, 500].
## Each animation frame is a separate primitive run (different random result).
## Blocking: call it from a Thread. Returns true on success.
static func generate(
		input_image: String,
		out_folder: String,
		shape_counts: Array[int],
		p_frames := 5,
		shape_mode := 1,       # 0 combo, 1 triangle, 2 rect, 3 ellipse, 4 circle, 5 rotated rect, 6 beziers, 7 rotated ellipse, 8 polygon
		resize_input := 256,   # -r
		output_size := 256,    # -s
		alpha := 128           # -a (0 = let primitive choose)
	) -> bool:

	if shape_counts.is_empty():
		push_warning("CustomLevel: shape_counts is empty")
		return false
	if shape_counts.size() > MAX_LEVELS:
		push_warning("CustomLevel: at most %d levels are supported" % MAX_LEVELS)
		return false
	for k in shape_counts.size():
		if shape_counts[k] <= 0 or (k > 0 and shape_counts[k] <= shape_counts[k - 1]):
			push_warning("CustomLevel: shape_counts must be positive and strictly increasing")
			return false

	var bin := _prepare_binary()
	if bin == "":
		return false

	var out_dir := USER_TEXTURES.path_join(out_folder)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var abs_dir := ProjectSettings.globalize_path(out_dir)

	var input := input_image
	if input.begins_with("res://") or input.begins_with("user://"):
		input = ProjectSettings.globalize_path(input)

	# Primitive saves every nth shape; the gcd of the counts hits all the ones we need.
	var step := shape_counts[0]
	for c in shape_counts:
		step = _gcd(step, c)
	var total: int = shape_counts[-1]

	for i in p_frames:
		var pattern := abs_dir.path_join("tmp_%d_%%d.png" % i)   # primitive fills in the shape count
		var args := PackedStringArray([
			"-i", input,
			"-o", pattern,
			"-n", str(total),
			"-nth", str(step),
			"-m", str(shape_mode),
			"-r", str(resize_input),
			"-s", str(output_size),
			"-a", str(alpha),
		])

		var output: Array = []
		var code := OS.execute(bin, args, output, true)
		if code != 0:
			push_warning("primitive failed (exit %d): %s" % [code, "".join(output)])
			return false

		# tmp_<i>_<shape count>.png -> output_<i>_<level>.png
		for n in shape_counts.size():
			var src := abs_dir.path_join("tmp_%d_%d.png" % [i, shape_counts[n]])
			var dst := abs_dir.path_join("output_%d_%d.png" % [i, n])
			if not FileAccess.file_exists(src):
				push_warning("CustomLevel: primitive did not produce %s" % src)
				return false
			DirAccess.rename_absolute(src, dst)

		# delete the in-between frames we don't need
		var d := DirAccess.open(out_dir)
		for f in d.get_files():
			if f.begins_with("tmp_%d_" % i):
				d.remove(f)

	return true
