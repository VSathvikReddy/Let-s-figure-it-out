class_name GameData
extends Resource
## All drop AND spawning numbers in one place. The live values are in
## sinan/systems/data/game_data.tres - select it and edit in the Inspector.
## Spawning: which enemies come out of portals and how often. While a run is on
## (RunManager), how many may be alive, how long portals stay open and how
## often the Forger visits come from the run's threat (difficulty.tres); the
## numbers here are only used in levels without a RunManager.
## Enemies look up their drop table by name (their `drop_table` export).
## Every drop is a coin: it bursts out, then flies to the player (PickupField)
## and goes to Progress.

## Pickup kinds the PickupField batches (one MultiMesh pair each).
enum Pickup { COIN }

@export_group("Coins")
@export var coin_color := Color(1.0, 0.8, 0.25)
@export var coin_icon: Texture2D
## Optional PickupField scene to create when a level has none (empty = default).
@export var pickup_field_scene: PackedScene

@export_group("Drop Tables")
@export var goblin_drops: Array[DropEntry] = []
@export var witch_drops: Array[DropEntry] = []
@export var ghost_drops: Array[DropEntry] = []
@export var bird_drops: Array[DropEntry] = []
@export var bat_drops: Array[DropEntry] = []
@export var priest_drops: Array[DropEntry] = []
## Coins that pop out when a portal closes (plus the Rift Bounty upgrade).
@export var portal_drops: Array[DropEntry] = []

@export_group("Spawning")
## Which enemies portals push out, and how often each is picked (weight).
@export var spawn_table: Array[SpawnEntry] = []
## Portals stop pushing out enemies while this many are alive (a whole bat
## flock counts as one). The Forger also stops opening portals.
@export var max_enemies_alive := 12
## Maximum portals open at the same time (the Sealed Sky upgrade lowers it).
@export var max_portals := 3
## Seconds between enemies coming out of one portal.
@export var portal_spawn_interval := 3.2
## How long each portal stays open (random in this range).
@export var portal_duration_min := 30.0
@export var portal_duration_max := 40.0
## Off (default): only the Forger opens portals. On: they also open by
## themselves, first after first_portal_delay, then every interval.
@export var auto_open_portals := false
@export var first_portal_delay := 3.0
@export var portal_interval_min := 10.0
@export var portal_interval_max := 18.0

@export_group("Forger Visits")
## Seconds before the Forger's first visit, then seconds he stays away between
## visits (random in this range; the Thin Veil upgrade makes it longer).
@export var forger_first_visit := 4.0
@export var forger_away_min := 22.0
@export var forger_away_max := 38.0
## Portals he tears open per visit (random in this range, capped by max_portals).
@export var portals_per_visit_min := 1
@export var portals_per_visit_max := 2

@export_group("Drop Spread")
## Every coin bursts out on its own. Burst speed range...
@export var drop_speed_min := 260.0
@export var drop_speed_max := 520.0
## ...within this half-angle of straight up (degrees). Wider = flatter spray.
@export var drop_spread_degrees := 70.0
## Seconds between coins popping out. 0 = the whole drop bursts out in the
## same instant (default); a small value turns it into a fountain.
@export var drop_stagger := 0.0


var _coin_frac := 0.0  # leftover part of a coin from the drop multiplier


func piece_color(_t: Pickup) -> Color:
	return coin_color


func piece_icon(_t: Pickup) -> Texture2D:
	return coin_icon


func drop_table(table_name: StringName) -> Array[DropEntry]:
	match table_name:
		&"goblin":
			return goblin_drops
		&"witch":
			return witch_drops
		&"ghost":
			return ghost_drops
		&"bird":
			return bird_drops
		&"bat":
			return bat_drops
		&"priest":
			return priest_drops
		&"portal":
			return portal_drops
	return []


## Roll a drop table and fountain the coins out of `pos` (global) into `world`.
func spawn_drops(world: Node, pos: Vector2, table_name: StringName) -> void:
	var n := 0
	for e in drop_table(table_name):
		if e != null and randf() <= e.chance:
			n += randi_range(e.min_count, maxi(e.min_count, e.max_count))
	if table_name != &"portal":
		world.get_tree().call_group("kill_listeners", "on_enemy_killed", table_name)
		n += int(Progress.stat(&"kill_bonus"))
		# enemy-branch bounties: more coins from that enemy (and from every kill)
		var more := Progress.stat(StringName(String(table_name) + "_bounty")) + Progress.stat(&"rift_drops")
		n = int(round(n * (1.0 + more)))
		if randf() < Progress.stat(&"lucky_drop"):
			n *= 2
	# Coin Value + milestones: more coins drop (each coin on the floor = 1 coin)
	var exact := n * Progress.coin_multiplier() + _coin_frac
	n = floori(exact)
	_coin_frac = exact - n
	if n <= 0:
		return
	var spread := deg_to_rad(drop_spread_degrees)
	var field := get_pickup_field(world)
	for i in n:
		var vel := Vector2.UP.rotated(randf_range(-spread, spread)) * randf_range(drop_speed_min, drop_speed_max)
		field.add_piece(pos, vel, Pickup.COIN, i * drop_stagger)


# ---------------------------------------------------------------- spawning

## Enemies alive for spawn limits: a whole bat flock counts as ONE enemy
## (single bats are in the "swarm" group), so a flock cannot block every portal.
static func unit_count(tree: SceneTree) -> int:
	return tree.get_nodes_in_group("enemies").size() - tree.get_nodes_in_group("swarm").size() \
		+ tree.get_nodes_in_group("bat_flocks").size()


## May another enemy come out right now?
func can_spawn(tree: SceneTree) -> bool:
	var limit := RunManager.current.max_enemies() if RunManager.current else max_enemies_alive
	return limit <= 0 or unit_count(tree) < limit


## A random enemy from the spawn table (by weight), skipping any at its own
## max_alive. Null if nothing can spawn.
func pick_enemy(tree: SceneTree) -> PackedScene:
	var ok: Array[SpawnEntry] = []
	var total := 0.0
	for e in spawn_table:
		if e and e.scene != "" and e.weight > 0.0 and Progress.is_unlocked(e.unlock_stat) 				and (e.max_alive <= 0 or _alive_of(tree, e.scene) < e.max_alive):
			ok.append(e)
			total += e.weight
	var roll := randf() * total
	for e in ok:
		roll -= e.weight
		if roll <= 0.0:
			return load(e.scene)
	return null if ok.is_empty() else load(ok[-1].scene)


func _alive_of(tree: SceneTree, scene: String) -> int:
	var n := 0
	for g in [&"enemies", &"bat_flocks"]:
		for e in tree.get_nodes_in_group(g):
			if e.scene_file_path == scene:
				n += 1
	return n


## How many portals may be open at once.
func portal_limit() -> int:
	return RunManager.current.max_portals() if RunManager.current else max_portals


## Seconds a new portal stays open.
func portal_duration() -> float:
	if RunManager.current:
		return RunManager.current.portal_duration() * randf_range(0.85, 1.15)
	return randf_range(portal_duration_min, portal_duration_max)


## Seconds between enemies coming out of a portal (read again for every enemy,
## so a rising threat speeds up portals that are already open).
func spawn_interval() -> float:
	return RunManager.current.spawn_interval() if RunManager.current else portal_spawn_interval


## Health multiplier for an enemy coming out of a portal now.
func enemy_health() -> float:
	return RunManager.current.enemy_health() if RunManager.current else 1.0


## Seconds the Forger stays away before his next visit.
func forger_away_time() -> float:
	if RunManager.current:
		return RunManager.current.forger_away() * randf_range(0.8, 1.2)
	return randf_range(forger_away_min, forger_away_max)


func portals_per_visit() -> int:
	if RunManager.current:
		return RunManager.current.portals_per_visit()
	return randi_range(portals_per_visit_min, maxi(portals_per_visit_min, portals_per_visit_max))


# ---------------------------------------------------------------- pickups

## The level's PickupField (created on first use).
func get_pickup_field(world: Node) -> Node:
	var existing := world.get_tree().get_first_node_in_group("pickup_field")
	if existing:
		return existing
	var field: Node
	if pickup_field_scene:
		field = pickup_field_scene.instantiate()
	else:
		field = preload("res://sinan/systems/pickups/pickup_field.gd").new()
	field.set("game_data", self)
	world.add_child(field)
	return field
