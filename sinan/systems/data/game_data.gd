class_name GameData
extends Resource
## All drop numbers in one place. The live values are in
## sinan/data/game_data.tres - select it and edit in the Inspector.
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

@export_group("Drop Spread")
## Every coin bursts out on its own. Burst speed range...
@export var drop_speed_min := 260.0
@export var drop_speed_max := 680.0
## ...within this half-angle of straight up (degrees). Wider = flatter spray.
@export var drop_spread_degrees := 80.0
## Seconds between coins popping out. 0 = the whole drop bursts out in the
## same instant (default); a small value turns it into a fountain.
@export var drop_stagger := 0.0


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
		n += int(Progress.stat(&"kill_bonus"))
	if n <= 0:
		return
	var spread := deg_to_rad(drop_spread_degrees)
	var field := get_pickup_field(world)
	for i in n:
		var vel := Vector2.UP.rotated(randf_range(-spread, spread)) * randf_range(drop_speed_min, drop_speed_max)
		field.add_piece(pos, vel, Pickup.COIN, i * drop_stagger)


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
