extends Camera2D
## Put this on the player's Camera2D (centred on the body, no limits, no smoothing).
##
## Keeps the screen filled with painting, whatever shape the window is and wherever
## the player walks:
##  - the sky is a backdrop that stays on the screen (its Parallax2D scroll_scale is 0,0);
##    it is scaled up to cover the whole view, a little over
##  - the camera zooms in just enough that the hill and village strips (which slide a
##    little as the player walks) are always wider than the view

## The sky layer (a Parallax2D with scroll_scale 0,0 whose last child is the full picture).
@export var sky: NodePath = ^"../../Painting/sky"
## The strips that must stay wider than the view: layer path, how far it slides over the
## whole play area (world px).
@export var strips: Array[NodePath] = [^"../../Painting/hill", ^"../../Painting/village"]
## The zoom the camera never goes below.
@export var min_zoom := 0.7
## A little extra picture kept on every side so no edge ever shows.
@export var edge := 24.0
## Extra width a strip needs for its slide (its scroll_scale x the walk width, about 2000).
@export var strip_slide := 200.0

var _last_view := Vector2.ZERO


func _ready() -> void:
	fit()


## The window can change shape at any time (and the stretch is applied after _ready),
## so everything is re-fitted whenever the visible area changes.
func _process(_delta: float) -> void:
	if get_viewport_rect().size != _last_view:
		fit()


func fit() -> void:
	var view := get_viewport_rect().size
	_last_view = view

	# zoom: every strip must be wider than the view (plus its slide)
	var z := min_zoom
	for path in strips:
		var width := _picture_size(get_node_or_null(path)).x
		if width > 0.0:
			z = maxf(z, view.x / maxf(width - strip_slide - edge, 1.0))
	zoom = Vector2(z, z)

	# sky: a Parallax2D with scroll_scale 0 sits at (scroll_offset + camera - half the screen, in
	# screen pixels), so this scroll_offset puts the picture's centre exactly on the camera centre
	var layer := get_node_or_null(sky) as Parallax2D
	var full := _full_sprite(layer)
	if layer == null or full == null:
		return
	var picture := full.texture.get_size() * full.scale
	var view_world := view / z
	var k := maxf((view_world.x + edge) / picture.x, (view_world.y + edge) / picture.y)
	layer.scale = Vector2(k, k)
	layer.scroll_offset = view / 2.0 - full.position * k


func _full_sprite(layer: Node) -> Sprite2D:
	if layer == null:
		return null
	var found: Sprite2D = null
	for child in layer.get_children():
		if child is Sprite2D:
			found = child
	return found


## Width and height of a layer's full picture, in the layer's own units.
func _picture_size(layer: Node) -> Vector2:
	var full := _full_sprite(layer)
	return full.texture.get_size() * full.scale if full else Vector2.ZERO
