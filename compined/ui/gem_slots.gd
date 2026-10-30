extends HBoxContainer
## The gem counter: one slot per gem to find. A slot shows its gem as a dark
## shadow until that gem is collected, then it lights up with a little pop.
## Set the pictures in the Inspector (one per slot, in order).

## The gem shown in each slot (blue, green, star, violet...).
@export var gem_pictures: Array[Texture2D] = []
## Size of each gem on screen, in px.
@export var slot_size := 34.0
## Colour of a gem that is not found yet.
@export var shadow_color := Color(0.0, 0.0, 0.0, 0.5)

var _slots: Array[TextureRect] = []
var _found: Array[bool] = []


## Makes `count` slots (the pictures repeat if there are more slots than pictures).
func setup(count: int) -> void:
	for slot in _slots:
		slot.queue_free()
	_slots.clear()
	_found.clear()
	for i in count:
		var slot := TextureRect.new()
		slot.custom_minimum_size = Vector2(slot_size, slot_size)
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not gem_pictures.is_empty():
			slot.texture = gem_pictures[i % gem_pictures.size()]
		slot.modulate = shadow_color
		add_child(slot)
		_slots.append(slot)
		_found.append(false)


## A gem was collected: light up its slot (the slot with the same picture, or
## else the first one still dark).
func light_up(picture: Texture2D = null) -> void:
	var index := -1
	for i in _slots.size():
		if not _found[i] and picture != null and _slots[i].texture == picture:
			index = i
			break
	if index < 0:
		index = _found.find(false)
	if index < 0:
		return   # all lit already
	_found[index] = true
	var slot := _slots[index]
	if picture:
		slot.texture = picture
	# pop: flash bright, grow, settle
	slot.pivot_offset = slot.size / 2.0
	slot.modulate = Color(2.5, 2.5, 2.5)
	slot.scale = Vector2.ONE * 1.6
	var pop := create_tween().set_parallel()
	pop.tween_property(slot, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(slot, "modulate", Color.WHITE, 0.35)
