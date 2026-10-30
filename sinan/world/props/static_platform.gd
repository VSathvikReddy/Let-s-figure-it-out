@tool  # also runs in the editor, so the platform shows while you place it
extends Node2D
## A fixed platform made from one picture (sinan/assets/props/platforms).
## The node's position is the middle of the WALKABLE TOP: put it where you want
## to stand. Collision is one-way (jump up through it, Down + Jump drops through),
## and it joins the "platforms" group with nav_surface(), so goblins plan jumps
## onto it like onto the hanging boards.

@export var texture: Texture2D:
	set(v):
		texture = v
		_build()
## Where the walkable top is, as a fraction of the picture's height from its
## top (0 = the very top; a rope bridge's deck is lower down).
@export_range(0.0, 1.0) var surface := 0.03:
	set(v):
		surface = v
		_build()
## How much of the picture's width you can stand on (trims the rounded ends).
@export_range(0.3, 1.0) var walk_width := 0.94:
	set(v):
		walk_width = v
		_build()
@export var one_way := true

var _sprite: Sprite2D
var _body: StaticBody2D
var _shape: CollisionShape2D


func _enter_tree() -> void:
	add_to_group("platforms")


func _ready() -> void:
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
	_sprite.offset = Vector2(-size.x * 0.5, -size.y * surface)  # the top line sits on the node
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size.x * walk_width, 14.0)
	_shape.shape = rect
	_shape.position = Vector2(0, 7.0)
	_shape.one_way_collision = one_way
	_shape.one_way_collision_margin = 8.0


## For the NavGraph: the walkable line, in world space.
func nav_surface() -> Dictionary:
	var half := (texture.get_size().x * walk_width * 0.5) if texture else 40.0
	return {"left": to_global(Vector2(-half, 0)), "right": to_global(Vector2(half, 0)),
		"body": _body, "one_way": one_way}
