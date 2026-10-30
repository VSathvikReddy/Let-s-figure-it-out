extends StaticBody2D

@export_group("Turret Settings")
@export var bullet_scene: PackedScene = preload("res://enemies/cannon/bullet.tscn")


@onready var barrel_pivot: Node2D = $BarrelPivot
@onready var barrel_sprite: AnimatedSprite2D = $BarrelPivot/BarrelSprite
@onready var muzzle: Marker2D = $BarrelPivot/Muzzle
@onready var detection_area: Area2D = $DetectionArea
@onready var fire_timer: Timer = $FireTimer
@onready var shoot_sound: AudioStreamPlayer2D = $TurretShoot

var target_player: Node2D = null


func _ready() -> void:
	# The clock runs forever on its own. It never starts or stops with the player.
	fire_timer.timeout.connect(_on_fire_timer_timeout)
	fire_timer.start()

	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)

	_play_spawn_effect()


func _process(_delta: float) -> void:
	if is_instance_valid(target_player):
		barrel_pivot.look_at(target_player.global_position)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		target_player = body


func _on_body_exited(body: Node2D) -> void:
	if body == target_player:
		target_player = null


# Every tick of the clock: shoot only if the player is in range.
func _on_fire_timer_timeout() -> void:
	if is_instance_valid(target_player):
		_fire_bullet()


func _fire_bullet() -> void:
	barrel_sprite.play("Cannon_fire")

	var bullet: Area2D = bullet_scene.instantiate()
	get_tree().current_scene.add_child.call_deferred(bullet)
	# Start at the muzzle, aim at where the player is right now
	bullet.setup(muzzle.global_position, target_player.global_position)
	shoot_sound.play()
	_play_recoil_effect()


# --- VISUAL EFFECTS ---

func _play_spawn_effect() -> void:
	scale = Vector2.ZERO
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.35)


func _play_recoil_effect() -> void:
	# Kick barrel backward and flash bright white
	barrel_sprite.position.x = 8.0
	barrel_sprite.modulate = Color(2.5, 2.5, 2.5)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(barrel_sprite, "position:x", 20.0, 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(barrel_sprite, "modulate", Color.WHITE, 0.15)

func take_damage(damage:int) ->void:
	barrel_sprite.modulate = Color(5.0, 5.0, 5.0, 1.0) # Flash bright white
	queue_free()
