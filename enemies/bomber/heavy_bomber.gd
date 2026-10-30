extends CharacterBody2D

enum State { WANDER, CHASE, IGNITED }

@export var chase_speed: float = 120.0
@export var wander_speed: float = 40.0
@export var explosion_damage: int = 3
@export var environment_damage:int = -3
@export var fuse_time: float = 1.5 # Time in seconds before exploding
@export var death_sound: AudioStream

var state: State = State.WANDER
var target_player: Node2D = null
var wander_direction: Vector2 = Vector2.ZERO
var trail: CPUParticles2D

@onready var detection_zone: Area2D = $DetectionZone
@onready var trigger_zone: Area2D = $TriggerZone
@onready var explosion_zone: Area2D = $ExplosionZone
@onready var wander_timer: Timer = $WanderTimer
@onready var ignition_timer: Timer = $IgnitionTimer
@onready var ignition_sound: AudioStreamPlayer2D = $Ignition

signal state_changed(new_state: State)

func _ready() -> void:
	detection_zone.body_entered.connect(_on_detection_zone_entered)
	detection_zone.body_exited.connect(_on_detection_zone_exited)
	trigger_zone.body_entered.connect(_on_trigger_zone_entered)
	wander_timer.timeout.connect(_on_wander_timer_timeout)
	ignition_timer.timeout.connect(_explode)

	ignition_timer.wait_time = fuse_time
	ignition_timer.one_shot = true

	_create_trail()
	_pick_new_wander_direction()
	wander_timer.start()
	_enter_state(state)

# --- State machine ---
func set_state(new_state: State) -> void:
	if state == new_state:
		return
	if state == State.IGNITED:
		return # point of no return
	state = new_state
	_enter_state(new_state)
	state_changed.emit(new_state)

func _enter_state(s: State) -> void:
	# Hook your animations / sounds / shaders here
	match s:
		State.WANDER:
			pass # e.g. $AnimatedSprite2D.play("walk")
		State.CHASE:
			pass # e.g. $AnimatedSprite2D.play("run")
		State.IGNITED:
			ignition_timer.start()
			# e.g. $AnimatedSprite2D.play("hiss"), flash shader, hiss sound

func _physics_process(_delta: float) -> void:
	match state:
		State.IGNITED:
			velocity = Vector2.ZERO
		State.CHASE:
			velocity = global_position.direction_to(target_player.global_position) * chase_speed
		State.WANDER:
			velocity = wander_direction * wander_speed

	move_and_slide()

	trail.emitting = state != State.IGNITED and velocity.length() > 5.0

func _pick_new_wander_direction() -> void:
	wander_direction = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()

func _on_wander_timer_timeout() -> void:
	if state == State.WANDER:
		_pick_new_wander_direction()

# --- Detection Zone ---
func _on_detection_zone_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		target_player = body
		set_state(State.CHASE)

func _on_detection_zone_exited(body: Node2D) -> void:
	if body == target_player:
		target_player = null
		_pick_new_wander_direction()
		set_state(State.WANDER) # ignored if already IGNITED

# --- Trigger Zone (starts the fuse, can't be cancelled) ---
func _on_trigger_zone_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		set_state(State.IGNITED)
		ignition_sound.play()

# --- Explosion ---
func _explode() -> void:
	for body in explosion_zone.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(explosion_damage)
			
	if PaintCanvas.can_paint():
		PaintCanvas.paint(explosion_zone, environment_damage)
	_spawn_explosion()
	if death_sound:
		var sfx_player = AudioStreamPlayer2D.new() #New Node
		sfx_player.stream = death_sound #Assign Sound
		sfx_player.global_position = global_position #set pos
		get_tree().current_scene.add_child(sfx_player) #make it the sibling
		sfx_player.play() #play
		sfx_player.finished.connect(sfx_player.queue_free) #let it play and then kill it
	_release_trail()
	queue_free()

# --- PARTICLE EFFECTS (unchanged) ---

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

func _spawn_explosion() -> void:
	_spawn_burst(40, 0.5, 120.0, 280.0, 4.0, 8.0, Color(1.0, 0.6, 0.1))
	_spawn_burst(16, 0.9, 30.0, 90.0, 8.0, 14.0, Color(0.25, 0.25, 0.25, 0.8))

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
