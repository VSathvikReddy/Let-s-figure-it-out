extends Area2D
class_name Destructible

@export var health: int = 3
@export var spawn_scene: PackedScene = preload("res://enemies/bomber/bomber.tscn")

var state: int = 0:
	set(value):
		state = clampi(value, 0, health) # Keep state within valid bounds
		_update_animation()
		if state >= health:
			_despawn_and_spawn()

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	_update_animation()

func take_damage(damage: int) -> void:
	state += damage

func _update_animation() -> void:
	if not anim_sprite:
		return
		
	var anim_name = str(state)

	if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(anim_name):
		anim_sprite.play(anim_name)

func _despawn_and_spawn() -> void:
	if spawn_scene:
		var instance = spawn_scene.instantiate()
		instance.global_position = global_position
		get_tree().current_scene.add_child(instance)
	
	queue_free()
