extends CharacterBody2D
## A flying fire-breather (like a baby dragon).
##   - Flies: no gravity, bobs up and down in the air.
##   - Spits fireballs from a distance; they burst and splash the player.
##   - Keeps its distance: hovers at `breath_range`, backs off if you come closer.
## It wanders until the player enters its DetectionZone.
##
## Animations (Sprite): "emerge" when it appears (shards come together into a
## bat), then "fly" on a loop.

const Effects := preload("res://compined/common/effects.gd")

enum State { WANDER, CHASE, BREATHE }

## Brush hits it can take (a small flyer).
@export var max_health := 2

@export_group("Flying")
@export var fly_speed := 200.0
@export var wander_speed := 45.0
@export var steering := 3.0          ## how quickly it turns (higher = snappier)
@export var bob_height := 8.0        ## px the sprite bobs up and down
@export var bob_speed := 2.5

@export_group("Fire Breath")
@export var breath_range := 230.0    ## distance it likes to keep from the player
@export var too_close := 150.0       ## closer than this and it backs away
@export var breath_interval := 1.4   ## seconds between fireballs
@export var fireball_scene: PackedScene = preload("res://compined/enemies/bat/fireball.tscn")
## How close it may get to the painting's edges, in px.
@export var edge_margin := 40.0

var health := 0
var state := State.WANDER
var target: Node2D = null
var wander_direction := Vector2.ZERO
var trail: CPUParticles2D
var _breath_cooldown := 0.0
var _time := 0.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var muzzle: Marker2D = $Muzzle
@onready var health_bar: Node2D = $HealthBar   # the small bar over its head
@onready var detection_zone: Area2D = $DetectionZone
@onready var wander_timer: Timer = $WanderTimer


func _ready() -> void:
	health = max_health
	health_bar.setup(max_health)
	add_to_group("enemy")
	detection_zone.body_entered.connect(_on_detection_zone_entered)
	detection_zone.body_exited.connect(_on_detection_zone_exited)
	wander_timer.timeout.connect(_pick_wander_direction)
	trail = Effects.make_trail(self, Color(1.0, 0.55, 0.15))
	_pick_wander_direction()
	_breath_cooldown = breath_interval
	sprite.play("emerge")
	sprite.animation_finished.connect(func() -> void: sprite.play("fly"), CONNECT_ONE_SHOT)


func _physics_process(delta: float) -> void:
	_time += delta
	if state != State.WANDER and not is_instance_valid(target):
		target = null
		state = State.WANDER   # the player is gone

	var wanted_velocity := Vector2.ZERO
	match state:
		State.WANDER:
			wanted_velocity = wander_direction * wander_speed
		State.CHASE:
			var to_player := target.global_position - global_position
			wanted_velocity = to_player.normalized() * fly_speed
			if to_player.length() <= breath_range:
				state = State.BREATHE
		State.BREATHE:
			wanted_velocity = _hover_near_player()
			_breathe_fire(delta)

	# smooth flying: turn toward the wanted velocity, no gravity
	velocity = velocity.lerp(wanted_velocity, 1.0 - exp(-steering * delta))
	global_position += velocity * delta
	_turn_back_at_edges()

	_update_looks()


## Never leaves the painting: at an edge it stops going that way.
func _turn_back_at_edges() -> void:
	var push := Effects.keep_inside_level(self, edge_margin)
	if push.x != 0.0:
		velocity.x = 0.0
		wander_direction.x = signf(push.x) * absf(wander_direction.x)
	if push.y != 0.0:
		velocity.y = 0.0
		wander_direction.y = signf(push.y) * absf(wander_direction.y)


## Stay at breath range: come closer when too far, back off when too close,
## circle a little so it is not an easy target, and stay above the player.
func _hover_near_player() -> Vector2:
	var to_player := target.global_position - global_position
	var distance := to_player.length()
	var toward := to_player / maxf(distance, 0.001)
	if distance > breath_range * 1.4:
		state = State.CHASE
		return toward * fly_speed

	var result := Vector2.ZERO
	if distance < too_close:
		result = -toward * fly_speed
	elif distance > breath_range:
		result = toward * fly_speed * 0.5
	result += toward.orthogonal() * sin(_time * 0.9) * wander_speed
	if global_position.y > target.global_position.y - 80.0:
		result.y -= 30.0
	return result


func _breathe_fire(delta: float) -> void:
	_breath_cooldown -= delta
	if _breath_cooldown > 0.0:
		return
	_breath_cooldown = breath_interval
	var fireball := fireball_scene.instantiate()
	get_tree().current_scene.add_child(fireball)
	fireball.global_position = muzzle.global_position
	fireball.launch(target.global_position)
	# a little recoil, like a dragon puffing
	velocity -= global_position.direction_to(target.global_position) * 60.0


func _update_looks() -> void:
	var facing := velocity.x
	if is_instance_valid(target):
		facing = target.global_position.x - global_position.x
	if absf(facing) > 1.0:
		sprite.flip_h = facing < 0.0
	sprite.position.y = sin(_time * bob_speed * PI) * bob_height
	trail.emitting = velocity.length() > 5.0


func _pick_wander_direction() -> void:
	if state == State.WANDER:
		wander_direction = Vector2(randf_range(-1, 1), randf_range(-0.5, 0.5)).normalized()


func _on_detection_zone_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		target = body
		state = State.CHASE


func _on_detection_zone_exited(body: Node2D) -> void:
	if body == target and state == State.CHASE:
		target = null
		state = State.WANDER
		_pick_wander_direction()


## Called by the brush. It dies when its health runs out.
func take_damage(damage: int) -> void:
	health -= damage
	health_bar.show_health(health)
	sprite.modulate = Color(3, 3, 3)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.15)
	if health > 0:
		return
	Effects.fire_explosion(self, false)
	Effects.leave_trail_behind(trail)
	queue_free()
