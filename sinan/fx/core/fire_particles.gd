extends Node2D
## A pooled particle system for fire (and its soot), drawn in one batch.
## Particles live in WORLD space, so the node can sit anywhere; it never moves
## them with itself. Each particle swells, rises (buoyancy), slows down and
## runs through the colour ramp: white-hot -> yellow -> orange -> deep red ->
## gone. Additive for flames, normal blending for soot.
##
##   var fire := FireParticles.new()            # add_child(fire)
##   fire.emit(world_pos, velocity, size, life)

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")

@export var additive := true
@export var max_particles := 1600
## Upward pull (px/s^2) - hot gas rises.
@export var buoyancy := 260.0
## Velocity lost per second.
@export var drag := 2.6
## Colour over life (0 = born, 1 = dead).
@export var ramp: Gradient

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _tex: Texture2D
var _drawn := false   # something is on screen from the last draw


func _ready() -> void:
	top_level = true          # draw in world space, whatever the parent does
	global_position = Vector2.ZERO
	_tex = FxLib.glow()
	if additive:
		material = FxLib.additive()
	if ramp == null:
		ramp = flame_ramp() if additive else soot_ramp()


static func flame_ramp() -> Gradient:
	return FxLib.gradient([
		[0.0, Color(1.0, 0.85, 0.55, 0.55)], [0.15, Color(1.0, 0.6, 0.18, 0.7)],
		[0.45, Color(0.9, 0.28, 0.06, 0.55)], [0.75, Color(0.5, 0.08, 0.03, 0.3)],
		[1.0, Color(0.2, 0.04, 0.02, 0.0)]])


static func soot_ramp() -> Gradient:
	return FxLib.gradient([
		[0.0, Color(0.15, 0.1, 0.1, 0.0)], [0.2, Color(0.14, 0.11, 0.12, 0.45)],
		[1.0, Color(0.2, 0.18, 0.2, 0.0)]])


func emit(at: Vector2, vel: Vector2, size: float, life: float) -> void:
	if _pos.size() >= max_particles:
		return
	_pos.append(at)
	_vel.append(vel)
	_age.append(0.0)
	_life.append(maxf(life, 0.05))
	_size.append(size)


func count() -> int:
	return _pos.size()


func _process(delta: float) -> void:
	if _pos.is_empty():
		if _drawn:
			_drawn = false
			queue_redraw()  # clear the last frame once, then sleep
		return
	_drawn = true
	global_position = Vector2.ZERO
	var keep := 1.0 - exp(-drag * delta)
	var i := 0
	while i < _pos.size():
		_age[i] += delta
		if _age[i] >= _life[i]:
			# swap-remove
			var last := _pos.size() - 1
			_pos[i] = _pos[last]; _vel[i] = _vel[last]; _age[i] = _age[last]
			_life[i] = _life[last]; _size[i] = _size[last]
			_pos.resize(last); _vel.resize(last); _age.resize(last); _life.resize(last); _size.resize(last)
			continue
		var v := _vel[i]
		v -= v * keep
		v.y -= buoyancy * delta
		_vel[i] = v
		_pos[i] += v * delta
		i += 1
	queue_redraw()


func _draw() -> void:
	for i in _pos.size():
		var k := _age[i] / _life[i]
		# swell quickly, then shrink away
		var s := _size[i] * (0.45 + 0.9 * sqrt(minf(k * 3.0, 1.0))) * (1.0 - 0.5 * k)
		var c := ramp.sample(k)
		draw_texture_rect(_tex, Rect2(_pos[i] - Vector2(s, s) * 0.5, Vector2(s, s)), false, c)
