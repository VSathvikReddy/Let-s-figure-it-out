extends Area2D
class_name Destructible

@export var health: int = 3
@export var spawn_scene: PackedScene

var state: int = 0:
	set(value):
		state = clampi(value, 0, health) # Keep state within valid bounds
		_update_sprites()
		if state >= health:
			_despawn_and_spawn()

var sprites: Array[Sprite2D] = []

func _ready() -> void:
	# Gather all Sprite2D children
	for child in get_children():
		if child is Sprite2D:
			sprites.append(child)
			
	_update_sprites()

func take_damage(damage: int) -> void:
	state += damage

func _update_sprites() -> void:
	if sprites.is_empty():
		return
		
	# Map the current state to a valid sprite index
	var sprite_index = clampi(state, 0, sprites.size() - 1)
	
	# Show only the sprite corresponding to the current state, hide the rest
	for i in range(sprites.size()):
		sprites[i].visible = (i == sprite_index)

func _despawn_and_spawn() -> void:
	if spawn_scene:
		var instance = spawn_scene.instantiate()
		instance.global_position = global_position
		get_tree().current_scene.add_child(instance)
	
	queue_free()
