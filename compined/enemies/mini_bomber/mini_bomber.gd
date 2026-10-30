extends CharacterBody2D
## Mini bomber. Small, fast and glowing. Wanders around; when the player comes
## close it chases them, and the moment it touches them it blows up at once
## (no fuse): hurts the player and breaks the painting a little.
## One brush hit kills it without an explosion.
##
## Zones (child Area2Ds):
##   DetectionZone - the player inside it gets chased
##   TriggerZone   - the player inside it makes it explode
##   ExplosionZone - what the explosion hits

const Effects := preload("res://compined/common/effects.gd")

enum State { WANDER, CHASE }

@export var chase_speed := 260.0
@export var wander_speed := 90.0
@export var explosion_damage := 1        ## damage to the player
@export var painting_damage := 1         ## how much the explosion breaks the painting
@export var explode_sound: AudioStream
@export var death_sound: AudioStream

var state := State.WANDER
var target: Node2D = null
var wander_direction := Vector2.ZERO
var dead := false                        # exploding or killed: ignore everything else
var trail: CPUParticles2D
var glow: Sprite2D
var glow_pulse: Tween

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $BodyShape
@onready var detection_zone: Area2D = $DetectionZone
@onready var trigger_zone: Area2D = $TriggerZone
@onready var explosion_zone: Area2D = $ExplosionZone
@onready var wander_timer: Timer = $WanderTimer


func _ready() -> void:
	add_to_group("enemy")
	detection_zone.body_entered.connect(_on_detection_zone_entered)
	detection_zone.body_exited.connect(_on_detection_zone_exited)
	trigger_zone.body_entered.connect(_on_trigger_zone_entered)
	wander_timer.timeout.connect(_pick_wander_direction)

	sprite.play("fly")
	trail = Effects.make_trail(self, Color(0.3, 0.9, 0.5), 12, 0.3)
	_create_glow()
	_pick_wander_direction()


func _physics_process(_delta: float) -> void:
	if dead:
		return
	if state == State.CHASE and not is_instance_valid(target):
		state = State.WANDER   # the player is gone

	match state:
		State.WANDER:
			velocity = wander_direction * wander_speed
		State.CHASE:
			velocity = global_position.direction_to(target.global_position) * chase_speed
	move_and_slide()
	trail.emitting = velocity.length() > 5.0


func _pick_wander_direction() -> void:
	wander_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()


func _on_detection_zone_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		target = body
		state = State.CHASE


func _on_detection_zone_exited(body: Node2D) -> void:
	if body == target:
		target = null
		state = State.WANDER
		_pick_wander_direction()


func _on_trigger_zone_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_explode()


## Touched the player: damage, explosion, then the death animation.
func _explode() -> void:
	if dead:
		return
	for body in explosion_zone.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(explosion_damage)
	Effects.paint(explosion_zone, -painting_damage)
	Effects.rpg_explosion(self, 73.0, Color(0.35, 1.0, 0.5))   # small and green, as big as its ExplosionZone
	Effects.play_sound(self, explode_sound)
	_die()


## Called by the brush: dies without exploding.
func take_damage(_damage: int) -> void:
	if dead:
		return
	Effects.play_sound(self, death_sound)
	_die()


func _die() -> void:
	dead = true
	velocity = Vector2.ZERO
	# physics can't be changed inside a physics callback, so do it a moment later
	body_shape.set_deferred("disabled", true)
	detection_zone.set_deferred("monitoring", false)
	trigger_zone.set_deferred("monitoring", false)
	explosion_zone.set_deferred("monitoring", false)
	wander_timer.stop()
	Effects.leave_trail_behind(trail)
	_flash_glow()
	sprite.play("death")
	await sprite.animation_finished
	queue_free()


# --- glow -----------------------------------------------------------------

## A soft white halo behind the sprite that beats like a heart.
func _create_glow() -> void:
	var halo := GradientTexture2D.new()
	halo.gradient = Effects.fade_out(Color(1, 1, 1, 0.55))
	halo.fill = GradientTexture2D.FILL_RADIAL
	halo.fill_from = Vector2(0.5, 0.5)
	halo.fill_to = Vector2(1.0, 0.5)

	var add_light := CanvasItemMaterial.new()
	add_light.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	glow = Sprite2D.new()
	glow.texture = halo
	glow.material = add_light
	glow.scale = Vector2(0.6, 0.6)
	add_child(glow)
	move_child(glow, sprite.get_index())   # behind the sprite

	glow_pulse = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	glow_pulse.tween_property(glow, "scale", Vector2(0.75, 0.75), 0.35)
	glow_pulse.parallel().tween_property(glow, "modulate:a", 1.0, 0.35)
	glow_pulse.tween_property(glow, "scale", Vector2(0.55, 0.55), 0.35)
	glow_pulse.parallel().tween_property(glow, "modulate:a", 0.6, 0.35)


## The halo blows up and fades when it dies.
func _flash_glow() -> void:
	glow_pulse.kill()
	glow.modulate.a = 1.0
	var flash := create_tween().set_parallel().set_ease(Tween.EASE_OUT)
	flash.tween_property(glow, "scale", Vector2(2.2, 2.2), 0.3)
	flash.tween_property(glow, "modulate:a", 0.0, 0.4)
