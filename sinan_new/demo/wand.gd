extends Node2D
## The wand (RIGHT mouse button). Works like the BrushAttack in player/.
##
## Hold: an arc grows around the player, centred on the mouse. The longer you
## hold, the wider the arc gets - and the tighter it pulls in, which makes it
## reach further when you let go (reach = rad_start * rad_start / radius).
## Release: the wand swings across the arc, the arc flies outward and fades,
## and the painting under that final fan shape is repaired by one detail level.
##
## Scene:
##   Wand (this script)
##   ├─ Brush (Node2D)            <- turned towards the mouse
##   │   └─ Sprite2D
##   └─ HurtBox (Area2D)
##       └─ CollisionPolygon2D    <- leave empty, filled with the fan on release

const CHASE_SHARPNESS := 12.0

@export var rad_start := 160.0       ## arc radius when you start holding
@export var rad_min := 40.0          ## arc radius at full charge (reach 160*160/40 = 640)
@export var rad_max := 640.0         ## radius at the far end of the colour gradient
@export var charge_speed := 10.0
@export var min_sweep := 0.1         ## arc width at the start (radians)
@export var max_sweep := PI          ## arc width at full charge (PI = half a circle)
@export var brush_distance := 0.0    ## how far from the player the wand is held
@export var shockwave_time := 0.35   ## seconds the arc takes to fly out and fade
@export var paint_amount := -1.0     ## detail levels changed (- repairs, + breaks)
@export var damage := 10             ## given to bodies with take_damage() in the fan
@export var color_gradient: Gradient ## arc colour by radius (white if empty)

enum State { IDLE, CHARGING, RELEASING }
var state := State.IDLE

var radius := rad_start
var sweep := 0.0
var chase_angle := 0.0
var chase_sharpness := CHASE_SHARPNESS
var wave_t := 0.0
var arc_alpha := 1.0
var rad_to := rad_start
var rad_from := rad_start
var shock_start_angle := 0.0
var was_down := false

@onready var brush: Node2D = $Brush
@onready var hurtbox: Area2D = $HurtBox
@onready var poly: CollisionPolygon2D = $HurtBox/CollisionPolygon2D


func _ready() -> void:
	hurtbox.monitoring = false


func _process(delta: float) -> void:
	var mouse_angle := to_local(get_global_mouse_position()).angle()
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var pressed := down and not was_down
	var released := was_down and not down
	was_down = down

	if pressed and state == State.IDLE:
		state = State.CHARGING
		sweep = min_sweep
		wave_t = 0.0
		arc_alpha = 1.0
		chase_angle = mouse_angle - sweep / 2
	elif state == State.CHARGING:
		# the arc widens fast at first, then slower as it nears max_sweep
		sweep = minf(sweep + charge_speed * ((1 - exp(-(max_sweep - sweep) * delta)) / (1 - exp(-max_sweep * delta))) * delta, max_sweep)
		chase_angle = mouse_angle - sweep / 2
		# ...and pulls in from rad_start towards rad_min
		radius = lerp(rad_start, rad_min, (1 - exp(-sweep * delta)) / (1 - exp(-max_sweep * delta)))
		if released:
			chase_angle = mouse_angle + sweep / 2  # swing to the other end of the arc
			chase_sharpness *= 2
			_release()
	elif state == State.IDLE:
		chase_angle = mouse_angle

	# the wand follows the arc's start while charging, and swings smoothly otherwise
	if state == State.CHARGING:
		brush.rotation = chase_angle
	else:
		brush.rotation = lerp_angle(brush.rotation, chase_angle, 1 - exp(-chase_sharpness * delta))
	brush.position = Vector2.from_angle(brush.rotation) * brush_distance

	if state == State.RELEASING:
		radius = lerpf(rad_from, rad_to, wave_t)  # the arc flying outward
	else:
		rad_to = rad_start * rad_start / radius
		rad_from = radius
		shock_start_angle = brush.rotation
	queue_redraw()


func _release() -> void:
	state = State.RELEASING

	# hit area = the same fan that is drawn on screen
	poly.polygon = _sector_points(rad_to, shock_start_angle, sweep)
	_hit()

	var tw := create_tween()
	tw.parallel().tween_property(self, "wave_t", 1.0, shockwave_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "arc_alpha", 0.0, shockwave_time)
	tw.tween_callback(_finish)


func _hit() -> void:
	Painting.paint(hurtbox, paint_amount)

	# overlaps only update after a physics step, so wait for it
	hurtbox.monitoring = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	for thing in hurtbox.get_overlapping_bodies() + hurtbox.get_overlapping_areas():
		if thing.has_method("take_damage"):
			thing.take_damage(damage)
	hurtbox.monitoring = false


func _finish() -> void:
	state = State.IDLE
	wave_t = 0.0
	arc_alpha = 1.0
	radius = rad_start
	chase_sharpness = CHASE_SHARPNESS


## A fan shape: the centre point plus points along the arc.
func _sector_points(r: float, from_angle: float, sweep_angle: float) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	var steps := maxi(4, int(ceil(sweep_angle / deg_to_rad(6.0))))
	for i in range(steps + 1):
		points.append(Vector2.from_angle(from_angle + sweep_angle * i / steps) * r)
	return points


func _draw() -> void:
	if state == State.IDLE:
		return
	var c := Color.WHITE
	if color_gradient:
		c = color_gradient.sample(clampf(remap(radius, rad_min, rad_max, 0.0, 1.0), 0.0, 1.0))
	c.a = arc_alpha
	var from := shock_start_angle if state == State.RELEASING else brush.rotation
	draw_arc(Vector2.ZERO, radius, from, from + sweep, maxi(8, int(sweep * 12.0)), c, 3.0, true)
