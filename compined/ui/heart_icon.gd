extends TextureRect
## One heart of the player's health. Uses the pixel heart-break animation in
## ui/hearts/ (cut from the sprite sheet): frames 0-5 the heart cracks, frames
## 6-23 it shatters into pieces.
##
##   full    - a whole heart (frame 0)
##   cracked - plays the crack and stays cracked (frame 5)
##   broken  - plays the shatter, then only a faint shadow of the heart is left

enum State { FULL, CRACKED, BROKEN }

const FRAME_COUNT := 24
const LAST_CRACK_FRAME := 5
## Frames per second of the crack and shatter animations.
const FPS := 24.0
## What is left in the slot of a broken heart.
const SHADOW := Color(0.0, 0.0, 0.0, 0.35)

static var _frames: Array[Texture2D] = []   # loaded once, shared by every heart

var state := State.FULL
var _animation: Tween


func _init() -> void:
	if _frames.is_empty():
		for i in FRAME_COUNT:
			_frames.append(load("res://compined/ui/hearts/heart_%02d.png" % i))
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp pixel art
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture = _frames[0]


## Shows how much of this heart is left: 0, part of it, or all of it.
func show_health(left: int, per_heart: int, animate := true) -> void:
	var wanted := State.FULL
	if left <= 0:
		wanted = State.BROKEN
	elif left < per_heart:
		wanted = State.CRACKED
	if wanted == state:
		return
	state = wanted
	if _animation:
		_animation.kill()
	modulate = Color.WHITE
	match wanted:
		State.FULL:
			texture = _frames[0]
		State.CRACKED:
			_play(0, LAST_CRACK_FRAME, animate)
		State.BROKEN:
			_play(LAST_CRACK_FRAME + 1, FRAME_COUNT - 1, animate)
			if animate:
				_animation.tween_callback(_leave_shadow)
			else:
				_leave_shadow()


## A quick beat (used on the last heart when health is low).
func beat() -> void:
	pivot_offset = size / 2.0
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE * 1.25, 0.1)
	tween.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _play(from_frame: int, to_frame: int, animate: bool) -> void:
	if not animate:
		texture = _frames[to_frame]
		return
	var frame_count := to_frame - from_frame + 1
	_animation = create_tween()
	_animation.tween_method(_show_frame, float(from_frame), float(to_frame) + 0.99, frame_count / FPS)


func _show_frame(frame: float) -> void:
	texture = _frames[clampi(int(frame), 0, FRAME_COUNT - 1)]


func _leave_shadow() -> void:
	texture = _frames[0]
	modulate = SHADOW
