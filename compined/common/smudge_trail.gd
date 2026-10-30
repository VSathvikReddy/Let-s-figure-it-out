extends Node2D
## Smudges the painting along the path of whatever it is attached to.
## Add it as a child of an enemy projectile (the cannon bullet, the bat's
## fireball): as the projectile flies, it leaves a band of broken painting
## behind it. Tweak it in the Inspector of this node.

const Effects := preload("res://compined/common/effects.gd")

## Width of the smudged band: the radius of each smudge, in px.
@export var radius := 70.0
## Distance travelled between two smudges, in px (smaller = smoother band).
@export var spacing := 55.0
## How much each smudge breaks the painting (1 = one detail level).
@export var strength := 1

var _last_stamp := Vector2.INF


func _physics_process(_delta: float) -> void:
	if _last_stamp == Vector2.INF:
		_stamp()   # first smudge right where it starts
		return
	if global_position.distance_to(_last_stamp) >= spacing:
		_stamp()


func _stamp() -> void:
	_last_stamp = global_position
	if Effects.is_inside_level(self, global_position):
		Effects.paint_circle(self, global_position, radius, -strength)
