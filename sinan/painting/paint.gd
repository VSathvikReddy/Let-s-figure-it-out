class_name Paint
## One entry point for everything that touches the painting. Every weapon and
## enemy calls Paint.hit() instead of poking the layers directly, so the kind
## of hit is known (for sounds / effects) and clarity is tracked in one place.
##
##   Paint.hit(self, layer, local, radius, strength, Paint.Kind.SCRATCH, &"bird")
##
## strength: + damages (1 = one detail level at the centre), - restores.
## Listeners in the "paint_listeners" group get on_paint_event(event: Dictionary)
## with keys: layer, local, radius, strength, kind, source.

enum Kind { SMUDGE, RESTORE, SCRATCH, BURN }


## A hit on one painting layer at a layer-local point.
static func hit(from: Node, layer: Node, local: Vector2, radius: float, strength: float,
		kind := Kind.SMUDGE, source := &"") -> void:
	if from == null or not from.is_inside_tree() or not is_instance_valid(layer):
		return
	var tree := from.get_tree()
	tree.call_group("painting", "on_paint_hit", layer, local, radius, strength)
	tree.call_group("paint_listeners", "on_paint_event", {
		"layer": layer, "local": local, "radius": radius, "strength": strength,
		"kind": kind, "source": source,
	})


## A hit on every layer behind a world position (e.g. a burst in the studio).
static func hit_world(from: Node, world_pos: Vector2, radius: float, strength: float,
		kind := Kind.SMUDGE, source := &"") -> void:
	if from == null or not from.is_inside_tree():
		return
	var tree := from.get_tree()
	tree.call_group("painting", "on_paint_hit_world", world_pos, radius, strength)
	tree.call_group("paint_listeners", "on_paint_event", {
		"layer": null, "world": world_pos, "radius": radius, "strength": strength,
		"kind": kind, "source": source,
	})


## Painting clarity 0..1 averaged over every layer (1 = fully restored).
static func clarity(from: Node) -> float:
	if from == null or not from.is_inside_tree():
		return 0.0
	var layers := from.get_tree().get_nodes_in_group("painting")
	if layers.is_empty():
		return 0.0
	var total := 0.0
	for l in layers:
		total += 1.0 - float(l.call("mean"))
	return total / layers.size()
