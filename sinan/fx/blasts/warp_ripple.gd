extends Node2D
## Subtle distortion "warp": one or two refraction rings that ripple out and
## bend the painting, plus a faint tint. Small on purpose (the black hole in
## black_hole.gd is kept for bigger moments later).

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const SHADER := preload("res://sinan/shaders/warp_ripple.gdshader")

var radius := 80.0
var duration := 0.6
## How far the image bends (fraction of the size).
var amplitude := 0.045
var rings := 2
var ring_delay := 0.12
var tint := Color(0.75, 0.9, 1.0)

var _t := 0.0
var _sprites: Array[Sprite2D] = []
var _mats: Array[ShaderMaterial] = []


func _ready() -> void:
	z_index = 0 if get_parent() is Parallax2D else 3
	for i in maxi(rings, 1):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("amplitude", amplitude)
		var s := Sprite2D.new()
		s.texture = FxLib.glow()
		s.scale = Vector2.ONE * radius * 2.0 / 128.0
		s.material = m
		s.visible = false
		add_child(s)
		_sprites.append(s)
		_mats.append(m)


func _process(delta: float) -> void:
	_t += delta
	var alive := false
	for i in _sprites.size():
		var k := (_t - i * ring_delay) / duration
		var on := k >= 0.0 and k <= 1.0
		_sprites[i].visible = on
		if on:
			alive = true
			_mats[i].set_shader_parameter("progress", 1.0 - pow(1.0 - k, 2.0))
	queue_redraw()
	if not alive and _t > duration:
		queue_free()


func _draw() -> void:
	var k := clampf(_t / duration, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius * 0.5 * (1.0 - k), Color(tint, 0.12 * (1.0 - k)))
