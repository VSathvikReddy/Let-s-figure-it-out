@tool  # also runs in the editor, to draw the spawn area
extends Node2D
## Spawns enemies at random spots, in waves, while the level runs.
##
## HOW TO USE: drop enemy_spawner.tscn into a level and fill in its Inspector:
##   Spawn List  - which enemies, how likely each one is, how many of each
##   How Many    - enemies per wave, most alive at once, total for the level
##   When        - first wave, time between waves, speeding up over time
##   Where       - anywhere in the painting, or around this node
##
## New enemies go into the level's "Enemies" node (like the ones you place by
## hand), appear with a little magic puff, and never right next to the player.

const Effects := preload("res://compined/common/effects.gd")
const Levels := preload("res://compined/levels/levels.gd")

enum Area { WHOLE_PAINTING, AROUND_SPAWNER }

@export var enabled := true

@export_group("Spawn List")
## The enemies this spawner can make. Each one has its own chance and limits.
@export var spawn_list: Array[EnemySpawnEntry] = []

@export_group("How Many")
## Enemies in each wave: a random number between these two.
@export_range(1, 20) var min_per_wave := 1
@export_range(1, 20) var max_per_wave := 2
## Most enemies from this spawner alive at the same time.
@export_range(1, 100) var max_alive := 6
## Total enemies it makes in the whole level (0 = it never stops).
@export var total_to_spawn := 0

@export_group("When")
## Seconds before the first wave.
@export var first_wave_after := 4.0
## Seconds between waves: a random time between these two.
@export var min_time_between_waves := 6.0
@export var max_time_between_waves := 10.0
## Waves come this much faster every minute (0.1 = 10% faster each minute).
@export_range(0.0, 1.0, 0.01) var speed_up_per_minute := 0.0
## They never come faster than this, in seconds.
@export var fastest_time_between_waves := 2.0

@export_group("Where")
## WHOLE_PAINTING: anywhere in the painting. AROUND_SPAWNER: within
## `area_radius` of this node (move the node in the level to choose the spot).
@export var area := Area.WHOLE_PAINTING:
	set(value):
		area = value
		queue_redraw()
@export var area_radius := 600.0:
	set(value):
		area_radius = value
		queue_redraw()
## How far from the painting's edges they may appear, in px.
@export var edge_margin := 150.0
## They never appear closer than this to the player, in px.
@export var min_distance_from_player := 450.0

var _time := 0.0                 # seconds since the level started
var _next_wave := 0.0            # seconds left until the next wave
var _spawned_total := 0
var _alive: Array[Node] = []     # enemies from this spawner that are still alive
var _alive_by_entry := {}        # entry -> Array of its enemies still alive
var _difficulty := 0.5           # set by the level (0 = easy, 1 = hard)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_next_wave = first_wave_after


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not enabled:
		return
	_time += delta
	_next_wave -= delta
	if _next_wave > 0.0:
		return
	_next_wave = _time_until_next_wave()
	_spawn_wave()


## Draws the spawn area in the editor (only for AROUND_SPAWNER).
func _draw() -> void:
	if not Engine.is_editor_hint() or area != Area.AROUND_SPAWNER:
		return
	draw_circle(Vector2.ZERO, area_radius, Color(1.0, 0.3, 0.3, 0.06))
	draw_arc(Vector2.ZERO, area_radius, 0.0, TAU, 64, Color(1.0, 0.3, 0.3, 0.8), 3.0)


## Called by the level when it starts: scales the numbers set in the Inspector
## to the painting's difficulty (see levels/difficulty.tres).
func apply_difficulty(amount: float) -> void:
	_difficulty = amount
	var difficulty := Levels.DIFFICULTY
	max_alive = maxi(1, roundi(max_alive * difficulty.spawn_max_alive(amount)))
	var per_wave := difficulty.spawn_per_wave(amount)
	min_per_wave = maxi(1, roundi(min_per_wave * per_wave))
	max_per_wave = maxi(min_per_wave, roundi(max_per_wave * per_wave))
	var rate := difficulty.spawn_rate(amount)
	min_time_between_waves /= rate
	max_time_between_waves /= rate
	fastest_time_between_waves /= rate
	first_wave_after *= difficulty.first_wave_wait(amount)
	_next_wave = first_wave_after


func _time_until_next_wave() -> float:
	var wait := randf_range(min_time_between_waves, maxf(min_time_between_waves, max_time_between_waves))
	var minutes := _time / 60.0
	wait /= 1.0 + speed_up_per_minute * minutes
	return maxf(wait, fastest_time_between_waves)


func _spawn_wave() -> void:
	_forget_dead()
	var count := randi_range(min_per_wave, maxi(min_per_wave, max_per_wave))
	for i in count:
		if _alive.size() >= max_alive:
			return
		if total_to_spawn > 0 and _spawned_total >= total_to_spawn:
			enabled = false   # made all of them
			return
		var entry := _pick_entry()
		if entry == null:
			return            # nothing may spawn right now
		var spot: Variant = _pick_spot()
		if spot == null:
			return            # no free spot (the player is everywhere?)
		_spawn(entry, spot)


## Picks a random entry, using each one's chance. Entries that are not allowed
## yet (appears_after) or that are at their own max_alive are skipped.
func _pick_entry() -> EnemySpawnEntry:
	var allowed: Array[EnemySpawnEntry] = []
	var total_chance := 0.0
	for entry in spawn_list:
		if entry == null or entry.enemy == null or entry.chance <= 0.0:
			continue
		if _time < entry.appears_after:
			continue
		if entry.max_alive > 0 and _alive_by_entry.get(entry, []).size() >= entry.max_alive:
			continue
		allowed.append(entry)
		total_chance += entry.chance
	var roll := randf() * total_chance
	for entry in allowed:
		roll -= entry.chance
		if roll <= 0.0:
			return entry
	return null


## A random spot inside the painting (and inside the area), far from the player.
func _pick_spot() -> Variant:
	var painting := Effects.level_rect(self).grow(-edge_margin)
	if painting.size.x <= 0.0 or painting.size.y <= 0.0:
		return null
	var player := get_tree().get_first_node_in_group("player") as Node2D
	for attempt in 40:
		var spot: Vector2
		if area == Area.AROUND_SPAWNER:
			spot = global_position + Vector2.from_angle(randf() * TAU) * sqrt(randf()) * area_radius
		else:
			spot = painting.position + Vector2(randf() * painting.size.x, randf() * painting.size.y)
		if not painting.has_point(spot):
			continue
		if player and spot.distance_to(player.global_position) < min_distance_from_player:
			continue
		return spot
	return null


func _spawn(entry: EnemySpawnEntry, spot: Vector2) -> void:
	var enemy := entry.enemy.instantiate() as Node2D
	_enemies_node().add_child(enemy)
	enemy.global_position = spot
	_alive.append(enemy)
	if not _alive_by_entry.has(entry):
		_alive_by_entry[entry] = []
	_alive_by_entry[entry].append(enemy)
	_spawned_total += 1
	Levels.scale_enemy_health(enemy, _difficulty)
	# a little magic puff where it appears
	Effects.burst(enemy, 18, Color(0.75, 0.45, 1.0), 0.5, 60.0, 160.0, 3.0, 6.0)


## The level's "Enemies" node, so spawned enemies sit with the hand-placed ones.
func _enemies_node() -> Node:
	var level := get_tree().current_scene
	var enemies := level.get_node_or_null("Enemies") if level else null
	return enemies if enemies else get_parent()


func _forget_dead() -> void:
	_alive = _alive.filter(func(enemy): return is_instance_valid(enemy))
	for entry in _alive_by_entry:
		_alive_by_entry[entry] = _alive_by_entry[entry].filter(func(enemy): return is_instance_valid(enemy))
