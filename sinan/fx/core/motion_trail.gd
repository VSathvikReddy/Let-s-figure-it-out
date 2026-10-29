class_name MotionTrail
extends Line2D
## A fading ribbon that follows a node while `emitting` is on - used to show an
## attack is committed (bird talons on a strike, bats on a dive pass).
## Add it as a child node, set Target (empty = its parent), the colour and
## Width in the Inspector; the owner just flips `emitting`.
## The line draws in world space (top_level), so it stays put behind the mover.

## Node whose position is traced (empty = parent).
@export var target: NodePath
@export var emitting := false
## How long a point lives (seconds) - the trail's length in time.
@export var trail_time := 0.18
## Minimum distance between recorded points (px).
@export var min_step := 4.0
@export var max_points := 24

var _ages := PackedFloat32Array()
var _target: Node2D


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	clear_points()
	_target = (get_node_or_null(target) if not target.is_empty() else get_parent()) as Node2D
	if width_curve == null:
		width_curve = Curve.new()
		width_curve.add_point(Vector2(0.0, 0.0))
		width_curve.add_point(Vector2(1.0, 1.0))
	if gradient == null:
		gradient = Gradient.new()
		gradient.set_color(0, Color(default_color, 0.0))
		gradient.set_color(1, default_color)
	joint_mode = Line2D.LINE_JOINT_ROUND
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND


func _process(delta: float) -> void:
	if _ages.is_empty() and not emitting:
		return  # nothing to age or record
	global_position = Vector2.ZERO
	global_rotation = 0.0
	# age points; drop the old ones (oldest are first)
	for i in _ages.size():
		_ages[i] += delta
	while _ages.size() > 0 and _ages[0] >= trail_time:
		_ages.remove_at(0)
		remove_point(0)
	if emitting and is_instance_valid(_target):
		var p := _target.global_position
		var n := get_point_count()
		if n == 0 or get_point_position(n - 1).distance_to(p) >= min_step:
			add_point(p)
			_ages.append(0.0)
			if get_point_count() > max_points:
				remove_point(0)
				_ages.remove_at(0)
		elif n > 0:
			set_point_position(n - 1, p)
