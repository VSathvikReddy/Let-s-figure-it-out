class_name ClawMarks
extends Node2D
## Parallel claw scratches (three by default) left on the canvas; they fade slowly.
## Spawn one inside a painting layer at the scratch point.
## Drawn once; the fade is a tween on modulate (no redraw every frame).
## At most MAX_ALIVE exist at once: a new one retires the oldest (a raking bat
## stream makes hundreds).

const MAX_ALIVE := 150
static var _alive: Array[Node] = []

@export var color := Color(0.15, 0.1, 0.12)
@export var dir := Vector2.RIGHT
@export var size := 14.0
@export var life := 2.5
## Number of parallel scratches.
@export var lines := 3


func _ready() -> void:
	_alive.append(self)
	while _alive.size() > MAX_ALIVE:
		var old: Node = _alive.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var tw := create_tween()
	tw.tween_interval(life * 0.48)
	tw.tween_property(self, "modulate:a", 0.0, life * 0.52)
	tw.tween_callback(queue_free)


func _exit_tree() -> void:
	_alive.erase(self)


func _draw() -> void:
	var n := dir.orthogonal()
	for i in lines:
		var o := n * (i - (lines - 1) * 0.5) * size * 0.35
		draw_line(o - dir * size * 0.6, o + dir * size * 0.6, Color(color, 0.8), 2.0, true)
