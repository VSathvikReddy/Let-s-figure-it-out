extends Area2D
## Fireball spat by the bat. Flies to where the player was, then bursts:
## hurts the player inside the SplashZone and breaks the painting there.
## Bursts early if it touches the player or anything else on the way.

const Effects := preload("res://compined/common/effects.gd")

@export var speed := 380.0
@export var splash_damage := 1
@export var painting_damage := 3
@export var max_life := 2.5          ## seconds before it bursts on its own

var _direction := Vector2.RIGHT
var _target := Vector2.ZERO
var _age := 0.0
var _burst_started := false
var trail: CPUParticles2D

@onready var splash_zone: Area2D = $SplashZone


## Called by the bat right after adding the fireball to the level.
func launch(target: Vector2) -> void:
	_target = target
	_direction = global_position.direction_to(target)
	rotation = _direction.angle()


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	trail = Effects.make_trail(self, Color(1.0, 0.6, 0.1), 30, 0.35)
	trail.emitting = true


func _physics_process(delta: float) -> void:
	if _burst_started:
		return
	_age += delta
	var step := speed * delta
	if global_position.distance_to(_target) <= step:
		global_position = _target   # arrived
		_burst()
	elif _age >= max_life:
		_burst()                    # never arrived
	else:
		global_position += _direction * step


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("enemy"):   # flies past enemies (and the bat itself)
		_burst()


func _burst() -> void:
	if _burst_started:
		return
	_burst_started = true
	# the SplashZone only knows what it overlaps after a physics step
	await get_tree().physics_frame
	await get_tree().physics_frame
	for body in splash_zone.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(splash_damage)
	Effects.paint(splash_zone, -painting_damage)
	Effects.fire_explosion(self, false)
	Effects.leave_trail_behind(trail)
	queue_free()
