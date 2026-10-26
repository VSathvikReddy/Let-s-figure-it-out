extends Area2D

# Signal emitted when the bullet hits the player
signal turret_bullet_hit_player(damage: int)

@export var speed: float = 450.0
@export var damage: int = 10
@export var max_lifetime: float = 5.0

var direction: Vector2 = Vector2.RIGHT

func _ready() -> void:
	# Connect collision and screen-exit cleanup signals automatically
	body_entered.connect(_on_body_entered)
	$VisibleOnScreenNotifier2D.screen_exited.connect(queue_free)
	
	# Destroy bullet after max_lifetime if it stays on screen without hitting anything
	get_tree().create_timer(max_lifetime).timeout.connect(queue_free)

# Locks in the straight-line direction toward the player's position AT FIRE TIME
func setup(start_pos: Vector2, target_initial_pos: Vector2) -> void:
	global_position = start_pos
	direction = (target_initial_pos - start_pos).normalized()
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		# Emit the signal so your player health function receives it
		turret_bullet_hit_player.emit(damage)
		_spawn_hit_effect(Color(1.0, 0.2, 0.2)) # Red burst on player hit
		queue_free()
	elif not body.is_in_group("turret"):
		# Hit a platform/wall
		_spawn_hit_effect(Color(1.0, 0.8, 0.2)) # Yellow sparks on wall hit
		queue_free()

func _spawn_hit_effect(effect_color: Color) -> void:
	var burst := CPUParticles2D.new()
	burst.global_position = global_position
	burst.emitting = true
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 16
	burst.lifetime = 0.3
	burst.spread = 180.0
	burst.gravity = Vector2.ZERO
	burst.initial_velocity_min = 60.0
	burst.initial_velocity_max = 140.0
	burst.scale_amount_min = 3.0
	burst.scale_amount_max = 5.0
	burst.color = effect_color
	
	get_tree().current_scene.add_child(burst)
	burst.finished.connect(burst.queue_free)
