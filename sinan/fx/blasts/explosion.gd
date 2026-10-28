extends Node2D
## Big impact explosion: flash, fireball, shockwave rings, sparks, smoke and a
## light pulse. Spawned by the missile; the breaking/knockback happens there.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")

const LIFE := 0.7

var radius := 130.0  # already multiplied by depth by the caller
var depth := 1.0     # < 1 shrinks the particles (currently painting hits use full size)
var in_painting := false
var _t := 0.0


func _ready() -> void:
	# In the painting: draw under the frame (z 1) and the player.
	z_index = 0 if in_painting else 4
	material = FxLib.additive()
	var world := get_parent()
	var pos := global_position

	# fireball
	FxLib.burst(world, FxLib.scaled({
		"amount": 36, "life": 0.55, "v_min": 80.0, "v_max": 430.0,
		"damp_min": 150.0, "damp_max": 320.0, "s_min": 0.7, "s_max": 1.9,
		"additive": true, "gravity": Vector2(0, -40),
	}, depth), pos)
	# sparks / embers
	FxLib.burst(world, FxLib.scaled({
		"amount": 42, "life": 0.9, "life_rand": 0.5, "v_min": 250.0, "v_max": 950.0,
		"gravity": Vector2(0, 900), "texture": FxLib.streak(), "align": true,
		"angle_min": 0.0, "angle_max": 0.0, "spin_min": 0.0, "spin_max": 0.0,
		"s_min": 0.4, "s_max": 1.0, "additive": true, "ramp": FxLib.spark_ramp(),
		"damp_min": 60.0, "damp_max": 200.0,
	}, depth), pos)
	# smoke
	FxLib.burst(world, FxLib.scaled({
		"amount": 24, "life": 1.7, "life_rand": 0.4, "explosiveness": 0.7,
		"v_min": 25.0, "v_max": 170.0, "damp_min": 50.0, "damp_max": 110.0,
		"gravity": Vector2(0, -70), "ramp": FxLib.smoke_ramp(0.6),
		"s_min": 1.0, "s_max": 2.6, "curve": FxLib.grow(),
	}, depth), pos)
	# light pulse
	FxLib.flash_light(world, pos, Color(1.0, 0.72, 0.38), 5.0, radius / 22.0, 0.6)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t > 3.0:
		queue_free()


func _draw() -> void:
	var k := clampf(_t / LIFE, 0.0, 1.0)
	if k >= 1.0:
		return
	var out := 1.0 - pow(1.0 - k, 3.0)

	var flash := 1.0 - clampf(_t / 0.14, 0.0, 1.0)
	if flash > 0.0:
		draw_circle(Vector2.ZERO, radius * (0.55 + 0.6 * (1.0 - flash)), Color(1.0, 0.95, 0.75, flash))

	var fa := 1.0 - k
	draw_circle(Vector2.ZERO, radius * (0.35 + 0.75 * out), Color(1.0, 0.5, 0.1, 0.45 * fa * fa))

	for i in 2:
		var kk := clampf((_t - i * 0.05) / (LIFE * 0.8), 0.0, 1.0)
		if kk > 0.0 and kk < 1.0:
			var r := radius * (0.3 + 1.9 * (1.0 - pow(1.0 - kk, 3.0)))
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(1.0, 0.85, 0.55, (1.0 - kk) * 0.9), lerpf(14.0, 2.0, kk), true)
