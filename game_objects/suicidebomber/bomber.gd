extends CharacterBody2D

@export var chase_speed: float = 120.0
@export var wander_speed: float = 40.0
@export var explosion_damage: int = 20

var target_player: Node2D = null
var wander_direction: Vector2 = Vector2.ZERO

@onready var detection_zone: Area2D = $DetectionZone
@onready var contact_zone: Area2D = $ContactZone
@onready var wander_timer: Timer = $WanderTimer

func _ready() -> void:
	# Wire up all signals via code
	detection_zone.body_entered.connect(_on_detection_zone_entered)
	detection_zone.body_exited.connect(_on_detection_zone_exited)
	contact_zone.body_entered.connect(_on_contact_zone_entered)
	wander_timer.timeout.connect(_on_wander_timer_timeout)
	
	# Initialize wandering state
	_pick_new_wander_direction()
	wander_timer.start()

func _physics_process(_delta: float) -> void:
	if target_player:
		# Chase logic
		var direction = global_position.direction_to(target_player.global_position)
		velocity = direction * chase_speed
	else:
		# Wander logic
		velocity = wander_direction * wander_speed
		
	move_and_slide()

func _pick_new_wander_direction() -> void:
	# Pick a random 2D vector for idle movement
	wander_direction = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()

func _on_wander_timer_timeout() -> void:
	# Change direction every time the timer ticks, if not chasing
	if not target_player:
		_pick_new_wander_direction()

func _on_detection_zone_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		target_player = body

func _on_detection_zone_exited(body: Node2D) -> void:
	if body == target_player:
		target_player = null
		_pick_new_wander_direction()

func _on_contact_zone_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		_explode(body)

func _explode(player_node: Node2D) -> void:
	# 1. Apply damage to the player. 
	# Make sure your player script has a take_damage() function!
	if player_node.has_method("take_damage"):
		player_node.take_damage(explosion_damage)
		
	# 2. (Optional) Instantiate an explosion particle effect here
	# var effect = explosion_scene.instantiate()
	# get_parent().add_child(effect)
	# effect.global_position = global_position
	
	# 3. Destroy this enemy
	queue_free()
