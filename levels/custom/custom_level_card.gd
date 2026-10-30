class_name CustomLevelCard
extends PanelContainer
## The 5th card in the level selector: "Create your own level".
## The player picks a PNG, chooses animation frames + number of levels and hits Generate.
## CustomLevel.generate() (fogleman/primitive) runs on a background Thread, and the progress
## bar is driven by counting how many of the expected output files already exist on disk.

signal play_requested   ## the player pressed "Enter Painting" on a finished custom level

const OUT_FOLDER := "levels/custom"   ## inside user://
const POLL_INTERVAL := 0.1            ## seconds between file-count checks

# --- HARD-CODED PRIMITIVE SETTINGS ---------------------------------------------------------
# Shape counts, from MOST BROKEN to FULL PAINTING. Must be strictly increasing, and the pool
# can't be bigger than MaskDisplay.MAX_LEVELS. When the player asks for N levels we pick N
# evenly spread entries, always including the first and the last one.
var shape_count_pool: Array[int] = [10, 30, 70, 300, 500, 2000, 5000]
var shape_mode := 1        # 1 = triangles (see CustomLevel.generate for the other modes)
var resize_input := 256    # primitive -r
var output_size := 256     # primitive -s
var alpha := 128           # primitive -a

# --- STATE ---------------------------------------------------------------------------------
var input_path := ""
var thread: Thread
var poll_timer := 0.0
var frames_target := 0
var counts_target: Array[int] = []

# --- UI ------------------------------------------------------------------------------------
var thumb: TextureRect
var thumb_hint: Label
var file_label: Label
var choose_button: Button
var frames_spin: SpinBox
var levels_spin: SpinBox
var progress: ProgressBar
var status_label: Label
var generate_button: Button
var play_button: Button
var file_dialog: FileDialog


func _init(card_size := Vector2(320, 400)) -> void:
	custom_minimum_size = card_size
	size = card_size
	pivot_offset = card_size / 2.0
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	_build_ui()
	set_process(false)
	_detect_existing()


func _exit_tree() -> void:
	# A Thread must be joined before it is freed (this blocks until primitive is done).
	if thread != null and thread.is_started():
		thread.wait_to_finish()
		thread = null


func is_busy() -> bool:
	return thread != null


## Called by the level select when the player tries to leave while generating.
func show_busy_hint() -> void:
	status_label.text = "Please wait, still generating..."


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(vbox)

	# 1. Preview of the chosen PNG
	var thumb_bg := ColorRect.new()
	thumb_bg.color = Color(0.30, 0.30, 0.38)
	thumb_bg.custom_minimum_size = Vector2(280, 90)
	thumb_bg.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(thumb_bg)

	thumb = TextureRect.new()
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
	thumb.mouse_filter = Control.MOUSE_FILTER_PASS
	thumb_bg.add_child(thumb)

	thumb_hint = Label.new()
	thumb_hint.text = "+  Your picture here"
	thumb_hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	thumb_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thumb_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	thumb_hint.modulate = Color(1, 1, 1, 0.6)
	thumb_hint.mouse_filter = Control.MOUSE_FILTER_PASS
	thumb_bg.add_child(thumb_hint)

	# 2. Title
	var title := Label.new()
	title.text = "Custom Painting: Create Your Own"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(title)

	# 3. PNG chooser row
	var file_row := HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 8)
	file_row.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(file_row)

	choose_button = Button.new()
	choose_button.text = "Choose PNG..."
	choose_button.pressed.connect(_on_choose_pressed)
	file_row.add_child(choose_button)

	file_label = Label.new()
	file_label.text = "No file selected"
	file_label.clip_text = true
	file_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_label.modulate = Color(0.75, 0.75, 0.85)
	file_label.mouse_filter = Control.MOUSE_FILTER_PASS
	file_row.add_child(file_label)

	# 4. Frames + levels row
	var param_row := HBoxContainer.new()
	param_row.add_theme_constant_override("separation", 6)
	param_row.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(param_row)

	frames_spin = _add_spin(param_row, "Frames", 1, 12, 5)
	levels_spin = _add_spin(param_row, "Levels", 2, mini(shape_count_pool.size(), CustomLevel.MAX_LEVELS), 5)

	# 5. Progress
	progress = ProgressBar.new()
	progress.min_value = 0
	progress.max_value = 1
	progress.value = 0
	progress.custom_minimum_size = Vector2(0, 20)
	progress.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(progress)

	status_label = Label.new()
	status_label.text = "Choose a PNG to begin"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.modulate = Color(0.75, 0.75, 0.85)
	status_label.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(status_label)

	# 6. Buttons
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	button_row.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(button_row)

	generate_button = Button.new()
	generate_button.text = "Generate"
	generate_button.custom_minimum_size = Vector2(0, 42)
	generate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	generate_button.disabled = true
	generate_button.pressed.connect(_on_generate_pressed)
	button_row.add_child(generate_button)

	play_button = Button.new()
	play_button.text = "Enter Painting"
	play_button.custom_minimum_size = Vector2(0, 42)
	play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_button.disabled = true
	play_button.pressed.connect(func() -> void: play_requested.emit())
	button_row.add_child(play_button)

	# 7. File dialog (a Window, so it lives outside the card layout)
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png ; PNG images"])
	file_dialog.title = "Choose a PNG"
	file_dialog.use_native_dialog = true
	file_dialog.file_selected.connect(_on_png_selected)
	add_child(file_dialog)


func _add_spin(parent: Control, label_text: String, min_v: int, max_v: int, default_v: int) -> SpinBox:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = 1
	spin.value = default_v
	spin.rounded = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spin)
	return spin


# ---------------------------------------------------------------------------
# Choosing the PNG
# ---------------------------------------------------------------------------

func _on_choose_pressed() -> void:
	if is_busy():
		return
	if file_dialog.use_native_dialog:
		file_dialog.popup()
	else:
		file_dialog.popup_centered_ratio(0.7)


func _on_png_selected(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		status_label.text = "Could not read that image"
		return

	input_path = path
	file_label.text = path.get_file()
	_show_texture(ImageTexture.create_from_image(img))
	generate_button.disabled = false
	status_label.text = "Ready to generate"
	progress.value = 0


func _show_texture(tex: Texture2D) -> void:
	thumb.texture = tex
	thumb_hint.visible = tex == null


# ---------------------------------------------------------------------------
# Generation (background thread)
# ---------------------------------------------------------------------------

## Picks `n` entries from shape_count_pool, evenly spread, always including first and last.
func _select_counts(n: int) -> Array[int]:
	var counts: Array[int] = []
	var last := shape_count_pool.size() - 1
	for k in n:
		counts.append(shape_count_pool[roundi(k * last / float(n - 1))])
	return counts


func _on_generate_pressed() -> void:
	if is_busy() or input_path == "":
		return

	frames_target = int(frames_spin.value)
	counts_target = _select_counts(int(levels_spin.value))

	_clear_output()   # old files would make the progress count wrong
	progress.max_value = frames_target * counts_target.size()
	progress.value = 0
	play_button.disabled = true
	_set_controls_locked(true)
	status_label.text = "Starting..."

	thread = Thread.new()
	var err := thread.start(CustomLevel.generate.bind(
		input_path, OUT_FOLDER, counts_target, frames_target,
		shape_mode, resize_input, output_size, alpha
	))
	if err != OK:
		thread = null
		_set_controls_locked(false)
		status_label.text = "Could not start the generator thread"
		return

	poll_timer = 0.0
	set_process(true)


func _process(delta: float) -> void:
	if thread == null:
		set_process(false)
		return

	poll_timer += delta
	if poll_timer >= POLL_INTERVAL:
		poll_timer = 0.0
		_update_progress()

	if not thread.is_alive():
		var ok: bool = thread.wait_to_finish()
		thread = null
		set_process(false)
		_on_generation_finished(ok)


## Progress = how many of the expected files exist. primitive writes tmp_<i>_<shapes>.png as it
## goes and CustomLevel.generate renames the needed ones to output_<i>_<n>.png, so either counts.
func _count_done() -> int:
	var dir := CustomLevel.USER_TEXTURES.path_join(OUT_FOLDER)
	var done := 0
	for i in frames_target:
		for n in counts_target.size():
			if FileAccess.file_exists(CustomLevel._file_path(OUT_FOLDER, i, n)) \
					or FileAccess.file_exists(dir.path_join("tmp_%d_%d.png" % [i, counts_target[n]])):
				done += 1
	return done


func _update_progress() -> void:
	var done := _count_done()
	progress.value = done
	status_label.text = "Generating... %d / %d files" % [done, int(progress.max_value)]


func _on_generation_finished(ok: bool) -> void:
	_set_controls_locked(false)
	if ok:
		progress.value = progress.max_value
		status_label.text = "Done! %d files generated" % int(progress.max_value)
		play_button.disabled = false
		_show_preview_from_output(counts_target.size() - 1)
	else:
		_update_progress()
		status_label.text = "Generation failed (check the Output log)"


func _set_controls_locked(locked: bool) -> void:
	choose_button.disabled = locked
	frames_spin.editable = not locked
	levels_spin.editable = not locked
	generate_button.disabled = locked or input_path == ""
	if locked:
		play_button.disabled = true


func _clear_output() -> void:
	var dir_path := CustomLevel.USER_TEXTURES.path_join(OUT_FOLDER)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.begins_with("output_") or f.begins_with("tmp_"):
			d.remove(f)


# ---------------------------------------------------------------------------
# Re-opening the menu: pick up a previously generated custom level
# ---------------------------------------------------------------------------

func _detect_existing() -> void:
	var frames := 0
	while frames < 64 and FileAccess.file_exists(CustomLevel._file_path(OUT_FOLDER, frames, 0)):
		frames += 1
	var levels := 0
	while levels < CustomLevel.MAX_LEVELS and FileAccess.file_exists(CustomLevel._file_path(OUT_FOLDER, 0, levels)):
		levels += 1
	if frames < 1 or levels < 2:
		return

	for i in frames:
		for n in levels:
			if not FileAccess.file_exists(CustomLevel._file_path(OUT_FOLDER, i, n)):
				return   # incomplete grid, ignore

	frames_spin.value = clampi(frames, int(frames_spin.min_value), int(frames_spin.max_value))
	levels_spin.value = clampi(levels, int(levels_spin.min_value), int(levels_spin.max_value))
	progress.max_value = frames * levels
	progress.value = progress.max_value
	status_label.text = "Saved custom level: %d frames x %d levels" % [frames, levels]
	play_button.disabled = false
	_show_preview_from_output(levels - 1)


func _show_preview_from_output(level: int) -> void:
	var path := ProjectSettings.globalize_path(CustomLevel._file_path(OUT_FOLDER, 0, level))
	var img := Image.load_from_file(path)
	if img != null and not img.is_empty():
		_show_texture(ImageTexture.create_from_image(img))
