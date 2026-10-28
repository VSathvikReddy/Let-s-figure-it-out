class_name NavGraph
extends Node2D
## Platform navigation for grounded enemies (goblins) and air / perch points
## for flyers (bird, bats). Put one in the level; it finds every HangingBoard
## (group "platforms") plus the floor bodies listed below, and works out which
## surfaces connect:
##   JUMP  - a ballistic jump (up, across or down) that fits the jump limits
##           and does not hit anything solid on the way
##   DROP  - fall through a one-way board onto the surface below it
## Enemies ask find_path(from, to) and get a list of links to follow.
## Press F3 in game to see surfaces and links.

enum { JUMP, DROP }

## Bodies whose rectangle shapes count as floor (their top edge is walkable).
@export var floor_bodies: Array[NodePath] = [^"../frame collision"]
## Navigator limits - keep them a bit below the goblin's real jump so the
## player can always out-climb it.
@export var jump_height := 112.0
@export var gravity := 1800.0
@export var max_speed_x := 430.0
## Stay this far from surface ends when taking off / landing.
@export var edge_inset := 16.0
## Air points for flyers stay inside this Control/Sprite rect (the frame), pulled in by air_margin.
@export var air_bounds: NodePath = ^"../frame/NinePatchRect"
@export var air_margin := Vector2(260, 160)

## The level's graph (set while one is in the tree) - cheap access for hot paths.
static var current: NavGraph

## [{id, left, right, body, one_way}] - left/right are world points on the surface.
var surfaces: Array[Dictionary] = []
## links[id] = [{from, to, type, start, end, vel, time, cost, key}]
var links: Array = []
var _air_rect := Rect2()
var _floor_y := INF


func _ready() -> void:
	add_to_group("nav_graph")
	current = self
	rebuild.call_deferred()


func _exit_tree() -> void:
	if current == self:
		current = null


## Surfaces / links from the current level layout (call again after moving boards).
func rebuild() -> void:
	surfaces.clear()
	links.clear()
	for p in get_tree().get_nodes_in_group("platforms"):
		if p.has_method("nav_surface"):
			var s: Dictionary = p.nav_surface()
			_add_surface(s["left"], s["right"], s["body"], s.get("one_way", true), s.get("left_node"), s.get("right_node"))
	for path in floor_bodies:
		var b := get_node_or_null(path) as CollisionObject2D
		if b == null:
			continue
		for c in b.get_children():
			if c is CollisionShape2D and c.shape is RectangleShape2D:
				var r := (c.shape as RectangleShape2D).size
				var xf := (c as CollisionShape2D).global_transform
				var corners := [xf * (Vector2(-r.x, -r.y) * 0.5), xf * (Vector2(r.x, -r.y) * 0.5),
					xf * (Vector2(-r.x, r.y) * 0.5), xf * (Vector2(r.x, r.y) * 0.5)]
				var top := INF
				var x0 := INF
				var x1 := -INF
				for k in corners:
					top = minf(top, k.y)
					x0 = minf(x0, k.x)
					x1 = maxf(x1, k.x)
				_add_surface(Vector2(x0, top), Vector2(x1, top), b, false)
	for i in surfaces.size():
		links.append([])
		for j in surfaces.size():
			if i != j:
				var l := _link(surfaces[i], surfaces[j])
				if not l.is_empty():
					links[i].append(l)
	_air_rect = _compute_air_rect()
	_floor_y = INF
	for s in surfaces:
		if not s["one_way"]:
			_floor_y = minf(_floor_y, s["left"].y)
	if _floor_y == INF:  # no solid floor listed: use the lowest surface
		for s in surfaces:
			_floor_y = s["left"].y if _floor_y == INF else maxf(_floor_y, s["left"].y)


## left_node / right_node (optional): markers on a moving board - the surface
## follows them every physics frame (jump links stay planned from the rest pose).
func _add_surface(l: Vector2, r: Vector2, body: Object, one_way: bool, l_node: Node2D = null, r_node: Node2D = null) -> void:
	if l.x > r.x:
		var t := l
		l = r
		r = t
		var tn := l_node
		l_node = r_node
		r_node = tn
	surfaces.append({"id": surfaces.size(), "left": l, "right": r, "body": body, "one_way": one_way,
		"left_node": l_node, "right_node": r_node})


func _physics_process(_delta: float) -> void:
	for s in surfaces:
		var ln: Node2D = s["left_node"]
		var rn: Node2D = s["right_node"]
		if is_instance_valid(ln) and is_instance_valid(rn):
			s["left"] = ln.global_position
			s["right"] = rn.global_position


# ---------------------------------------------------------------- links

func _link(a: Dictionary, b: Dictionary) -> Dictionary:
	var ya: float = a["left"].y
	var yb: float = b["left"].y
	var al: float = a["left"].x
	var ar: float = a["right"].x
	var bl: float = b["left"].x
	var br: float = b["right"].x
	var overlap_l := maxf(al, bl)
	var overlap_r := minf(ar, br)
	if overlap_r - overlap_l > edge_inset * 2.0:
		# stacked: straight up through a one-way board, or drop down through ours
		var x := (overlap_l + overlap_r) * 0.5
		if yb < ya - 8.0 and b["one_way"]:
			# take off from the overlap end nearest a's middle for a short hop
			return _jump_link(a, b, Vector2(x, ya), Vector2(x, yb))
		if yb > ya + 8.0 and a["one_way"]:
			return _make(a, b, DROP, Vector2(x, ya), Vector2(x, yb), Vector2.ZERO,
				sqrt(2.0 * (yb - ya) / gravity))
		return {}
	var start: Vector2
	var end: Vector2
	if bl >= ar - edge_inset:     # b is to the right
		start = Vector2(ar - edge_inset * 0.5, ya)
		end = Vector2(maxf(bl + edge_inset, bl), yb)
	else:                         # b is to the left
		start = Vector2(al + edge_inset * 0.5, ya)
		end = Vector2(minf(br - edge_inset, br), yb)
	return _jump_link(a, b, start, end)


## The fastest ballistic arc from start to end within the jump limits.
func _jump_link(a: Dictionary, b: Dictionary, start: Vector2, end: Vector2) -> Dictionary:
	var dx := end.x - start.x
	for clearance: float in [12.0, 30.0, 60.0, 0.0]:
		var apex := minf(start.y, end.y) - clearance
		var rise := start.y - apex
		if rise > jump_height or (clearance == 0.0 and end.y < start.y):
			continue
		var vy := -sqrt(2.0 * gravity * maxf(rise, 0.0))
		var fall := end.y - apex
		var t := -vy / gravity + sqrt(2.0 * maxf(fall, 0.0) / gravity)
		if t <= 0.05:
			continue
		var vx := dx / t
		if absf(vx) > max_speed_x:
			continue
		var vel := Vector2(vx, vy)
		if not _arc_clear(start, vel, t, [a["body"], b["body"]]):
			continue
		return _make(a, b, JUMP, start, end, vel, t)
	return {}


func _make(a: Dictionary, b: Dictionary, type: int, start: Vector2, end: Vector2, vel: Vector2, t: float) -> Dictionary:
	return {
		"from": a["id"], "to": b["id"], "type": type, "start": start, "end": end,
		"vel": vel, "time": t, "cost": t + 0.15, "key": "%d>%d" % [a["id"], b["id"]],
	}


func _arc_clear(start: Vector2, vel: Vector2, t: float, ignore: Array) -> bool:
	var space := get_world_2d().direct_space_state
	var ex: Array[RID] = []
	for s in surfaces:
		if s["one_way"] and s["body"] is CollisionObject2D:
			ex.append((s["body"] as CollisionObject2D).get_rid())
	for o in ignore:
		if o is CollisionObject2D:
			ex.append((o as CollisionObject2D).get_rid())
	var steps := 8
	var prev := start + Vector2(0, -20)
	for i in range(1, steps):
		var tt := t * i / steps
		var p := start + vel * tt + Vector2(0, 0.5 * gravity * tt * tt) + Vector2(0, -20)
		var q := PhysicsRayQueryParameters2D.create(prev, p, 1, ex)
		if not space.intersect_ray(q).is_empty():
			return false
		prev = p
	return true


# ---------------------------------------------------------------- queries

## Surface id under a world point (searching down `reach` px), or -1.
func surface_at(pos: Vector2, reach := 80.0, exclude: Array[RID] = []) -> int:
	var best := -1
	var best_dy := INF
	for s in surfaces:
		var l: Vector2 = s["left"]
		var r: Vector2 = s["right"]
		if pos.x < l.x - edge_inset or pos.x > r.x + edge_inset:
			continue
		var dy := l.y - pos.y
		if dy >= -12.0 and dy <= reach and dy < best_dy:
			best_dy = dy
			best = s["id"]
	return best


## Cheapest list of links from surface a to surface b ([] if none or a == b).
## penalties: link key -> extra cost (recently used links, so enemies do not loop).
func find_path(a: int, b: int, penalties := {}) -> Array:
	if a < 0 or b < 0 or a == b or a >= links.size():
		return []
	var dist := {a: 0.0}
	var via := {}
	var open := [a]
	var done := {}
	while not open.is_empty():
		var cur: int = open[0]
		for o in open:
			if dist[o] < dist[cur]:
				cur = o
		open.erase(cur)
		if cur == b:
			break
		done[cur] = true
		for l in links[cur]:
			var n: int = l["to"]
			if done.has(n):
				continue
			var c: float = dist[cur] + float(l["cost"]) + float(penalties.get(l["key"], 0.0))
			if not dist.has(n) or c < dist[n]:
				dist[n] = c
				via[n] = l
				if not open.has(n):
					open.append(n)
	if not via.has(b):
		return []
	var path := []
	var cur := b
	while cur != a:
		var l: Dictionary = via[cur]
		path.push_front(l)
		cur = l["from"]
	return path


## Spots on the boards where a flyer can land: [{id, u, pos}] (u = 0..1 along
## the board, so a perched flyer can ride a swinging board with point_on()).
func perch_spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in surfaces:
		if s["one_way"]:
			var u := randf_range(0.25, 0.75)
			out.append({"id": s["id"], "u": u, "pos": point_on(s["id"], u)})
	return out


## A point u (0..1) along a surface, where it is right now.
func point_on(id: int, u: float) -> Vector2:
	if id < 0 or id >= surfaces.size():
		return Vector2.ZERO
	return (surfaces[id]["left"] as Vector2).lerp(surfaces[id]["right"], u)


## Top of the ground (the solid floor). Nothing should ever go below this.
func floor_y() -> float:
	return _floor_y if _floor_y != INF else 1e9


## Push a flyer back above the ground. Returns true if it was clamped.
static func keep_above_ground(node: Node2D, margin: float) -> bool:
	if current == null:
		return false
	var limit: float = current.floor_y() - margin
	if node.global_position.y > limit:
		node.global_position.y = limit
		return true
	return false


## Area flyers move around in (inside the frame).
func air_rect() -> Rect2:
	return _air_rect


func _compute_air_rect() -> Rect2:
	var n := get_node_or_null(air_bounds)
	var r := Rect2(-1500, -400, 3600, 800)
	if n is Control:
		var c := n as Control
		var xf := c.get_global_transform()
		var a := xf * Vector2.ZERO
		var b := xf * c.size
		r = Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())
	elif n is Sprite2D:
		var s := n as Sprite2D
		r = s.get_global_transform() * s.get_rect()
	r = r.grow_individual(-air_margin.x, -air_margin.y, -air_margin.x, -air_margin.y)
	return r


## Make a CharacterBody2D fall through the one-way board it stands on.
## Returns false if it is not standing on one.
static func drop_through(who: CharacterBody2D, time := 0.3) -> bool:
	for i in who.get_slide_collision_count():
		var c := who.get_slide_collision(i)
		var col := c.get_collider()
		if c.get_normal().y < -0.6 and col is PhysicsBody2D and (col as Node).is_in_group("one_way_platforms"):
			who.add_collision_exception_with(col)
			who.position.y += 2.0
			var tree := who.get_tree()
			tree.create_timer(time, false, true).timeout.connect(func():
				if is_instance_valid(who) and is_instance_valid(col):
					who.remove_collision_exception_with(col))
			return true
	return false


# ---------------------------------------------------------------- debug

func debug_draw(canvas: CanvasItem) -> void:
	for s in surfaces:
		var l: Vector2 = canvas.to_local(s["left"])
		var r: Vector2 = canvas.to_local(s["right"])
		canvas.draw_line(l, r, Color(0.3, 1.0, 0.4, 0.8), 3.0)
		canvas.draw_string(ThemeDB.fallback_font, (l + r) * 0.5 + Vector2(-6, -6), str(s["id"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 1.0, 0.4))
	for list in links:
		for l in list:
			var col := Color(0.3, 0.8, 1.0, 0.55) if l["type"] == JUMP else Color(1.0, 0.6, 0.2, 0.55)
			var prev: Vector2 = canvas.to_local(l["start"])
			for i in range(1, 11):
				var t: float = l["time"] * i / 10.0
				var p: Vector2 = l["start"] + l["vel"] * t + Vector2(0, 0.5 * gravity * t * t)
				p = canvas.to_local(p)
				canvas.draw_line(prev, p, col, 1.5)
				prev = p
	canvas.draw_rect(Rect2(canvas.to_local(_air_rect.position), _air_rect.size), Color(1, 1, 1, 0.15), false, 2.0)
