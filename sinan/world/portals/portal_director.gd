class_name PortalDirector
extends Node2D
## Runs every portal: the Forger tears them open (open_portal), this keeps
## them in check and rewards closing ones. Several portals can be open at once;
## each stays open far longer than the Forger's visit, pushing out enemies at a
## steady rate, then closes and drops coins. The Forger skill-tree branch
## weakens it (shorter portals, slower spawns, fewer at once).
## All spawning numbers (which enemies, how many, how long) are in
## game_data.tres; this node only places and draws the portals.
## Add one to a level (portal_director.tscn).

const Portal := preload("res://sinan/world/portals/portal.gd")
const FxLib := preload("res://sinan/fx/core/fx_lib.gd")

## Spawning rules and portal rewards.
@export var game_data: GameData = preload("res://sinan/systems/data/game_data.tres")
## The line-appears-then-tears opening (seconds).
@export var opening_time := 0.7

@export_group("Placement")
## Distance from the player (left or right) a portal opens at.
@export var distance_min := 280.0
@export var distance_max := 700.0
## Height of the portal centre above the floor.
@export var height_above_floor := 90.0
## Portals keep at least this far from each other.
@export var min_spacing := 220.0
@export var floor_search := 1400.0

@export_group("Look")
@export var portal_height := 140.0
@export var portal_width := 64.0
@export var glow_color := Color(0.7, 0.35, 1.0)

var _wait := 0.0
var _portals: Array[Node2D] = []
var _player


func _ready() -> void:
	add_to_group("portal_director")
	_wait = game_data.first_portal_delay


func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return
	for i in range(_portals.size() - 1, -1, -1):
		if not is_instance_valid(_portals[i]):
			_portals.remove_at(i)
	if not game_data.auto_open_portals:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = randf_range(game_data.portal_interval_min, game_data.portal_interval_max)
	open_portal()


## How many portals may be open at once (Sealed Sky lowers it).
func portal_limit() -> int:
	return game_data.portal_limit()


## Open one portal at `at` (global), or near the player when not given.
## Returns null if the open-portal limit is reached or no spot was found.
func open_portal(at: Variant = null) -> Node2D:
	for i in range(_portals.size() - 1, -1, -1):
		if not is_instance_valid(_portals[i]):
			_portals.remove_at(i)
	if _portals.size() >= portal_limit():
		return null
	var spot: Variant = at if at != null else _find_spot()
	if spot == null:
		return null
	var p := Portal.new()
	var duration := game_data.portal_duration()
	p.height = portal_height
	p.max_width = portal_width
	p.glow_color = glow_color
	p.cut_time = opening_time
	p.spawn_duration = duration
	p.game_data = game_data
	p.on_closed = _on_portal_closed.bind(p)
	var world := get_parent()
	p.position = FxLib.to_parent_space(world, spot)
	world.add_child(p)
	_portals.append(p)
	return p


## Called through the "portal_director" group when a new run starts.
func clear_portals() -> void:
	for p in _portals:
		if is_instance_valid(p):
			p.queue_free()
	_portals.clear()
	_wait = game_data.first_portal_delay


func _on_portal_closed(p: Node2D) -> void:
	if game_data == null or not is_instance_valid(p):
		return
	game_data.spawn_drops(get_parent(), p.global_position, &"portal")
	var bonus := int(Progress.stat(&"portal_bounty"))
	if bonus > 0:
		var field = game_data.get_pickup_field(get_parent())
		for i in bonus:
			var v := Vector2.UP.rotated(randf_range(-1.2, 1.2)) * randf_range(200.0, 450.0)
			field.add_piece(p.global_position, v, GameData.Pickup.COIN)


func _find_spot() -> Variant:
	if not is_instance_valid(_player):
		return null
	var space := get_world_2d().direct_space_state
	var pp: Vector2 = _player.global_position
	var ex: Array[RID] = []
	if _player is CollisionObject2D:
		ex.append(_player.get_rid())
	for attempt in 8:
		var side := -1.0 if randf() < 0.5 else 1.0
		var x := pp.x + side * randf_range(distance_min, distance_max)
		var from := Vector2(x, pp.y - 400.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(from, from + Vector2(0, floor_search), 1, ex))
		if hit.is_empty():
			continue
		var spot: Vector2 = hit.position + Vector2(0, -height_above_floor)
		var ok := true
		for other in _portals:
			if is_instance_valid(other) and other.global_position.distance_to(spot) < min_spacing:
				ok = false
				break
		if ok:
			return spot
	return null
