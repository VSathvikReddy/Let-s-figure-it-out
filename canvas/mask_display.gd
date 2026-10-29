class_name MaskDisplay
extends Node2D
## Just a viewer. It owns no damage data: it draws itself from the global PaintMask.
## Children: Sprite2Ds ordered from MOST BROKEN (first) to FULL PAINTING (last).
## Put as many of these in the scene as you like; they all show the same mask.

const SHADER := preload("res://canvas/paint_canvas.gdshader")
const MAX_LEVELS := 8

@export var blur := 1.5        ## blur radius, in mask pixels

var full: Sprite2D
var mat: ShaderMaterial


func _ready() -> void:
	
	var sprites: Array[Sprite2D] = []
	for c in get_children():
		if c is Sprite2D:
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
	for i in mini(sprites.size(), MAX_LEVELS):
		mat.set_shader_parameter("lvl%d" % i, sprites[i].texture)
		if sprites[i] != full:
			sprites[i].visible = false   # only donates its texture
	full.material = mat

	PaintCanvas.configured.connect(_apply)
	_apply()

func _error_check(sprites) ->bool:
	if sprites.size() < 2:
		push_warning("PaintCanvas needs at least 2 Sprite2D children")
		return true
	if sprites.size() > MAX_LEVELS:
		push_warning("PaintCanvas supports at most %d sprites" % MAX_LEVELS)
		return true
	return false

func _apply() -> void:
	mat.set_shader_parameter("steps", float(PaintCanvas.steps))
	mat.set_shader_parameter("step_value", PaintCanvas.step / 255.0)
