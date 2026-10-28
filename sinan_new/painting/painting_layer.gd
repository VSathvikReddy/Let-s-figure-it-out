@tool  # also runs in the editor, so the detail levels line up while you edit
extends Parallax2D
## One layer of the painting (sky, hill or village). Put this on a Parallax2D.
##
## Its child Sprite2Ds are the SAME picture at different detail levels:
## first child = most broken, last child = the full painting.
##
## A small grey image, the "mask", stores how damaged each spot is:
## 0 = perfect, 1 = fully broken. The shader on each sprite hides that
## sprite where the damage is too high, so a less detailed one shows through.

const CELL := 4.0  # one mask pixel covers 4x4 picture pixels

## How damaged the layer is when the game starts (0 to 1).
@export var start_damage := 0.75

var sprites: Array[Sprite2D] = []
var mask: Image                 # the damage numbers - we change these
var mask_texture: ImageTexture  # the same numbers, sent to the shader
var picture: Image              # pixels of the full painting, to find transparent spots


func _ready() -> void:
	_fit_sprites()
	if Engine.is_editor_hint():
		return  # in the editor we only line the sprites up
	var full := sprites[-1]
	picture = full.texture.get_image()

	# make the mask: one grey pixel per CELL x CELL picture pixels
	var size := Vector2i(full.texture.get_size() / CELL)
	mask = Image.create_empty(size.x, size.y, false, Image.FORMAT_R8)
	mask.fill(Color(start_damage, 0, 0))
	mask_texture = ImageTexture.create_from_image(mask)

	var levels := sprites.size() - 1
	for i in sprites.size():
		var sprite := sprites[i]
		sprite.material = ShaderMaterial.new()
		sprite.material.shader = preload("res://sinan_new/painting/painting_layer.gdshader")
		sprite.material.set_shader_parameter("mask", mask_texture)
		# the first sprite never hides; more detailed ones hide sooner
		var hide_above := 2.0 if i == 0 else (levels - i + 0.5) / levels
		sprite.material.set_shader_parameter("hide_above", hide_above)


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


## Is there paint (not a transparent pixel) at this world point?
func has_paint_at(world_point: Vector2) -> bool:
	var full := sprites[-1]
	var pixel := Vector2i(full.to_local(world_point) - full.get_rect().position)
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= picture.get_width() or pixel.y >= picture.get_height():
		return false
	return picture.get_pixelv(pixel).a > 0.2


## Add damage (amount > 0) or repair (amount < 0) under one collision shape.
## `offset` moves the shape before stamping (zero = stamp where it is).
func stamp(shape_node: CollisionShape2D, offset: Vector2, amount: float) -> void:
	if sprites.size() < 2:
		return  # only one detail level: nothing to show or hide
	var full := sprites[-1]

	# a square around the shape, in mask pixels, so we only check pixels near it
	var center := shape_node.global_position + offset
	var radius := shape_node.shape.get_rect().size.length() / 2.0 * shape_node.global_scale.x
	var corner_a := _world_to_mask(center - Vector2(radius, radius))
	var corner_b := _world_to_mask(center + Vector2(radius, radius))

	for y in range(maxi(0, corner_a.y), mini(mask.get_height(), corner_b.y + 1)):
		for x in range(maxi(0, corner_a.x), mini(mask.get_width(), corner_b.x + 1)):
			# where is this mask pixel in the world, and in the shape's own space?
			var world := full.to_global((Vector2(x, y) + Vector2(0.5, 0.5)) * CELL + full.get_rect().position)
			var in_shape := shape_node.to_local(world - offset)
			if _is_inside(shape_node.shape, in_shape):
				var damage := mask.get_pixel(x, y).r + amount
				mask.set_pixel(x, y, Color(clampf(damage, 0.0, 1.0), 0, 0))

	mask_texture.update(mask)  # send the new numbers to the shader


func _world_to_mask(world: Vector2) -> Vector2i:
	var full := sprites[-1]
	return Vector2i((full.to_local(world) - full.get_rect().position) / CELL)


## Is a point (in the shape's own space) inside the shape?
func _is_inside(shape: Shape2D, point: Vector2) -> bool:
	if shape is CircleShape2D:
		return point.length() <= shape.radius
	if shape is RectangleShape2D:
		return absf(point.x) <= shape.size.x / 2 and absf(point.y) <= shape.size.y / 2
	return shape.get_rect().has_point(point)  # any other shape: its bounding box
