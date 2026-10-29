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

## Restoring done since the last take_restored(), as a fraction of ONE layer's
## fresh damage, summed over layers (the layers add to it). The RunManager turns
## it into Entropy.
static var _restored_gross := 0.0


## Called by the painting layers whenever restoring removes damage.
static func add_restored(amount: float) -> void:
	_restored_gross += amount


## Restoring done since the last call, as a fraction of the whole painting
## (0.01 = 1%), and start counting again.
static func take_restored(from: Node) -> float:
	var layers := from.get_tree().get_nodes_in_group("painting").size() if from and from.is_inside_tree() else 0
	var r := _restored_gross / maxf(layers, 1)
	_restored_gross = 0.0
	return r


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


## How much of the painting the player has restored, 0..1 averaged over every
## layer (0 = as a fresh game starts, 1 = the full painting everywhere).
## Runs, milestones and the run summary use this.
static func restored(from: Node) -> float:
	if from == null or not from.is_inside_tree():
		return 0.0
	var layers := from.get_tree().get_nodes_in_group("painting")
	if layers.is_empty():
		return 0.0
	var total := 0.0
	for l in layers:
		total += float(l.call("restored"))
	return total / layers.size()


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
