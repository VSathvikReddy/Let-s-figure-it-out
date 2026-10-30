extends MaskDisplay
class_name CustomLevel
## Builds its AnimatedSprite2D children at runtime from user-made PNGs named
## output_<i>_<n>.png (i = animation frame, n = level), then hands off to MaskDisplay.
## Set the variables (or use CustomLevel.create) BEFORE add_child().



# explicit counts
#var lvl := CustomLevel.create("levels/my_level", 5, 5, 8.0)
#add_child(lvl)
#
## auto-detect counts from the files
#var lvl2 := CustomLevel.create("levels/other_level")
#add_child(lvl2)
#
## from a scene
#var lvl3 := preload("res://custom_level.tscn").instantiate() as CustomLevel
#lvl3.folder = "levels/my_level"
#lvl3.levels = 5
#lvl3.animation_frames = 5
#add_child(lvl3)

const USER_TEXTURES := "user://"

var folder := ""                 ## subfolder inside user://, e.g. "levels/my_level"
var levels := 0                  ## 0 = auto-detect from files
var animation_frames := 0        ## 0 = auto-detect from files
var zoom_level := 8.0            ## scale applied on top of the image's native size
var fps := 8.0
var first_index := 0             ## set to 1 if files start at output_1_1.png
var reverse_levels := false      ## flip if n=0 is the FULL painting instead of the most broken


## Create and configure in one step. Add the result to the tree afterwards.
static func create(p_folder: String, p_levels := 0, p_frames := 0, p_zoom := 8.0) -> CustomLevel:
	var lvl := CustomLevel.new()
	lvl.folder = p_folder
	lvl.levels = p_levels
	lvl.animation_frames = p_frames
	lvl.zoom_level = p_zoom
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


func _path(i: int, n: int) -> String:
	return USER_TEXTURES.path_join(folder).path_join("output_%d_%d.png" % [i, n])


## Number of consecutive levels (n), checked on the first frame.
func _count_levels() -> int:
	var k := 0
	while FileAccess.file_exists(_path(first_index, first_index + k)):
		k += 1
	return k


## Number of consecutive animation frames (i), checked on the first level.
func _count_frames() -> int:
	var k := 0
	while FileAccess.file_exists(_path(first_index + k, first_index)):
		k += 1
	return k


func _build_sprites() -> bool:
	var level_sprites: Array[AnimatedSprite2D] = []

	for n in levels:
		var sf := SpriteFrames.new()   # comes with a "default" animation
		sf.set_animation_speed("default", fps)
		sf.set_animation_loop("default", true)

		for i in animation_frames:
			var path := _path(first_index + i, first_index + n)
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
		spr.scale = Vector2.ONE * zoom_level
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		level_sprites.append(spr)

	# MaskDisplay wants MOST BROKEN first, FULL PAINTING last
	if reverse_levels:
		level_sprites.reverse()

	# Remove any placeholder sprites immediately so MaskDisplay doesn't see them
	for c in get_children():
		if c is AnimatedSprite2D:
			remove_child(c)
			c.queue_free()

	for s in level_sprites:
		add_child(s)
	return true
