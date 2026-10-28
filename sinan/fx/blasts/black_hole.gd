extends Node2D
## Distortion explosion: a glassy black hole that warps and swallows what is
## behind it (screen-refraction shader), drags particles into its core, then
## collapses with a small pop. Used by everything that DISTORTS the painting
## (ghost attacks, rockets fired into the painting).

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const SHADER := preload("res://sinan/shaders/black_hole.gdshader")

var radius := 90.0
var rim_color := Color(0.75, 0.55, 1.0)
var core_color := Color(0.02, 0.0, 0.05)
var grow_time := 0.35
var hold_time := 0.45
var collapse_time := 0.18
## Swirling glints / dark wisps being sucked in, and the streaks on collapse.
var particles := true

var _t := 0.0
var _popped := false
var _sprite: Sprite2D
var _mat: ShaderMaterial
var _suck: CPUParticles2D
var _wisps: CPUParticles2D


func _ready() -> void:
	z_index = 0 if get_parent() is Parallax2D else 3
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("rim_color", rim_color)
	_mat.set_shader_parameter("core_color", core_color)
	_sprite = Sprite2D.new()
	_sprite.texture = FxLib.glow()
	_sprite.scale = Vector2.ONE * radius * 2.0 / 128.0
	_sprite.material = _mat
	add_child(_sprite)

	FxLib.flash_light(get_parent(), global_position, rim_color, 1.2, radius / 40.0, grow_time + hold_time)
	if not particles:
		return
	# glints and dark wisps spiralling into the core
	_suck = FxLib.emitter({
		"one_shot": false, "amount": 40, "life": 0.5, "v_min": 0.0, "v_max": 0.0,
		"emit_radius": radius, "emit_ring": true,
		"radial_min": -radius * 9.0, "radial_max": -radius * 6.0,
		"tangent_min": radius * 2.0, "tangent_max": radius * 3.0,
		"texture": FxLib.glow(), "s_min": 0.04, "s_max": 0.1,
		"ramp": FxLib.fade_ramp(rim_color), "additive": true, "curve": FxLib.shrink(),
	})
	_suck.local_coords = true
	add_child(_suck)
	_wisps = FxLib.emitter({
		"one_shot": false, "amount": 18, "life": 0.55, "v_min": 0.0, "v_max": 0.0,
		"emit_radius": radius * 0.9, "emit_ring": true,
		"radial_min": -radius * 6.0, "radial_max": -radius * 4.0,
		"tangent_min": radius * 2.5, "tangent_max": radius * 3.5,
		"s_min": radius / 200.0, "s_max": radius / 110.0,
		"ramp": FxLib.gradient([[0.0, Color(core_color, 0.0)], [0.3, Color(core_color, 0.7)], [1.0, Color(core_color, 0.0)]]),
		"curve": FxLib.shrink(),
	})
	_wisps.local_coords = true
	add_child(_wisps)


func _process(delta: float) -> void:
	_t += delta
	var total := grow_time + hold_time + collapse_time
	var s := 0.0
	if _t < grow_time:
		var k := _t / grow_time
		s = k * k
	elif _t < grow_time + hold_time:
		s = 1.0
	elif _t < total:
		s = 1.0 - (_t - grow_time - hold_time) / collapse_time
	if not _popped and _t >= grow_time + hold_time:
		_pop()
	_mat.set_shader_parameter("strength", s)
	_mat.set_shader_parameter("swirl", 2.0 + _t * 6.0)
	_mat.set_shader_parameter("core_size", 0.22 * (1.0 + 0.12 * sin(_t * 30.0)))
	_sprite.visible = _t < total
	queue_redraw()
	if _t > total + 1.2:
		queue_free()


func _pop() -> void:
	_popped = true
	FxLib.flash_light(get_parent(), global_position, Color.WHITE, 1.2, radius / 60.0, 0.15)
	if not particles:
		return
	_suck.emitting = false
	_wisps.emitting = false
	FxLib.burst(get_parent(), {
		"amount": 16, "life": 0.35, "v_min": radius * 2.0, "v_max": radius * 4.5,
		"texture": FxLib.streak(), "align": true, "angle_min": 0.0, "angle_max": 0.0,
		"spin_min": 0.0, "spin_max": 0.0, "s_min": 0.25, "s_max": 0.5,
		"damp_min": 300.0, "damp_max": 500.0, "ramp": FxLib.fade_ramp(rim_color), "additive": true,
	}, global_position)


func _draw() -> void:
	var total := grow_time + hold_time + collapse_time
	# faint glass edge while it is open
	if _t < total:
		var open := clampf(_t / grow_time, 0.0, 1.0)
		draw_arc(Vector2.ZERO, radius * 0.97, 0.0, TAU, 64, Color(1, 1, 1, 0.12 * open), 1.5, true)
	# collapse shock ring
	if _popped:
		var k := clampf((_t - grow_time - hold_time) / 0.35, 0.0, 1.0)
		if k < 1.0:
			draw_arc(Vector2.ZERO, radius * (0.15 + 1.1 * (1.0 - pow(1.0 - k, 3.0))), 0.0, TAU, 64,
				Color(rim_color, (1.0 - k) * 0.9), lerpf(4.0, 1.0, k), true)
		var flash := 1.0 - clampf((_t - grow_time - hold_time) / 0.1, 0.0, 1.0)
		if flash > 0.0:
			draw_circle(Vector2.ZERO, radius * 0.25, Color(1, 1, 1, flash))
