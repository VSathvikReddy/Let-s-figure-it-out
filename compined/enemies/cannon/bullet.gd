extends Area2D
## The cannon's bullet. Flies in a straight line toward where the player WAS
## when it was fired. Hurts the player on touch, pops on anything else, or
## pops by itself after `lifetime`. When it pops it breaks a bit of the
## painting around it.

const Effects := preload("res://compined/common/effects.gd")

@export var speed := 450.0
@export var damage := 1
@export var lifetime := 1.0           ## seconds before it pops on its own
@export var painting_damage := 1

var direction := Vector2.RIGHT
var _popped := false

@onready var paint_area: Area2D = $PaintArea


## Called by the cannon right after adding the bullet to the level.
func fire(from: Vector2, toward: Vector2) -> void:
	global_position = from
	direction = from.direction_to(toward)
	rotation = direction.angle()


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime, false).timeout.connect(_pop.bind(Color(1.0, 0.8, 0.2)))


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemy"):
		return   # flies through other enemies
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(damage)
		_pop(Color(1.0, 0.2, 0.2))
	else:
		_pop(Color(1.0, 0.8, 0.2))


func _pop(color: Color) -> void:
	if _popped:
		return   # the timer and a hit can both arrive
	_popped = true
	Effects.burst(self, 16, color, 0.3, 60.0, 140.0, 3.0, 5.0)
	Effects.paint(paint_area, -painting_damage)
	queue_free()
