extends "res://compined/level.gd"
## The custom level: the same as every other level (bounds from the painting,
## player, gems, enemies, win screen), but its painting is the one the player
## made in the level selector, so its size is only known when it starts.
## Because of that, every gem, enemy and the player are moved inside the
## painting if they would be outside it.
##
## No pictures made yet? Then it goes straight back to the level selector.

## How far from the painting's edge things are kept, in px.
@export var edge_margin := 120.0


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	if painting == null or not painting.has_pictures():
		Levels.go_to_level_select.call_deferred(get_tree())
		return
	_keep_inside_painting()


func _keep_inside_painting() -> void:
	var inside := get_bounds_rect().grow(-edge_margin)
	var things: Array[Node] = [$Player]
	things.append_array($HiddenGems.get_children())
	things.append_array($Enemies.get_children())
	for thing in things:
		thing.global_position = thing.global_position.clamp(inside.position, inside.end)
