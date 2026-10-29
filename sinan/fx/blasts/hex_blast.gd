extends Node2D
## DAMAGING magic explosion (witch orbs, witch death...). Deliberately harsh and
## angular so it never reads like the soft, round restoring burst (orb_blast.gd):
## a jagged spiky star, crackling lightning, one hard shock ring, dark shards
## and a puff of smoke.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")

const LIFE := 0.45

var radius := 50.0
var color := Color(0.85, 0.2, 0.9)
var core_color := Color(1.0, 0.85, 1.0)
var dark_color := Color(0.15, 0.02, 0.2)
var light_energy := 2.5
var smoke := true

var _t := 0.0
var _bolt_t := 0.0
var _spikes := PackedFloat32Array()
var _bolts: Array[PackedVector2Array] = []
var _spin := 0.0


func _ready() -> void:
	z_index = 0 if get_parent() is Parallax2D else 4
	_spin = randf() * TAU
	for i in 10:
		_spikes.append(randf_range(0.6, 1.15))
	_make_bolts()
	var world := get_parent()
	var pos := global_position
	var k := radius / 50.0
	# dark shards
	FxLib.burst(world, {
		"amount": 14, "life": 0.6, "v_min": 150.0 * k, "v_max": 420.0 * k, "gravity": Vector2(0, 700),
		"texture": null, "s_min": 3.0 * k, "s_max": 6.0 * k, "curve": null,
		"spin_min": -720.0, "spin_max": 720.0,
		"ramp": FxLib.gradient([[0.0, dark_color], [0.8, dark_color], [1.0, Color(dark_color, 0.0)]]),
	}, pos)
	# hot embers
	FxLib.burst(world, {
		"amount": 18, "life": 0.4, "v_min": 200.0 * k, "v_max": 520.0 * k,
		"texture": FxLib.streak(), "align": true, "angle_min": 0.0, "angle_max": 0.0,
		"spin_min": 0.0, "spin_max": 0.0, "s_min": 0.25, "s_max": 0.5,
		"damp_min": 250.0, "damp_max": 450.0, "ramp": FxLib.fade_ramp(color), "additive": true,
	}, pos)
	if smoke:
		FxLib.smoke_burst(world, pos, 0.6 * k, dark_color.lerp(Color(0.3, 0.25, 0.3), 0.5))
	FxLib.flash_light(world, pos, color, light_energy, radius / 25.0, 0.3)


func _make_bolts() -> void:
	_bolts.clear()
	for i in 5:
		var a := randf() * TAU
		var dir := Vector2.from_angle(a)
		var side := dir.orthogonal()
		var pts := PackedVector2Array()
		var reach := radius * randf_range(0.7, 1.15)
		for j in 6:
			var u := float(j) / 5.0
			pts.append(dir * lerpf(radius * 0.1, reach, u) + side * randf_range(-1.0, 1.0) * radius * 0.12 * u)
		_bolts.append(pts)


func _process(delta: float) -> void:
	_t += delta
	_bolt_t -= delta
	if _bolt_t <= 0.0:
		_bolt_t = 0.05
		_make_bolts()  # crackle
	View.redraw(self)
	if _t > 1.6:
		queue_free()


func _draw() -> void:
	var k := clampf(_t / LIFE, 0.0, 1.0)
	if k >= 1.0:
		return
	var out := 1.0 - pow(1.0 - k, 3.0)
	var fade := 1.0 - k
	if _t < 0.06:
		draw_circle(Vector2.ZERO, radius * 0.55, Color(core_color, 1.0))
	# jagged spiky star (two layers)
	for layer in 2:
		var scale_l := 1.0 if layer == 0 else 0.55
		var col := color if layer == 0 else core_color
		var star := PackedVector2Array()
		var n := _spikes.size()
		for i in n * 2:
			var a := _spin + i * PI / n
			var r := radius * (0.35 + 0.85 * out) * scale_l
			r *= _spikes[i / 2] if i % 2 == 0 else 0.38
			star.append(Vector2.from_angle(a) * r)
		draw_colored_polygon(star, Color(col, fade * (0.85 if layer == 0 else 1.0)))
	# hard shock ring
	draw_arc(Vector2.ZERO, radius * (0.3 + 1.1 * out), 0.0, TAU, 40, Color(color, fade * fade), lerpf(5.0, 1.0, k), true)
	# crackling lightning
	for b in _bolts:
		draw_polyline(b, Color(core_color, fade), 1.5, true)
