class_name LightBudget
extends Node
## Enemy lights cost real rendering time when a crowd is on screen (every lit
## sprite is shaded once per light). Only the MAX_LIGHTS enemies nearest the
## middle of the screen keep their lights on; the others switch theirs off
## until they are among the nearest again. With a normal number of enemies
## every light stays on. Created automatically the first time an enemy asks
## View.cull(), so levels need no setup.

const MAX_LIGHTS := 14
## Seconds between re-checks (sorting the crowd every frame is not needed).
const INTERVAL := 0.25

static var _node: Node
var _t := 0.0


static func ensure(from: Node) -> void:
	if is_instance_valid(_node) or not from.is_inside_tree():
		return
	_node = LightBudget.new()
	_node.name = "LightBudget"
	var tree := from.get_tree()
	var host: Node = tree.current_scene if tree.current_scene else tree.root
	host.add_child.call_deferred(_node)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = INTERVAL
	var centre := View.rect(self).get_center()
	var list := []
	for e in get_tree().get_nodes_in_group("enemies"):
		var lights: Array = e.get_meta("_lights") if e.has_meta("_lights") else _collect(e)
		if not lights.is_empty():
			list.append([(e as Node2D).global_position.distance_squared_to(centre), lights])
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in list.size():
		var on := i < MAX_LIGHTS
		for l in list[i][1]:
			if is_instance_valid(l) and l.enabled != on:
				l.enabled = on


## An enemy's own lights (found once, then remembered on it).
func _collect(e: Node) -> Array:
	var lights: Array = e.find_children("*", "PointLight2D", true, false)
	e.set_meta("_lights", lights)
	return lights
