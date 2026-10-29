extends Node2D
## Click demo. Left click = break one level, right click = repair one level,
## mouse wheel = brush size. Painting only works after PaintMask.setup() is called.

@export var reference: Sprite2D   ## the full-painting sprite (last child of a PaintCanvas)

var brush: Area2D
var circle := CircleShape2D.new()


func _ready() -> void:
	circle.radius = 60.0
	var shape := CollisionShape2D.new()
	shape.shape = circle
	brush = Area2D.new()
	brush.add_child(shape)
	add_child(brush)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_paint(1)
			MOUSE_BUTTON_RIGHT:
				_paint(-1)
			MOUSE_BUTTON_WHEEL_UP:
				circle.radius = minf(circle.radius + 10.0, 400.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				circle.radius = maxf(circle.radius - 10.0, 10.0)


func _paint(count: int) -> void:
	brush.global_position = get_global_mouse_position()
	PaintCanvas.paint(brush, count)
