extends RefCounted
## Small helpers every object in this level uses, so the same code is not
## copied into every script.
##
## Use it like this:
##     const Effects := preload("res://compined/common/effects.gd")
##     Effects.play_sound(self, my_sound)
##     Effects.burst(self, 30, Color.ORANGE)
##     Effects.paint(my_area, -3)
##     Effects.rpg_explosion(self, 140.0)

const EXPLOSION := preload("res://compined/common/explosion.gd")


## Plays a sound where `from` is. The sound keeps playing even if `from` is
## deleted right after (a dying enemy, a collected gem).
static func play_sound(from: Node2D, sound: AudioStream, volume_db := 0.0) -> void:
	if sound == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = sound
	player.volume_db = volume_db
	from.get_tree().current_scene.add_child(player)
	player.global_position = from.global_position
	player.play()
	player.finished.connect(player.queue_free)


## A one-time explosion of particles where `from` is.
static func burst(from: Node2D, count: int, color: Color, lifetime := 0.5,
		speed_min := 100.0, speed_max := 240.0, size_min := 4.0, size_max := 8.0) -> void:
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0     # all particles at once
	particles.amount = count
	particles.lifetime = lifetime
	particles.spread = 180.0          # in every direction
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = speed_min
	particles.initial_velocity_max = speed_max
	particles.scale_amount_min = size_min
	particles.scale_amount_max = size_max
	particles.color_ramp = fade_out(color)
	from.get_tree().current_scene.add_child(particles)
	particles.global_position = from.global_position
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


## A fire-and-smoke explosion (used by the bomber, the bat and its fireball).
static func fire_explosion(from: Node2D, big := true) -> void:
	var size := 1.0 if big else 0.75
	burst(from, int(40 * size), Color(1.0, 0.6, 0.1), 0.5, 120.0 * size, 280.0 * size)
	burst(from, int(16 * size), Color(0.25, 0.25, 0.25, 0.8), 0.9, 30.0, 90.0, 8.0, 14.0)


## A big RPG-style explosion (flash, shockwave, fireball, sparks, debris,
## embers, smoke and a camera shake). `radius` = how far the shockwave reaches.
static func rpg_explosion(from: Node2D, radius := 150.0, fire_color := Color(1.0, 0.55, 0.15)) -> void:
	var explosion = EXPLOSION.new()
	explosion.radius = radius
	explosion.fire_color = fire_color
	from.get_tree().current_scene.add_child(explosion)
	explosion.global_position = from.global_position


## A trail of particles that follows `owner` (and stays in the world, so it
## leaves a streak behind). Turn it on and off with `trail.emitting`.
static func make_trail(owner: Node2D, color: Color, amount := 20, lifetime := 0.45) -> CPUParticles2D:
	var trail := CPUParticles2D.new()
	trail.local_coords = false
	trail.emitting = false
	trail.amount = amount
	trail.lifetime = lifetime
	trail.spread = 180.0
	trail.gravity = Vector2.ZERO
	trail.initial_velocity_min = 5.0
	trail.initial_velocity_max = 20.0
	trail.scale_amount_min = 2.0
	trail.scale_amount_max = 4.0
	trail.color_ramp = fade_out(color)
	trail.z_index = -1
	owner.add_child(trail)
	return trail


## Lets a trail finish fading after its owner is deleted.
static func leave_trail_behind(trail: CPUParticles2D) -> void:
	trail.emitting = false
	trail.reparent(trail.get_tree().current_scene)
	trail.get_tree().create_timer(trail.lifetime).timeout.connect(trail.queue_free)


## A colour that fades to transparent (for particles).
static func fade_out(color: Color) -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, color)
	gradient.set_color(1, Color(color, 0.0))
	return gradient


## Paints the level's painting inside `area`.
## count > 0 brings the painting's detail back, count < 0 breaks it.
static func paint(area: Area2D, count: int) -> void:
	var painting := area.get_tree().get_first_node_in_group("painting")
	if painting:
		painting.paint(area, count)


## Paints a circle of the painting around `world_position` (no Area2D needed).
## count > 0 brings detail back, count < 0 smudges it.
## Safe to call anywhere, also from inside physics callbacks (body_entered).
static func paint_circle(from: Node, world_position: Vector2, radius: float, count: int) -> void:
	var painting := from.get_tree().get_first_node_in_group("painting")
	if painting:
		painting.paint_circle(world_position, radius, count)


## The level bounds (the painting's edges) in the world, or an empty Rect2.
static func level_rect(from: Node) -> Rect2:
	var bounds := from.get_tree().get_first_node_in_group("level_bounds") as Control
	return bounds.get_global_rect() if bounds else Rect2()


## Keeps `node` inside the level, at least `margin` px from the edges.
## Returns how far it was pushed back (zero if it was already inside), so the
## caller can turn around when it hits an edge.
static func keep_inside_level(node: Node2D, margin := 0.0) -> Vector2:
	var rect := level_rect(node)
	if rect.size == Vector2.ZERO:
		return Vector2.ZERO
	var inside := rect.grow(-margin)
	var clamped := node.global_position.clamp(inside.position, inside.end)
	var push := clamped - node.global_position
	node.global_position = clamped
	return push


## True if a world position is inside the level (true when there are no bounds).
static func is_inside_level(from: Node, world_position: Vector2) -> bool:
	var rect := level_rect(from)
	return rect.size == Vector2.ZERO or rect.has_point(world_position)
