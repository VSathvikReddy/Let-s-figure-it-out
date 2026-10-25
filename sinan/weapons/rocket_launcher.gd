extends "res://sinan/weapons/weapon.gd"
## Rocket launcher: big recoil, explosive missile. Drawn in code (player-local
## units, scaled with the player); replace with art whenever.

const FxLib := preload("res://sinan/fx/fx_lib.gd")
const Missile := preload("res://sinan/fx/missile.gd")

const ART_MUZZLE := 168.0  # where the drawn tube ends


func _init() -> void:
	recoil_recover = 4.5


func fire(player, aim: Vector2, painting: bool, pick: Dictionary, target: Vector2) -> void:
	var world: Node = player.get_parent()
	var from := muzzle_global()
	var m := Missile.new()
	if painting:
		m.launch_into_painting(world, from, pick, target, paint_arc, impact_radius, distortion_strength)
	else:
		m.launch(world, from, aim, player, player.global_position)
	world.add_child(m)
	kick()
	FxLib.muzzle(world, from, aim)
	player.knock_back(-aim * recoil_force * (PAINT_RECOIL_MULT if painting else 1.0))
	player.squash(Vector2(0.75, 1.22))
	player.add_trauma(0.22)


func _draw() -> void:
	var kb := recoil * recoil
	var flip := signf(scale.y)
	draw_set_transform(Vector2(-kb * 46.0, sin(_t * 3.0) * 2.0), (-kb * 0.25 - spin) * flip, Vector2.ONE)

	# Rocket slides forward out of the breech while reloading.
	var p := 1.0 - pow(1.0 - clampf(reload, 0.0, 1.0), 3.0)
	if reload > 0.02:
		var off := (1.0 - p) * -90.0
		draw_rect(Rect2(ART_MUZZLE - 70.0 + off, -12, 80, 24), Color(0.86, 0.86, 0.9))
		draw_rect(Rect2(ART_MUZZLE - 20.0 + off, -12, 14, 24), Color(0.8, 0.15, 0.12))
		draw_colored_polygon(PackedVector2Array([
			Vector2(ART_MUZZLE + 10.0 + off, -12), Vector2(ART_MUZZLE + 46.0 + off, 0), Vector2(ART_MUZZLE + 10.0 + off, 12)
		]), Color(0.85, 0.15, 0.12))

	# Tube (drawn over the rocket so only the nose pokes out).
	draw_rect(Rect2(-30, -17, ART_MUZZLE + 30.0, 34), Color(0.3, 0.34, 0.27))
	draw_rect(Rect2(-30, 6, ART_MUZZLE + 30.0, 11), Color(0.2, 0.23, 0.18))
	draw_line(Vector2(-30, -15), Vector2(ART_MUZZLE, -15), Color(1, 1, 1, 0.25), 3.0)
	draw_rect(Rect2(40, -19, 8, 38), Color(0.17, 0.19, 0.15))
	draw_rect(Rect2(110, -19, 8, 38), Color(0.17, 0.19, 0.15))
	draw_rect(Rect2(ART_MUZZLE - 14.0, -21, 18, 42), Color(0.45, 0.47, 0.4))
	draw_rect(Rect2(-42, -20, 18, 40), Color(0.4, 0.42, 0.36))
	draw_rect(Rect2(70, -26, 30, 9), Color(0.2, 0.22, 0.18))
	draw_rect(Rect2(50, 17, 22, 40), Color(0.25, 0.17, 0.1))
	draw_rect(Rect2(112, 17, 16, 24), Color(0.25, 0.17, 0.1))

	if recoil > 0.7:
		draw_circle(Vector2(ART_MUZZLE + 12.0, 0), 38.0 * recoil, Color(1.0, 0.85, 0.4, recoil))
