class_name Hurtbox
extends Area2D

@export_flags_2d_physics var hurtbox_layer: int = 1 << 3  # editor "Layer 4"

# Optional: brief invincibility after being hit (0 = off)
@export var iframes: float = 0.0

signal damaged(amount: int, source: Node)

var _invincible := false

func _ready() -> void:
	collision_layer = hurtbox_layer
	collision_mask = 0
	monitoring = false   # hurtboxes never scan; the AttackBox does the detecting
	monitorable = true   # but they must be detectable

func receive_damage(amount: int, source: Node = null) -> bool:
	if _invincible:
		return false
	damaged.emit(amount, source)
	if iframes > 0.0:
		_invincible = true
		get_tree().create_timer(iframes).timeout.connect(func(): _invincible = false)
	return true
