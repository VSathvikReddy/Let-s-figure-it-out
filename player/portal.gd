class_name VoidBrush
extends Node2D

signal veil_opened
signal veil_closed

@export var start_radius := 140.0        # screen px
@export var disk_width := 70.0
@export var max_veil_alpha := 0.6
@export var hide_material: ShaderMaterial
@export var dim_material: ShaderMaterial

@onready var brush: Node2D = $Wand
@onready var rect: ColorRect = $Veil/VeilRect
@onready var mat := rect.material as ShaderMaterial
@onready var edge_rect: ColorRect = $Veil/EdgeRect
@onready var player := $".."
@onready var collision_polygon_2d: CollisionPolygon2D = $"../BrushAttack/HurtBox/CollisionPolygon2D"

var _closing := false
var _brush_rest: Vector2
var _center := Vector2.ZERO     # world position the effect is locked to
var active := false
var _veil_amount := 0.0
var _tween: Tween
var _saved := {}                # node -> original material


func _ready() -> void:
	_brush_rest = brush.position
	rect.visible = false
	edge_rect.visible = false

func _process(_d: float) -> void:
	if active:
		_update_center()

func _zoom() -> float:
	return get_viewport().get_canvas_transform().get_scale().x


func _update_center() -> void:
	var screen_pos := get_viewport().get_canvas_transform() * _center
	var vp := get_viewport().get_visible_rect().size
	mat.set_shader_parameter("center_px", screen_pos)
	mat.set_shader_parameter("viewport_size", vp)
	RenderingServer.global_shader_parameter_set("veil_center", screen_pos)
	RenderingServer.global_shader_parameter_set("veil_viewport", vp)


func _max_radius() -> float:
	var vp := get_viewport().get_visible_rect().size
	var c := get_viewport().get_canvas_transform() * _center
	var r := 0.0
	for corner in [Vector2.ZERO, Vector2(vp.x, 0), Vector2(0, vp.y), vp]:
		r = maxf(r, c.distance_to(corner))
	return r + 30.0     # core is a perfect circle, so only a small margin is needed


# ---- tween setters (tween_method passes the value first, bound args after) ----
func _set_u(value, param: String) -> void:
	mat.set_shader_parameter(param, value)

func _on_sweep(v: float) -> void:
	mat.set_shader_parameter("sweep", v)
	# brush tip travels around the circle as it "paints" it
	brush.global_position = _center + Vector2.UP.rotated(v * TAU) * (start_radius / _zoom())
	brush.rotation = v * TAU

func _on_veil_amount(v: float) -> void:
	_veil_amount = v
	mat.set_shader_parameter("veil_alpha", v * max_veil_alpha)
	RenderingServer.global_shader_parameter_set("veil_amount", v)

func _on_veil_radius(r: float) -> void:
	mat.set_shader_parameter("veil_radius", r)
	RenderingServer.global_shader_parameter_set("veil_reach", r)

func activate() -> void:
	await player._settle()
	player.fast_gravity = 0.0
	collision_polygon_2d.set_deferred("disabled", true)
	get_tree().paused = true
	if active:
		return
	active = true
	_center = global_position
	rect.visible = true
	edge_rect.visible = true
	_update_center()
	_apply_materials()

	var max_r := _max_radius()
	var pad := disk_width * 0.5      # veil sits just inside the disk's glow

	# Reset state
	mat.set_shader_parameter("disk_width", disk_width)
	mat.set_shader_parameter("sweep", 0.0)
	mat.set_shader_parameter("hole_radius", start_radius)
	mat.set_shader_parameter("disk_fade", 1.0)
	_on_veil_radius(0.0)
	_on_veil_amount(0.0)

	if _tween: _tween.kill()
	_tween = create_tween()

	# PHASE 1: brush paints the sector: fill + disk reveal together
	_tween.tween_method(_on_sweep, 0.0, 1.0, 0.9)

	# PHASE 2: EXPAND. Hole grows, veil grows just under its edge and fades in
	_tween.tween_method(_set_u.bind("hole_radius"), start_radius, max_r, 1.6)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_method(_on_veil_radius, start_radius + pad, max_r + pad, 1.6)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_method(_on_veil_amount, 0.0, 1.0, 1.6)

	# Brief moment where the screen is fully black
	_tween.tween_interval(0.2)

	# PHASE 3: CLOSE. The black hole shrinks back; the veil is already under it,
	# so the area it leaves behind is revealed as the translucent veil.
	_tween.tween_method(_set_u.bind("hole_radius"), max_r, 0.0, 1.2)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_method(_set_u.bind("disk_fade"), 1.0, 0.0, 0.4).set_delay(0.8)

	# PHASE 4: lock the veil over the whole screen permanently
	_tween.tween_callback(_on_veil_radius.bind(100000.0))
	_tween.tween_callback(veil_opened.emit)
	_tween.tween_property(brush, "position", _brush_rest, 0.3)
	_tween.parallel().tween_property(brush, "rotation", 0.0, 0.3)
	await _tween.finished
	player.fast_gravity = 900.00

func deactivate() -> void:
	await player._settle()
	player.fast_gravity = 0.0
	collision_polygon_2d.set_deferred("disabled", false)
	get_tree().paused = false
	if not active or _closing:
		return
	_closing = true
	if _tween: _tween.kill()

	# Re-center the hole on the weapon's current position
	_center = global_position
	_update_center()

	var max_r := _max_radius()
	var pad := disk_width * 0.5

	# Start a fresh hole; the veil stays fully covering the screen underneath it
	mat.set_shader_parameter("disk_width", disk_width)
	mat.set_shader_parameter("sweep", 0.0)
	mat.set_shader_parameter("hole_radius", start_radius)
	mat.set_shader_parameter("disk_fade", 1.0)
	_on_veil_radius(100000.0)
	_on_veil_amount(1.0)

	_tween = create_tween()

	# PHASE 1: brush sweeps the black sector + paint again
	_tween.tween_method(_on_sweep, 0.0, 1.0, 0.9)

	# PHASE 2: hole expands until the whole screen is black
	_tween.tween_method(_set_u.bind("hole_radius"), start_radius, max_r, 1.4)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	# Screen is fully black here, so swap everything back unseen
	_tween.tween_callback(_reveal_normal_scene)
	_tween.tween_interval(0.2)

	# PHASE 3: hole shrinks, revealing the normal scene (no veil, original materials)
	_tween.tween_method(_set_u.bind("hole_radius"), max_r, 0.0, 1.2)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_method(_set_u.bind("disk_fade"), 1.0, 0.0, 0.4).set_delay(0.8)

	# Return the brush to the hand, then clean up
	_tween.tween_property(brush, "position", _brush_rest, 0.3)
	_tween.parallel().tween_property(brush, "rotation", 0.0, 0.3)
	_tween.tween_callback(_cleanup)
	await _tween.finished
	player.fast_gravity = 900.00

# Runs while the screen is fully covered by the black hole
func _reveal_normal_scene() -> void:
	_on_veil_amount(0.0)
	_on_veil_radius(0.0)
	_restore_materials()

func _cleanup() -> void:
	_closing = false
	active = false
	rect.visible = false
	edge_rect.visible = false
	_on_veil_radius(0.0)
	_restore_materials()
	brush.position = _brush_rest
	brush.rotation = 0.0
	veil_closed.emit()

func _apply_materials() -> void:
	for n in get_tree().get_nodes_in_group("veil_hide"):
		if n is CanvasItem and hide_material:
			_saved[n] = n.material
			n.material = hide_material
	for n in get_tree().get_nodes_in_group("veil_dim"):
		if n is CanvasItem and dim_material:
			_saved[n] = n.material
			n.material = dim_material

func _restore_materials() -> void:
	for n in _saved:
		if is_instance_valid(n):
			n.material = _saved[n]
	_saved.clear()
