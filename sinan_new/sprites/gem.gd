@tool  # also runs in the editor, so you see the gem (and its animation) while editing
extends Node2D
## A cartoon gem, drawn in code: thick dark outline, faceted body (light on
## the top-left, dark on the bottom-right), a darker inner shape, a white glint
## and a little twinkle. It floats up and down and gently pulses.
## Change the look in the Inspector: the shape is `points` + `inner`.

@export_group("Shape")
## How many tips the gem has (4 = star like the inspiration, 6 = hexagon...).
@export_range(3, 12) var points := 4
## How far in the dips between tips go (0.4 = pointy star, 0.9 = almost round).
@export_range(0.2, 1.0) var inner := 0.42
@export var radius := 40.0
## Size of the darker shape in the middle (0 = none).
@export_range(0.0, 0.9) var core_size := 0.45

@export_group("Colors")
@export var color := Color(0.62, 0.38, 0.95)
## Tint on the bottom-right facets (the pink in the inspiration).
@export var accent := Color(0.95, 0.35, 0.85)
@export var outline_color := Color(0.05, 0.03, 0.08)
@export var outline_width := 6.0

@export_group("Animation")
## Up-and-down float: how far (px) and how fast (per second).
@export var float_height := 6.0
@export var float_speed := 1.6
## Size pulse (0.05 = grows 5%).
@export var pulse := 0.05
## Seconds between twinkles.
@export var twinkle_every := 2.2

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var grow := 1.0 + sin(_t * float_speed * 2.0) * pulse
	var center := Vector2(0, sin(_t * float_speed * TAU * 0.5) * float_height)
	var shape := _star(center, radius * grow, inner)

	# 1. outline: the same shape pushed outward with round corners
	var outline := Geometry2D.offset_polygon(shape, outline_width, Geometry2D.JOIN_ROUND)
	if not outline.is_empty():
		draw_colored_polygon(outline[0], outline_color)

	# 2. facets: one triangle per edge, lit from the top-left
	var light := Vector2(-1, -1).normalized()
	for i in shape.size():
		var a := shape[i]
		var b := shape[(i + 1) % shape.size()]
		var facing := ((a + b) * 0.5 - center).normalized().dot(light)  # 1 = faces the light
		var c := color.lightened(facing * 0.35) if facing > 0.0 else color.darkened(-facing * 0.3)
		if facing < -0.5:
			c = c.lerp(accent, 0.45)  # the pink edge on the bottom-right
		draw_colored_polygon(PackedVector2Array([center, a, b]), c)

	# 3. darker core in the middle
	if core_size > 0.0:
		draw_colored_polygon(_star(center, radius * grow * core_size, inner), color.darkened(0.2))

	# 4. white glint near the top-left
	var glint := center + Vector2(-0.3, -0.38) * radius * grow
	draw_set_transform(glint, -0.6, Vector2(1.0, 0.55))
	draw_circle(Vector2.ZERO, radius * 0.16, Color(1, 1, 1, 0.9))
	draw_set_transform(Vector2.ZERO)

	# 5. twinkle: a small sparkle that pops on the top-right every few seconds
	var k := fmod(_t, twinkle_every) / 0.45
	if k < 1.0:
		var s := sin(k * PI) * radius * 0.3
		var at := center + Vector2(0.55, -0.55) * radius
		draw_colored_polygon(_star(at, s, 0.25), Color(1, 1, 1, 0.95))


## A star with `points` tips around `c`: tips at `r`, dips at `r * dip`.
## (dip close to 1 makes a plain polygon: hexagon, pentagon...)
func _star(c: Vector2, r: float, dip: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var angle := -PI / 2.0 + i * PI / points
		pts.append(c + Vector2.from_angle(angle) * (r if i % 2 == 0 else r * dip))
	return pts
