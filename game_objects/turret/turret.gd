extends StaticBody2D

@export_group("Turret Settings")
@export var bullet_scene: PackedScene = preload("res://game_objects/turret/Bullet.tscn")
## Shots fired per second (e.g., 1.0 = 1 shot/sec, 2.0 = 2 shots/sec, 0.5 = 1 shot every 2 sec)
@export var fire_rate: float = 1.0:
	set(value):
		fire_rate = max(0.05, value)
		if is_node_ready() and fire_timer:
			fire_timer.wait_time = 1.0 / fire_rate

## How close the player must be (in pixels) for the turret to start firing
@export var detection_radius: float = 350.0
## Name of the function on your Player script to connect the bullet's turret_bullet_hit_player signal to
@export var player_damage_Method: StringName = &"_on_bullet_hit"
@export var show_range_circle: bool = true

@onready var barrel_pivot: Node2D = $BarrelPivot
@onready var barrel_sprite: Sprite2D = $BarrelPivot/BarrelSprite
@onready var muzzle: Marker2D = $BarrelPivot/Muzzle
@onready var detection_area: Area2D = $DetectionArea
@onready var detection_shape: CollisionShape2D = $DetectionArea/DetectionShape
@onready var fire_timer: Timer = $FireTimer

var target_player: Node2D = null

func _ready() -> void:
	# Apply detection radius to the Area2D's CircleShape2D
	var circle := CircleShape2D.new()
	circle.radius = detection_radius
	detection_shape.shape = circle
	
	# Configure FireTimer based on fire_rate
	fire_timer.wait_time = 1.0 / max(0.05, fire_rate)
	fire_timer.one_shot = false
	
	# Connect signals
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)
	fire_timer.timeout.connect(_on_fire_timer_timeout)
	
	# Spawn pop-in effect
	_play_spawn_effect()
	queue_redraw()

func _process(_delta: float) -> void:
	# Stationary turret: only rotates its barrel toward the player while in range
	if is_instance_valid(target_player):
		barrel_pivot.look_at(target_player.global_position)

func _on_detection_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		target_player = body
		_fire_bullet() # Fire immediately on spotting player
		fire_timer.start()
		queue_redraw()

func _on_detection_area_body_exited(body: Node2D) -> void:
	if body == target_player:
		target_player = null
		fire_timer.stop()
		queue_redraw()

func _on_fire_timer_timeout() -> void:
	if is_instance_valid(target_player):
		_fire_bullet()

func _fire_bullet() -> void:
	if not bullet_scene or not is_instance_valid(target_player):
		return
		
	var bullet: Area2D = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	
	# Pass muzzle start position and the player's CURRENT position (locked at fire time)
	bullet.setup(muzzle.global_position, target_player.global_position)
	
	# Connect the bullet's turret_bullet_hit_player signal directly to your player's health/damage function
	if target_player.has_method(player_damage_Method):
		bullet.turret_bullet_hit_player.connect(Callable(target_player, player_damage_Method))
		
	_play_recoil_effect()

# --- VISUAL EFFECTS ---

func _play_spawn_effect() -> void:
	scale = Vector2.ZERO
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.35)

func _play_recoil_effect() -> void:
	# Kick barrel backward and flash bright white
	barrel_sprite.position.x = 8.0
	barrel_sprite.modulate = Color(2.5, 2.5, 2.5) # Glow flash
	
	var tween := create_tween().set_parallel(true)
	tween.tween_property(barrel_sprite, "position:x", 20.0, 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(barrel_sprite, "modulate", Color.WHITE, 0.15)

func _draw() -> void:
	if show_range_circle:
		var ring_color := Color(1, 0.2, 0.2, 0.25) if target_player else Color(1, 1, 1, 0.1)
		draw_arc(Vector2.ZERO, detection_radius, 0.0, TAU, 64, ring_color, 2.0)
