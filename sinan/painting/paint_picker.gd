extends RefCounted
## Finds which painting layer (a Parallax2D under the level) is under a world
## point. Layers are tested nearest-first and a layer only "catches" the shot
## where its sprite pixel is opaque, so you can shoot past the village into the
## hills or sky. Depth comes from scroll_scale.x, read live every call.

## Shot scale at scroll_scale.x = 0 (infinitely far, e.g. the sky).
const FAR_SCALE := 0.45

static var _images := {}


## Returns {} if no layer is under the point, else
## {layer: Parallax2D, local: Vector2 (layer space), scale: float, scroll: float}.
static func pick(root: Node, world_pos: Vector2) -> Dictionary:
	var layers: Array[Parallax2D] = []
	for c in root.get_children():
		if c is Parallax2D:
			layers.append(c)
	layers.sort_custom(func(a: Parallax2D, b: Parallax2D) -> bool: return a.scroll_scale.x > b.scroll_scale.x)

	var fallback := {}
	for layer in layers:
		var local := layer.to_local(world_pos)
		for s in layer.get_children():
			if not (s is Sprite2D) or s.texture == null:
				continue
			var hit := _sprite_hit(layer, s, local)
			if hit < 0:
				continue
			var res := {"layer": layer, "local": local, "scale": depth_scale(layer.scroll_scale.x), "scroll": layer.scroll_scale.x}
			if hit == 1:
				return res
			fallback = res  # transparent pixel: remember the farthest layer that contains it
	return fallback


## scroll_scale.x (0 = far .. 1 = studio plane) -> on-screen shot scale.
## sqrt spreads small scroll values apart (0.05 and 0.1 look clearly different).
static func depth_scale(scroll: float) -> float:
	return lerpf(FAR_SCALE, 1.0, sqrt(clampf(scroll, 0.0, 1.0)))


## -1 = outside, 0 = inside but transparent, 1 = opaque pixel.
static func _sprite_hit(layer: Parallax2D, s: Sprite2D, layer_local: Vector2) -> int:
	var reps := layer.repeat_times if layer.repeat_size != Vector2.ZERO else 0
	var r := s.get_rect()
	var result := -1
	for k in range(-reps, reps + 1):
		var p := s.transform.affine_inverse() * (layer_local - layer.repeat_size * k)
		if not r.has_point(p):
			continue
		var img := _image(s.texture)
		if img == null:
			return 1
		var px := Vector2i((p - r.position).floor()).clamp(Vector2i.ZERO, img.get_size() - Vector2i.ONE)
		if s.flip_h:
			px.x = img.get_width() - 1 - px.x
		if s.flip_v:
			px.y = img.get_height() - 1 - px.y
		if img.get_pixelv(px).a > 0.2:
			return 1
		result = 0
	return result


static func _image(tex: Texture2D) -> Image:
	if not _images.has(tex):
		var img := tex.get_image()
		if img and img.is_compressed():
			img.decompress()
		_images[tex] = img
	return _images[tex]
