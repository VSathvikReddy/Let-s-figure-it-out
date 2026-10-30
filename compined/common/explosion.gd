extends Node2D
## A big RPG-style explosion. Create it with
##     Effects.rpg_explosion(where, radius, fire_color)
## and it plays by itself, then deletes itself.
##
## What you see, in order:
##   1. FLASH      - a blinding white disc and a burst of light (first 0.12 s)
##   2. SHOCKWAVE  - a ring that races out to `radius` and thins out
##   3. FIREBALL   - a ball of glowing fire that swells and burns out
##   4. SPARKS     - fast streaks that fly out and fall
##   5. DEBRIS     - dark chunks thrown out, tumbling down
##   6. EMBERS     - glowing bits that drift up
##   7. SMOKE      - dark smoke that rises and spreads slowly
## Plus a short camera shake.

## How far the shockwave reaches, in px (match it to the explosion's damage area).
@export var radius := 150.0
## Main colour of the fire (orange for the bomber, green for the mini bomber).
@export var fire_color := Color(1.0, 0.55, 0.15)
@export var smoke_color := Color(0.16, 0.14, 0.14, 0.85)

const FLASH_TIME := 0.12
const SHOCKWAVE_TIME := 0.45
const TOTAL_TIME := 2.2

var _age := 0.0
var _size := 1.0          # radius compared to a 150 px explosion


func _ready() -> void:
	z_index = 5
	_size = radius / 150.0
	_add_light_flash()
	_add_fireball()
	_add_sparks()
	_add_debris()
	_add_embers()
	_add_smoke()
	_shake_camera()


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _age >= TOTAL_TIME:
		queue_free()


func _draw() -> void:
	# 1. flash: a white-hot disc that grows a little and vanishes
	var flash := 1.0 - clampf(_age / FLASH_TIME, 0.0, 1.0)
	if flash > 0.0:
		draw_circle(Vector2.ZERO, radius * (0.55 + 0.25 * (1.0 - flash)), Color(1.0, 1.0, 0.92, flash))

	# 2. shockwave: a fast ring out to the full radius, and a softer one behind it
	var wave := clampf(_age / SHOCKWAVE_TIME, 0.0, 1.0)
	if wave < 1.0:
		var reach := ease(wave, 0.35)   # fast at first, slowing down
		var ring_color := Color(1.0, 0.95, 0.8).lerp(fire_color, wave)
		draw_arc(Vector2.ZERO, radius * (0.15 + 0.85 * reach), 0.0, TAU, 64,
			Color(ring_color, (1.0 - wave) * 0.9), lerpf(16.0, 2.0, wave) * _size, true)
		draw_arc(Vector2.ZERO, radius * (0.1 + 0.6 * reach), 0.0, TAU, 48,
			Color(fire_color, (1.0 - wave) * 0.35), lerpf(26.0, 4.0, wave) * _size, true)


# --- the parts ---------------------------------------------------------------

func _add_light_flash() -> void:
	var light := PointLight2D.new()
	light.texture = _soft_dot(128)
	light.texture_scale = 5.0 * _size
	light.color = fire_color.lerp(Color.WHITE, 0.5)
	light.energy = 2.5
	add_child(light)
	create_tween().tween_property(light, "energy", 0.0, 0.4).set_ease(Tween.EASE_OUT)


## The ball of fire: big soft blobs that swell, then shrink and darken.
func _add_fireball() -> void:
	var fire := _particles(int(30 * _size) + 8, 0.85, _soft_dot(64), true)
	fire.initial_velocity_min = 40.0 * _size
	fire.initial_velocity_max = 260.0 * _size
	fire.damping_min = 300.0
	fire.damping_max = 500.0
	fire.scale_amount_min = 0.7 * _size
	fire.scale_amount_max = 1.6 * _size
	fire.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(0.2, 1.0), Vector2(1, 0.0)])
	# soft colours: many glowing blobs add up, so they start pale yellow, not white
	fire.color_ramp = _ramp([Color(1.0, 0.85, 0.45, 0.7), Color(fire_color, 0.65), Color(fire_color.darkened(0.4), 0.45),
		Color(fire_color.darkened(0.7), 0.2), Color(0.1, 0.05, 0.05, 0.0)])


## Fast bright streaks that fly out and arc down.
func _add_sparks() -> void:
	var sparks := _particles(int(34 * _size) + 8, 0.7, _streak(), true)
	sparks.particle_flag_align_y = true          # stretched along the way they fly
	sparks.initial_velocity_min = 320.0 * _size
	sparks.initial_velocity_max = 700.0 * _size
	sparks.gravity = Vector2(0, 700)
	sparks.damping_min = 60.0
	sparks.damping_max = 140.0
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.0
	sparks.color_ramp = _ramp([Color(1, 1, 0.85), fire_color.lightened(0.3), Color(fire_color, 0.0)])


## Dark chunks that tumble out and fall.
func _add_debris() -> void:
	var debris := _particles(int(10 * _size) + 4, 1.1, null, false)
	debris.initial_velocity_min = 180.0 * _size
	debris.initial_velocity_max = 460.0 * _size
	debris.direction = Vector2.UP
	debris.spread = 80.0
	debris.gravity = Vector2(0, 980)
	debris.angular_velocity_min = -600.0
	debris.angular_velocity_max = 600.0
	debris.scale_amount_min = 3.0 * _size
	debris.scale_amount_max = 7.0 * _size
	debris.color_ramp = _ramp([Color(0.25, 0.18, 0.14), Color(0.12, 0.09, 0.08), Color(0.12, 0.09, 0.08, 0.0)])


## Little glowing bits that float up after the blast.
func _add_embers() -> void:
	var embers := _particles(int(24 * _size) + 6, 1.5, _soft_dot(16), true)
	embers.explosiveness = 0.7
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = radius * 0.35
	embers.initial_velocity_min = 20.0
	embers.initial_velocity_max = 90.0
	embers.gravity = Vector2(0, -110)
	embers.scale_amount_min = 0.4
	embers.scale_amount_max = 0.9
	embers.color_ramp = _ramp([fire_color.lightened(0.4), fire_color, Color(fire_color, 0.0)])


## Smoke that rises slowly and spreads out.
func _add_smoke() -> void:
	var smoke := _particles(int(20 * _size) + 8, 2.0, _soft_dot(64), false)
	smoke.explosiveness = 0.85
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = radius * 0.25
	smoke.initial_velocity_min = 20.0 * _size
	smoke.initial_velocity_max = 90.0 * _size
	smoke.damping_min = 30.0
	smoke.damping_max = 60.0
	smoke.gravity = Vector2(0, -70)
	smoke.scale_amount_min = 1.6 * _size
	smoke.scale_amount_max = 3.0 * _size
	smoke.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(1, 1.0)])   # spreads as it rises
	smoke.color_ramp = _ramp([Color(smoke_color, 0.0), smoke_color, Color(smoke_color, 0.0)])
	smoke.z_index = -1   # behind the fire


func _shake_camera() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera and camera.has_method("shake"):
		camera.shake(0.5 * _size)


# --- helpers -----------------------------------------------------------------

## A one-time burst of particles in every direction.
## `glowing` = bright colours add up (fire, sparks); off for smoke and debris.
func _particles(amount: int, lifetime: float, texture: Texture2D, glowing: bool) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = amount
	particles.lifetime = lifetime
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.texture = texture
	if glowing:
		var add_light := CanvasItemMaterial.new()
		add_light.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		particles.material = add_light
	add_child(particles)
	particles.emitting = true
	return particles


## A round soft dot, white in the middle and clear at the edge.
func _soft_dot(size: int) -> GradientTexture2D:
	var dot := GradientTexture2D.new()
	dot.width = size
	dot.height = size
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.gradient = _ramp([Color.WHITE, Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)])
	return dot


## A thin vertical line of light, used for sparks.
func _streak() -> GradientTexture2D:
	var streak := GradientTexture2D.new()
	streak.width = 4
	streak.height = 28
	streak.fill_from = Vector2(0.5, 0.0)
	streak.fill_to = Vector2(0.5, 1.0)
	streak.gradient = _ramp([Color(1, 1, 1, 0.0), Color.WHITE, Color(1, 1, 1, 0.0)])
	return streak


## A colour gradient through the given colours, evenly spaced.
func _ramp(colors: Array) -> Gradient:
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / (colors.size() - 1))
	gradient.offsets = offsets
	gradient.colors = PackedColorArray(colors)
	return gradient


func _curve(points: Array) -> Curve:
	var curve := Curve.new()
	for point in points:
		curve.add_point(point)
	return curve
