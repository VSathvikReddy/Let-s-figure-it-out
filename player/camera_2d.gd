extends Camera2D

# Exported Smoothness Controls
@export_range(1.0, 30.0) var horizontal_smoothness: float = 10.0
@export_range(1.0, 30.0) var vertical_smoothness: float = 10.0
@export_range(1.0, 30.0) var fall_smoothness: float = 16.0

# Dead Zones
@export var horizontal_dead_zone: float = 30.0
@export var vertical_dead_zone: float = 30.0

# Pixel Art Crispness
@export var snap_to_pixels: bool = true

var player: CharacterBody2D
var level_bounds: ReferenceRect
var exact_position: Vector2

func _ready() -> void:
	top_level = true
	player = get_parent() as CharacterBody2D
	
	if player:
		exact_position = player.global_position
		global_position = exact_position
		
	setup_level_bounds()

func _process(delta: float) -> void:
	update_camera_position(delta)

func setup_level_bounds() -> void:
	var bounds_nodes = get_tree().get_nodes_in_group("level_bounds")
	if bounds_nodes.size() > 0:
		level_bounds = bounds_nodes[0] as ReferenceRect
		var bounds_rect: Rect2 = level_bounds.get_global_rect()
		
		limit_left = int(bounds_rect.position.x)
		limit_right = int(bounds_rect.end.x)
		limit_top = int(bounds_rect.position.y)
		limit_bottom = int(bounds_rect.end.y)

func update_camera_position(delta: float) -> void:
	if not player:
		return
		
	# Use player's interpolated visual position rather than raw physics position
	var player_pos = player.global_position
	var target_pos = exact_position
	
	# 1. Calculate Edge-Anchored Targets (Prevents sudden deadzone snaps)
	var diff_x = player_pos.x - exact_position.x
	if abs(diff_x) > horizontal_dead_zone:
		target_pos.x = player_pos.x - (sign(diff_x) * horizontal_dead_zone)
		
	var diff_y = player_pos.y - exact_position.y
	if abs(diff_y) > vertical_dead_zone:
		target_pos.y = player_pos.y - (sign(diff_y) * vertical_dead_zone)

	# 2. Frame-rate independent decay weights
	var x_weight = 1.0 - exp(-horizontal_smoothness * delta)
	var active_y_smooth = fall_smoothness if player_pos.y > exact_position.y else vertical_smoothness
	var y_weight = 1.0 - exp(-active_y_smooth * delta)

	# 3. Smooth sub-pixel tracking variable
	exact_position.x = lerp(exact_position.x, target_pos.x, x_weight)
	exact_position.y = lerp(exact_position.y, target_pos.y, y_weight)

	# 4. Render Position (Optionally rounded to avoid pixel distortion)
	if snap_to_pixels:
		global_position = exact_position.round()
	else:
		global_position = exact_position
