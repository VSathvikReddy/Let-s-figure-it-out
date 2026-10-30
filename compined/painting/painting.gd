@tool  # also runs in the editor, so you see the pictures stretched while you work
extends Node2D
## The painting behind the level.
##
## It is made of several pictures of the SAME painting, from crude to detailed
## (the Sprite2D children; AnimatedSprite2D children work too, for a moving
## painting).
## A hidden "mask" remembers, for every small square of the painting, how
## detailed it is right now. The shader mixes the pictures using that mask.
##
##   - The brush paints the mask brighter  -> more detail comes back.
##   - Bombs, bullets and fireballs paint it darker -> it becomes crude again.
##
## Children order: MOST DETAILED picture first, CRUDEST picture last.
## The last child is the one you see; the others only lend their pictures.
##
## SIZE: the FIRST child is the "root" picture. With match_benchmark_area on
## (the default) it is scaled automatically so every painting covers the same
## area as The Starry Night. Turn that off to scale it by hand (Transform).
## Every other picture copies the root: same place, and stretched to exactly
## the root's size on screen, so the other detail levels can be any size.
## The level reads world_rect() to build the camera bounds, so changing the
## root picture changes the level size too.
##
## Anything can paint with:  Effects.paint(some_area2d, amount)

const SHADER := preload("res://compined/painting/painting.gdshader")
const MAX_PICTURES := 8          # the shader has room for 8 pictures

## Benchmark: The Starry Night (1680 x 1050 picture at scale 2).
const BENCHMARK_SIZE := Vector2(3360, 2100)

## On: the root picture is scaled so the painting covers the SAME AREA as the
## benchmark (keeping its own shape). Every level is then equally big, so the
## player looks the same size everywhere and only the camera zoom changes that.
## Off: the root picture keeps the scale you give it in the Inspector.
@export var match_benchmark_area := true

@export var blur := 1.5          ## softens the mask edges (in mask squares)
@export var square_size := 4.0   ## size of one mask square, in picture pixels

var pictures: Array[Node2D] = []   # Sprite2D or AnimatedSprite2D
var shown: Node2D                # the picture you actually see (the last child)
var material_for_shown: ShaderMaterial

# --- the mask ---
var steps := 0                   # hits from crudest to fully detailed
var step_value := 0              # how much one hit adds (0..255)
var mask_size := Vector2i.ONE
var mask_data := PackedByteArray()
var mask_texture: ImageTexture


func _ready() -> void:
	add_to_group("painting")
	_find_pictures()
	_stretch_pictures()
	set_process(Engine.is_editor_hint())   # _process only re-stretches in the editor
	if Engine.is_editor_hint():
		return   # in the editor only the stretching is needed
	if pictures.size() < 2 or pictures.size() > MAX_PICTURES:
		push_warning("Painting needs between 2 and %d Sprite2D children" % MAX_PICTURES)
		return

	shown = pictures[-1]
	_create_mask()
	_create_material()

	for picture in pictures:
		if picture != shown:
			picture.visible = false   # only lends its picture to the shader
			if picture is AnimatedSprite2D:
				picture.stop()        # its frame follows the shown picture
	if shown is AnimatedSprite2D:
		shown.frame_changed.connect(_send_frames_to_shader)
		shown.animation_changed.connect(_send_frames_to_shader)
	_send_frames_to_shader()


## Keeps the stretching up to date while you edit (swap a picture and see it).
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_find_pictures()
		_stretch_pictures()


## The root picture's rectangle in the world. The level builds its camera
## bounds from this.
func world_rect() -> Rect2:
	if pictures.is_empty():
		_find_pictures()
	var root := root_picture()
	if root == null or _texture_of(root) == null:
		return Rect2()
	var size := _texture_of(root).get_size()
	return root.get_global_transform() * Rect2(-size / 2.0, size)


## How detailed the painting is at a world position:
## 0 = crudest, 1 = fully restored. Outside the painting it returns 1.
func detail_at(world: Vector2) -> float:
	if steps == 0:
		return 1.0
	var square := Vector2i(_world_to_mask(world).floor())
	if square.x < 0 or square.y < 0 or square.x >= mask_size.x or square.y >= mask_size.y:
		return 1.0
	return mask_data[square.y * mask_size.x + square.x] / 255.0


## The first picture: it sets the size of the whole painting.
func root_picture() -> Node2D:
	return pictures[0] if not pictures.is_empty() else null


## Paints the mask inside a circle in the world (no shapes or physics needed).
## count > 0 brings detail back, count < 0 removes it.
func paint_circle(world_center: Vector2, radius: float, count: int) -> void:
	if steps == 0:
		return
	var reach := Vector2(radius, radius)
	var changed := false
	for square in _squares_between(_world_to_mask(world_center - reach), _world_to_mask(world_center + reach)):
		if _mask_to_world(Vector2(square) + Vector2(0.5, 0.5)).distance_to(world_center) <= radius:
			_add_to_square(square, count)
			changed = true
	if changed:
		mask_texture.update(_mask_image())


## Paints the mask inside every collision shape of `area`.
## count > 0 brings detail back, count < 0 removes it.
func paint(area: Area2D, count: int) -> void:
	if steps == 0:
		return
	var changed := false
	for child in area.get_children():
		if child is CollisionShape2D and not child.disabled and child.shape:
			changed = _paint_shape(child, count) or changed
		elif child is CollisionPolygon2D and not child.disabled:
			changed = _paint_polygon(child, count) or changed
	if changed:
		mask_texture.update(_mask_image())


# ---------------------------------------------------------------- setup

func _find_pictures() -> void:
	pictures.clear()
	for child in get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			pictures.append(child)


## The root picture is left exactly as you set it. Every other picture is
## placed on top of it and stretched to cover exactly the same area.
func _stretch_pictures() -> void:
	var root := root_picture()
	if root == null or _texture_of(root) == null:
		return
	if match_benchmark_area:
		var picture_size := _texture_of(root).get_size()
		var area_scale := sqrt((BENCHMARK_SIZE.x * BENCHMARK_SIZE.y) / (picture_size.x * picture_size.y))
		root.scale = Vector2(area_scale, area_scale)
	var root_size_on_screen := _texture_of(root).get_size() * root.scale
	for picture in pictures:
		var texture := _texture_of(picture)
		if picture == root or texture == null:
			continue
		picture.position = root.position
		picture.rotation = root.rotation
		picture.centered = true
		picture.offset = Vector2.ZERO
		picture.scale = root_size_on_screen / texture.get_size()

func _create_mask() -> void:
	steps = pictures.size()
	step_value = int(255.0 / steps)
	mask_size = Vector2i((_shown_texture().get_size() / square_size).ceil())
	mask_data = PackedByteArray()
	mask_data.resize(mask_size.x * mask_size.y)   # all zero = crudest
	mask_texture = ImageTexture.create_from_image(_mask_image())


func _create_material() -> void:
	material_for_shown = ShaderMaterial.new()
	material_for_shown.shader = SHADER
	material_for_shown.set_shader_parameter("mask", mask_texture)
	material_for_shown.set_shader_parameter("max_level", float(pictures.size() - 1))
	material_for_shown.set_shader_parameter("step_value", step_value / 255.0)
	material_for_shown.set_shader_parameter("blur", blur)
	shown.material = material_for_shown


## Gives the shader the current picture (or animation frame) of every child.
func _send_frames_to_shader() -> void:
	for i in pictures.size():
		var picture := pictures[i]
		if picture is AnimatedSprite2D and picture != shown and picture.sprite_frames:
			var frame_count: int = picture.sprite_frames.get_frame_count(picture.animation)
			if frame_count > 0:
				picture.frame = shown.frame % frame_count   # pictures with fewer frames loop
		material_for_shown.set_shader_parameter("lvl%d" % i, _texture_of(picture))


func _mask_image() -> Image:
	return Image.create_from_data(mask_size.x, mask_size.y, false, Image.FORMAT_R8, mask_data)


func _shown_texture() -> Texture2D:
	return _texture_of(shown)


func _texture_of(picture: Node2D) -> Texture2D:
	if picture is AnimatedSprite2D:
		if picture.sprite_frames == null:
			return null
		return picture.sprite_frames.get_frame_texture(picture.animation, picture.frame)
	return picture.texture


# ---------------------------------------------------------------- painting

func _paint_shape(node: CollisionShape2D, count: int) -> bool:
	var shape := node.shape
	var half_size: Vector2
	if shape is CircleShape2D:
		half_size = Vector2.ONE * shape.radius
	elif shape is RectangleShape2D:
		half_size = shape.size / 2.0
	else:
		return false   # other shapes are not supported

	# only look at the mask squares near the shape
	var reach := half_size.length() * maxf(node.global_scale.abs().x, node.global_scale.abs().y)
	var corner_a := _world_to_mask(node.global_position - Vector2(reach, reach))
	var corner_b := _world_to_mask(node.global_position + Vector2(reach, reach))
	var changed := false
	for square in _squares_between(corner_a, corner_b):
		var point := node.to_local(_mask_to_world(Vector2(square) + Vector2(0.5, 0.5)))
		var inside: bool
		if shape is CircleShape2D:
			inside = point.length() <= shape.radius
		else:
			inside = absf(point.x) <= half_size.x and absf(point.y) <= half_size.y
		if inside:
			_add_to_square(square, count)
			changed = true
	return changed


func _paint_polygon(node: CollisionPolygon2D, count: int) -> bool:
	var points := node.polygon
	if points.size() < 3:
		return false
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for p in points:
		var m := _world_to_mask(node.to_global(p))
		low = low.min(m)
		high = high.max(m)
	var changed := false
	for square in _squares_between(low, high):
		var point := node.to_local(_mask_to_world(Vector2(square) + Vector2(0.5, 0.5)))
		if Geometry2D.is_point_in_polygon(point, points):
			_add_to_square(square, count)
			changed = true
	return changed


## Every mask square inside the box from `a` to `b` (clamped to the mask).
func _squares_between(a: Vector2, b: Vector2) -> Array[Vector2i]:
	var low := a.min(b)
	var high := a.max(b)
	var x_from := clampi(floori(low.x), 0, mask_size.x - 1)
	var x_to := clampi(ceili(high.x), 0, mask_size.x - 1)
	var y_from := clampi(floori(low.y), 0, mask_size.y - 1)
	var y_to := clampi(ceili(high.y), 0, mask_size.y - 1)
	var squares: Array[Vector2i] = []
	for y in range(y_from, y_to + 1):
		for x in range(x_from, x_to + 1):
			squares.append(Vector2i(x, y))
	return squares


func _add_to_square(square: Vector2i, count: int) -> void:
	var i := square.y * mask_size.x + square.x
	mask_data[i] = clampi(mask_data[i] + count * step_value, 0, 255)


# ---------------------------------------------------------------- positions

## The shown picture's rectangle, in its own local space.
func _picture_rect() -> Rect2:
	var size := _shown_texture().get_size()
	var top_left: Vector2 = shown.offset - (size / 2.0 if shown.centered else Vector2.ZERO)
	return Rect2(top_left, size)


func _world_to_mask(world: Vector2) -> Vector2:
	var rect := _picture_rect()
	return (shown.to_local(world) - rect.position) / rect.size * Vector2(mask_size)


func _mask_to_world(mask_point: Vector2) -> Vector2:
	var rect := _picture_rect()
	return shown.to_global(rect.position + mask_point / Vector2(mask_size) * rect.size)
