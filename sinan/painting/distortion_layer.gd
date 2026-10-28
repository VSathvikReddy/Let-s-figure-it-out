extends Parallax2D
## Distortion for one painting layer (attach to a Parallax2D).
## Children Sprite2Ds are the same picture at different detail levels, stacked
## in tree order: LAST child = full painting (on top, fades first), FIRST child =
## most abstract (bottom, never fades). Hits raise a soft damage mask; each
## sprite fades out where the mask passes its threshold, revealing the next one.
## Each weapon sets its own impact radius and strength in its scene's inspector.

const SHADER := preload("res://sinan/shaders/distortion_layer.gdshader")

## Texture pixels of the top sprite per mask texel (lower = sharper, costlier).
@export var mask_cell := 4.0
## Global toughness: full-strength hits on the same spot needed to peel one
## detail level. (Hit radius/strength are set per weapon in its inspector.)
@export var hits_per_layer := 1.0
## Inner part of the hit that gets the full amount; outside it fades to 0.
@export_range(0.0, 0.95) var hit_core := 0.3
@export var softness := 0.06
@export var edge_noise := 0.05

@export_group("Start State")
## Name of the detail level (child Sprite2D) shown across the WHOLE canvas when
## the level starts, e.g. "40". Restore shots then bring it back one level at a
## time (40 -> 60 -> 80 -> 100). Empty = start with the full painting.
@export var start_level := "40"
@export_group("")

var _sprites: Array[Sprite2D] = []
var _ref: Sprite2D
var _mask: Image
var _tex: ImageTexture
var _size := Vector2i.ZERO
var _amount := 0.25
var _sum := 0.0       # running total of the mask (0..1 per texel), for mean()
var _dirty := false   # mask changed this frame; uploaded once in _process


func _ready() -> void:
	add_to_group("painting")
	for c in get_children():
		if c is Sprite2D and c.texture:
			_sprites.append(c)
	if _sprites.size() < 2:
		push_warning("%s: distortion needs at least 2 Sprite2D children" % name)
		return
	_ref = _sprites[-1]
	_fit_to_reference()

	var ref_px := _ref.texture.get_size()
	_size = Vector2i(ceili(ref_px.x / mask_cell), ceili(ref_px.y / mask_cell))
	_mask = Image.create_empty(_size.x, _size.y, false, Image.FORMAT_R8)
	_tex = ImageTexture.create_from_image(_mask)

	# n removable levels; with amount 1/n per hit, each hit at the centre peels one.
	var n := _sprites.size() - 1
	_amount = 1.0 / (n * maxf(hits_per_layer, 0.01))
	var thresholds: Array[float] = []
	for i in _sprites.size():
		var k := n - i  # 0 = top sprite
		thresholds.append(2.0 if i == 0 else (k + 0.6) / n)
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("mask", _tex)
		mat.set_shader_parameter("threshold", thresholds[i])
		mat.set_shader_parameter("softness", softness)
		mat.set_shader_parameter("edge_noise", edge_noise)
		_sprites[i].material = mat
	_apply_start_level(thresholds)


## Fill the whole mask with one value that sits halfway between the start
## level's threshold and the one above it, so exactly that level shows everywhere.
func _apply_start_level(thresholds: Array[float]) -> void:
	if start_level.is_empty():
		return
	var idx := -1
	for i in _sprites.size():
		if String(_sprites[i].name) == start_level:
			idx = i
	if idx < 0:
		push_warning("%s: start_level '%s' is not a child Sprite2D" % [name, start_level])
		return
	if idx == _sprites.size() - 1:
		return  # the full painting: mask stays clean
	var upper := thresholds[idx + 1]
	var lower := 1.0 if idx == 0 else thresholds[idx]
	_mask.fill(Color((upper + lower) * 0.5, 0.0, 0.0))
	_tex.update(_mask)
	_recount()


## The detail levels are lower-res images; scale each to cover exactly the same
## area as the top (full) painting so the mask lines up on every level.
func _fit_to_reference() -> void:
	var ref_size := _ref.texture.get_size() * _ref.scale
	for s in _sprites:
		if s == _ref:
			continue
		s.centered = _ref.centered
		s.offset = _ref.offset * _ref.texture.get_size() / s.texture.get_size()
		s.position = _ref.position
		s.scale = ref_size / s.texture.get_size()


## Called through the "painting" group when a shot lands in the painting.
## radius (layer px) and strength (1 = one detail level) come from the weapon.
func on_paint_hit(layer: Node, local: Vector2, radius: float, strength := 1.0) -> void:
	if layer != self or _mask == null:
		return
	var uv: Variant = _to_uv(local)
	if uv != null:
		stamp(uv, radius, _amount * strength)


## Same, but from a world position (e.g. an orb that burst in the studio
## restores whatever part of this layer is behind it). Negative strength restores.
func on_paint_hit_world(world_pos: Vector2, radius: float, strength := 1.0) -> void:
	if _mask == null:
		return
	var uv: Variant = _to_uv(to_local(world_pos))
	if uv != null:
		stamp(uv, radius, _amount * strength)


## Add (or with a negative amount, remove) damage around uv (0..1 over the layer).
func stamp(uv: Vector2, radius: float, amount: float) -> void:
	var c := uv * Vector2(_size)
	var texels_per_px := Vector2(_size) / (_ref.get_rect().size * _ref.scale.abs())
	var rx := maxf(radius * texels_per_px.x, 1.0)
	var ry := maxf(radius * texels_per_px.y, 1.0)
	for y in range(maxi(0, floori(c.y - ry)), mini(_size.y, ceili(c.y + ry) + 1)):
		for x in range(maxi(0, floori(c.x - rx)), mini(_size.x, ceili(c.x + rx) + 1)):
			var d := Vector2((x + 0.5 - c.x) / rx, (y + 0.5 - c.y) / ry).length()
			if d >= 1.0:
				continue
			var f := 1.0 - smoothstep(hit_core, 1.0, d)
			var old := _mask.get_pixel(x, y).r
			var v := clampf(old + amount * f, 0.0, 1.0)
			_mask.set_pixel(x, y, Color(v, 0.0, 0.0))
			_sum += v - old
	# many hits in one frame (a bat flock, a scratch line) upload the mask once
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_tex.update(_mask)


## Mask value at a layer-space point (0 = clean, 1 = most distorted). Ghosts use
## it to hunt the cleanest parts of the painting.
func distortion_at(local: Vector2) -> float:
	if _mask == null:
		return 1.0
	var uv: Variant = _to_uv(local)
	if uv == null:
		return 1.0
	var p := Vector2i((uv as Vector2) * Vector2(_size)).clamp(Vector2i.ZERO, _size - Vector2i.ONE)
	return _mask.get_pixelv(p).r


## 0 = untouched, 1 = fully distorted. (Painting restored % = 1 - mean().)
func mean() -> float:
	if _mask == null:
		return 0.0
	return clampf(_sum / float(_size.x * _size.y), 0.0, 1.0)


func _recount() -> void:
	var total := 0
	for b in _mask.get_data():
		total += b
	_sum = total / 255.0


func _to_uv(local: Vector2) -> Variant:
	var reps := repeat_times if repeat_size != Vector2.ZERO else 0
	var r := _ref.get_rect()
	for k in range(-reps, reps + 1):
		var p := _ref.transform.affine_inverse() * (local - repeat_size * k)
		if r.has_point(p):
			return (p - r.position) / r.size
	return null
