extends "res://sinan/weapons/orb_staff.gd"
## Paint-brush staff: same behaviour as the orb staff (lob, land, charge, burst,
## restore), but throws a wobbling blob of paint. Inherits every orb setting;
## the Paint group adds the paint colours. Drawn in code; replace with art whenever.

const PaintBlob := preload("res://sinan/fx/paint_blob.gd")
const PaintStroke := preload("res://sinan/fx/paint_stroke.gd")

const BRUSH_TIP := 165.0  # tip of the drawn bristles

@export_group("Paint")
@export var paint_color := Color(0.2, 0.42, 0.9)
@export var paint_shade := Color(0.07, 0.15, 0.42)
## Splat radius where the blob lands, in blob radii.
@export var splat_size := 1.8
## Paint drips per second-ish while it flies.
@export var drip_amount := 30

@export_group("Paint Effects")
## Thick tapered brush-stroke ribbon behind the blob in flight.
@export var stroke_trail := true
@export var trail_length := 16
## Ribbon width in blob diameters.
@export var trail_width := 1.0
## Seconds the big paint splat stays where the blob bursts (0 = none).
@export var splat_decal_life := 2.5
## Curved brush-stroke swoosh painted in front of you when you swing.
@export var swing_swoosh := true
@export var swoosh_width := 12.0
## Paint drops flicked off the brush on each swing.
@export var flick_amount := 16


func _make_projectile() -> Node2D:
	return PaintBlob.new()


func _configure(o) -> void:
	super._configure(o)
	o.paint_color = paint_color
	o.paint_shade = paint_shade
	o.splat_size = splat_size
	o.drip_amount = drip_amount
	o.stroke_trail = stroke_trail
	o.trail_length = trail_length
	o.trail_width = trail_width
	o.decal_life = splat_decal_life


func fire(player, aim: Vector2, painting: bool, pick: Dictionary, target: Vector2) -> void:
	super.fire(player, aim, painting, pick, target)
	var world: Node = player.get_parent()
	var tip := muzzle_global()
	if swing_swoosh:
		var s := PaintStroke.new()
		s.radius = (tip - global_position).length()
		s.width = swoosh_width
		s.color = paint_color
		s.shade = paint_shade
		s.position = FxLib.to_parent_space(world, global_position)
		s.rotation = aim.angle()
		world.add_child(s)
	if flick_amount > 0:
		FxLib.spawn(world, FxLib.emitter({
			"amount": flick_amount, "life": 0.6, "life_rand": 0.4, "v_min": 180.0, "v_max": 460.0,
			"spread": 28.0, "direction": Vector2.RIGHT, "gravity": Vector2(0, 950),
			"s_min": 0.06, "s_max": 0.16, "spin_min": 0.0, "spin_max": 0.0,
			"ramp": FxLib.gradient([[0.0, paint_color.lightened(0.1)], [0.75, paint_color], [1.0, Color(paint_shade, 0.0)]]),
		}), tip, aim.angle())


func _draw() -> void:
	var kb := recoil * recoil
	var flip := signf(scale.y)
	draw_set_transform(Vector2(-kb * 18.0, sin(_t * 3.0) * 2.0), (-kb * 0.35 - spin) * flip, Vector2.ONE)

	var lacquer := Color(0.55, 0.16, 0.1)
	var steel := Color(0.72, 0.72, 0.76)
	var bristle := Color(0.78, 0.62, 0.4)

	# tapered lacquered handle
	draw_colored_polygon(PackedVector2Array([
		Vector2(-55, -3), Vector2(95, -7), Vector2(95, 7), Vector2(-55, 3)
	]), lacquer)
	draw_line(Vector2(-50, -2), Vector2(93, -5), Color(1, 1, 1, 0.25), 2.0)
	draw_circle(Vector2(-55, 0), 4.0, lacquer.darkened(0.3))

	# metal ferrule with crimp lines
	draw_rect(Rect2(95, -9, 26, 18), steel)
	for x in [101.0, 107.0]:
		draw_line(Vector2(x, -9), Vector2(x, 9), steel.darkened(0.35), 2.0)
	draw_line(Vector2(95, -7), Vector2(121, -7), Color(1, 1, 1, 0.5), 2.0)

	# bristles bend back a little on recoil; tip dipped in paint
	var bend := -kb * 8.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(121, -10), Vector2(145, -11), Vector2(BRUSH_TIP, bend), Vector2(145, 11), Vector2(121, 10)
	]), bristle)
	draw_colored_polygon(PackedVector2Array([
		Vector2(140, -11), Vector2(BRUSH_TIP, bend), Vector2(140, 11)
	]), paint_color)
	for y in [-6.0, 0.0, 6.0]:
		draw_line(Vector2(123, y), Vector2(138, y * 0.9), bristle.darkened(0.25), 1.0)

	# the paint blob re-forms on the tip while reloading (wobbles a little)
	var p := clampf(reload, 0.0, 1.0)
	var r := 15.0 * p
	if r > 0.5:
		var c := Vector2(BRUSH_TIP + r * 0.6, bend)
		var w := r * (1.0 + 0.06 * sin(_t * 9.0))
		draw_circle(c, r * 2.0, Color(glow_color, 0.12))
		draw_circle(c, w, paint_shade)
		draw_circle(c + Vector2(-0.08, -0.12) * r, w * 0.8, paint_color)
		draw_circle(c + Vector2(-0.35, -0.42) * r, r * 0.26, Color(1, 1, 1, 0.75))

	# a drip forms under the bristles, stretches and falls
	var cycle := fmod(_t * 0.7, 1.0)
	var drip := Vector2(150, 9 + cycle * cycle * 30.0)
	draw_circle(drip, 3.5 * (1.0 - cycle * 0.4), Color(paint_color, 1.0 - cycle))

	if recoil > 0.6:
		draw_circle(Vector2(BRUSH_TIP, 0), 40.0 * recoil, Color(glow_color, recoil * 0.5))
