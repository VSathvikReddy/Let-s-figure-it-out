@tool  # also runs in the editor, so the collision shows while you place it
extends Sprite2D
## A decoration (sinan/assets/props/decor) you can stand on: like the
## platforms, it only collides on its TOP and only one way - jump up through
## it, land on it, Down + Jump drops through. Walking into its sides does
## nothing. Wide enough tops (min_nav_width) also join the "platforms" group,
## so goblins can plan jumps onto them.

## Where the top is, as a fraction of the picture's height from its top.
@export_range(0.0, 1.0) var top := 0.0:
	set(v):
		top = v
		_build()
## How much of the picture's width the top covers.
@export_range(0.1, 1.0) var top_width := 0.8:
	set(v):
		top_width = v
		_build()
## Off = only a picture (nothing to stand on).
@export var standable := true:
	set(v):
		standable = v
		_build()
## Tops narrower than this (world px) are not used by the goblins' path finding.
@export var min_nav_width := 40.0

var _body: StaticBody2D
var _shape: CollisionShape2D


func _enter_tree() -> void:
	if standable and not Engine.is_editor_hint() and _world_width() >= min_nav_width:
		add_to_group("platforms")


func _ready() -> void:
	_build()


func _build() -> void:
	if not is_inside_tree() or texture == null:
		return
	if _body == null:
		_body = StaticBody2D.new()
		_body.collision_mask = 0
		_body.add_to_group("one_way_platforms")
		add_child(_body)
		_shape = CollisionShape2D.new()
		_body.add_child(_shape)
	var size := texture.get_size()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size.x * top_width, 14.0)
	_shape.shape = rect
	# the picture is drawn from `offset`; its top edge is offset.y
	_shape.position = Vector2(offset.x + size.x * 0.5, offset.y + size.y * top + 7.0)
	_shape.one_way_collision = true
	_shape.one_way_collision_margin = 8.0
	_shape.disabled = not standable


func _world_width() -> float:
	return (texture.get_size().x * top_width * global_scale.x) if texture else 0.0


## For the NavGraph: the top line, in world space.
func nav_surface() -> Dictionary:
	var size := texture.get_size()
	var y := offset.y + size.y * top
	var cx := offset.x + size.x * 0.5
	var half := size.x * top_width * 0.5
	return {"left": to_global(Vector2(cx - half, y)), "right": to_global(Vector2(cx + half, y)),
		"body": _body, "one_way": true}
