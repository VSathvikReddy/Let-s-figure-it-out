class_name ClawMarks
extends Node2D
## Parallel claw scratches (three by default) left on the canvas; they fade slowly.
## Spawn one inside a painting layer at the scratch point.

@export var color := Color(0.15, 0.1, 0.12)
@export var dir := Vector2.RIGHT
@export var size := 14.0
@export var life := 2.5
## Number of parallel scratches.
@export var lines := 3

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t > life:
		queue_free()


func _draw() -> void:
	var a := clampf(1.0 - (_t - life * 0.48) / (life * 0.52), 0.0, 1.0)
	var n := dir.orthogonal()
	for i in lines:
		var o := n * (i - (lines - 1) * 0.5) * size * 0.35
		draw_line(o - dir * size * 0.6, o + dir * size * 0.6, Color(color, 0.8 * a), 2.0, true)
