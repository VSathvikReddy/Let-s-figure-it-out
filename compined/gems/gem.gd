extends Area2D
## A gem the player can pick up. It floats, glows and sparkles.
## When the player touches it: a burst of particles, a sound, and the
## player's collect_gem() is called (the player removes the gem).

const Effects := preload("res://compined/common/effects.gd")

@export var picture: Texture2D
@export var glow_color := Color(0.3, 0.55, 1.0)
@export var sparkle_color := Color(0.8, 0.93, 1.0)
@export var pickup_sound: AudioStream

## How long one float-up-and-down takes, in seconds.
const FLOAT_TIME := 2.4
const GEM_SIZE := 56.0     # px on screen

@onready var gem_sprite: Sprite2D = $Gem
@onready var glow: Sprite2D = $Glow
@onready var sparkles: Array[Node] = $Sparkles.get_children()

var _collected := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	gem_sprite.texture = picture
	if picture:
		gem_sprite.scale = Vector2.ONE * GEM_SIZE / picture.get_width()
	glow.modulate = Color(glow_color, 0.1)
	for sparkle in sparkles:
		sparkle.modulate = Color(sparkle_color, 0.7)
		sparkle.scale = Vector2.ZERO
	_start_float()
	_start_glow()
	for i in sparkles.size():
		_start_sparkle(sparkles[i], i * FLOAT_TIME / sparkles.size())


func _on_body_entered(body: Node2D) -> void:
	if _collected or not body.has_method("collect_gem"):
		return
	_collected = true
	Effects.burst(self, 15, Color.WHITE, 0.4, 80.0, 150.0)
	Effects.play_sound(self, pickup_sound)
	body.collect_gem(self)


# --- looks -----------------------------------------------------------------

## Gently floats up and down and wobbles.
func _start_float() -> void:
	var base_scale := gem_sprite.scale
	var tween := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	tween.tween_property(gem_sprite, "position:y", -2.5, FLOAT_TIME / 2)
	tween.parallel().tween_property(gem_sprite, "scale", base_scale * 1.04, FLOAT_TIME / 2)
	tween.parallel().tween_property(gem_sprite, "rotation", 0.05, FLOAT_TIME / 4)
	tween.tween_property(gem_sprite, "position:y", 0.0, FLOAT_TIME / 2)
	tween.parallel().tween_property(gem_sprite, "scale", base_scale, FLOAT_TIME / 2)
	tween.parallel().tween_property(gem_sprite, "rotation", -0.05, FLOAT_TIME / 4)


## The soft light behind the gem pulses.
func _start_glow() -> void:
	var tween := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	tween.tween_property(glow, "modulate:a", 0.24, FLOAT_TIME / 2)
	tween.parallel().tween_property(glow, "scale", Vector2.ONE * 0.64, FLOAT_TIME / 2)
	tween.tween_property(glow, "modulate:a", 0.1, FLOAT_TIME / 2)
	tween.parallel().tween_property(glow, "scale", Vector2.ONE * 0.55, FLOAT_TIME / 2)


## A little star pops up, spins and disappears, once per float.
func _start_sparkle(sparkle: Node2D, delay: float) -> void:
	var tween := create_tween().set_loops()
	tween.tween_interval(delay)
	tween.tween_property(sparkle, "scale", Vector2.ONE * 0.25, 0.3)
	tween.parallel().tween_property(sparkle, "rotation", 0.5, 0.3).as_relative()
	tween.tween_property(sparkle, "scale", Vector2.ZERO, 0.5)
	tween.parallel().tween_property(sparkle, "rotation", 0.5, 0.5).as_relative()
	tween.tween_interval(FLOAT_TIME - delay - 0.8)
