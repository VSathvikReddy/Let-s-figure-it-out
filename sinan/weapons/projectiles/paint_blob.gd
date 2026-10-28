extends "res://sinan/weapons/projectiles/orb.gd"
## Paint version of the magic orb: a wobbling, glossy blob of paint that drips
## while it flies, splats where it lands, bubbles while charging, then bursts in
## a paint splash + the magic burst, restoring the painting. All behaviour
## (flight, fuse, restore) is inherited from orb.gd.

const PaintSplat := preload("res://sinan/fx/marks/paint_splat.gd")

# --- set by the weapon (brush_staff.gd)
var paint_color := Color(0.2, 0.42, 0.9)
var paint_shade := Color(0.07, 0.15, 0.42)
var splat_size := 1.8   # splat radius in orb radii
var drip_amount := 30
var stroke_trail := true
var trail_length := 16  # points in the brush-stroke ribbon behind it
var trail_width := 1.0  # ribbon width in blob diameters
var decal_life := 2.5   # seconds the big burst splat stays

var _stroke: Line2D
var _splat := PackedVector2Array()
var _splat_inner := PackedVector2Array()
var _drops: Array[Vector3] = []  # x, y, radius


func _setup_fx() -> void:
	material = null  # paint is opaque (the light still glows)

	# thick tapered brush-stroke ribbon following the blob (global points)
	if stroke_trail:
		_stroke = Line2D.new()
		_stroke.top_level = true
		_stroke.show_behind_parent = true
		_stroke.width = orb_radius * 2.0 * trail_width
		var wc := Curve.new()
		wc.add_point(Vector2(0.0, 0.0))
		wc.add_point(Vector2(0.6, 0.7))
		wc.add_point(Vector2(1.0, 1.0))
		_stroke.width_curve = wc
		_stroke.gradient = FxLib.gradient([
			[0.0, Color(paint_shade, 0.0)], [0.45, Color(paint_shade, 0.85)], [1.0, paint_color],
		])
		_stroke.joint_mode = Line2D.LINE_JOINT_ROUND
		_stroke.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_stroke.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(_stroke)

	# paint drips falling off the blob
	_trails.append(_child_emitter({
		"one_shot": false, "amount": drip_amount, "life": 0.7, "v_min": 10.0, "v_max": 60.0,
		"gravity": Vector2(0, 900), "s_min": orb_radius / 110.0, "s_max": orb_radius / 50.0,
		"ramp": FxLib.gradient([[0.0, paint_color], [0.7, Color(paint_shade, 0.9)], [1.0, Color(paint_shade, 0.0)]]),
		"spin_min": 0.0, "spin_max": 0.0,
	}))
	# a little magic glitter so it still reads as a spell
	_trails.append(_child_emitter({
		"one_shot": false, "amount": 10, "life": 0.5, "v_min": 10.0, "v_max": 40.0,
		"texture": FxLib.glow(), "s_min": 0.04, "s_max": 0.09,
		"ramp": FxLib.fade_ramp(glow_color), "additive": true, "curve": null,
	}))
	# charging: paint bubbles rising off the blob
	_charge = _child_emitter({
		"one_shot": false, "amount": 14, "life": 0.6, "v_min": 20.0, "v_max": 55.0,
		"direction": Vector2.UP, "spread": 35.0, "emit_radius": orb_radius * 0.9,
		"gravity": Vector2(0, -40), "s_min": orb_radius / 160.0, "s_max": orb_radius / 80.0,
		"ramp": FxLib.gradient([[0.0, paint_color.lightened(0.4)], [1.0, Color(paint_color, 0.0)]]),
	})
	_charge.local_coords = true
	_charge.emitting = false


func _process(delta: float) -> void:
	super._process(delta)
	if _stroke == null:
		return
	if _state == State.FLYING:
		# a little sideways wobble makes the ribbon read as a hand-made stroke
		var wob := Vector2.from_angle(rotation + PI / 2.0) * sin(_age * 25.0) * orb_radius * 0.15 * scale.x
		_stroke.add_point(global_position + wob)
		while _stroke.get_point_count() > trail_length:
			_stroke.remove_point(0)
		_stroke.width = orb_radius * 2.0 * trail_width * scale.x


func _on_land_fx() -> void:
	rotation = 0.0
	if _stroke:
		var tw := _stroke.create_tween()
		tw.tween_property(_stroke, "modulate:a", 0.0, 0.35)
	# Splat polygon: an irregular blob with a few longer spikes.
	var n := 20
	var r0 := orb_radius * splat_size
	for i in n:
		var a := float(i) / n * TAU
		var r := r0 * randf_range(0.75, 1.1) * (1.55 if i % 5 == 0 else 1.0)
		_splat.append(Vector2.from_angle(a) * r)
	for i in 6:
		var a := randf() * TAU
		var d := r0 * randf_range(1.5, 2.3)
		_drops.append(Vector3(cos(a) * d, sin(a) * d, orb_radius * randf_range(0.15, 0.35)))
	# On a floor/wall the splat lies flat along the surface.
	if _rest_normal != Vector2.ZERO:
		var rot := _rest_normal.angle() + PI / 2.0
		for i in _splat.size():
			_splat[i] = Vector2(_splat[i].x, _splat[i].y * 0.35).rotated(rot) + _rest_normal * -orb_radius * 0.6
		for i in _drops.size():
			var p := Vector2(_drops[i].x, _drops[i].y * 0.35).rotated(rot) + _rest_normal * -orb_radius * 0.6
			_drops[i] = Vector3(p.x, p.y, _drops[i].z)
	for p in _splat:
		_splat_inner.append(p * 0.8)

	# spatter
	FxLib.burst(get_parent(), {
		"amount": 14, "life": 0.5, "v_min": 120.0, "v_max": 320.0, "gravity": Vector2(0, 900),
		"s_min": orb_radius / 120.0, "s_max": orb_radius / 55.0, "spin_min": 0.0, "spin_max": 0.0,
		"ramp": FxLib.gradient([[0.0, paint_color], [1.0, Color(paint_shade, 0.0)]]),
	}, global_position)


func _spawn_burst(parent: Node) -> void:
	# big wet splat left on the surface (under the burst)
	if decal_life > 0.0:
		var sp := PaintSplat.new()
		sp.radius = blast_radius * 0.55
		sp.color = paint_color
		sp.shade = paint_shade
		sp.life = decal_life
		sp.flat_normal = _rest_normal
		sp.position = position + (_rest_normal * -orb_radius * 0.6 if _rest_normal != Vector2.ZERO else Vector2.ZERO)
		parent.add_child(sp)
	super._spawn_burst(parent)
	var pos := global_position
	var k := blast_radius / 120.0
	# big paint splash: heavy droplets + flung brush-stroke streaks
	FxLib.burst(parent, {
		"amount": 40, "life": 0.9, "life_rand": 0.4, "v_min": 200.0 * k, "v_max": 540.0 * k,
		"gravity": Vector2(0, 1000), "damp_min": 20.0, "damp_max": 60.0,
		"s_min": 0.12 * k, "s_max": 0.32 * k, "spin_min": 0.0, "spin_max": 0.0,
		"ramp": FxLib.gradient([[0.0, paint_color.lightened(0.15)], [0.7, paint_color], [1.0, Color(paint_shade, 0.0)]]),
	}, pos)
	FxLib.burst(parent, {
		"amount": 18, "life": 0.6, "v_min": 350.0 * k, "v_max": 700.0 * k,
		"texture": FxLib.streak(), "align": true, "angle_min": 0.0, "angle_max": 0.0,
		"spin_min": 0.0, "spin_max": 0.0, "s_min": 0.5 * k, "s_max": 1.1 * k,
		"damp_min": 250.0, "damp_max": 500.0, "gravity": Vector2(0, 600),
		"ramp": FxLib.gradient([[0.0, paint_color], [1.0, Color(paint_color, 0.0)]]),
	}, pos)


func _draw() -> void:
	var charging := _state == State.CHARGING
	var k := clampf(_t / fuse_time, 0.0, 1.0) if charging else 0.0
	var r := orb_radius * (1.0 + 0.3 * k)

	# splat on the surface it landed on
	if charging and _splat.size() > 2:
		draw_colored_polygon(_splat, paint_shade)
		draw_colored_polygon(_splat_inner, paint_color)
		for d in _drops:
			draw_circle(Vector2(d.x, d.y), d.z, paint_color)

	# faint glow behind (normal blend, so keep it soft)
	draw_circle(Vector2.ZERO, r * 2.2, Color(glow_color, 0.10 + 0.15 * k))

	# wobbling blob: jelly-like while charging, stretched along its flight in the air
	var speed := 8.0 + 18.0 * k
	var amp := (0.08 + 0.16 * k) if charging else 0.1
	var stretch := 1.0
	var dir := 0.0
	if not charging:
		if _flight:
			stretch = 1.25  # node is already rotated along the flight by DepthFlight
		elif vel.length() > 1.0:
			stretch = 1.0 + clampf(vel.length() / 2500.0, 0.0, 0.5)
			dir = vel.angle()
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var n := 18
	for i in n:
		var a := float(i) / n * TAU
		var w := 1.0 + amp * sin(a * 3.0 + _age * speed) + amp * 0.5 * sin(a * 5.0 - _age * speed * 1.3)
		var p := Vector2(cos(a) * r * w * stretch, sin(a) * r * w / stretch).rotated(dir)
		outer.append(p)
		inner.append(p * 0.8 + Vector2(-0.08, -0.12) * r)
	draw_colored_polygon(outer, paint_shade)
	draw_colored_polygon(inner, paint_color)
	# glossy highlight
	draw_circle(Vector2(-0.35, -0.42) * r, r * 0.28, Color(1, 1, 1, 0.75))
	draw_circle(Vector2(-0.12, -0.55) * r, r * 0.1, Color(1, 1, 1, 0.9))

	if charging:
		draw_arc(Vector2.ZERO, r * 2.6, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - k), 48, Color(glow_color, 0.8), 2.0, true)
