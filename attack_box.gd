class_name AttackBox
extends Area2D

@export_flags_2d_physics var target_mask: int = 1 << 3  # must match Hurtbox layer
@export var damage: int = 1
@export var hit_once_per_swing := true

signal change_entropy(area: Area2D, change: int)
signal hit_target()

var _already_hit: Array[Hurtbox] = []

#func _ready() -> void:
	#collision_layer = 0          # attack boxes aren't targets
	#collision_mask = target_mask
	#monitorable = false
	#monitoring = false           # off until an attack starts
	#area_entered.connect(_on_area_entered)

# Call these from your attack state / animation
#func activate() -> void:
	#_already_hit.clear()
	#set_deferred("monitoring", true)
#
#func deactivate() -> void:
	#set_deferred("monitoring", false)

func _on_area_entered(area: Area2D) -> void:
	if not area is Hurtbox:
		return

	if hit_once_per_swing and area in _already_hit:
		return
	_already_hit.append(area)

	if area.receive_damage(damage, owner):
		change_entropy.emit(area, damage)
		hit_target.emit()
		
		
		
		
		
	
	
	
	
	
	
	
		
		
		
		
		
		
		
		
		
		
		
		
		
		


@export var debug_color := Color(0.5, 0.5, 1, 0.7)   # added

# ...your existing exports, signals and variables...

func _ready() -> void:
	collision_layer = 0          # attack boxes aren't targets
	collision_mask = target_mask
	monitorable = false
	monitoring = false           # off until an attack starts
	area_entered.connect(_on_area_entered)
	# ...existing setup...
	visible = false                                # added

func activate() -> void:
	_already_hit.clear()
	set_deferred("monitoring", true)
	visible = true                                 # added

func deactivate() -> void:
	set_deferred("monitoring", false)
	visible = false                                # added

func _draw() -> void:
	for child in get_children():
		if child is CollisionShape2D and child.shape:
			draw_set_transform(child.position, child.rotation, child.scale)
			child.shape.draw(get_canvas_item(), debug_color)
		elif child is CollisionPolygon2D:
			draw_set_transform(child.position, child.rotation, child.scale)
			draw_colored_polygon(child.polygon, debug_color)
