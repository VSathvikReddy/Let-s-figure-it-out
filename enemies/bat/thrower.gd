extends CharacterBody2D
## Thrower - flies like the Baby Dragon in Clash of Clans:
##  - FLIES: ignores the ground and platforms, bobs in the air
##  - SPLASH FIRE BREATH: from range it spits fireballs (fire ball.tscn) that
##    burst in an area, hurting the player and marking the painting
##  - KEEPS DISTANCE: hovers at breath range and backs off if you get too close
## Wanders until the player comes into the DetectionZone.

enum State { WANDER, CHASE, BREATHE }

@export_group("Flying")
@export var fly_speed: float = 200.0
@export var wander_speed: float = 45.0
## How quickly it changes direction (higher = snappier).
@export var steering: float = 3.0
## Up-and-down hover bob of the sprite.
@export var bob_height: float = 8.0
@export var bob_speed: float = 2.5

@export_group("Fire Breath")
## Distance it likes to keep from the player while breathing fire.
@export var breath_range: float = 230.0
## Closer than this and it backs away.
@export var too_close: float = 150.0
## Seconds between fireballs.
@export var breath_interval: float = 1.4
@export var fireball_scene: PackedScene = preload("res://enemies/bat/fire ball.tscn")


var state: State = State.WANDER
var target_player: Node2D = null
var wander_direction: Vector2 = Vector2.ZERO

var trail: CPUParticles2D
var _breath_cd := 0.0
var _t := 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var muzzle: Marker2D = $Muzzle
@onready var detection_zone: Area2D = $DetectionZone
@onready var wander_timer: Timer = $WanderTimer

signal state_changed(new_state: State)


func _ready() -> void:
	detection_zone.body_entered.connect(_on_detection_zone_entered)
	detection_zone.body_exited.connect(_on_detection_zone_exited)
	wander_timer.timeout.connect(_on_wander_timer_timeout)
	_create_trail()
	_pick_new_wander_direction()
	wander_timer.start()
	_breath_cd = breath_interval


# --- State machine ---
func set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(new_state)


func _physics_process(delta: float) -> void:
	_t += delta
	if state != State.WANDER and not is_instance_valid(target_player):
		target_player = null
		set_state(State.WANDER)

	var want := Vector2.ZERO
	match state:
		State.WANDER:
			want = wander_direction * wander_speed
		State.CHASE:
			# fly in until it is in breath range
			var to := target_player.global_position - global_position
			want = to.normalized() * fly_speed
			if to.length() <= breath_range:
				set_state(State.BREATHE)
		State.BREATHE:
			want = _keep_distance()
			_breathe(delta)

	# smooth flying: steer toward the wanted velocity, no gravity
	velocity = velocity.lerp(want, 1.0 - exp(-steering * delta))
	global_position += velocity * delta

	# look where it is going / at the player, and bob in the air
	var face := velocity.x
	if is_instance_valid(target_player):
		face = target_player.global_position.x - global_position.x
	if absf(face) > 1.0:
		sprite.flip_h = face < 0.0
	sprite.position.y = sin(_t * bob_speed * TAU * 0.5) * bob_height
	trail.emitting = velocity.length() > 5.0


## Hover at breath range: come closer when too far, back off when too close,
## and drift sideways a little so it is not a sitting duck.
func _keep_distance() -> Vector2:
	var to := target_player.global_position - global_position
	var dist := to.length()
	var dir := to / maxf(dist, 0.001)
	if dist > breath_range * 1.4:
		set_state(State.CHASE)
		return dir * fly_speed
	var v := Vector2.ZERO
	if dist < too_close:
		v = -dir * fly_speed  # too close: back away
	elif dist > breath_range:
		v = dir * fly_speed * 0.5
	v += dir.orthogonal() * sin(_t * 0.9) * wander_speed  # circle a bit
	v.y -= 30.0 if global_position.y > target_player.global_position.y - 80.0 else 0.0  # stay above
	return v


func _breathe(delta: float) -> void:
	_breath_cd -= delta
	if _breath_cd > 0.0:
		return
	_breath_cd = breath_interval
	var ball := fireball_scene.instantiate()
	get_tree().current_scene.add_child(ball)
	ball.global_position = muzzle.global_position
	# works with either fireball script: fire_ball.gd (splash) or fire ball.gd
	if ball.has_method("launch"):
		ball.launch(target_player.global_position)
	elif ball.has_method("setup"):
		ball.setup(muzzle.global_position, target_player.global_position)
	# a little recoil, like a dragon puffing
	velocity -= (target_player.global_position - global_position).normalized() * 60.0


func _pick_new_wander_direction() -> void:
	wander_direction = Vector2(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5)).normalized()


func _on_wander_timer_timeout() -> void:
	if state == State.WANDER:
		_pick_new_wander_direction()


# --- Detection Zone ---
func _on_detection_zone_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		target_player = body
		set_state(State.CHASE)


func _on_detection_zone_exited(body: Node2D) -> void:
	if body == target_player and state == State.CHASE:
		target_player = null
		_pick_new_wander_direction()
		set_state(State.WANDER)


# --- Getting hurt ---
func take_damage(damage: int) -> void:
	_die()


func _die() -> void:
	_spawn_burst(30, 0.6, 80.0, 220.0, 4.0, 8.0, Color(1.0, 0.5, 0.1))
	_spawn_burst(12, 0.9, 20.0, 70.0, 8.0, 14.0, Color(0.25, 0.25, 0.25, 0.8))
	_release_trail()
	queue_free()


# --- PARTICLE EFFECTS ---

func _create_trail() -> void:
	trail = CPUParticles2D.new()
	trail.local_coords = false
	trail.emitting = false
	trail.amount = 20
	trail.lifetime = 0.45
	trail.spread = 180.0
	trail.gravity = Vector2.ZERO
	trail.initial_velocity_min = 5.0
	trail.initial_velocity_max = 20.0
	trail.scale_amount_min = 2.0
	trail.scale_amount_max = 4.0
	trail.color_ramp = _fade(Color(1.0, 0.55, 0.15))
	trail.z_index = -1
	add_child(trail)


func _release_trail() -> void:
	trail.emitting = false
	trail.reparent(get_tree().current_scene)
	get_tree().create_timer(trail.lifetime).timeout.connect(trail.queue_free)


func _spawn_burst(count: int, life: float, vel_min: float, vel_max: float,
		size_min: float, size_max: float, color: Color) -> void:
	var burst := CPUParticles2D.new()
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = count
	burst.lifetime = life
	burst.spread = 180.0
	burst.gravity = Vector2.ZERO
	burst.initial_velocity_min = vel_min
	burst.initial_velocity_max = vel_max
	burst.scale_amount_min = size_min
	burst.scale_amount_max = size_max
	burst.color_ramp = _fade(color)
	get_tree().current_scene.add_child(burst)
	burst.global_position = global_position
	burst.emitting = true
	burst.finished.connect(burst.queue_free)


func _fade(c: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	return g
