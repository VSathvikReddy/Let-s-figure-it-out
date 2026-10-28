extends Node2D
## Ghost summoned by the witch. The moment it is released it LOCKS a target in
## the painting (marked with a pulsing ring), slowly rises out of the summoning
## circle, glides into the painting, haunts the spot (the player can kill it
## there with a painting shot), then shrieks and distorts the painting. Drawn in code: a
## translucent wiggly sheet-ghost with a wavy tail and glowing eyes.
## The witch overrides these values from her "Ghost" group when she summons.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const PaintPicker := preload("res://sinan/painting/paint_picker.gd")
const DepthFlight := preload("res://sinan/painting/depth_flight.gd")
const WarpRipple := preload("res://sinan/fx/blasts/warp_ripple.gd")
const TargetMarker := preload("res://sinan/actors/enemies/forger/target_marker.gd")

enum State { WAITING, RISE, DIVE, HAUNT, ATTACK }

@export_group("Timing")
## Wait before appearing (lets a group of ghosts come out one after another).
@export var start_delay := 0.0
## How high it floats up out of the circle before gliding into the painting.
@export var rise_height := 140.0
## Seconds the slow rise takes.
@export var rise_time := 2.4
## Seconds the glide from the top of the rise into the painting takes.
@export var dive_time := 1.8
## Show a pulsing ring on the locked target from the moment it is released.
@export var show_target_marker := true
## Seconds it hovers over its target before attacking (the player's window to kill it).
@export var haunt_time := 2.0

@export_group("Painting Attack")
## Radius of the distortion it causes when it attacks (painting layer px).
@export var distortion_radius := 110.0
## 1 = pushes the painting one detail level worse at the centre.
@export var distortion_strength := 1.0
## Pick the cleanest of several random spots (undoes the player's restoring).
@export var target_restored_areas := true
@export var target_candidates := 6
## A painting shot landing this close (plus half the shot's radius) kills it.
@export var hit_radius := 30.0
## Size multiplier once it is inside the painting (depth shrinks it otherwise).
@export var painting_size := 1.6
## Size of the warp ripple when it attacks, relative to distortion_radius.
@export var warp_size := 0.6
## How strongly the ripple bends the painting.
@export var warp_strength := 0.045

@export_group("Look")
@export var ghost_radius := 14.0
@export var ghost_color := Color(0.75, 0.9, 1.0)
@export_range(0.0, 1.0) var opacity := 0.55
@export var eye_color := Color(0.12, 0.0, 0.22)
@export var angry_eye_color := Color(1.0, 0.25, 0.45)
@export var wiggle_speed := 6.0
@export var wiggle_amount := 1.0

var _state := State.WAITING
var _t := 0.0
var _age := 0.0
var _start := Vector2.ZERO
var _flight: DepthFlight
var _layer: Node2D
var _local := Vector2.ZERO
var _wisps: CPUParticles2D
var _target := {}          # locked at release: {layer, local, scale}
var _marker: Node2D
var _light: PointLight2D


func _ready() -> void:
	add_to_group("ghosts")
	z_index = 3
	_start = position
	scale = Vector2.ZERO
	# its glow (the Light node in ghost.tscn; tune it there)
	_light = get_node_or_null("Light") as PointLight2D
	if _light == null:
		_light = PointLight2D.new()
		_light.texture = FxLib.glow()
		_light.energy = 0.7
		_light.texture_scale = ghost_radius / 12.0
		add_child(_light)
	_light.color = ghost_color
	_wisps = FxLib.emitter({
		"one_shot": false, "amount": 18, "life": 0.7, "v_min": 5.0, "v_max": 20.0,
		"direction": Vector2.DOWN, "spread": 40.0, "gravity": Vector2(0, -15),
		"texture": FxLib.glow(), "s_min": ghost_radius / 140.0, "s_max": ghost_radius / 80.0,
		"ramp": FxLib.fade_ramp(ghost_color), "additive": true, "curve": null,
	})
	_wisps.position = Vector2(0, ghost_radius)
	_wisps.emitting = false
	add_child(_wisps)


func _physics_process(delta: float) -> void:
	_age += delta
	_t += delta
	match _state:
		State.WAITING:
			if _t >= start_delay:
				_release()
		State.RISE:
			var k := clampf(_t / rise_time, 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)  # slow start, slow stop
			position = _start + Vector2(sin(_age * 2.5) * 10.0, -rise_height * e)
			scale = Vector2.ONE * minf(1.0, _t / 0.5)
			if k >= 1.0:
				_begin_dive()
		State.DIVE:
			if _flight.step(delta):
				_arrive()
			rotation = 0.0
		State.HAUNT:
			if _t >= haunt_time:
				_attack()
		State.ATTACK:
			if _t > 0.5:
				queue_free()


func _set_state(s: State) -> void:
	_state = s
	_t = 0.0


## Released: pick and LOCK the target right now, mark it, start rising.
func _release() -> void:
	_target = _choose_target()
	if _target.is_empty():
		queue_free()
		return
	if show_target_marker and is_instance_valid(_target["layer"]):
		var m := TargetMarker.new()
		m.radius = distortion_radius * 0.55
		m.color = angry_eye_color
		m.position = _target["local"]
		(_target["layer"] as Node).add_child(m)
		_marker = m
	_set_state(State.RISE)
	_wisps.emitting = true
	_puff(8)


func _begin_dive() -> void:
	if _target.is_empty() or not is_instance_valid(_target["layer"]):
		_puff(10)
		queue_free()
		return
	var p := _target.duplicate()
	p["scale"] = minf(float(_target["scale"]) * painting_size, 1.2)
	_flight = DepthFlight.new(self, global_position, p, Vector2.ZERO, dive_time, 60.0)
	z_index = 0
	_set_state(State.DIVE)


func _exit_tree() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()


## A random visible spot in the painting; optionally the least distorted of a few.
func _choose_target() -> Dictionary:
	var root := get_parent()
	var vp := get_viewport()
	var view_to_world := vp.get_canvas_transform().affine_inverse()
	var view := vp.get_visible_rect()
	var best := {}
	var best_value := INF
	var tries := maxi(target_candidates, 1) if target_restored_areas else 1
	for attempt in tries * 3:
		var screen := view.position + Vector2(randf_range(0.1, 0.9) * view.size.x, randf_range(0.08, 0.75) * view.size.y)
		var pick := PaintPicker.pick(root, view_to_world * screen)
		if pick.is_empty():
			continue
		var value := 0.0
		var layer = pick["layer"]
		if target_restored_areas and layer.has_method("distortion_at"):
			value = layer.distortion_at(pick["local"])
		if value < best_value:
			best_value = value
			best = pick
		tries -= 1
		if tries <= 0:
			break
	return best


func _arrive() -> void:
	_layer = _flight.layer
	_local = _flight.local
	if is_instance_valid(_layer):
		reparent(_layer)
	_set_state(State.HAUNT)
	_puff(6)


func _attack() -> void:
	_set_state(State.ATTACK)
	if is_instance_valid(_layer):
		Paint.hit(self, _layer, _local, distortion_radius, distortion_strength, Paint.Kind.SMUDGE, &"ghost")
	# the painting warps where it shrieks
	var b := WarpRipple.new()
	b.radius = distortion_radius * warp_size
	b.amplitude = warp_strength
	b.tint = ghost_color
	b.position = position
	get_parent().add_child(b)
	get_tree().call_group("player", "add_trauma", 0.1, global_position)


## Called by player painting shots (bullets, rockets, orbs, paint blobs).
func on_painting_shot(layer: Node, local: Vector2, radius: float) -> void:
	if _state != State.HAUNT or layer != _layer:
		return
	if local.distance_to(_local) <= hit_radius + radius * 0.5:
		# dies in a cold, smoky poof
		_puff(16)
		FxLib.smoke_burst(get_parent(), global_position, ghost_radius / 14.0 * scale.x, ghost_color.darkened(0.25), 12)
		FxLib.flash_light(get_parent(), global_position, ghost_color, 1.5, 1.2, 0.25)
		queue_free()


func _puff(amount: int) -> void:
	FxLib.burst(get_parent(), {
		"amount": amount, "life": 0.6, "v_min": 20.0, "v_max": 80.0, "gravity": Vector2(0, -30),
		"texture": FxLib.glow(), "s_min": 0.06, "s_max": 0.16, "damp_min": 40.0, "damp_max": 80.0,
		"ramp": FxLib.fade_ramp(ghost_color), "additive": true, "curve": null,
	}, global_position)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _state == State.WAITING:
		return
	var R := ghost_radius
	var alpha := 1.0
	var grow := 1.0
	var anger := 0.0
	var shiver := 0.0
	match _state:
		State.HAUNT:
			anger = clampf(_t / haunt_time, 0.0, 1.0)
			grow = 1.0 + 0.15 * anger
			shiver = anger * anger * R * 0.15
		State.ATTACK:
			anger = 1.0
			var k := clampf(_t / 0.5, 0.0, 1.0)
			grow = 1.3 + 0.4 * k
			alpha = 1.0 - k

	# danger ring while haunting: tells the player where it will strike
	if _state == State.HAUNT:
		var ring_r := R * 2.6 * (1.0 - anger * 0.25)
		for i in 8:
			var a0 := _age * 2.0 + i * TAU / 8.0
			draw_arc(Vector2.ZERO, ring_r, a0, a0 + 0.45, 6, Color(angry_eye_color, 0.25 + 0.5 * anger), 1.5, true)

	var w := wiggle_amount
	var sway := Vector2(sin(_age * wiggle_speed * 0.5) * R * 0.25 * w + randf_range(-shiver, shiver),
		sin(_age * wiggle_speed * 0.8) * R * 0.12 * w)
	var tilt := sin(_age * wiggle_speed * 0.5) * 0.15 * w
	var squish := 1.0 + sin(_age * wiggle_speed) * 0.06 * w
	draw_set_transform(sway, tilt, Vector2(grow / squish, grow * squish))

	draw_circle(Vector2(0, R * 0.2), R * 1.9, Color(ghost_color, 0.08 * alpha))

	# body: round head, straight sides, wavy tail
	var body := PackedVector2Array()
	for i in 11:
		var a := PI + PI * i / 10.0
		body.append(Vector2(cos(a), sin(a)) * R)
	body.append(Vector2(R, R * 0.9))
	for i in 9:
		var x := R - i * (2.0 * R / 8.0)
		body.append(Vector2(x, R * 1.3 + sin(x / R * PI * 1.5 + _age * wiggle_speed * 1.5) * R * 0.25 * w))
	body.append(Vector2(-R, R * 0.9))
	draw_colored_polygon(body, Color(ghost_color, opacity * alpha))
	var inner := PackedVector2Array()
	for p in body:
		inner.append(p * 0.62 + Vector2(0, -R * 0.15))
	draw_colored_polygon(inner, Color(1, 1, 1, opacity * 0.45 * alpha))

	# eyes (turn angry and glow) and a mouth that opens into a shriek
	var eye := eye_color.lerp(angry_eye_color, anger)
	for sx in [-1.0, 1.0]:
		var c := Vector2(sx * R * 0.35, -R * 0.15)
		draw_circle(c, R * 0.2, Color(eye, 0.95 * alpha))
		if anger > 0.3:
			draw_circle(c, R * 0.32, Color(angry_eye_color, 0.25 * anger * alpha))
	var mouth := R * (0.1 + 0.2 * anger)
	draw_circle(Vector2(0, R * 0.35), mouth, Color(eye_color, 0.9 * alpha))
