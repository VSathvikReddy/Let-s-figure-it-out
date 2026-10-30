extends CanvasLayer
## The power-up slot in the top-right corner. Shows the ability the player is
## holding (its picture and name) and "Q" to use it. Empty when she holds none.
## When she picks up a new one it pops in; when she uses it, it flashes out.

@onready var slot: Control = %Slot
@onready var icon: TextureRect = %Icon
@onready var name_label: Label = %Name

var _player: Node


func _ready() -> void:
	_show(null, "")
	_connect_player.call_deferred()


func _connect_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player and _player.has_signal("power_changed"):
		_player.power_changed.connect(_on_power_changed)


## texture == null means she used it up (or holds nothing).
func _on_power_changed(texture: Texture2D, power_name: String) -> void:
	_show(texture, power_name)
	slot.pivot_offset = slot.size / 2.0
	var pop := create_tween()
	if texture:
		slot.scale = Vector2.ONE * 1.3
		slot.modulate = Color(2, 2, 2)
		pop.set_parallel().tween_property(slot, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(slot, "modulate", Color.WHITE, 0.3)
	else:
		slot.modulate = Color(2, 2, 2)
		pop.tween_property(slot, "modulate", Color.WHITE, 0.3)


func _show(texture: Texture2D, power_name: String) -> void:
	icon.texture = texture
	icon.modulate = Color.WHITE if texture else Color(1, 1, 1, 0)
	name_label.text = ("%s  [Q]" % power_name) if texture else "no power-up"
	name_label.modulate.a = 1.0 if texture else 0.5
