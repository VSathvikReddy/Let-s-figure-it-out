@tool  # also runs in the editor, so you see the bounds while you build the level
extends Node2D
## Put this on the root of every level.
##
## It builds the LEVEL BOUNDS from the painting: a rectangle exactly the size
## of the painting's root picture. Change the picture and the bounds follow
## by themselves; there is nothing to set by hand.
## The camera stays inside these bounds, and so does the player.

## The painting the bounds are taken from.
@export var painting: Node2D

## Colour of the bounds outline (only drawn in the editor).
@export var bounds_color := Color(1.0, 0.8, 0.2)

const BOUNDS_NAME := "CameraBounds"

var bounds: ReferenceRect


func _ready() -> void:
	_update_bounds()
	set_process(Engine.is_editor_hint())   # _process only follows edits in the editor


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_bounds()   # follow the painting while you edit


## Creates (once) and sizes the bounds rectangle to match the painting.
## The camera finds it through the "level_bounds" group.
func _update_bounds() -> void:
	if painting == null or not painting.has_method("world_rect"):
		return
	var rect: Rect2 = painting.world_rect()
	if rect.size == Vector2.ZERO:
		return

	if bounds == null:
		bounds = ReferenceRect.new()
		bounds.name = BOUNDS_NAME
		bounds.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bounds.editor_only = true          # outline shows in the editor, not in the game
		bounds.border_width = 4.0
		bounds.add_to_group("level_bounds")
		add_child(bounds)                  # made by code, so it is never saved into the scene
	bounds.border_color = bounds_color
	bounds.global_position = rect.position
	bounds.size = rect.size


## The world rectangle the camera and player must stay inside.
func get_bounds_rect() -> Rect2:
	return bounds.get_global_rect() if bounds else Rect2()
