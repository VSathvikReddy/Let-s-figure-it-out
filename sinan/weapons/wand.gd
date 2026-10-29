extends "res://sinan/weapons/weapon.gd"
## The starting weapon: a wand that snaps small electric bolts. Weak and short
## ranged, but quick. Left click: a bolt to the first enemy in line (Chain
## Lightning makes it jump on to more). Right click: a tiny spark that restores
## a little of the painting. Skill tree: wand_damage, wand_rate, wand_radius,
## wand_chain (jumps), wand_bolts (extra bolts).

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const Lightning := preload("res://sinan/weapons/projectiles/lightning.gd")

## Collision layers a bolt stops at: 1 = world, 2 = enemies.
const HIT_MASK := 1 | 2

## How far a bolt reaches.
@export var bolt_range := 520.0
## How far a chain jump can reach from one enemy to the next.
@export var chain_range := 220.0
## Damage left after each chain jump (0.7 = 70% of the hit before).
@export var chain_falloff := 0.7
## Angle between extra bolts (Twin Bolts), degrees.
@export var bolt_spread := 7.0
@export var bolt_color := Color(0.6, 0.85, 1.0)


func _init() -> void:
	recoil_recover = 9.0


func fire(player, aim: Vector2, painting: bool, pick: Dictionary, target: Vector2) -> void:
	var world: Node = player.get_parent()
	var from := muzzle_global()
	kick()
	player.add_trauma(0.02)
	if painting:
		_spark_painting(world, from, pick, target)
		return
	var bolts := 1 + int(Progress.stat(&"wand_bolts"))
	for b in bolts:
		var dir := aim.rotated(deg_to_rad(bolt_spread) * (b - (bolts - 1) * 0.5))
		_bolt(world, player, from, dir)
	player.velocity -= aim * recoil_force


## One bolt: straight to the first thing in line, then jumps between enemies.
func _bolt(world: Node, player, from: Vector2, dir: Vector2) -> void:
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(from, from + dir * bolt_range, HIT_MASK, [player.get_rid()])
	var hit := space.intersect_ray(q)
	var pts := PackedVector2Array([from])
	if hit.is_empty():
		pts.append(from + dir * bolt_range * randf_range(0.6, 1.0))
		_draw_bolt(world, pts)
		return
	pts.append(hit.position)
	var target: Object = hit.collider
	if not (target and target.has_method("take_hit")):
		FxLib.impact_small(world, hit.position, hit.normal)
		_draw_bolt(world, pts)
		return
	var dmg := roll_damage()
	target.call("take_hit", dmg, hit.position, HitInfo.make(HitInfo.SINGLE, &"wand", hit.position, dir))
	FxLib.impact_small(world, hit.position, -dir)
	# Chain Lightning: jump on to the nearest enemy not hit yet
	var done := [target]
	var at: Vector2 = hit.position
	for j in int(Progress.stat(&"wand_chain")):
		var next := _nearest_enemy(at, done)
		if next == null:
			break
		dmg *= chain_falloff
		var p: Vector2 = next.global_position + Vector2(0, -24)
		next.call("take_hit", dmg, p, HitInfo.make(HitInfo.SINGLE, &"wand", p, (p - at).normalized()))
		pts.append(p)
		done.append(next)
		at = p
	_draw_bolt(world, pts)


func _nearest_enemy(at: Vector2, skip: Array) -> Node2D:
	var best: Node2D = null
	var best_d := chain_range * chain_range
	for e in get_tree().get_nodes_in_group("enemies"):
		if e in skip or not (e is Node2D) or not e.has_method("take_hit"):
			continue
		var d := at.distance_squared_to((e as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## Right click: a little spark lands in the painting and restores a small spot.
func _spark_painting(world: Node, from: Vector2, pick: Dictionary, target: Vector2) -> void:
	var layer: Node = pick.get("layer")
	var end := target
	if is_instance_valid(layer):
		end = (layer as Node2D).to_global(pick["local"])
		Paint.hit(self, layer, pick["local"], impact_radius, -distortion_strength, Paint.Kind.RESTORE, &"wand")
		get_tree().call_group("ghosts", "on_painting_shot", layer, pick["local"], impact_radius)
	_draw_bolt(world, PackedVector2Array([from, end]), 2.0)


func _draw_bolt(world: Node, pts: PackedVector2Array, w := 3.0) -> void:
	var l := Lightning.new()
	l.points = pts
	l.color = bolt_color
	l.width = w
	world.add_child(l)
	FxLib.flash_light(world, pts[-1], bolt_color, 1.2, 0.8, 0.08)


func _draw() -> void:
	var kb := recoil * recoil
	var flip := signf(scale.y)
	draw_set_transform(Vector2(-kb * 10.0, sin(_t * 3.0) * 2.0), (-kb * 0.15 - spin) * flip, Vector2.ONE)
	var wood := Color(0.36, 0.22, 0.12)
	var dark := Color(0.2, 0.12, 0.06)
	# handle (thicker, with a wrapped grip) tapering into the shaft
	draw_colored_polygon(PackedVector2Array([
		Vector2(-10, -6), Vector2(40, -4), Vector2(muzzle.x - 6.0, -2), Vector2(muzzle.x - 6.0, 2), Vector2(40, 4), Vector2(-10, 6)
	]), wood)
	for i in 4:
		draw_line(Vector2(-6 + i * 9, -6), Vector2(-2 + i * 9, 6), dark, 2.0)
	draw_line(Vector2(42, -3), Vector2(muzzle.x - 8.0, -1), Color(1, 1, 1, 0.18), 1.5)
	# crackling tip
	var tip := Vector2(muzzle.x - 4.0, 0)
	var pulse := 0.7 + 0.3 * sin(_t * 23.0) + recoil * 0.8
	draw_circle(tip, 9.0 * pulse, Color(bolt_color, 0.25))
	draw_circle(tip, 4.5, Color(bolt_color, 0.9))
	draw_circle(tip, 2.0, Color.WHITE)
	for i in 3:
		var a := _t * 9.0 + i * TAU / 3.0
		draw_line(tip, tip + Vector2.from_angle(a) * (7.0 + 5.0 * recoil), Color(bolt_color, 0.7), 1.2)
