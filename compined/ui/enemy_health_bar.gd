extends Node2D
## A small health bar that floats above an enemy, in the same style as the
## player's: a red bar, and a light "damage" bar that catches up after a hit.
##
## Add enemy_health_bar.tscn as a child called "HealthBar" and move it above
## the enemy's head. The enemy calls:
##     health_bar.setup(max_health)      once, in _ready
##     health_bar.show_health(health)    every time it is hit

## Hide the bar until the enemy is first hit.
@export var hide_when_full := false
@export var trail_delay := 0.25
@export var trail_duration := 0.35

@onready var health_bar: ProgressBar = $HealthBar
@onready var trail_bar: ProgressBar = $TrailBar

var _trail_tween: Tween


func setup(max_health: float) -> void:
	health_bar.max_value = max_health
	trail_bar.max_value = max_health
	health_bar.value = max_health
	trail_bar.value = max_health
	visible = not hide_when_full


func show_health(current: float) -> void:
	visible = true
	health_bar.value = maxf(current, 0.0)
	if _trail_tween:
		_trail_tween.kill()
	_trail_tween = create_tween()
	_trail_tween.tween_interval(trail_delay)
	_trail_tween.tween_property(trail_bar, "value", health_bar.value, trail_duration)
