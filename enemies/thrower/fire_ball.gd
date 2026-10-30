extends Area2D
## Fireball spat by the Thrower (baby dragon). Flies to where the player was,
## then bursts: splash damage to the player inside the SplashZone and a mark on
## the painting (PaintCanvas), with fire and smoke particles.
## Bursts early if it touches the player or a wall on the way.

@export var speed: float = 380.0
@export var splash_damage: int = 1
## What the burst does to the painting (same as the old explosion's environment_damage).
@export var environment_damage: int = -3
## Seconds before it bursts on its own if it never reaches the target.
@export var max_life: float = 2.5

var _dir := Vector2.RIGHT
var _target := Vector2.ZERO
var _life := 0.0
var _done := false
var trail: CPUParticles2D

@onready var splash_zone: Area2D = $SplashZone


## Called by the thrower right after adding it to the scene.
func launch(target: Vector2) -> void:
	_target = target
	_dir = global_position.direction_to(target)
	rotation = _dir.angle()


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	trail = CPUParticles2D.new()
	trail.local_coords = false
	trail.amount = 30
	trail.lifetime = 0.35
	trail.spread = 25.0
	trail.direction = Vector2.LEFT
	trail.gravity = Vector2.ZERO
	trail.initial_velocity_min = 20.0
	trail.initial_velocity_max = 60.0
	trail.scale_amount_min = 3.0
	trail.scale_amount_max = 6.0
	trail.color_ramp = _fade(Color(1.0, 0.6, 0.1))
	add_child(trail)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_life += delta
	var step := speed * delta
	if global_position.distance_to(_target) <= step or _life >= max_life:
		global_position = _target if _life < max_life else global_position
		_burst()
		return
	global_position += _dir * step


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemy"):
		return  # flies past other enemies (and the dragon itself)
	_burst()


## Splash: hurt the player in the SplashZone, mark the painting, then vanish.
## The overlap check needs one physics step after moving, so it waits for it.
func _burst() -> void:
	if _done:
		return
	_done = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	for body in splash_zone.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(splash_damage)
	if PaintCanvas.can_paint():
		PaintCanvas.paint(splash_zone, environment_damage)
	_spawn_burst(30, 0.45, 100.0, 240.0, 4.0, 8.0, Color(1.0, 0.6, 0.1))
	_spawn_burst(12, 0.8, 20.0, 80.0, 8.0, 12.0, Color(0.25, 0.25, 0.25, 0.8))
	trail.emitting = false
	trail.reparent(get_tree().current_scene)
	get_tree().create_timer(trail.lifetime).timeout.connect(trail.queue_free)
	queue_free()


func _spawn_burst(count: int, life: float, vel_min: float, vel_max: float,
		size_min: float, size_max: float, color: Color) -> void:
	var burst := CPUParticles2D.new()
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = count
	burst.lifetime = life
	burst.spread = 180.0
	burst.gravity = Vector2.ZERO
	burst.initial_velocity_min = vel_min
	burst.initial_velocity_max = vel_max
	burst.scale_amount_min = size_min
	burst.scale_amount_max = size_max
	burst.color_ramp = _fade(color)
	get_tree().current_scene.add_child(burst)
	burst.global_position = global_position
	burst.emitting = true
	burst.finished.connect(burst.queue_free)


func _fade(c: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	return g
