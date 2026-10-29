@tool  # also runs in the editor, so the detail levels line up while you edit
extends Parallax2D
## One layer of the painting (sky, hill or village). Put this on a Parallax2D.
##
## Its child Sprite2Ds are the SAME picture at different detail levels:
## first child = most broken, last child = the full painting (2 to 8 sprites).
##
## A small grey image, the "mask", stores how damaged each spot is:
## 0 = perfect, 1 = fully broken. Only the full-painting sprite is drawn; its
## shader reads the mask and shows, at each spot, the two detail levels the
## damage falls between, mixed. The other sprites only lend their pictures.

const CELL := 4.0       # one mask pixel covers 4x4 picture pixels
const MAX_LEVELS := 8   # the shader has room for 8 pictures

## How damaged the layer is when the game starts (0 to 1).
@export var start_damage := 0.75
## How far (in mask pixels) the edges of the damage are smeared.
@export var blur := 6.0

var sprites: Array[Sprite2D] = []
var mask: Image                 # the damage numbers - we change these
var mask_texture: ImageTexture  # the same numbers, sent to the shader


func _ready() -> void:
	_fit_sprites()
	if Engine.is_editor_hint() or sprites.is_empty():
		return  # in the editor we only line the sprites up
	var full := sprites[-1]
	if sprites.size() < 2 or sprites.size() > MAX_LEVELS:
		push_warning("%s needs 2 to %d sprites to be paintable" % [name, MAX_LEVELS])
		return

	# make the mask: one pixel per CELL x CELL picture pixels.
	# FORMAT_RF keeps a whole float per pixel, so even tiny steps add up exactly.
	var size := Vector2i(full.texture.get_size() / CELL)
	mask = Image.create_empty(size.x, size.y, false, Image.FORMAT_RF)
	mask.fill(Color(start_damage, 0, 0))
	mask_texture = ImageTexture.create_from_image(mask)

	var material := ShaderMaterial.new()
	material.shader = preload("res://sinan_new/painting/painting_layer.gdshader")
	material.set_shader_parameter("mask", mask_texture)
	material.set_shader_parameter("max_level", float(sprites.size() - 1))
	material.set_shader_parameter("blur", blur)
	for i in sprites.size():
		material.set_shader_parameter("lvl%d" % i, sprites[i].texture)
		sprites[i].visible = sprites[i] == full  # the others only lend their picture
	full.material = material


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_fit_sprites()  # keep them lined up when you add or change a sprite


## Make every detail level sit exactly on top of the full painting (the last
## child), whatever size its image is: same position, stretched to the same size.
func _fit_sprites() -> void:
	sprites.clear()
	for child in get_children():
		if child is Sprite2D and child.texture:
			sprites.append(child)
	if sprites.is_empty():
		return
	var full := sprites[-1]
	for sprite in sprites:
		sprite.position = full.position
		sprite.scale = full.texture.get_size() * full.scale / sprite.texture.get_size()


## Add damage (amount > 0) or repair (amount < 0) under one shape: a
## CollisionShape2D (circle or rectangle) or a CollisionPolygon2D (any shape).
## amount 1.0 = one detail level. `offset` moves the shape before stamping.
func stamp(shape_node: Node2D, offset: Vector2, amount: float) -> void:
	if mask == null:
		return  # this layer can't be damaged

	# the shape's outline, in mask pixels
	var outline := _outline(shape_node, offset)
	if outline.size() < 3:
		return

	# the rows of mask pixels the outline covers
	var top := INF
	var bottom := -INF
	for point in outline:
		top = minf(top, point.y)
		bottom = maxf(bottom, point.y)
	var y0 := maxi(0, floori(top))
	var y1 := mini(mask.get_height() - 1, ceili(bottom))

	var step := amount / (sprites.size() - 1)  # 1.0 = one detail level
	for y in range(y0, y1 + 1):
		# where does this row (through the pixel middles) cross the outline?
		var row := y + 0.5
		var crossings: Array[float] = []
		for i in outline.size():
			var a := outline[i]
			var b := outline[(i + 1) % outline.size()]
			if (a.y <= row) != (b.y <= row):
				crossings.append(a.x + (row - a.y) / (b.y - a.y) * (b.x - a.x))
		crossings.sort()
		# the row is inside the shape between crossing 1 and 2, 3 and 4, ...
		for k in range(0, crossings.size() - 1, 2):
			var x0 := maxi(0, ceili(crossings[k] - 0.5))
			var x1 := mini(mask.get_width() - 1, floori(crossings[k + 1] - 0.5))
			for x in range(x0, x1 + 1):
				var damage := mask.get_pixel(x, y).r + step
				mask.set_pixel(x, y, Color(clampf(damage, 0.0, 1.0), 0, 0))

	mask_texture.update(mask)  # send the new numbers to the shader


## Any shape as a list of corner points, in mask pixels.
## (A circle becomes a 32-sided polygon - close enough at this size.)
func _outline(shape_node: Node2D, offset: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	if shape_node is CollisionPolygon2D:
		points = shape_node.polygon
	elif shape_node is CollisionShape2D and shape_node.shape is CircleShape2D:
		for i in 32:
			points.append(Vector2.from_angle(TAU * i / 32) * shape_node.shape.radius)
	elif shape_node is CollisionShape2D and shape_node.shape != null:
		var r: Rect2 = shape_node.shape.get_rect()  # rectangle (other shapes: their bounding box)
		points = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])

	var outline := PackedVector2Array()
	for point in points:
		outline.append(_world_to_mask(shape_node.to_global(point) + offset))
	return outline


func _world_to_mask(world: Vector2) -> Vector2:
	var full := sprites[-1]
	return (full.to_local(world) - full.get_rect().position) / CELL
