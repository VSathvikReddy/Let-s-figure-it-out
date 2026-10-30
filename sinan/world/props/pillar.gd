@tool  # also runs in the editor, so the pillar shows while you place it
extends Node2D
## A pillar made from one picture (sinan/assets/props/pillars). The node's
## position is the middle of its FOOT: put it on the floor. It stands behind the
## player (you walk past it), and its flat top is a one-way ledge you can stand
## on - it joins the "platforms" group, so goblins can jump onto it too.

@export var texture: Texture2D:
	set(v):
		texture = v
		_build()
## Where the flat top is, as a fraction of the picture's height from its top.
@export_range(0.0, 0.5) var top := 0.02:
	set(v):
		top = v
		_build()
## How much of the picture's width the top ledge covers.
@export_range(0.2, 1.0) var top_width := 0.85:
	set(v):
		top_width = v
		_build()
## Off = only a decoration (nothing to stand on).
@export var standable := true

var _sprite: Sprite2D
var _body: StaticBody2D
var _shape: CollisionShape2D


func _enter_tree() -> void:
	if standable:
		add_to_group("platforms")


func _ready() -> void:
	z_index = 1  # in front of the painting, behind the player (z 2)
	_build()


func _build() -> void:
	if not is_inside_tree() or texture == null:
		return
	if _sprite == null:
		_sprite = Sprite2D.new()
		add_child(_sprite)
		_body = StaticBody2D.new()
		_body.collision_mask = 0
		_body.add_to_group("one_way_platforms")
		add_child(_body)
		_shape = CollisionShape2D.new()
		_body.add_child(_shape)
	var size := texture.get_size()
	_sprite.texture = texture
	_sprite.centered = false
	_sprite.offset = Vector2(-size.x * 0.5, -size.y)  # foot on the node
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size.x * top_width, 14.0)
	_shape.shape = rect
	_shape.position = Vector2(0, -size.y * (1.0 - top) + 7.0)
	_shape.one_way_collision = true
	_shape.one_way_collision_margin = 8.0
	_shape.disabled = not standable


## For the NavGraph: the top ledge, in world space.
func nav_surface() -> Dictionary:
	var size := texture.get_size() if texture else Vector2(60, 200)
	var y := -size.y * (1.0 - top)
	var half := size.x * top_width * 0.5
	return {"left": to_global(Vector2(-half, y)), "right": to_global(Vector2(half, y)),
		"body": _body, "one_way": true}
