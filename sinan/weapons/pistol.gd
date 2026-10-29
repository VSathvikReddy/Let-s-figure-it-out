extends "res://sinan/weapons/weapon.gd"
## Luger-style pistol (long thin barrel, toggle lock on top, raked grip): fast,
## light recoil, small impacts. Drawn in code; replace with art whenever.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const Bullet := preload("res://sinan/weapons/projectiles/bullet.gd")

const ART_MUZZLE := 130.0  # where the drawn barrel ends

## Where spent casings fly out (weapon-local).
@export var ejection_port := Vector2(14, -18)


func _init() -> void:
	recoil_recover = 7.0


func ejection_global() -> Vector2:
	return to_global(ejection_port)


func fire(player, aim: Vector2, painting: bool, pick: Dictionary, target: Vector2) -> void:
	var world: Node = player.get_parent()
	var from := muzzle_global()
	var b := Bullet.new()
	b.damage = roll_damage()
	if painting:
		b.launch_into_painting(world, from, pick, target, paint_arc, impact_radius, distortion_strength)
	else:
		b.launch(world, from, aim, player, player.global_position)
	world.add_child(b)
	kick()
	FxLib.muzzle_small(world, from, aim)
	FxLib.casing(world, ejection_global(), aim)
	# Light recoil: a nudge only, no loss of control.
	player.velocity -= aim * recoil_force * (PAINT_RECOIL_MULT if painting else 1.0)
	player.squash(Vector2(0.92, 1.06))
	player.add_trauma(0.06)


func _draw() -> void:
	var kb := recoil * recoil
	var flip := signf(scale.y)
	draw_set_transform(Vector2(-kb * 22.0, sin(_t * 3.0) * 2.0), (-kb * 0.5 - spin) * flip, Vector2.ONE)

	var steel := Color(0.24, 0.25, 0.28)
	var dark := Color(0.12, 0.12, 0.14)
	var wood := Color(0.45, 0.27, 0.13)
	var hi := Color(1, 1, 1, 0.28)

	# grip (raked back like a Luger)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-6, 6), Vector2(20, 6), Vector2(6, 60), Vector2(-22, 55)
	]), wood)
	for i in 4:
		var y := 18.0 + i * 9.0
		draw_line(Vector2(-6 - y * 0.25, y), Vector2(16 - y * 0.25, y), Color(0.3, 0.17, 0.08), 2.0)
	draw_rect(Rect2(-24, 52, 26, 7), dark)  # magazine base

	# trigger guard + trigger
	draw_arc(Vector2(32, 14), 11.0, 0.0, PI, 12, dark, 4.0)
	draw_line(Vector2(30, 8), Vector2(27, 20), dark, 3.0)

	# receiver and barrel
	draw_rect(Rect2(-12, -12, 62, 20), steel)
	draw_rect(Rect2(46, -8, ART_MUZZLE - 46.0, 11), steel)
	draw_line(Vector2(46, -6), Vector2(ART_MUZZLE, -6), hi, 2.0)
	draw_rect(Rect2(ART_MUZZLE - 7.0, -13, 6, 5), dark)  # front sight

	# toggle lock: the knuckle jumps up when fired
	var tog := kb * 16.0
	draw_line(Vector2(-6, -12), Vector2(12, -13 - tog), dark, 7.0)
	draw_line(Vector2(12, -13 - tog), Vector2(32, -12), dark, 7.0)
	draw_circle(Vector2(12, -13 - tog), 5.0, steel)
	draw_circle(Vector2(-9, -12), 7.0, dark)  # rear grip knobs

	if recoil > 0.65:
		var c := Vector2(ART_MUZZLE + 8.0, -2.0)
		draw_circle(c, 20.0 * recoil, Color(1.0, 0.85, 0.45, recoil))
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -8), c + Vector2(34 * recoil, 0), c + Vector2(0, 8)
		]), Color(1.0, 0.95, 0.7, recoil))
