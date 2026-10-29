extends Area2D
class_name Gem

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("collect_gem"):
		body.collect_gem(self)
		
			
	
