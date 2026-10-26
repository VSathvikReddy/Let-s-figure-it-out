extends Node2D

@export var turret_scene: PackedScene = preload("res://game_objects/turret/Turret.tscn")
## Radius around this spawner node where turrets can randomly appear
@export var spawn_area_radius: float = 400.0
## Minimum distance away from the player so a turret doesn't spawn directly on top of them
@export var min_distance_from_player: float = 120.0
@export var max_active_turrets: int = 5
@export var spawn_interval: float = 3.0
@export var spawn_on_ready: int = 2

@onready var spawn_timer: Timer = $SpawnTimer

func _ready() -> void:
	# Spawn initial batch of turrets
	for i in range(spawn_on_ready):
		spawn_random_turret()
		
	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	spawn_timer.start()

func _on_spawn_timer_timeout() -> void:
	var current_turrets := get_tree().get_nodes_in_group("turret").size()
	if current_turrets < max_active_turrets:
		spawn_random_turret()

func spawn_random_turret() -> void:
	if not turret_scene:
		return
		
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var chosen_pos := global_position
	
	# Pick a random point inside the circle (using sqrt for uniform distribution)
	for attempt in range(10):
		var angle := randf() * TAU
		var dist := sqrt(randf()) * spawn_area_radius
		var candidate_pos := global_position + Vector2(cos(angle), sin(angle)) * dist
		
		if not is_instance_valid(player) or candidate_pos.distance_to(player.global_position) >= min_distance_from_player:
			chosen_pos = candidate_pos
			break
			
	var turret := turret_scene.instantiate() as Node2D
	get_tree().current_scene.call_deferred("add_child", turret)
	turret.global_position = chosen_pos
