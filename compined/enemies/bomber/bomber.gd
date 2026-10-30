extends CharacterBody2D
## Heavy bomber. Wanders around; when the player comes close it chases them.
## When the player gets VERY close it lights its fuse (cannot be stopped) and
## explodes: hurts the player and breaks the painting around it.
##
## Zones (child Area2Ds):
##   DetectionZone - big circle, the player inside it gets chased
##   TriggerZone   - small circle, the player inside it lights the fuse
##   ExplosionZone - what the explosion hits

const Effects := preload("res://compined/common/effects.gd")

enum State { WANDER, CHASE, LIT }

@export var chase_speed := 120.0
@export var wander_speed := 40.0
@export var health := 3
@export var explosion_damage := 3        ## damage to the player
@export var painting_damage := 3         ## how much the explosion breaks the painting
@export var fuse_time := 1.5             ## seconds from lighting to exploding
@export var explode_sound: AudioStream
@export var death_sound: AudioStream

var state := State.WANDER
var target: Node2D = null
var wander_direction := Vector2.ZERO
var trail: CPUParticles2D

@onready var detection_zone: Area2D = $DetectionZone
@onready var trigger_zone: Area2D = $TriggerZone
@onready var explosion_zone: Area2D = $ExplosionZone
@onready var wander_timer: Timer = $WanderTimer
@onready var fuse_timer: Timer = $FuseTimer
@onready var fuse_sound: AudioStreamPlayer2D = $FuseSound


func _ready() -> void:
	add_to_group("enemy")
	detection_zone.body_entered.connect(_on_detection_zone_entered)
	detection_zone.body_exited.connect(_on_detection_zone_exited)
	trigger_zone.body_entered.connect(_on_trigger_zone_entered)
	wander_timer.timeout.connect(_pick_wander_direction)
	fuse_timer.timeout.connect(_explode)
	fuse_timer.wait_time = fuse_time

	trail = Effects.make_trail(self, Color(1.0, 0.55, 0.15))
	_pick_wander_direction()


func _physics_process(_delta: float) -> void:
	if state == State.CHASE and not is_instance_valid(target):
		state = State.WANDER   # the player is gone

	match state:
		State.WANDER:
			velocity = wander_direction * wander_speed
		State.CHASE:
			velocity = global_position.direction_to(target.global_position) * chase_speed
		State.LIT:
			velocity = Vector2.ZERO
	move_and_slide()
	trail.emitting = velocity.length() > 5.0


func _pick_wander_direction() -> void:
	wander_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()


func _on_detection_zone_entered(body: Node2D) -> void:
	if body.is_in_group("player") and state == State.WANDER:
		target = body
		state = State.CHASE


func _on_detection_zone_exited(body: Node2D) -> void:
	if body == target and state == State.CHASE:
		target = null
		state = State.WANDER
		_pick_wander_direction()


func _on_trigger_zone_entered(body: Node2D) -> void:
	if body.is_in_group("player") and state != State.LIT:
		state = State.LIT
		fuse_sound.play()
		fuse_timer.start()


func _explode() -> void:
	for body in explosion_zone.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(explosion_damage)
	Effects.paint(explosion_zone, -painting_damage)
	Effects.fire_explosion(self)
	Effects.play_sound(self, explode_sound)
	Effects.leave_trail_behind(trail)
	queue_free()


## Called by the brush.
func take_damage(damage: int) -> void:
	health -= damage
	if health <= 0:
		Effects.play_sound(self, death_sound)
		Effects.leave_trail_behind(trail)
		queue_free()
