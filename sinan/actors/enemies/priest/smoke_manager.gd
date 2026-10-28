extends Node2D
## Holds and draws all priest smoke as one batch of puffs. Puffs come from
## smoke vents (the orbs the priest throws): each one drifts out sideways,
## swells, and slowly RISES, so a vent gradually fills the area and the smoke
## lifts away over time. Shoot the vent and its smoke clears fast (rises away).
##
## Fresh smoke only blocks vision (drawn over everything) and never touches the
## painting. The smoke is FUEL: fire (breath or burst) catches a puff and races
## through the cloud from puff to puff, engulfing it in a fraction of a second.
## Each burning puff throws out flame particles while it consumes itself - it
## shrinks and thins as its fuel runs out, leaving only rising soot. Burning
## smoke hurts whoever is inside and scorches the painting behind it.
## Created on demand by SmokeManager.get_for(node) - no need to place one.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const FireParticles := preload("res://sinan/fx/core/fire_particles.gd")
const PaintPicker := preload("res://sinan/painting/paint_picker.gd")

enum { SMOKE, BURNING }

@export var max_puffs := 220
@export var smoke_color := Color(0.42, 0.39, 0.44)
## Rising: slow drift normally, fast when its vent was shot.
@export var rise_speed := 30.0
@export var clear_rise_speed := 150.0
@export_group("Fire")
## Seconds a puff takes to burn through its fuel.
@export var burn_time := 0.75
## Fire jumps to puffs this close (x their combined radius) after a tiny delay
## - small delay = the flame front races through the cloud.
@export var spread_reach := 0.6
@export var spread_delay := 0.08
## Flame particles per second from a fully fuelled puff (scaled by its size).
@export var flame_rate := 45.0
@export var soot_rate := 9.0
@export var burn_damage := 0.5
@export var damage_tick := 0.5
@export var paint_tick := 0.35
@export var burn_radius := 28.0
@export var burn_strength := 0.3

# puff: [pos, vel, r, r_max, age, life, vent_id, state, fuel, ignite_in, clearing, seed]
var _puffs: Array = []
var _damage_t := 0.0
var _paint_t := 0.0
var _time := 0.0
var _fire: Node2D
var _soot: Node2D
var _light: PointLight2D


static var _current: Node2D


static func get_for(from: Node) -> Node2D:
	if is_instance_valid(_current) and _current.is_inside_tree():
		return _current
	_current = from.get_tree().get_first_node_in_group("smoke_manager")
	if _current == null:
		_current = load("res://sinan/actors/enemies/priest/smoke_manager.gd").new()
		_current.name = "SmokeManager"
		from.get_tree().current_scene.add_child(_current)
	return _current


func _ready() -> void:
	add_to_group("smoke_manager")
	z_index = 40   # over the characters: smoke really hides them
	_soot = FireParticles.new()
	_soot.additive = false
	_soot.buoyancy = 90.0
	_soot.drag = 1.2
	add_child(_soot)
	_fire = FireParticles.new()
	add_child(_fire)
	_light = PointLight2D.new()
	_light.texture = FxLib.glow()
	_light.color = Color(1.0, 0.5, 0.18)
	_light.energy = 0.0
	add_child(_light)


func add_puff(at: Vector2, vel: Vector2, r_max: float, life: float, vent_id: int) -> void:
	if _puffs.size() >= max_puffs:
		# the oldest plain smoke makes room
		for i in _puffs.size():
			if _puffs[i][7] == SMOKE:
				_puffs.remove_at(i)
				break
	_puffs.append([to_local(at), vel, r_max * 0.25, r_max, 0.0, life, vent_id, SMOKE, 1.0, -1.0, false, randf() * 10.0])


## The vent was destroyed: its smoke lifts away quickly.
func clear_vent(vent_id: int) -> void:
	for p in _puffs:
		if p[6] == vent_id and p[7] == SMOKE:
			p[10] = true
			p[5] = minf(p[5], p[4] + randf_range(0.9, 1.5))


## Middle of a vent's smoke (world), or Vector2.INF if it has none left.
func smoke_center(vent_id: int) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for p in _puffs:
		if p[6] == vent_id and p[7] == SMOKE:
			c += p[0]
			n += 1
	return to_global(c / n) if n > 0 else Vector2.INF


## A fire cone lights the FIRST smoke puff it reaches (nearest along the
## flame); the fire then spreads through the rest of the cloud on its own.
## Returns true if something caught.
func ignite_cone(origin: Vector2, dir: Vector2, half_angle: float, length: float) -> bool:
	var o := to_local(origin)
	var first: Array = []
	var first_d := INF
	for p in _puffs:
		if p[7] != SMOKE:
			continue
		var to: Vector2 = p[0] - o
		var d := to.length()
		var r: float = p[2]
		if d - r > length:
			continue
		if (absf(dir.angle_to(to)) <= half_angle + atan2(r, maxf(d, 1.0)) or d < r) and d < first_d:
			first_d = d
			first = p
	if first.is_empty():
		return false
	_ignite(first)
	return true


## Light the puff nearest a point (if any is within radius); it spreads from there.
func ignite_at(at: Vector2, radius: float) -> void:
	var o := to_local(at)
	var best: Array = []
	var best_d := INF
	for p in _puffs:
		var d: float = (p[0] as Vector2).distance_to(o)
		if p[7] == SMOKE and d <= p[2] + radius and d < best_d:
			best_d = d
			best = p
	if not best.is_empty():
		_ignite(best)


## True if a point is hidden inside smoke.
func is_hidden(at: Vector2) -> bool:
	var o := to_local(at)
	for p in _puffs:
		if (p[0] as Vector2).distance_to(o) <= p[2] * 0.7 * p[8]:
			return true
	return false


func _ignite(p: Array) -> void:
	if p[7] == BURNING:
		return
	p[7] = BURNING
	p[9] = -1.0
	p[5] = maxf(p[5], p[4] + burn_time * 2.0)
	# the catch: a quick bright puff of flame where it lights
	var at := to_global(p[0])
	for i in 6:
		_fire.emit(at + Vector2.from_angle(randf() * TAU) * p[2] * 0.4,
			Vector2.from_angle(randf() * TAU) * randf_range(40.0, 120.0), p[2] * randf_range(0.7, 1.1), randf_range(0.25, 0.45))


func _process(delta: float) -> void:
	_time += delta
	_damage_t -= delta
	_paint_t -= delta
	var burning: Array = []
	for p in _puffs:
		p[4] += delta
		var vel: Vector2 = p[1]
		# sideways drift dies off, rising takes over (and speeds up as it ages)
		vel.x *= exp(-1.1 * delta)
		var rise: float = clear_rise_speed if p[10] else rise_speed * (1.0 + p[4] * 0.12)
		if p[7] == BURNING:
			rise *= 2.5  # the heat lifts it
		vel.y = lerpf(vel.y, -rise, 1.0 - exp(-(3.0 if p[10] else 0.6) * delta))
		p[1] = vel
		p[0] += vel * delta
		p[2] = lerpf(p[2], p[3], 1.0 - exp(-0.9 * delta))
		if p[7] == SMOKE and p[9] >= 0.0:
			p[9] -= delta
			if p[9] < 0.0:
				_ignite(p)
		elif p[7] == BURNING:
			# consume the fuel; the puff is eaten by the flames
			p[8] -= delta / burn_time
			if p[8] <= 0.0:
				p[5] = p[4]  # gone
			else:
				burning.append(p)
	# fire spreads to neighbouring puffs
	for b in burning:
		for p in _puffs:
			if p[7] == SMOKE and p[9] < 0.0 and (p[0] as Vector2).distance_to(b[0]) < (p[2] + b[2]) * spread_reach:
				p[9] = spread_delay * randf_range(0.5, 1.5)
	_puffs = _puffs.filter(func(p): return p[4] < p[5])
	if not burning.is_empty():
		_burn(burning)
	_emit_fire(burning, delta)
	queue_redraw()


## Flame and soot particles from every burning puff, plus one light that
## follows the fire and grows with it.
func _emit_fire(burning: Array, delta: float) -> void:
	var centre := Vector2.ZERO
	for b in burning:
		var fuel: float = b[8]
		var r: float = b[2]
		var at := to_global(b[0])
		centre += at
		var n: float = flame_rate * delta * fuel * clampf(r / 45.0, 0.5, 2.0) + randf()
		for i in int(n):
			var o := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * r * 0.65
			var v := Vector2(randf_range(-30.0, 30.0), randf_range(-140.0, -50.0)) + (b[1] as Vector2) * 0.5
			_fire.emit(at + o, v, r * randf_range(0.4, 0.75) * (0.5 + 0.5 * fuel), randf_range(0.35, 0.65))
		if randf() < soot_rate * delta * 3.0:
			_soot.emit(at + Vector2(randf_range(-r, r) * 0.4, -r * 0.3), Vector2(randf_range(-15, 15), -60.0),
				r * randf_range(0.8, 1.3), randf_range(1.2, 2.0))
	if burning.is_empty():
		_light.energy = move_toward(_light.energy, 0.0, delta * 6.0)
	else:
		_light.global_position = centre / burning.size()
		_light.energy = minf(0.4 + 0.08 * burning.size(), 1.2)
		_light.texture_scale = clampf(2.0 + burning.size() * 0.3, 2.0, 8.0)


func _burn(burning: Array) -> void:
	if _damage_t <= 0.0:
		_damage_t = damage_tick
		var pl := get_tree().get_first_node_in_group("player")
		if pl and pl.has_method("take_damage"):
			var o := to_local(pl.global_position)
			for b in burning:
				if (b[0] as Vector2).distance_to(o) <= b[2] * 0.75:
					pl.take_damage(burn_damage, to_global(b[0]), 140.0)
					break
	if _paint_t <= 0.0:
		_paint_t = paint_tick
		var world := get_parent()
		for i in mini(3, burning.size()):
			var b: Array = burning.pick_random()
			var pick := PaintPicker.pick(world, to_global(b[0]))
			if not pick.is_empty():
				Paint.hit(self, pick["layer"], pick["local"], burn_radius, burn_strength, Paint.Kind.BURN, &"smoke")


func _draw() -> void:
	var tex := FxLib.glow()
	for p in _puffs:
		var age: float = p[4]
		var life: float = p[5]
		var a := clampf(age / 0.5, 0.0, 1.0) * (1.0 - clampf((age - (life - 1.6)) / 1.6, 0.0, 1.0))
		var fuel: float = p[8]
		var r: float = p[2] * (0.55 + 0.45 * fuel)
		var wob := Vector2(sin(_time * 0.7 + p[11]), cos(_time * 0.6 + p[11] * 1.3)) * r * 0.06
		var col: Color = smoke_color
		if p[7] == BURNING:
			# lit from inside and thinning as the fire eats it
			col = smoke_color.darkened(0.6).lerp(Color(0.45, 0.14, 0.05), 0.2)
			a *= fuel
		col.a = 0.72 * a
		var s := r * 2.6
		draw_texture_rect(tex, Rect2(p[0] + wob - Vector2(s, s) * 0.5, Vector2(s, s)), false, col)
