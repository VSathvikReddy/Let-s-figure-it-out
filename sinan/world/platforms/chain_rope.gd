@tool
class_name ChainRope
extends Node2D
## A hanging chain, one link sprite per physics node. Its two ends follow
## nodes you pick in the Inspector (Start Node = ceiling end, End Node = bottom
## end - e.g. an anchor Marker2D and a bracket on a swinging board). Leave them
## empty and it uses its own Start / End child markers instead. Move the ends
## in the editor and the links fill the gap; it simulates in the editor too.
##
## Physics: a cheap Verlet rope (point masses + fixed-length links, a few
## correction passes per frame) with gravity and damping. When the board it
## holds swings, the links follow, lag and settle.
##
## Front Links: the last few links at the bottom end are drawn on a layer in
## front of the board (Front Z Offset), so the chain wraps over the bracket
## instead of disappearing behind the board.

const LINK_TEX := preload("res://sinan/assets/props/board/chain_link.png")
const HOOK_TEX := preload("res://sinan/assets/props/board/hook.png")

## Node the top of the chain hangs from (empty = this node's Start child).
@export var start_node: NodePath
## Node the bottom of the chain is fixed to (empty = this node's End child).
@export var end_node: NodePath
@export var link_texture: Texture2D = LINK_TEX:
	set(v):
		link_texture = v
		_rebuild()
## Ceiling hook drawn at the start (empty = none).
@export var hook_texture: Texture2D = HOOK_TEX
## On-screen width of the chain; link length follows the sprite's proportions.
@export var link_width := 12.0:
	set(v):
		link_width = maxf(v, 1.0)
		_rebuild()
## Chain length / straight distance. 1 = taut, 1.1 = hangs in a soft curve.
@export_range(1.0, 2.0) var slack := 1.0:
	set(v):
		slack = v
		_rebuild()
## Keep the bottom end fixed. Off = it dangles freely.
@export var pin_end := true

@export_group("Front Links")
## How many links at the bottom end are drawn in front of the board.
@export_range(0, 8) var front_links := 2
## Z of those links relative to this chain (raise it if the board draws over them).
@export var front_z_offset := 1

@export_group("Physics")
@export var gravity := 900.0
## Velocity lost per second (higher = calmer chain).
@export var drag := 3.0
## Constraint passes per frame (more = stiffer links).
@export_range(1, 16) var iterations := 6

var _pts := PackedVector2Array()
var _prev := PackedVector2Array()
var _seg := 10.0
var _start := Vector2.ZERO
var _end := Vector2(0, 120)
var _last_start := Vector2.INF
var _last_end := Vector2.INF
var _front: Node2D


func _ready() -> void:
	if start_node.is_empty() or end_node.is_empty():
		_ensure_markers()
	_front = Node2D.new()
	_front.z_index = front_z_offset
	_front.draw.connect(_draw_front)
	add_child(_front, false, Node.INTERNAL_MODE_BACK)
	_read_ends()
	_rebuild()


## Knock the chain: adds velocity to the links near a local point.
func poke(local_point: Vector2, impulse: Vector2, radius := 40.0) -> void:
	var dt := 1.0 / 60.0
	for i in _pts.size():
		var f := 1.0 - clampf(_pts[i].distance_to(local_point) / radius, 0.0, 1.0)
		if f > 0.0:
			_prev[i] -= impulse * f * dt


func _ensure_markers() -> void:
	for n in ["Start", "End"]:
		if (n == "Start" and not start_node.is_empty()) or (n == "End" and not end_node.is_empty()):
			continue
		if get_node_or_null(n) == null:
			var m := Marker2D.new()
			m.name = n
			m.position = Vector2.ZERO if n == "Start" else Vector2(0, 160)
			add_child(m)
			if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
				m.owner = get_tree().edited_scene_root


func _end_point(path: NodePath, fallback: String, current: Vector2) -> Vector2:
	var n := (get_node_or_null(path) if not path.is_empty() else get_node_or_null(fallback)) as Node2D
	return to_local(n.global_position) if n else current


func _read_ends() -> void:
	_start = _end_point(start_node, "Start", _start)
	_end = _end_point(end_node, "End", _end)


func _tile_length() -> float:
	if link_texture == null:
		return link_width
	var sz := link_texture.get_size()
	return link_width * sz.y / sz.x


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var length := _start.distance_to(_end) * slack
	var n := maxi(1, roundi(length / maxf(_tile_length(), 1.0)))
	_seg = length / n
	_pts.resize(n + 1)
	_prev.resize(n + 1)
	# a slack chain starts bowed sideways (perpendicular to it), not bunched up
	var sag := sqrt(maxf(length * length - _start.distance_squared_to(_end), 0.0)) * 0.5
	var side := (_end - _start).orthogonal().normalized()
	if side.y < 0.0:
		side = -side
	for i in n + 1:
		var u := float(i) / n
		var p := _start.lerp(_end, u) + side * sin(u * PI) * sag
		_pts[i] = p
		_prev[i] = p
	_last_start = _start
	_last_end = _end
	_redraw()


func _physics_process(delta: float) -> void:
	_read_ends()
	if _pts.size() < 2:
		return
	# in the editor the ends are being dragged around: re-lay the chain
	if Engine.is_editor_hint() and (_start.distance_to(_last_start) > 0.5 or _end.distance_to(_last_end) > 0.5):
		_rebuild()
	_last_start = _start
	_last_end = _end
	_simulate(delta)
	_redraw()


func _redraw() -> void:
	queue_redraw()
	if _front:
		_front.z_index = front_z_offset
		_front.queue_redraw()


func _simulate(delta: float) -> void:
	var n := _pts.size()
	var keep := exp(-drag * delta)
	var acc := Vector2(0, gravity) * delta * delta
	for i in n:
		var p := _pts[i]
		var v := (p - _prev[i]) * keep
		_prev[i] = p
		_pts[i] = p + v + acc
	for _k in iterations:
		_pts[0] = _start
		if pin_end:
			_pts[n - 1] = _end
		for i in n - 1:
			var a := _pts[i]
			var b := _pts[i + 1]
			var d := b - a
			var len := d.length()
			if len < 0.0001:
				continue
			var diff := (len - _seg) / len
			var a_fixed := i == 0
			var b_fixed := pin_end and i + 1 == n - 1
			if a_fixed and b_fixed:
				continue
			elif a_fixed:
				_pts[i + 1] = b - d * diff
			elif b_fixed:
				_pts[i] = a + d * diff
			else:
				_pts[i] = a + d * diff * 0.5
				_pts[i + 1] = b - d * diff * 0.5
	_pts[0] = _start
	if pin_end:
		_pts[n - 1] = _end
		# under tension (ends pulled as far apart as the chain is long) a real
		# chain is a straight line: pull the links onto it, harder the tauter it is
		var length := _seg * (n - 1)
		var taut := clampf((_start.distance_to(_end) / maxf(length, 0.001) - 0.97) / 0.03, 0.0, 1.0)
		if taut > 0.0:
			for i in range(1, n - 1):
				var on_line := _start.lerp(_end, float(i) / (n - 1))
				_pts[i] = _pts[i].lerp(on_line, taut)
				_prev[i] = _prev[i].lerp(on_line, taut * 0.8)


func _draw() -> void:
	var links := _pts.size() - 1
	_draw_links(self, 0, links - mini(front_links, links))
	if hook_texture and _pts.size() > 0:
		var hs := hook_texture.get_size()
		var k := link_width * 1.45 / hs.x
		draw_set_transform(_pts[0], 0.0, Vector2(k, k))
		draw_texture(hook_texture, Vector2(-hs.x * 0.5, -hs.y * 0.55))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_front() -> void:
	var links := _pts.size() - 1
	_draw_links(_front, links - mini(front_links, links), links)


## Draw links [from, to) on a canvas item; each sprite stretched between its two nodes.
func _draw_links(ci: CanvasItem, from: int, to: int) -> void:
	if link_texture == null:
		return
	var tex_size := link_texture.get_size()
	var sx := link_width / tex_size.x
	for i in range(maxi(from, 0), to):
		var a := _pts[i]
		var d := _pts[i + 1] - a
		var len := d.length()
		if len < 0.01:
			continue
		ci.draw_set_transform(a, d.angle() - PI * 0.5, Vector2(sx, len / tex_size.y))
		ci.draw_texture(link_texture, Vector2(-tex_size.x * 0.5, 0.0))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
