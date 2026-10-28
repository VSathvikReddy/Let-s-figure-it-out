@tool
extends Polygon2D
## A sprite that moves like hanging cloth: the texture is cut into a grid,
## the top row is pinned at `pivot`, and every row below swings on its own
## spring, so the hem lags behind the motion, overshoots and settles, and a
## soft wave ripples down it. Used for the priest's robe, sleeves and stole.
##
## In a scene: set Texture, Pivot (where it hangs from, in texture pixels),
## Cols / Rows - it builds itself and shows in the editor. Flare and Bias can
## be keyed in an AnimationPlayer. The owner calls drive() every frame:
##   cloth.drive(velocity_x_in_facing_space, delta)

## Where the cloth hangs from (texture pixels). The node's origin sits here.
@export var pivot := Vector2.ZERO:
	set(v):
		pivot = v
		_setup()
@export_range(1, 12) var cols := 3:
	set(v):
		cols = v
		_setup()
@export_range(1, 16) var rows := 6:
	set(v):
		rows = v
		_setup()
## 0..1+: blow the hem outward / upward (bursts, casting). Animatable.
@export var flare := 0.0
## Extra sideways push at the hem (texture px), e.g. blown back. Animatable.
@export var bias := 0.0

@export_group("Cloth")
## Sideways swing per px/s of the owner's velocity (texture px), at the hem.
@export var drag_amount := 0.22
## Spring stiffness / damping of each row.
@export var stiffness := 60.0
@export var damping := 7.0
## Idle ripple: amplitude at the hem (texture px), speed, and wavelength in rows.
@export var wave_amount := 6.0
@export var wave_speed := 2.4
@export var wave_rows := 3.0
## How much the hem lags compared to rows near the top (curve exponent).
@export var falloff := 1.4

var _size := Vector2.ONE
var _x := PackedFloat32Array()
var _v := PackedFloat32Array()
var _t := 0.0
var _built_for: Texture2D


func _ready() -> void:
	_setup()


func _setup() -> void:
	if texture == null or not is_inside_tree():
		return
	_built_for = texture
	_size = texture.get_size()
	var c := maxi(cols, 1)
	var r := maxi(rows, 1)
	_x.resize(r + 1)
	_v.resize(r + 1)
	_x.fill(0.0)
	_v.fill(0.0)
	_t = randf() * 10.0
	var uvs := PackedVector2Array()
	for y in r + 1:
		for x in c + 1:
			uvs.append(Vector2(_size.x * x / c, _size.y * y / r))
	uv = uvs
	var polys := []
	for y in r:
		for x in c:
			var i := y * (c + 1) + x
			polys.append(PackedInt32Array([i, i + 1, i + c + 2, i + c + 1]))
	polygons = polys
	_rebuild()


## Swing the cloth from the owner's movement (velocity in the cloth's own
## horizontal direction, so pass it already flipped for the facing).
func drive(local_velocity_x: float, delta: float) -> void:
	if texture != _built_for:
		_setup()
	if _x.size() < rows + 1:
		return
	_t += delta
	for r in range(1, rows + 1):
		var k := pow(float(r) / rows, falloff)
		var wave := sin(_t * wave_speed - r / maxf(wave_rows, 0.1)) * wave_amount * k
		var target := (-local_velocity_x * drag_amount + bias) * k + wave
		_v[r] += ((target - _x[r]) * stiffness - _v[r] * damping) * delta
		_x[r] += _v[r] * delta
	_rebuild()


func _process(_delta: float) -> void:
	# in the editor: follow keyed flare / bias so the pose previews correctly
	if Engine.is_editor_hint():
		if texture != _built_for:
			_setup()
		_rebuild()


func _rebuild() -> void:
	if _x.size() < rows + 1:
		return
	var pts := PackedVector2Array()
	for r in rows + 1:
		var k := float(r) / rows
		var f := flare * pow(k, 1.6)
		var b := bias * pow(k, falloff) if Engine.is_editor_hint() else 0.0
		for c in cols + 1:
			var u := float(c) / cols
			var p := Vector2(_size.x * u, _size.y * k) - pivot
			# flare: spread out from the centre line and lift the hem
			p.x += (u - 0.5) * _size.x * 0.45 * f
			p.y -= _size.y * 0.12 * f
			p.x += _x[r] + b
			pts.append(p)
	polygon = pts
