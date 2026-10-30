extends "res://compined/painting/painting.gd"
## The painting of the custom level. It works exactly like the other paintings
## (painting.gd), but its pictures are not in the scene: they are loaded when
## the level starts, from the pictures the player made with the custom card
## (user://levels/custom/output_<frame>_<level>.png).
##
## The generated pictures are small (256 px); like every painting, it is
## scaled up to the same area as the benchmark (painting.gd).

const Generator := preload("res://compined/levels/custom/painting_generator.gd")

## Animation speed of the pictures (each frame is a slightly different drawing).
@export var frames_per_second := 8.0
## Folder inside user:// with the pictures.
@export var folder := Generator.CUSTOM_FOLDER


func _ready() -> void:
	if not Engine.is_editor_hint():
		_load_pictures()
	super._ready()


## True when there were enough pictures to make a painting.
func has_pictures() -> bool:
	return pictures.size() >= 2


## Adds one AnimatedSprite2D per detail level, MOST DETAILED first (that is the
## order painting.gd wants). Each one plays through all the animation frames.
func _load_pictures() -> void:
	var levels := Generator.count_levels(folder)
	var frames := Generator.count_frames(folder)
	if levels < 2 or frames < 1:
		push_warning("Custom painting: no pictures in user://%s - make some with the custom card first" % folder)
		return

	for level in range(levels - 1, -1, -1):   # generated level 0 is the crudest, so go backwards
		var animation := SpriteFrames.new()   # comes with a "default" animation
		animation.set_animation_speed("default", frames_per_second)
		animation.set_animation_loop("default", true)
		for frame in frames:
			var image := Image.load_from_file(Generator.file_path(folder, frame, level))
			if image == null or image.is_empty():
				push_warning("Custom painting: could not load %s" % Generator.file_path(folder, frame, level))
				return
			animation.add_frame("default", ImageTexture.create_from_image(image))

		var picture := AnimatedSprite2D.new()
		picture.name = "Level%d" % level
		picture.sprite_frames = animation
		picture.autoplay = "default"
		add_child(picture)

