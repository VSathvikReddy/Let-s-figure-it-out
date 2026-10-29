class_name PaintBrush
extends Weapon

@export var cooldown := 0.5          # measured from the start of the attack
@export var attack_duration := 0.3  # how long the AttackBox stays on

@onready var attack_box: AttackBox = $AttackBox

var _can_attack := true

func start_attack() -> void:

	if not _can_attack:
		return
	_can_attack = false

	attack_box.activate()
	get_tree().create_timer(attack_duration).timeout.connect(attack_box.deactivate)
	get_tree().create_timer(cooldown).timeout.connect(
		func():
			_can_attack = true
	)
