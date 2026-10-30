@tool  # also runs in the editor, so you see the bounds while you build the level
extends Node2D
## Put this on the root of every level.
##
## It builds the LEVEL BOUNDS from the painting: a rectangle exactly the size
## of the painting's root picture. Change the picture and the bounds follow
## by themselves; there is nothing to set by hand.
## The camera stays inside these bounds, and so does the player.
##
## It also SCATTERS THE HIDDEN GEMS: every time the level starts, each child
## of the "HiddenGems" node is moved to a new random spot in the painting -
## away from the edges, from each other and from where the player starts.
## Where you place them in the editor does not matter (turn it off below to
## use your own spots).

## The painting the bounds are taken from.
@export var painting: Node2D

## Colour of the bounds outline (only drawn in the editor).
@export var bounds_color := Color(1.0, 0.8, 0.2)

@export_group("Random Gems")
## On: the hidden gems get new random spots every time the level starts.
@export var random_gem_spots := true
## How far from the painting's edges a gem may be, in px.
@export var gem_edge_margin := 150.0
## Gems are at least this far apart, in px.
@export var gem_spacing := 500.0
## Gems are at least this far from where the player starts, in px.
@export var gem_distance_from_player := 350.0

const BOUNDS_NAME := "CameraBounds"

var bounds: ReferenceRect


func _ready() -> void:
	_update_bounds()
	set_process(Engine.is_editor_hint())   # _process only follows edits in the editor
	if random_gem_spots and not Engine.is_editor_hint():
		_scatter_gems()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_bounds()   # follow the painting while you edit


## Creates (once) and sizes the bounds rectangle to match the painting.
## The camera finds it through the "level_bounds" group.
func _update_bounds() -> void:
	if painting == null or not painting.has_method("world_rect"):
		return
	var rect: Rect2 = painting.world_rect()
	if rect.size == Vector2.ZERO:
		return

	if bounds == null:
		bounds = ReferenceRect.new()
		bounds.name = BOUNDS_NAME
		bounds.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bounds.editor_only = true          # outline shows in the editor, not in the game
		bounds.border_width = 4.0
		bounds.add_to_group("level_bounds")
		add_child(bounds)                  # made by code, so it is never saved into the scene
	bounds.border_color = bounds_color
	bounds.global_position = rect.position
	bounds.size = rect.size


## The world rectangle the camera and player must stay inside.
func get_bounds_rect() -> Rect2:
	return bounds.get_global_rect() if bounds else Rect2()


## Moves every hidden gem to a random spot that is far enough from the edges,
## from the other gems and from the player. If a spot that far apart cannot be
## found (a small painting, many gems), the rules are relaxed a little at a time.
func _scatter_gems() -> void:
	var gems := get_node_or_null("HiddenGems")
	var area := get_bounds_rect().grow(-gem_edge_margin)
	if gems == null or area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	var player := get_node_or_null("Player") as Node2D
	var taken: Array[Vector2] = []            # spots already used
	for gem in gems.get_children():
		var spacing := gem_spacing
		var from_player := gem_distance_from_player
		var spot := _random_point_in(area)
		for attempt in 200:
			if _far_enough(spot, taken, spacing) 					and (player == null or spot.distance_to(player.global_position) >= from_player):
				break
			spot = _random_point_in(area)
			if attempt % 40 == 39:            # hard to fit: ask for a little less room
				spacing *= 0.8
				from_player *= 0.8
		gem.global_position = spot
		taken.append(spot)


func _random_point_in(area: Rect2) -> Vector2:
	return area.position + Vector2(randf() * area.size.x, randf() * area.size.y)


func _far_enough(spot: Vector2, others: Array[Vector2], distance: float) -> bool:
	for other in others:
		if spot.distance_to(other) < distance:
			return false
	return true
