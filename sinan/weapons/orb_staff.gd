extends "res://sinan/weapons/weapon.gd"
## Orb staff: lobs a magic orb that lands, charges for `fuse_time`, then bursts
## and RESTORES the painting. For this weapon the Painting group means:
## impact_radius = restore radius, distortion_strength = detail levels restored
## at the centre (1 = one level). Drawn in code; replace with art whenever.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const Orb := preload("res://sinan/weapons/projectiles/orb.gd")

const ART_TIP := 140.0  # where the drawn crystal sits

@export_group("Orb Flight")
@export var throw_speed := 900.0
@export var orb_gravity := 1600.0
@export var bounces := 1
@export_range(0.0, 1.0) var bounce_damping := 0.4
## Seconds the orb sits charging after landing before it bursts.
@export var fuse_time := 2.0
## If it never lands (thrown off-screen), it bursts after this long.
@export var max_flight_time := 3.0
@export var orb_radius := 9.0
## Size multiplier once it is inside the painting (depth shrinks it otherwise).
@export var painting_size := 1.0

@export_group("Orb Look")
@export var core_color := Color(0.9, 1.0, 1.0)
@export var glow_color := Color(0.35, 0.85, 1.0)
@export var trail_color := Color(0.6, 0.95, 1.0)
@export var blast_color := Color(1.0, 0.9, 0.55)
@export var light_energy := 1.4
## Visual size of the burst (restore size is impact_radius).
@export var blast_radius := 120.0
@export var blast_shake := 0.15


func _init() -> void:
	recoil_recover = 5.0


## Projectile to throw. Override to throw something else built on orb.gd.
func _make_projectile() -> Node2D:
	return Orb.new()


## Copy this weapon's inspector values onto the projectile.
func _configure(o) -> void:
	o.damage = roll_damage()
	o.throw_speed = throw_speed
	o.gravity = orb_gravity
	o.bounces = bounces
	o.bounce_damping = bounce_damping
	o.fuse_time = fuse_time
	o.max_flight_time = max_flight_time
	o.orb_radius = orb_radius
	o.core_color = core_color
	o.glow_color = glow_color
	o.trail_color = trail_color
	o.blast_color = blast_color
	o.light_energy = light_energy
	o.blast_radius = blast_radius
	o.blast_shake = blast_shake
	o.restore_radius = impact_radius
	o.restore_strength = distortion_strength


func fire(player, aim: Vector2, painting: bool, pick: Dictionary, target: Vector2) -> void:
	var world: Node = player.get_parent()
	var from := muzzle_global()
	var o = _make_projectile()
	_configure(o)
	if painting:
		var p := pick.duplicate()
		p["scale"] = float(pick.get("scale", 0.3)) * painting_size
		o.launch_into_painting(world, from, p, target, paint_arc)
	else:
		o.launch(world, from, aim, player, player.global_position)
	world.add_child(o)
	kick()
	FxLib.burst(world, {
		"amount": 12, "life": 0.35, "v_min": 80.0, "v_max": 220.0, "spread": 40.0,
		"direction": Vector2.RIGHT, "texture": FxLib.glow(), "s_min": 0.05, "s_max": 0.12,
		"ramp": FxLib.fade_ramp(glow_color), "additive": true, "curve": null,
	}, from, aim.angle())
	FxLib.flash_light(world, from, glow_color, 1.5, 1.5, 0.2)
	player.velocity -= aim * recoil_force * (PAINT_RECOIL_MULT if painting else 1.0)
	player.squash(Vector2(0.9, 1.1))
	player.add_trauma(0.05)


func update_preview(guide, aim: Vector2, shooter: RID, ready_shot: bool) -> void:
	guide.update_lob(muzzle_global(), aim * throw_speed, orb_gravity, shooter, ready_shot, impact_radius, glow_color)


func _draw() -> void:
	var kb := recoil * recoil
	var flip := signf(scale.y)
	draw_set_transform(Vector2(-kb * 18.0, sin(_t * 3.0) * 2.0), (-kb * 0.35 - spin) * flip, Vector2.ONE)

	var wood := Color(0.36, 0.22, 0.12)
	var gold := Color(0.85, 0.68, 0.3)
	# shaft
	draw_line(Vector2(-40, 4), Vector2(ART_TIP - 18.0, 0), wood, 11.0)
	draw_line(Vector2(-40, 1), Vector2(ART_TIP - 18.0, -3), Color(1, 1, 1, 0.15), 3.0)
	draw_rect(Rect2(20, -8, 10, 16), gold)
	draw_rect(Rect2(ART_TIP - 30.0, -9, 8, 18), gold)
	# prongs cradling the crystal
	draw_line(Vector2(ART_TIP - 22.0, -6), Vector2(ART_TIP + 4.0, -22), gold, 4.0)
	draw_line(Vector2(ART_TIP - 22.0, 6), Vector2(ART_TIP + 4.0, 22), gold, 4.0)

	# the orb regrows in the cradle while reloading
	var p := clampf(reload, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	var r := 16.0 * p * (1.0 + 0.08 * pulse)
	if r > 0.5:
		var c := Vector2(ART_TIP, 0)
		draw_circle(c, r * 2.4, Color(glow_color, 0.12))
		draw_circle(c, r * 1.5, Color(glow_color, 0.35))
		draw_circle(c, r, core_color)
		draw_circle(c + Vector2(-r, -r) * 0.3, r * 0.3, Color(1, 1, 1, 0.8))

	if recoil > 0.6:
		draw_circle(Vector2(ART_TIP, 0), 40.0 * recoil, Color(glow_color, recoil * 0.6))
