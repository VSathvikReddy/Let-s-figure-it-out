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
## amount 1.0 = one detail level. Only the front-most layer at that spot changes.

static var current: Painting  # the painting in the scene, so anyone can reach it


func _enter_tree() -> void:
	current = self


static func paint(area: Area2D, amount: float, at := Vector2.INF) -> void:
	if current == null:
		return
	var offset := Vector2.ZERO
	if at != Vector2.INF:
		offset = at - area.global_position
	var layer := current.layer_at(area.global_position + offset)
	for child in area.get_children():
		if child is CollisionShape2D:
			layer.stamp(child, offset, amount)


## The front-most layer that has paint at this point.
## Children further down the list are drawn in front, so check them first.
func layer_at(point: Vector2) -> Parallax2D:
	var layers: Array[Parallax2D] = []
	for child in get_children():
		if child is Parallax2D:
			layers.append(child)
	for i in range(layers.size() - 1, 0, -1):
		if layers[i].has_paint_at(point):
			return layers[i]
	return layers[0]  # the back layer (sky) catches everything else
