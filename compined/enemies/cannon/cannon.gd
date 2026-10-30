extends StaticBody2D
## A turret. Turns its barrel toward the player while the player is inside
## the DetectionArea, and shoots a bullet at them every time FireTimer ticks.
## An armoured turret: it takes many brush hits (max_health).

const Effects := preload("res://compined/common/effects.gd")

@export var bullet_scene: PackedScene = preload("res://compined/enemies/cannon/bullet.tscn")
@export var death_sound: AudioStream
## Brush hits it can take (armoured, so the toughest enemy).
@export var max_health := 8

## Where the barrel sprite rests (it kicks back when shooting).
const BARREL_REST_X := 37.0

var target: Node2D = null
var health := 0

@onready var barrel_pivot: Node2D = $BarrelPivot
@onready var barrel_sprite: AnimatedSprite2D = $BarrelPivot/BarrelSprite
@onready var muzzle: Marker2D = $BarrelPivot/Muzzle
@onready var health_bar: Node2D = $HealthBar   # the small bar over its head
@onready var detection_area: Area2D = $DetectionArea
@onready var fire_timer: Timer = $FireTimer
@onready var shoot_sound: AudioStreamPlayer2D = $ShootSound


func _ready() -> void:
	health = max_health
	health_bar.setup(max_health)
	add_to_group("enemy")
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)
	fire_timer.timeout.connect(_on_fire_timer_timeout)
	_pop_in()


func _process(_delta: float) -> void:
	if is_instance_valid(target):
		barrel_pivot.look_at(target.global_position)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		target = body


func _on_body_exited(body: Node2D) -> void:
	if body == target:
		target = null


## The timer ticks all the time; it only shoots when the player is in range.
func _on_fire_timer_timeout() -> void:
	if is_instance_valid(target):
		_shoot()


func _shoot() -> void:
	var bullet: Node2D = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.fire(muzzle.global_position, target.global_position)
	barrel_sprite.play("fire")
	shoot_sound.play()
	_kick_back()


## Called by the brush.
func take_damage(damage: int) -> void:
	health -= damage
	health_bar.show_health(health)
	barrel_sprite.modulate = Color(3, 3, 3)
	create_tween().tween_property(barrel_sprite, "modulate", Color.WHITE, 0.15)
	if health > 0:
		return
	Effects.play_sound(self, death_sound)
	Effects.burst(self, 20, Color(1.0, 0.8, 0.3), 0.4)
	queue_free()


# --- looks -----------------------------------------------------------------

## Grows from nothing when the level starts.
func _pop_in() -> void:
	scale = Vector2.ZERO
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.35)


## The barrel jumps back and flashes white, then returns.
func _kick_back() -> void:
	barrel_sprite.position.x = BARREL_REST_X - 12.0
	barrel_sprite.modulate = Color(2.5, 2.5, 2.5)
	var tween := create_tween().set_parallel()
	tween.tween_property(barrel_sprite, "position:x", BARREL_REST_X, 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(barrel_sprite, "modulate", Color.WHITE, 0.15)
