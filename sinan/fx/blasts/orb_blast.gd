extends Node2D
## Elegant magic burst: soft flash, staggered thin rings, a slowly turning star
## of light rays, spiralling sparkles, glints and slow rising motes.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")

const LIFE := 0.9

var radius := 120.0
var color := Color(1.0, 0.9, 0.55)   # warm highlight
var glow := Color(0.35, 0.85, 1.0)   # main magic colour
var light_energy := 3.0
var _t := 0.0


func _ready() -> void:
	z_index = 0 if get_parent() is Parallax2D else 3
	material = FxLib.additive()
	var world := get_parent()
	var pos := global_position
	var k := radius / 120.0

	# spiralling sparkles
	FxLib.burst(world, {
		"amount": 48, "life": 0.9, "v_min": 120.0 * k, "v_max": 320.0 * k,
		"tangent_min": 300.0 * k, "tangent_max": 520.0 * k,
		"damp_min": 150.0 * k, "damp_max": 260.0 * k,
		"texture": FxLib.glow(), "s_min": 0.08, "s_max": 0.22,
		"ramp": FxLib.fade_ramp(color, glow), "additive": true,
	}, pos)
	# glints
	FxLib.burst(world, {
		"amount": 16, "life": 0.5, "v_min": 300.0 * k, "v_max": 650.0 * k,
		"texture": FxLib.streak(), "align": true, "angle_min": 0.0, "angle_max": 0.0,
		"spin_min": 0.0, "spin_max": 0.0, "s_min": 0.3, "s_max": 0.7,
		"damp_min": 300.0, "damp_max": 600.0,
		"ramp": FxLib.fade_ramp(color), "additive": true,
	}, pos)
	# slow rising motes that linger
	FxLib.burst(world, {
		"amount": 30, "life": 2.0, "life_rand": 0.4, "explosiveness": 0.6,
		"emit_radius": radius * 0.5, "v_min": 10.0, "v_max": 50.0,
		"gravity": Vector2(0, -60), "texture": FxLib.glow(), "s_min": 0.05, "s_max": 0.12,
		"ramp": FxLib.fade_ramp(glow), "additive": true, "curve": null,
	}, pos)
	FxLib.flash_light(world, pos, glow, light_energy, radius / 30.0, 0.8)


func _process(delta: float) -> void:
	_t += delta
	View.redraw(self)
	if _t > 2.5:
		queue_free()


func _draw() -> void:
	var k := clampf(_t / LIFE, 0.0, 1.0)
	if k >= 1.0:
		return
	var out := 1.0 - pow(1.0 - k, 3.0)
	var fade := 1.0 - k

	var flash := 1.0 - clampf(_t / 0.12, 0.0, 1.0)
	if flash > 0.0:
		draw_circle(Vector2.ZERO, radius * 0.6, Color(1, 1, 1, flash * 0.8))
	draw_circle(Vector2.ZERO, radius * 0.35 * fade, Color(glow, 0.4 * fade))

	# staggered thin rings
	for i in 3:
		var kk := clampf((_t - i * 0.08) / (LIFE * 0.85), 0.0, 1.0)
		if kk > 0.0 and kk < 1.0:
			var r := radius * (0.2 + 1.0 * (1.0 - pow(1.0 - kk, 3.0)))
			var c := color if i == 0 else glow
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(c, (1.0 - kk) * 0.9), lerpf(6.0, 1.0, kk), true)

	# slowly turning star of light rays (long + short alternate)
	for i in 16:
		var a := i * TAU / 16.0 + _t * 0.8
		var is_long := i % 2 == 0
		var ray_len := radius * (0.3 + (0.9 if is_long else 0.5) * out) * (1.0 - k * 0.5)
		var inner := radius * 0.15 * out
		var d := Vector2.from_angle(a)
		draw_line(d * inner, d * ray_len, Color(color if is_long else glow, fade * fade), 2.0 if is_long else 1.0, true)
