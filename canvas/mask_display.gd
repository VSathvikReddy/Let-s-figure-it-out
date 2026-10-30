class_name MaskDisplay
extends Node2D
## Just a viewer. It owns no damage data: it draws itself from the global PaintCanvas.
## Children: AnimatedSprite2Ds ordered from MOST BROKEN (first) to FULL PAINTING (last).
## The LAST one is the visible, animating one; the others follow its frame number
## and only donate their current frame texture to the shader.
## Frames must be separate images (not AtlasTexture) and the same size across levels.
## Put as many of these in the scene as you like; they all show the same mask.

const SHADER := preload("res://canvas/paint_canvas.gdshader")
const MAX_LEVELS := 8

@export var blur := 1.5        ## blur radius, in mask pixels

var sprites: Array[AnimatedSprite2D] = []
var full: AnimatedSprite2D
var mat: ShaderMaterial


func _ready() -> void:
	for c in get_children():
		if c is AnimatedSprite2D:
			sprites.append(c)
	if _error_check(sprites):
		return

	full = sprites[-1]
	PaintCanvas.setup(full, sprites.size())

	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("mask", PaintCanvas.texture)
	mat.set_shader_parameter("max_level", float(sprites.size() - 1))
	mat.set_shader_parameter("blur", blur)
	for s in sprites:
		if s != full:
			s.visible = false   # only donates its current frame
			s.stop()            # its frame is driven by `full`
	full.material = mat

	full.frame_changed.connect(_push_frames)
	full.animation_changed.connect(_push_frames)
	PaintCanvas.configured.connect(_apply)
	_push_frames()
	_apply()


## Hand the current frame of every level to the shader.
func _push_frames() -> void:
	for i in sprites.size():
		var s := sprites[i]
		if s.sprite_frames == null:
			continue
		if s != full:
			var n := s.sprite_frames.get_frame_count(s.animation)
			if n > 0:
				s.frame = full.frame % n   # levels with fewer frames loop
		mat.set_shader_parameter("lvl%d" % i, s.sprite_frames.get_frame_texture(s.animation, s.frame))


func _error_check(list) -> bool:
	if list.size() < 2:
		push_warning("MaskDisplay needs at least 2 AnimatedSprite2D children")
		return true
	if list.size() > MAX_LEVELS:
		push_warning("MaskDisplay supports at most %d sprites" % MAX_LEVELS)
		return true
	return false


func _apply() -> void:
	mat.set_shader_parameter("steps", float(PaintCanvas.steps))
	mat.set_shader_parameter("step_value", PaintCanvas.step / 255.0)
