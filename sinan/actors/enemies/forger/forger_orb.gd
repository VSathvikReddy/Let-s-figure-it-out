extends Node2D
## One of the Forger's void orbs for his black-hole attack. It circles around
## `center` while charging (spinning faster and tightening), then launches and
## homes onto a point inside the painting layer. Calls `on_arrive` when it lands.
## Everything is set by the Forger before it is added to the tree.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")

enum State { ORBIT, FLY }

var center: Node2D              # what it circles (the Forger)
var center_offset := Vector2(0, -60)
var angle := 0.0                # start angle on the ring
var orbit_radius := 70.0
var orbit_speed := 2.5          # radians/second at the start of the charge
var charge_time := 1.6          # orbit spin-up before launching
var launch_delay := 0.0         # extra wait so orbs launch one after another
var fly_speed := 900.0
var fly_accel := 1800.0
var target_layer: Node2D        # painting layer (orb homes onto it as it scrolls)
var target_local := Vector2.ZERO
var orb_radius := 9.0
var core_color := Color(0.01, 0.01, 0.02)
var glow_color := Color(0.85, 0.9, 1.0)
var on_arrive: Callable

var _state := State.ORBIT
var _t := 0.0
var _speed := 0.0
var _trail: CPUParticles2D


func _ready() -> void:
	z_index = 3
	scale = Vector2.ZERO
	_trail = FxLib.emitter({
		"one_shot": false, "amount": 24, "life": 0.4, "v_min": 5.0, "v_max": 20.0,
		"ramp": FxLib.gradient([[0.0, Color(0.02, 0.02, 0.03, 0.8)], [1.0, Color(0.02, 0.02, 0.03, 0.0)]]),
		"s_min": orb_radius / 60.0, "s_max": orb_radius / 35.0,
	})
	add_child(_trail)


func _process(delta: float) -> void:
	_t += delta
	match _state:
		State.ORBIT:
			if not is_instance_valid(center):
				queue_free()
				return
			var k := clampf(_t / charge_time, 0.0, 1.0)
			scale = Vector2.ONE * minf(1.0, _t / 0.25) * (1.0 + 0.25 * k)
			angle += orbit_speed * (1.0 + 2.5 * k) * delta          # spins up
			var r := orbit_radius * (1.0 - 0.25 * k)                 # tightens
			global_position = center.global_position + center_offset + Vector2(cos(angle), sin(angle) * 0.55) * r
			if _t >= charge_time + launch_delay:
				_state = State.FLY
				_t = 0.0
				_speed = fly_speed * 0.4
				FxLib.flash_light(get_parent(), global_position, glow_color, 1.2, 0.8, 0.15)
		State.FLY:
			if not is_instance_valid(target_layer):
				queue_free()
				return
			var target := target_layer.to_global(target_local)
			var to := target - global_position
			_speed = minf(_speed + fly_accel * delta, fly_speed * 2.0)
			var step := _speed * delta
			if to.length() <= step:
				global_position = target
				_arrive()
				return
			global_position += to.normalized() * step
	queue_redraw()


func _arrive() -> void:
	FxLib.burst(get_parent(), {
		"amount": 8, "life": 0.3, "v_min": 60.0, "v_max": 150.0, "texture": FxLib.glow(),
		"s_min": 0.04, "s_max": 0.08, "ramp": FxLib.fade_ramp(glow_color), "additive": true, "curve": null,
	}, global_position)
	if on_arrive.is_valid():
		on_arrive.call()
	_trail.emitting = false
	_trail.reparent(get_parent())
	get_tree().create_timer(0.5).timeout.connect(_trail.queue_free)
	queue_free()


func _draw() -> void:
	var charging := _state == State.ORBIT
	var pulse := 1.0 + 0.15 * sin(_t * (12.0 if charging else 25.0))
	var r := orb_radius * pulse
	# dark smoke halo, pale rim, void core
	draw_circle(Vector2.ZERO, r * 2.2, Color(0.0, 0.0, 0.0, 0.25))
	draw_arc(Vector2.ZERO, r * 1.15, 0.0, TAU, 24, Color(glow_color, 0.55), 1.5, true)
	draw_circle(Vector2.ZERO, r, core_color)
	draw_circle(Vector2(-r, -r) * 0.25, r * 0.22, Color(glow_color, 0.6))
