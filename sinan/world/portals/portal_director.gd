class_name PortalDirector
extends Node2D
## Runs every portal: the Forger tears them open (open_portal), this keeps
## them in check and rewards closing ones. Several portals can be open at once;
## each stays open far longer than the Forger's visit, pushing out enemies at a
## steady rate, then closes and drops coins. The Forger skill-tree branch
## weakens it (shorter portals, slower spawns, fewer at once).
## Add one to a level (portal_director.tscn).

const Portal := preload("res://sinan/world/portals/portal.gd")
const FxLib := preload("res://sinan/fx/core/fx_lib.gd")

@export var enemy_scenes: Array[PackedScene] = []

@export_group("Timing")
## Off (default): only the Forger opens portals. On: portals also open by themselves.
@export var auto_open := false
## Seconds before the first portal.
@export var first_portal_delay := 3.0
## Seconds between new portals (random in this range).
@export var portal_interval_min := 10.0
@export var portal_interval_max := 18.0
## How long each portal stays open (random in this range).
@export var portal_duration_min := 30.0
@export var portal_duration_max := 40.0
## The line-appears-then-tears opening (seconds).
@export var opening_time := 0.7

@export_group("Spawning")
## Maximum portals open at the same time.
@export var max_portals := 3
## Seconds between enemies coming out of one portal.
@export var spawn_interval := 3.2
## Portals stop pushing out enemies while this many are alive.
@export var max_enemies_alive := 12

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

@export_group("Rewards")
@export var game_data: GameData = preload("res://sinan/systems/data/game_data.tres")

var _wait := 0.0
var _portals: Array[Node2D] = []
var _player


## Enemies alive for spawn limits: a whole bat flock counts as ONE enemy
## (single bats are in the "swarm" group), so a flock cannot block every portal.
static func unit_count(tree: SceneTree) -> int:
	return tree.get_nodes_in_group("enemies").size() - tree.get_nodes_in_group("swarm").size() 		+ tree.get_nodes_in_group("bat_flocks").size()


func _ready() -> void:
	add_to_group("portal_director")
	_wait = first_portal_delay


func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return
	for i in range(_portals.size() - 1, -1, -1):
		if not is_instance_valid(_portals[i]):
			_portals.remove_at(i)
	if not auto_open:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = randf_range(portal_interval_min, portal_interval_max)
	open_portal()


## How many portals may be open at once (Sealed Sky lowers it).
func portal_limit() -> int:
	return maxi(1, max_portals - int(Progress.stat(&"portal_max_reduce")))


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
	var duration := randf_range(portal_duration_min, portal_duration_max) * maxf(0.2, 1.0 - Progress.stat(&"portal_duration"))
	var interval := spawn_interval * (1.0 + Progress.stat(&"portal_spawn_slow"))
	p.height = portal_height
	p.max_width = portal_width
	p.glow_color = glow_color
	p.cut_time = opening_time
	p.spawn_duration = duration
	p.enemies_to_spawn = maxi(1, int(duration / interval))
	p.enemy_scenes = enemy_scenes
	p.max_enemies_alive = max_enemies_alive
	p.on_closed = _on_portal_closed.bind(p)
	var world := get_parent()
	p.position = FxLib.to_parent_space(world, spot)
	world.add_child(p)
	_portals.append(p)
	return p


func _on_portal_closed(p: Node2D) -> void:
	if game_data == null or not is_instance_valid(p):
		return
	game_data.spawn_drops(get_parent(), p.global_position, &"portal")
	var bonus := int(Progress.stat(&"portal_bounty"))
	if bonus > 0 and game_data.use_batched_drops:
		var field = game_data.get_pickup_field(get_parent())
		for i in bonus:
			var v := Vector2.UP.rotated(randf_range(-1.2, 1.2)) * randf_range(200.0, 450.0)
			field.add_piece(p.global_position, v, GameData.Pickup.COIN)


func _find_spot() -> Variant:
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
