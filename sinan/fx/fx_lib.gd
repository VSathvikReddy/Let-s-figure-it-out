extends RefCounted
## Code-built visual effect helpers. No sprite assets: every texture here is a
## generated gradient, so effects keep working when art is swapped later.

static var _glow: GradientTexture2D
static var _puff: GradientTexture2D
static var _streak: GradientTexture2D
static var _add_mat: CanvasItemMaterial
static var _shrink: Curve
static var _grow: Curve


# ---------------------------------------------------------------- resources

static func gradient(stops: Array) -> Gradient:
	## stops: [[offset, Color], ...]
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(s[1])
	var g := Gradient.new()
	g.offsets = offs
	g.colors = cols
	return g


static func _radial(w: int, h: int, stops: Array) -> GradientTexture2D:
	var t := GradientTexture2D.new()
	t.gradient = gradient(stops)
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = w
	t.height = h
	return t


## Soft round light/glow. 128px; PointLight2D.texture_scale 1.0 = 64px radius.
static func glow() -> GradientTexture2D:
	if _glow == null:
		_glow = _radial(128, 128, [
			[0.0, Color(1, 1, 1, 1)],
			[0.35, Color(1, 1, 1, 0.45)],
			[1.0, Color(1, 1, 1, 0)],
		])
	return _glow


## Round smoke/fire blob, 64px.
static func puff() -> GradientTexture2D:
	if _puff == null:
		_puff = _radial(64, 64, [
			[0.0, Color(1, 1, 1, 1)],
			[0.55, Color(1, 1, 1, 0.7)],
			[1.0, Color(1, 1, 1, 0)],
		])
	return _puff


## Thin vertical streak for sparks (long axis = local Y, use align_y).
static func streak() -> GradientTexture2D:
	if _streak == null:
		_streak = _radial(6, 40, [
			[0.0, Color(1, 1, 1, 1)],
			[0.6, Color(1, 1, 1, 0.6)],
			[1.0, Color(1, 1, 1, 0)],
		])
	return _streak


static func additive() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat


static func shrink() -> Curve:
	if _shrink == null:
		_shrink = Curve.new()
		_shrink.add_point(Vector2(0.0, 1.0))
		_shrink.add_point(Vector2(1.0, 0.0))
	return _shrink


static func grow() -> Curve:
	if _grow == null:
		_grow = Curve.new()
		_grow.add_point(Vector2(0.0, 0.3))
		_grow.add_point(Vector2(0.3, 0.8))
		_grow.add_point(Vector2(1.0, 1.0))
	return _grow


static func fire_ramp() -> Gradient:
	return gradient([
		[0.0, Color(1.0, 0.96, 0.75, 1.0)],
		[0.25, Color(1.0, 0.55, 0.12, 0.95)],
		[0.65, Color(0.55, 0.14, 0.05, 0.6)],
		[1.0, Color(0.1, 0.05, 0.05, 0.0)],
	])


static func spark_ramp() -> Gradient:
	return gradient([
		[0.0, Color(1.0, 1.0, 0.8, 1.0)],
		[0.4, Color(1.0, 0.65, 0.2, 1.0)],
		[1.0, Color(0.8, 0.2, 0.05, 0.0)],
	])


static func smoke_ramp(alpha := 0.55) -> Gradient:
	return gradient([
		[0.0, Color(0.42, 0.38, 0.4, alpha)],
		[0.5, Color(0.25, 0.23, 0.26, alpha * 0.7)],
		[1.0, Color(0.12, 0.12, 0.14, 0.0)],
	])


static func dust_ramp() -> Gradient:
	return gradient([
		[0.0, Color(0.85, 0.78, 0.68, 0.55)],
		[1.0, Color(0.6, 0.55, 0.5, 0.0)],
	])


# ---------------------------------------------------------------- emitters

## Build a CPUParticles2D from a loose option dictionary (see defaults below).
static func emitter(o: Dictionary) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	var one_shot: bool = o.get("one_shot", true)
	p.one_shot = one_shot
	p.explosiveness = o.get("explosiveness", 0.95 if one_shot else 0.0)
	p.amount = o.get("amount", 16)
	p.lifetime = o.get("life", 0.6)
	p.lifetime_randomness = o.get("life_rand", 0.3)
	p.local_coords = false
	p.texture = o.get("texture", puff())
	p.direction = o.get("direction", Vector2.UP)
	p.spread = o.get("spread", 180.0)
	p.initial_velocity_min = o.get("v_min", 50.0)
	p.initial_velocity_max = o.get("v_max", 150.0)
	p.gravity = o.get("gravity", Vector2.ZERO)
	p.damping_min = o.get("damp_min", 0.0)
	p.damping_max = o.get("damp_max", 0.0)
	p.scale_amount_min = o.get("s_min", 0.5)
	p.scale_amount_max = o.get("s_max", 1.0)
	p.scale_amount_curve = o.get("curve", shrink())
	p.angle_min = o.get("angle_min", 0.0)
	p.angle_max = o.get("angle_max", 360.0)
	p.angular_velocity_min = o.get("spin_min", -90.0)
	p.angular_velocity_max = o.get("spin_max", 90.0)
	p.color_ramp = o.get("ramp", fire_ramp())
	p.particle_flag_align_y = o.get("align", false)
	p.radial_accel_min = o.get("radial_min", 0.0)
	p.radial_accel_max = o.get("radial_max", 0.0)
	p.tangential_accel_min = o.get("tangent_min", 0.0)
	p.tangential_accel_max = o.get("tangent_max", 0.0)
	var emit_radius: float = o.get("emit_radius", 0.0)
	if emit_radius > 0.0:
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = emit_radius
	if o.get("additive", false):
		p.material = additive()
	return p


## Two-stop colour fade: c at full alpha -> c transparent (optionally via a mid colour).
static func fade_ramp(c: Color, mid := Color(0, 0, 0, 0)) -> Gradient:
	var a := Color(c, 1.0)
	var z := Color(c, 0.0)
	if mid.a > 0.0:
		return gradient([[0.0, Color(1, 1, 1, 1)], [0.25, a], [0.6, Color(mid, 0.8)], [1.0, Color(mid, 0.0)]])
	return gradient([[0.0, Color(1, 1, 1, 1)], [0.3, a], [1.0, z]])


## Convert a global position into parent's local space (for placing a node
## before add_child, so it never exists at the origin for a frame).
static func to_parent_space(parent: Node, global_pos: Vector2) -> Vector2:
	if parent is Node2D:
		return (parent as Node2D).to_local(global_pos)
	return global_pos


## Shrink an emitter option dict for effects happening "deep" in the painting.
## Defaults mirror emitter()'s.
static func scaled(o: Dictionary, s: float) -> Dictionary:
	if is_equal_approx(s, 1.0):
		return o
	var r := o.duplicate()
	r["v_min"] = o.get("v_min", 50.0) * s
	r["v_max"] = o.get("v_max", 150.0) * s
	r["s_min"] = o.get("s_min", 0.5) * s
	r["s_max"] = o.get("s_max", 1.0) * s
	r["gravity"] = o.get("gravity", Vector2.ZERO) * s
	r["damp_min"] = o.get("damp_min", 0.0) * s
	r["damp_max"] = o.get("damp_max", 0.0) * s
	return r


## Add a one-shot emitter to the world at pos and let it clean itself up.
static func spawn(parent: Node, p: CPUParticles2D, pos: Vector2, rot := 0.0) -> CPUParticles2D:
	p.position = to_parent_space(parent, pos)
	# Rotate the emission direction rather than the node, so gravity stays
	# pointing down even when particles simulate in local space.
	p.direction = p.direction.rotated(rot)
	# Inside a painting layer: simulate in the layer's space so the particles
	# scroll with the parallax instead of sliding off the background.
	if parent is Parallax2D:
		p.local_coords = true
	parent.add_child(p)
	if p.one_shot:
		p.finished.connect(p.queue_free)
	return p


static func flash_light(parent: Node, pos: Vector2, color: Color, energy: float, size: float, time: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = glow()
	l.color = color
	l.energy = energy
	l.texture_scale = size
	l.position = to_parent_space(parent, pos)
	parent.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "energy", 0.0, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(l, "texture_scale", size * 1.4, time)
	tw.chain().tween_callback(l.queue_free)
	return l


# ---------------------------------------------------------------- recipes

static func muzzle(parent: Node, pos: Vector2, dir: Vector2) -> void:
	var rot := dir.angle()
	spawn(parent, emitter({
		"amount": 14, "life": 0.25, "v_min": 300.0, "v_max": 750.0, "spread": 22.0,
		"direction": Vector2.RIGHT, "texture": streak(), "align": true,
		"angle_min": 0.0, "angle_max": 0.0, "spin_min": 0.0, "spin_max": 0.0,
		"s_min": 0.4, "s_max": 0.9, "additive": true, "ramp": spark_ramp(),
		"damp_min": 200.0, "damp_max": 450.0,
	}), pos, rot)
	spawn(parent, emitter({
		"amount": 8, "life": 0.18, "v_min": 40.0, "v_max": 160.0, "spread": 35.0,
		"direction": Vector2.RIGHT, "s_min": 0.4, "s_max": 0.9, "additive": true,
	}), pos, rot)
	spawn(parent, emitter({
		"amount": 10, "life": 0.6, "v_min": 60.0, "v_max": 190.0, "spread": 38.0,
		"direction": Vector2.RIGHT, "ramp": smoke_ramp(), "s_min": 0.25, "s_max": 0.6,
		"curve": grow(), "gravity": Vector2(0, -30), "damp_min": 40.0, "damp_max": 90.0,
	}), pos, rot)
	flash_light(parent, pos, Color(1.0, 0.7, 0.3), 2.5, 2.2, 0.18)


## Small bullet hit: a spray of sparks along the surface normal, a puff, a blink of light.
## s < 1 shrinks the whole effect for hits deep in the painting.
static func impact_small(parent: Node, pos: Vector2, normal: Vector2, s := 1.0) -> void:
	var rot := normal.angle()
	spawn(parent, emitter(scaled({
		"amount": 10, "life": 0.25, "v_min": 150.0, "v_max": 520.0, "spread": 60.0,
		"direction": Vector2.RIGHT, "texture": streak(), "align": true,
		"angle_min": 0.0, "angle_max": 0.0, "spin_min": 0.0, "spin_max": 0.0,
		"s_min": 0.25, "s_max": 0.6, "additive": true, "ramp": spark_ramp(),
		"gravity": Vector2(0, 700),
	}, s)), pos, rot)
	spawn(parent, emitter(scaled({
		"amount": 4, "life": 0.4, "v_min": 20.0, "v_max": 70.0, "spread": 50.0,
		"direction": Vector2.RIGHT, "ramp": smoke_ramp(0.4), "s_min": 0.15, "s_max": 0.35,
		"curve": grow(),
	}, s)), pos, rot)
	flash_light(parent, pos, Color(1.0, 0.75, 0.4), 1.5, 1.0 * s, 0.1)


## Pistol muzzle: smaller flash, no smoke cloud.
static func muzzle_small(parent: Node, pos: Vector2, dir: Vector2) -> void:
	spawn(parent, emitter({
		"amount": 6, "life": 0.12, "v_min": 200.0, "v_max": 500.0, "spread": 18.0,
		"direction": Vector2.RIGHT, "texture": streak(), "align": true,
		"angle_min": 0.0, "angle_max": 0.0, "spin_min": 0.0, "spin_max": 0.0,
		"s_min": 0.25, "s_max": 0.5, "additive": true, "ramp": spark_ramp(),
	}), pos, dir.angle())
	flash_light(parent, pos, Color(1.0, 0.8, 0.45), 1.4, 1.2, 0.08)


## Spent brass flipping out of the ejection port.
static func casing(parent: Node, pos: Vector2, aim: Vector2) -> void:
	var back := -signf(aim.x) if aim.x != 0.0 else -1.0
	spawn(parent, emitter({
		"amount": 1, "life": 0.7, "life_rand": 0.0, "texture": null, "curve": null,
		"direction": Vector2(back * 0.45, -1.0).normalized(), "spread": 15.0,
		"v_min": 160.0, "v_max": 240.0, "gravity": Vector2(0, 1100),
		"s_min": 3.0, "s_max": 3.0, "spin_min": 500.0, "spin_max": 900.0,
		"ramp": gradient([[0.0, Color(1.0, 0.8, 0.35, 1.0)], [0.8, Color(0.85, 0.6, 0.25, 1.0)], [1.0, Color(0.85, 0.6, 0.25, 0.0)]]),
	}), pos)


static func dust(parent: Node, pos: Vector2, amount := 8, strength := 1.0) -> void:
	spawn(parent, emitter({
		"amount": amount, "life": 0.45, "v_min": 30.0 * strength, "v_max": 130.0 * strength,
		"spread": 75.0, "direction": Vector2.UP, "ramp": dust_ramp(),
		"s_min": 0.15, "s_max": 0.4, "curve": grow(), "damp_min": 120.0, "damp_max": 240.0,
	}), pos)
