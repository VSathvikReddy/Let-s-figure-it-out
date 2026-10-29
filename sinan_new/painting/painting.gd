class_name Painting
extends Node2D
## The painting. Put this on the node that holds the layers (Parallax2Ds).
##
## Anything in the game can change the painting with ONE line,
## passing its own Area2D:
##
##     Painting.paint($MyArea, 1.0)            # break the painting under the area
##     Painting.paint($MyArea, -1.0)           # repair it
##     Painting.paint($MyArea, 1.0, point)     # same, but with the area moved to `point`
##
## amount 1.0 = one detail level. Every layer under the shape changes.
## The area's shapes can be CollisionShape2D (circle, rectangle) or CollisionPolygon2D.

static var current: Painting  # the painting in the scene, so anyone can reach it


func _enter_tree() -> void:
	current = self


static func paint(area: Area2D, amount: float, at := Vector2.INF) -> void:
	if current == null:
		return
	var offset := Vector2.ZERO
	if at != Vector2.INF:
		offset = at - area.global_position
	for layer in current.get_children():
		if not layer is Parallax2D:
			continue
		for child in area.get_children():
			if (child is CollisionShape2D or child is CollisionPolygon2D) and not child.disabled:
				layer.stamp(child, offset, amount)
