extends Line2D
## A fading ribbon that follows a node while `emitting` is on. Used to show
## that an attack is coming for you (the bird's talons during a lunge or dive).
##
## Add it as a child, set `target` (empty = its parent), the colour and the
## width in the Inspector. The owner only switches `emitting` on and off.
## The line is drawn in world space, so it stays behind the thing that moves.

## The node whose path is traced (empty = the parent).
@export var target: NodePath
@export var emitting := false
## How long a point of the ribbon lives, in seconds (= how long the ribbon is).
@export var trail_time := 0.18
## Smallest distance between two recorded points, in px.
@export var min_step := 4.0
@export var max_points := 24

var _ages := PackedFloat32Array()   # age of every point, oldest first
var _target: Node2D


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	clear_points()
	_target = (get_node_or_null(target) if not target.is_empty() else get_parent()) as Node2D
	# thin and transparent at the old end, full at the new end
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
		return
	global_position = Vector2.ZERO
	global_rotation = 0.0

	# old points fade away
	for i in _ages.size():
		_ages[i] += delta
	while _ages.size() > 0 and _ages[0] >= trail_time:
		_ages.remove_at(0)
		remove_point(0)

	# new points follow the target
	if emitting and is_instance_valid(_target):
		var point := _target.global_position
		var count := get_point_count()
		if count == 0 or get_point_position(count - 1).distance_to(point) >= min_step:
			add_point(point)
			_ages.append(0.0)
			if get_point_count() > max_points:
				remove_point(0)
				_ages.remove_at(0)
		elif count > 0:
			set_point_position(count - 1, point)
