class_name CoinManager
extends Node2D

var children: Array[Node]
var collected: Dictionary[String,bool]
@export var id := "coin_manager1" 
func _ready() -> void:
	children = get_children()
	collected = SaveState.get_state(id)
	if collected == null:
		collected = _make_new_save_state(children)
	
		
	
	for child in children:
		assert(child is Area2D, "Child node of CoinManager is not an Area2D!")
		
		if collected[child.name] == false:
			child.queue_free()
			continue
		child.body_entered.connect(func(body): _on_coin_entered(body, child))

func _on_coin_entered(body: Node2D, coin_node: Area2D) -> void:
	if not body.is_in_group("player"):
		return
	
	
	coin_node.queue_free()

func _make_new_save_state(_children: Array[Node]) -> Dictionary[String,bool]:
	var out:Dictionary[String,bool]  = {}
	for child in _children:
		out[child.name] = false
	return out
