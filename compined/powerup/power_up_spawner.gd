extends Node2D
## Drops random power-up tokens around the level while it runs. Several can
## lie around at the same time; each one vanishes after a while if nobody
## takes it. Drop power_up_spawner.tscn into a level and set its Inspector.

const Effects := preload("res://compined/common/effects.gd")
const TOKEN := preload("res://compined/powerup/power_up.tscn")

@export var enabled := true

@export_group("Which Power-ups")
## How likely each ability is (0 = never). Same order as PowerUp.PowerType.
@export var dash_chance := 1.0
@export var ghost_chance := 1.0
@export var trail_chance := 1.0
@export var shield_chance := 1.0
@export var veil_chance := 0.6

@export_group("How Many")
## Most tokens lying in the level at the same time.
@export_range(1, 20) var max_on_map := 3
## Seconds a token stays before it vanishes (it blinks at the end).
@export var token_lifetime := 20.0

@export_group("When")
@export var first_token_after := 5.0
## Seconds between new tokens: a random time between these two.
@export var min_time_between := 8.0
@export var max_time_between := 14.0

@export_group("Where")
## How far from the painting's edges tokens appear, in px.
@export var edge_margin := 150.0
## Tokens never appear closer than this to the player, in px.
@export var min_distance_from_player := 300.0

var _next := 0.0
var _tokens: Array[Node] = []


func _ready() -> void:
	_next = first_token_after


func _process(delta: float) -> void:
	if not enabled:
		return
	_next -= delta
	if _next > 0.0:
		return
	_next = randf_range(min_time_between, maxf(min_time_between, max_time_between))
	_tokens = _tokens.filter(func(token): return is_instance_valid(token))
	if _tokens.size() < max_on_map:
		_drop_token()


func _drop_token() -> void:
	var spot: Variant = _pick_spot()
	if spot == null:
		return
	var token: PowerUp = TOKEN.instantiate()
	token.type = _pick_type()
	token.lifetime = token_lifetime
	get_tree().current_scene.add_child(token)
	token.global_position = spot
	_tokens.append(token)
	Effects.burst(token, 14, Color(1.0, 0.9, 0.6), 0.5, 40.0, 120.0, 2.0, 4.0)


## A random ability, using the chances above.
func _pick_type() -> PowerUp.PowerType:
	var chances := [dash_chance, ghost_chance, trail_chance, shield_chance, veil_chance]
	var total := 0.0
	for chance in chances:
		total += maxf(chance, 0.0)
	var roll := randf() * total
	for i in chances.size():
		roll -= maxf(chances[i], 0.0)
		if roll <= 0.0:
			return i as PowerUp.PowerType
	return PowerUp.PowerType.DASH


func _pick_spot() -> Variant:
	var area := Effects.level_rect(self).grow(-edge_margin)
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return null
	var player := get_tree().get_first_node_in_group("player") as Node2D
	for attempt in 40:
		var spot := area.position + Vector2(randf() * area.size.x, randf() * area.size.y)
		if player == null or spot.distance_to(player.global_position) >= min_distance_from_player:
			return spot
	return null
