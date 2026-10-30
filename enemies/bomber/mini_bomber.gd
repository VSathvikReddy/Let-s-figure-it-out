extends CharacterBody2D

enum State { WANDER, CHASE }

@export var chase_speed: float = 260.0
@export var wander_speed: float = 90.0
@export var explosion_damage: int = 1
@export var environment_damage: int = -1
@export var explode_sound: AudioStream
@export var death_sound: AudioStream

var state: State = State.WANDER
var target_player: Node2D = null
var wander_direction: Vector2 = Vector2.ZERO
var trail: CPUParticles2D
var dead := false # true once exploding or killed; blocks everything else
var glow: Sprite2D
var glow_tween: Tween

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: CollisionShape2D = $Hitbox
@onready var detection_zone: Area2D = $DetectionZone
@onready var trigger_zone: Area2D = $TriggerZone
@onready var explosion_zone: Area2D = $ExplosionZone
@onready var wander_timer: Timer = $WanderTimer

signal state_changed(new_state: State)

func _ready() -> void:
	detection_zone.body_entered.connect(_on_detection_zone_entered)
	detection_zone.body_exited.connect(_on_detection_zone_exited)
	trigger_zone.body_entered.connect(_on_trigger_zone_entered)
	wander_timer.timeout.connect(_on_wander_timer_timeout)

	# animation_finished never fires on a looping animation, so force it off
	sprite.sprite_frames.set_animation_loop("death", false)
	sprite.play("fly")

	_create_glow()
	_create_trail()
	_pick_new_wander_direction()
	wander_timer.start()

func set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(new_state)

func _physics_process(_delta: float) -> void:
	if dead:
		return

	match state:
		State.CHASE:
			if is_instance_valid(target_player):
				velocity = global_position.direction_to(target_player.global_position) * chase_speed
			else:
				target_player = null
				set_state(State.WANDER)
				velocity = wander_direction * wander_speed
		State.WANDER:
			velocity = wander_direction * wander_speed

	move_and_slide()
	trail.emitting = velocity.length() > 5.0

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
		set_state(State.WANDER)

# --- Trigger Zone (instant explosion, no fuse) ---
func _on_trigger_zone_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_explode()

# --- Explosion: damage + particles + sound, then death animation ---
func _explode() -> void:
	if dead:
		return

	# 1. Deal damage first, while the explosion zone is still active
	for body in explosion_zone.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(explosion_damage)
	if PaintCanvas.can_paint():
		PaintCanvas.paint(explosion_zone, environment_damage)

	# 2. Effects
	_spawn_explosion()
	_play_sound_detached(explode_sound)

	# 3. Death animation, then free
	_start_death()

# --- Killed by a hit: no damage, just sound + death animation ---
func take_damage(_damage: int) -> void:
	if dead:
		return
	_play_sound_detached(death_sound)
	_start_death()

# --- Shared death sequence ---
func _start_death() -> void:
	dead = true
	velocity = Vector2.ZERO

	# Can't change physics state inside a physics callback, so defer
	hitbox.set_deferred("disabled", true)
	detection_zone.set_deferred("monitoring", false)
	trigger_zone.set_deferred("monitoring", false)
	explosion_zone.set_deferred("monitoring", false)
	wander_timer.stop()

	_release_trail()
	_flash_glow()

	sprite.play("death")
	await sprite.animation_finished
	queue_free()

func _play_sound_detached(stream: AudioStream) -> void:
	if not stream:
		return
	var sfx_player := AudioStreamPlayer2D.new()
	sfx_player.stream = stream
	get_tree().current_scene.add_child(sfx_player)
	sfx_player.global_position = global_position
	sfx_player.play()
	sfx_player.finished.connect(sfx_player.queue_free)

# --- GLOW ---
# Soft additive white halo behind the sprite. Built in code, no lighting setup needed.

func _create_glow() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 1.0, 0.55))
	g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))

	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128

	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	glow = Sprite2D.new()
	glow.texture = tex
	glow.material = mat
	glow.scale = Vector2(0.6, 0.6)
	add_child(glow)
	move_child(glow, sprite.get_index()) # draw behind the sprite

	# Gentle heartbeat pulse; it flickers faster than it breathes so it feels volatile
	glow_tween = create_tween().set_loops()
	glow_tween.set_trans(Tween.TRANS_SINE)
	glow_tween.tween_property(glow, "scale", Vector2(0.75, 0.75), 0.35)
	glow_tween.parallel().tween_property(glow, "modulate:a", 1.0, 0.35)
	glow_tween.tween_property(glow, "scale", Vector2(0.55, 0.55), 0.35)
	glow_tween.parallel().tween_property(glow, "modulate:a", 0.6, 0.35)

func _flash_glow() -> void:
	if glow_tween:
		glow_tween.kill()
	glow.modulate.a = 1.0
	var t := create_tween().set_parallel()
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(glow, "scale", Vector2(2.2, 2.2), 0.3)
	t.tween_property(glow, "modulate:a", 0.0, 0.4)

# --- PARTICLE EFFECTS ---

func _create_trail() -> void:
	trail = CPUParticles2D.new()
	trail.local_coords = false
	trail.emitting = false
	trail.amount = 12
	trail.lifetime = 0.3
	trail.spread = 180.0
	trail.gravity = Vector2.ZERO
	trail.initial_velocity_min = 5.0
	trail.initial_velocity_max = 20.0
	trail.scale_amount_min = 1.5
	trail.scale_amount_max = 3.0
	trail.color_ramp = _fade(Color(0.3, 0.9, 0.5))
	trail.z_index = -1
	add_child(trail)

func _release_trail() -> void:
	trail.emitting = false
	trail.reparent(get_tree().current_scene)
	get_tree().create_timer(trail.lifetime).timeout.connect(trail.queue_free)

func _spawn_explosion() -> void:
	_spawn_burst(24, 0.4, 100.0, 220.0, 3.0, 6.0, Color(0.4, 1.0, 0.5))
	_spawn_burst(8, 0.7, 30.0, 70.0, 6.0, 10.0, Color(0.15, 0.3, 0.25, 0.8))

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
