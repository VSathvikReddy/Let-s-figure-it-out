extends RefCounted
## Turns any picture into a painting the game can use, with the "primitive"
## tool (fogleman/primitive, its programs are in res://bin). It redraws the
## picture with a few triangles (crude) up to many triangles (detailed).
##
## Output: user://<folder>/output_<frame>_<level>.png
##   frame - animation frame (each frame is a separate run, so the shapes wiggle)
##   level - 0 = crudest (fewest shapes), the last one = most detailed
##
## Copied from the team's levels/custom/custom_level.gd (the same logic), so
## files made by their custom card and by ours are the same.

const USER_FOLDER := "user://"
## The folder the custom card writes to (shared with the team's custom card).
const CUSTOM_FOLDER := "levels/custom"
## The painting can mix at most this many detail levels.
const MAX_LEVELS := 8


## Path of one generated picture.
static func file_path(folder: String, frame: int, level: int) -> String:
	return USER_FOLDER.path_join(folder).path_join("output_%d_%d.png" % [frame, level])


## How many detail levels exist in a folder (counted on frame 0).
static func count_levels(folder: String) -> int:
	var count := 0
	while count < MAX_LEVELS and FileAccess.file_exists(file_path(folder, 0, count)):
		count += 1
	return count


## How many animation frames exist in a folder (counted on level 0).
static func count_frames(folder: String) -> int:
	var count := 0
	while count < 64 and FileAccess.file_exists(file_path(folder, count, 0)):
		count += 1
	return count


## Makes the pictures. shape_counts = how many shapes each level has, from the
## crudest to the most detailed (must go up), e.g. [10, 30, 80, 200, 500].
## This takes a while, so call it from a Thread. Returns true when it worked.
static func generate(
		input_image: String,
		out_folder: String,
		shape_counts: Array[int],
		frames := 5,
		shape_mode := 1,       # 0 combo, 1 triangle, 2 rect, 3 ellipse, 4 circle, 5 rotated rect, 6 beziers, 7 rotated ellipse, 8 polygon
		resize_input := 256,   # the picture is shrunk to this before drawing (-r)
		output_size := 256,    # size of the pictures it writes (-s)
		alpha := 128           # see-through-ness of each shape (-a, 0 = automatic)
	) -> bool:

	if shape_counts.is_empty() or shape_counts.size() > MAX_LEVELS:
		push_warning("Generator: give between 1 and %d shape counts" % MAX_LEVELS)
		return false
	for k in shape_counts.size():
		if shape_counts[k] <= 0 or (k > 0 and shape_counts[k] <= shape_counts[k - 1]):
			push_warning("Generator: shape counts must be positive and go up")
			return false

	var program := _prepare_program()
	if program == "":
		return false

	var out_dir := USER_FOLDER.path_join(out_folder)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var out_dir_on_disk := ProjectSettings.globalize_path(out_dir)

	var input := input_image
	if input.begins_with("res://") or input.begins_with("user://"):
		input = ProjectSettings.globalize_path(input)

	# primitive saves a picture every `step` shapes; the greatest common
	# divisor of the counts makes sure every count we need gets saved
	var step := shape_counts[0]
	for count in shape_counts:
		step = _gcd(step, count)
	var total: int = shape_counts[-1]

	for frame in frames:
		var pattern := out_dir_on_disk.path_join("tmp_%d_%%d.png" % frame)   # primitive fills in the shape count
		var args := PackedStringArray([
			"-i", input, "-o", pattern,
			"-n", str(total), "-nth", str(step),
			"-m", str(shape_mode), "-r", str(resize_input),
			"-s", str(output_size), "-a", str(alpha),
		])
		var output: Array = []
		var exit_code := OS.execute(program, args, output, true)
		if exit_code != 0:
			push_warning("primitive failed (exit %d): %s" % [exit_code, "".join(output)])
			return false

		# tmp_<frame>_<shape count>.png  ->  output_<frame>_<level>.png
		for level in shape_counts.size():
			var from := out_dir_on_disk.path_join("tmp_%d_%d.png" % [frame, shape_counts[level]])
			var to := out_dir_on_disk.path_join("output_%d_%d.png" % [frame, level])
			if not FileAccess.file_exists(from):
				push_warning("Generator: primitive did not make %s" % from)
				return false
			DirAccess.rename_absolute(from, to)

		# delete the in-between pictures we do not need
		var dir := DirAccess.open(out_dir)
		for file in dir.get_files():
			if file.begins_with("tmp_%d_" % frame):
				dir.remove(file)
	return true


# --- the primitive program ---------------------------------------------------

## Name of the primitive program for this computer, or "" if there is none.
static func _program_name() -> String:
	var cpu := Engine.get_architecture_name()   # "x86_64", "arm64", ...
	match OS.get_name():
		"Windows":
			return "primitive_windows_%s.exe" % cpu
		"Linux":
			return "primitive_linux_%s" % cpu
		"macOS":
			return "primitive_macos_%s" % cpu
	return ""   # phones and the web cannot run other programs


## Copies the program from res://bin to user://bin (a program inside the game
## files cannot be started directly) and returns its full path, or "".
static func _prepare_program() -> String:
	var program_name := _program_name()
	if program_name == "":
		push_warning("Generator: cannot run programs on %s" % OS.get_name())
		return ""
	var source := "res://bin/".path_join(program_name)
	var target := "user://bin/".path_join(program_name)
	if not FileAccess.file_exists(source):
		push_warning("Generator: no primitive program for this computer: %s" % program_name)
		return ""

	var source_file := FileAccess.open(source, FileAccess.READ)
	if source_file == null:
		return ""
	var needs_copy := true
	if FileAccess.file_exists(target):
		var target_file := FileAccess.open(target, FileAccess.READ)
		needs_copy = target_file == null or target_file.get_length() != source_file.get_length()
	if needs_copy:
		DirAccess.make_dir_recursive_absolute("user://bin")
		var copy := FileAccess.open(target, FileAccess.WRITE)
		if copy == null:
			push_warning("Generator: cannot write %s" % target)
			return ""
		copy.store_buffer(source_file.get_buffer(source_file.get_length()))
		copy.close()

	var full_path := ProjectSettings.globalize_path(target)
	if OS.get_name() != "Windows":
		OS.execute("chmod", ["+x", full_path])
	return full_path


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var rest := a % b
		a = b
		b = rest
	return a
