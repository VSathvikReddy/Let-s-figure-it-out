extends RefCounted
## Flies a projectile from the muzzle "into" the painting: arcs toward a point
## pinned to a Parallax2D layer (so it follows the layer as the camera moves)
## and shrinks with perspective toward the layer's depth scale.

var node: Node2D
var layer: Node2D        # null = fixed world point
var local := Vector2.ZERO
var end_scale := 1.0
var start := Vector2.ZERO
var duration := 0.4
var arc := 60.0
var t := 0.0


func _init(n: Node2D, from: Vector2, pick: Dictionary, world_fallback: Vector2, dur: float, arc_height: float) -> void:
	node = n
	start = from
	duration = dur
	arc = arc_height
	if pick.is_empty():
		layer = null
		local = world_fallback
		end_scale = 0.3
	else:
		layer = pick["layer"]
		local = pick["local"]
		end_scale = pick["scale"]


func end_point() -> Vector2:
	return layer.to_global(local) if is_instance_valid(layer) else local


static func point_at(a: Vector2, b: Vector2, arc_height: float, k: float) -> Vector2:
	return a.lerp(b, k) + Vector2(0.0, -arc_height * sin(PI * k))


## Perspective-correct shrink: 1/z interpolation, fast at first, then settles.
static func scale_at(end_s: float, k: float) -> float:
	return 1.0 / lerpf(1.0, 1.0 / maxf(end_s, 0.01), k)


## Advance; returns true on landing.
func step(delta: float) -> bool:
	t += delta
	var k := clampf(t / duration, 0.0, 1.0)
	var prev := node.global_position
	var p := point_at(start, end_point(), arc, k)
	node.global_position = p
	node.scale = Vector2.ONE * scale_at(end_scale, k)
	if p.distance_squared_to(prev) > 0.01:
		node.rotation = (p - prev).angle()
	return k >= 1.0
