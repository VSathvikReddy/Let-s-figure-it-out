extends Node2D
## A friendly ghost summoned by the player (the witch).
##
## Its life:
##   1. WAITING - waits `start_delay` (so a group comes out one by one).
##   2. RISE    - picks the MOST DAMAGED spot of the painting it can see and
##                marks it with a soft ring, then floats slowly up out of the
##                summoning circle.
##   3. GLIDE   - glides over to that spot.
##   4. CLEAN   - hovers there, glowing brighter and brighter...
##   5. DONE    - ...then releases its light: the painting around it is
##                restored (more detail), and the ghost fades away.
##
## It is drawn in code: a see-through wiggly sheet ghost with a wavy tail.

const Effects := preload("res://compined/common/effects.gd")

enum State { WAITING, RISE, GLIDE, CLEAN, DONE }

@export_group("Timing")
## Seconds before it appears.
@export var start_delay := 0.0
## How high it floats up out of the circle, and how long that takes.
@export var rise_height := 140.0
@export var rise_time := 2.4
## Seconds to glide from the top of the rise to its spot.
@export var glide_time := 1.8
## Seconds it hovers over the spot before cleaning it.
@export var clean_time := 2.0

@export_group("Cleaning")
## Radius of the area it restores, in px.
@export var clean_radius := 110.0
## How many detail levels it brings back at the centre (1 = one level).
@export var clean_amount := 1
## It checks this many random spots on screen and picks the most damaged one.
@export var spots_to_check := 12

@export_group("Look")
@export var ghost_radius := 14.0
@export var ghost_color := Color(1.0, 0.82, 0.86)
@export var clean_color := Color(1.0, 0.92, 0.6)   ## its glow while cleaning
@export_range(0.0, 1.0) var opacity := 0.55
@export var eye_color := Color(0.12, 0.0, 0.22)
@export var wiggle_speed := 6.0
@export var wiggle_amount := 1.0

var state := State.WAITING
var target := Vector2.ZERO          # the painting spot it will clean (world)
var _time_in_state := 0.0
var _age := 0.0
var _start := Vector2.ZERO
var _glide_from := Vector2.ZERO
var _wisps: CPUParticles2D

@onready var clean_area: Area2D = $CleanArea
@onready var clean_shape: CollisionShape2D = $CleanArea/Shape


func _ready() -> void:
	z_index = 3
	_start = global_position
	scale = Vector2.ZERO
	(clean_shape.shape as CircleShape2D).radius = clean_radius
	_wisps = Effects.make_trail(self, ghost_color, 18, 0.7)
	_wisps.position = Vector2(0, ghost_radius)


func _process(delta: float) -> void:
	_age += delta
	_time_in_state += delta
	match state:
		State.WAITING:
			if _time_in_state >= start_delay:
				_appear()
		State.RISE:
			var progress := clampf(_time_in_state / rise_time, 0.0, 1.0)
			var eased := smoothstep(0.0, 1.0, progress)   # slow start, slow stop
			global_position = _start + Vector2(sin(_age * 2.5) * 10.0, -rise_height * eased)
			scale = Vector2.ONE * minf(1.0, _time_in_state / 0.5)
			if progress >= 1.0:
				_glide_from = global_position
				_set_state(State.GLIDE)
		State.GLIDE:
			var progress := clampf(_time_in_state / glide_time, 0.0, 1.0)
			var eased := smoothstep(0.0, 1.0, progress)
			# a gentle arc: it lifts a little in the middle of the glide
			var lift := Vector2(0, -sin(progress * PI) * 40.0)
			global_position = _glide_from.lerp(target, eased) + lift
			if progress >= 1.0:
				_set_state(State.CLEAN)
		State.CLEAN:
			global_position = target + Vector2(0, sin(_age * 2.0) * 4.0)
			if _time_in_state >= clean_time:
				_clean()
		State.DONE:
			if _time_in_state > 0.5:
				queue_free()
	queue_redraw()


func _set_state(new_state: State) -> void:
	state = new_state
	_time_in_state = 0.0


func _appear() -> void:
	target = _find_most_damaged_spot()
	_wisps.emitting = true
	Effects.burst(self, 8, ghost_color, 0.6, 20.0, 80.0, 3.0, 6.0)
	_set_state(State.RISE)


## Checks random spots on the screen (inside the painting) and returns the one
## with the least detail. Without a painting it just picks a spot above.
func _find_most_damaged_spot() -> Vector2:
	var painting := get_tree().get_first_node_in_group("painting")
	var screen_to_world := get_viewport().get_canvas_transform().affine_inverse()
	var screen := get_viewport().get_visible_rect()
	var best_spot := _start + Vector2(randf_range(-150, 150), -rise_height - 60.0)
	if painting == null:
		return best_spot
	var painting_rect: Rect2 = painting.world_rect()
	var best_detail := INF
	for i in spots_to_check:
		var on_screen := screen.position + Vector2(randf_range(0.1, 0.9), randf_range(0.1, 0.9)) * screen.size
		var spot := screen_to_world * on_screen
		if not painting_rect.has_point(spot):
			continue
		var detail: float = painting.detail_at(spot)
		if detail < best_detail:
			best_detail = detail
			best_spot = spot
	return best_spot


## Releases its light: restores the painting around it, then fades away.
func _clean() -> void:
	Effects.paint(clean_area, clean_amount)
	Effects.burst(self, 24, clean_color, 0.7, 60.0, 180.0, 3.0, 7.0)
	Effects.leave_trail_behind(_wisps)
	_set_state(State.DONE)


# --- drawing ---------------------------------------------------------------

func _draw() -> void:
	if state == State.WAITING:
		return
	var R := ghost_radius
	var alpha := 1.0
	var grow := 1.0
	var glow := 0.0                  # 0..1, how close it is to cleaning

	match state:
		State.CLEAN:
			glow = clampf(_time_in_state / clean_time, 0.0, 1.0)
			grow = 1.0 + 0.15 * glow
		State.DONE:
			glow = 1.0
			var fade := clampf(_time_in_state / 0.5, 0.0, 1.0)
			grow = 1.3 + 0.4 * fade
			alpha = 1.0 - fade

	# the spot it is going to clean: a soft turning ring
	if state in [State.RISE, State.GLIDE]:
		var ring_at := to_local(target)
		for i in 8:
			var start_angle := _age * 1.5 + i * TAU / 8.0
			draw_arc(ring_at, clean_radius * 0.5, start_angle, start_angle + 0.45, 6, Color(clean_color, 0.4), 2.0, true)

	# while cleaning: a growing ring of light around it
	if state == State.CLEAN:
		var ring := R * 2.6 * (1.0 + glow * 0.5)
		draw_arc(Vector2.ZERO, ring, 0.0, TAU, 32, Color(clean_color, 0.2 + 0.6 * glow), 2.0, true)
		draw_circle(Vector2.ZERO, ring, Color(clean_color, 0.08 * glow))

	# body wobble
	var w := wiggle_amount
	var sway := Vector2(sin(_age * wiggle_speed * 0.5) * R * 0.25 * w, sin(_age * wiggle_speed * 0.8) * R * 0.12 * w)
	var tilt := sin(_age * wiggle_speed * 0.5) * 0.15 * w
	var squish := 1.0 + sin(_age * wiggle_speed) * 0.06 * w
	draw_set_transform(sway, tilt, Vector2(grow / squish, grow * squish))

	var body_color := ghost_color.lerp(clean_color, glow)
	draw_circle(Vector2(0, R * 0.2), R * 1.9, Color(body_color, 0.08 * alpha))   # soft halo

	# body: round head, straight sides, wavy tail
	var body := PackedVector2Array()
	for i in 11:
		var angle := PI + PI * i / 10.0
		body.append(Vector2(cos(angle), sin(angle)) * R)
	body.append(Vector2(R, R * 0.9))
	for i in 9:
		var x := R - i * (2.0 * R / 8.0)
		body.append(Vector2(x, R * 1.3 + sin(x / R * PI * 1.5 + _age * wiggle_speed * 1.5) * R * 0.25 * w))
	body.append(Vector2(-R, R * 0.9))
	draw_colored_polygon(body, Color(body_color, opacity * alpha))
	var inner := PackedVector2Array()
	for point in body:
		inner.append(point * 0.62 + Vector2(0, -R * 0.15))
	draw_colored_polygon(inner, Color(1, 1, 1, opacity * 0.45 * alpha))

	# kind eyes and a small smile
	for side in [-1.0, 1.0]:
		var eye := Vector2(side * R * 0.35, -R * 0.15)
		draw_circle(eye, R * 0.2, Color(eye_color, 0.95 * alpha))
		draw_circle(eye + Vector2(-R * 0.06, -R * 0.07), R * 0.07, Color(1, 1, 1, 0.9 * alpha))
	draw_arc(Vector2(0, R * 0.25), R * 0.22, 0.2, PI - 0.2, 8, Color(eye_color, 0.9 * alpha), 1.5, true)
