extends Camera2D

# Exported Variables
@export var horizontal_dead_zone: float = 30.0
@export var vertical_dead_zone: float = 30.0
@export var follow_speed: float = 120000.0

var player: CharacterBody2D
var level_bounds: ReferenceRect

func _ready() -> void:
	# Make camera ignore parent transform movement (treats coordinates as global space)
	top_level = true
	
	# Get reference to parent player
	player = get_parent() as CharacterBody2D
	
	if player:
		global_position = player.global_position
		
	# Find ReferenceRect in the loaded level scene via Group
	setup_level_bounds()

func _physics_process(delta: float) -> void:
	update_camera_position(delta)

## Finds ReferenceRect in level scene and sets Camera2D bounds
func setup_level_bounds() -> void:
	# Search scene tree for ReferenceRect node tagged in group "level_bounds"
	var bounds_nodes = get_tree().get_nodes_in_group("level_bounds")
	
	if bounds_nodes.size() > 0:
		level_bounds = bounds_nodes[0] as ReferenceRect
		var bounds_rect: Rect2 = level_bounds.get_global_rect()
		
		limit_left = int(bounds_rect.position.x)
		limit_right = int(bounds_rect.end.x)
		limit_top = int(bounds_rect.position.y)
		limit_bottom = int(bounds_rect.end.y)
		
		print("Camera limits updated from ReferenceRect:", limit_left, limit_right, limit_top, limit_bottom)

## Smooth dead-zone tracking using global coordinates
func update_camera_position(delta: float) -> void:
	if not player:
		return
		
	var player_pos = player.global_position
	var camera_pos = global_position
	var target_pos = camera_pos
	
	# Horizontal Dead Zone
	if abs(player_pos.x - camera_pos.x) > horizontal_dead_zone:
		target_pos.x = player_pos.x
		
	# Vertical Dead Zone
	if player_pos.y < camera_pos.y - vertical_dead_zone:
		target_pos.y = player_pos.y
	elif player_pos.y > camera_pos.y + vertical_dead_zone:
		target_pos.y = player_pos.y

	# Global Position Tracking (Horizontal)
	global_position.x = move_toward(global_position.x, target_pos.x, follow_speed * delta)
	
	# Global Position Tracking (Vertical - match fall velocity if falling)
	if player_pos.y > camera_pos.y:
		global_position.y = move_toward(global_position.y, target_pos.y, player.velocity.y * delta)
	else:
		global_position.y = move_toward(global_position.y, target_pos.y, follow_speed * delta)
