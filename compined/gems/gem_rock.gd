extends Area2D
## A hidden gem. At first you see nothing; every brush hit shows the next
## picture in `pictures` (cracks, then the gem). After the last hit the rock
## is replaced by a real gem (`gem_scene`) that the player can pick up.

const Effects := preload("res://compined/common/effects.gd")

## One picture per hit, in order. Leave the first one empty to start invisible.
@export var pictures: Array[Texture2D] = []
## The gem that appears after the last hit.
@export var gem_scene: PackedScene
@export var appear_sound: AudioStream
## Size of the pictures on screen, in px.
@export var picture_size := 58.0

var hits := 0

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("destructible")   # the brush only hits enemies and destructibles
	_show_picture()


## Called by the brush.
func take_damage(damage: int) -> void:
	hits += damage
	if hits >= pictures.size():
		_turn_into_gem()
	else:
		_show_picture()


func _show_picture() -> void:
	var picture: Texture2D = pictures[hits] if hits < pictures.size() else null
	sprite.texture = picture
	if picture:
		sprite.scale = Vector2.ONE * picture_size / picture.get_width()


func _turn_into_gem() -> void:
	if gem_scene:
		var gem := gem_scene.instantiate()
		get_tree().current_scene.add_child.call_deferred(gem)
		gem.global_position = global_position
		Effects.play_sound(self, appear_sound)
	queue_free()
