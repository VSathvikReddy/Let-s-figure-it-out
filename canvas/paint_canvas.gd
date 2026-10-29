extends Node
## AUTOLOAD (Project Settings -> Globals -> Autoload, name it "PaintMask").
## Do NOT give this script a class_name.
##
## The one global canvas everything paints on.
## Black (0) = untouched, white (255) = fully broken, stored as integers.
## Nothing can paint until setup(reference, steps) is called: steps starts at 0.

signal configured   ## emitted by setup()/reset-by-setup, painters re-read `steps`

var steps := 0              ## hits from perfect to fully broken. 0 = painting disabled
var step := 0               ## brightness added per hit (integer, 255 / steps)
var size := Vector2i(1, 1)
var data := PackedByteArray()
var mask: Image
var texture: ImageTexture   ## the same object for the whole game, canvases just sample it
var reference: Sprite2D     ## says where the picture sits in the world (given to setup())


func _init() -> void:
	mask = Image.create_from_data(1, 1, false, Image.FORMAT_R8, PackedByteArray([0]))
	texture = ImageTexture.create_from_image(mask)
	data = PackedByteArray([0])


## Turn painting on.
## p_reference = the Sprite2D that shows the full picture; it says where the painting is in the world.
## p_steps = hits from perfect to most broken (e.g. 4 for 5 sprites).
## p_size = mask resolution; leave at zero to derive it from the picture size / cell_size.
func setup(p_reference: Sprite2D, p_steps: int, p_size := Vector2i.ZERO, cell_size := 4.0) -> void:
	if not is_instance_valid(p_reference) or p_reference.texture == null:
		push_error("PaintMask.setup needs a Sprite2D with a texture as reference")
		return
	reference = p_reference
	steps = clampi(p_steps, 0, 255)
	step = 0 if steps == 0 else int(floor(255.0 / steps))
	if p_size == Vector2i.ZERO:
		p_size = Vector2i((reference.texture.get_size() / cell_size).ceil())
	size = p_size
	data = PackedByteArray()
	data.resize(size.x * size.y)   # zeros = black
	_upload(true)
	configured.emit()


func reset() -> void:
	data.fill(0)
	_upload(false)


func can_paint() -> bool:
	return steps > 0 and is_instance_valid(reference)


## count > 0 breaks, count < 0 repairs. Does nothing until setup() was called.
func paint(area: Area2D, count: int = 1) -> void:
	if not can_paint():
		return
	var dirty := false
	for c in area.get_children():
		if c is CollisionShape2D and not c.disabled and c.shape != null:
			dirty = _stamp(c, count) or dirty
		elif c is CollisionPolygon2D and not c.disabled:
			dirty = _stamp_polygon(c, count) or dirty
	if dirty:
		_upload(false)


func _upload(new_size: bool) -> void:
	mask = Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, data)
	if new_size:
		texture.set_image(mask)   # size may have changed
	else:
		texture.update(mask)


func _stamp(node: CollisionShape2D, count: int) -> bool:
	var shape := node.shape
	var half: Vector2
	if shape is CircleShape2D:
		half = Vector2.ONE * shape.radius
	elif shape is RectangleShape2D:
		half = shape.size / 2.0
	else:
		return false

	var s := node.global_scale.abs()
	var reach := half.length() * maxf(s.x, s.y)
	var c := node.global_position
	var p1 := _world_to_mask(c - Vector2(reach, reach))
	var p2 := _world_to_mask(c + Vector2(reach, reach))
	var lo := p1.min(p2)
	var hi := p1.max(p2)
	var x0 := clampi(floori(lo.x), 0, size.x - 1)
	var x1 := clampi(ceili(hi.x), 0, size.x - 1)
	var y0 := clampi(floori(lo.y), 0, size.y - 1)
	var y1 := clampi(ceili(hi.y), 0, size.y - 1)

	var changed := false
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if _inside(node, shape, _mask_to_world(Vector2(x + 0.5, y + 0.5))):
				var i := y * size.x + x
				data[i] = clampi(data[i] + count * step, 0, 255)
				changed = true
	return changed


func _stamp_polygon(node: CollisionPolygon2D, count: int) -> bool:
	var pts := node.polygon
	if pts.size() < 3:
		return false

	# bounding box of the polygon, in mask pixels
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		var m := _world_to_mask(node.to_global(p))
		lo = lo.min(m)
		hi = hi.max(m)
	var x0 := clampi(floori(lo.x), 0, size.x - 1)
	var x1 := clampi(ceili(hi.x), 0, size.x - 1)
	var y0 := clampi(floori(lo.y), 0, size.y - 1)
	var y1 := clampi(ceili(hi.y), 0, size.y - 1)

	var changed := false
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var local := node.to_local(_mask_to_world(Vector2(x + 0.5, y + 0.5)))
			if Geometry2D.is_point_in_polygon(local, pts):
				var i := y * size.x + x
				data[i] = clampi(data[i] + count * step, 0, 255)
				changed = true
	return changed


func _inside(node: CollisionShape2D, shape: Shape2D, world: Vector2) -> bool:
	var p := node.to_local(world)
	if shape is CircleShape2D:
		return p.length() <= shape.radius
	var h: Vector2 = shape.size / 2.0
	return absf(p.x) <= h.x and absf(p.y) <= h.y


func _world_to_mask(world: Vector2) -> Vector2:
	var r := reference.get_rect()
	return (reference.to_local(world) - r.position) / r.size * Vector2(size)


func _mask_to_world(m: Vector2) -> Vector2:
	var r := reference.get_rect()
	return reference.to_global(r.position + m / Vector2(size) * r.size)
