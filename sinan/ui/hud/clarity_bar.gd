extends Control
## Painting clarity bar (top centre): how much of the painting is restored,
## averaged over every distortion layer. Added by hud.gd; drawn in code.
## Polls Paint.clarity() a few times a second and eases toward it.

@export var bar_size := Vector2(360, 10)
@export var top_margin := 18.0
@export var poll_interval := 0.25
@export var low_color := Color(0.55, 0.32, 0.5)
@export var high_color := Color(1.0, 0.85, 0.4)
@export var back_color := Color(0.05, 0.04, 0.08, 0.7)

var _target := 0.0
var _shown := -1.0
var _poll := 0.0
var _flash := 0.0
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	size = get_viewport_rect().size
	_poll -= delta
	if _poll <= 0.0:
		_poll = poll_interval
		var c := Paint.clarity(self)
		if _shown >= 0.0 and absf(c - _target) > 0.002:
			_flash = 1.0
		_target = c
	if _shown < 0.0:
		_shown = _target
	_shown = lerpf(_shown, _target, 1.0 - exp(-6.0 * delta))
	_flash = move_toward(_flash, 0.0, delta * 2.5)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var r := Rect2(Vector2((w - bar_size.x) * 0.5, top_margin), bar_size)
	draw_rect(r.grow(3.0), back_color)
	var fill := r
	fill.size.x = r.size.x * clampf(_shown, 0.0, 1.0)
	var col := low_color.lerp(high_color, clampf(_shown, 0.0, 1.0))
	draw_rect(fill, col.lightened(0.35 * _flash))
	# a soft highlight along the top of the fill
	draw_rect(Rect2(fill.position, Vector2(fill.size.x, 2.0)), Color(1, 1, 1, 0.25 + 0.3 * _flash))
	var text := "PAINTING  %d%%" % roundi(_shown * 100.0)
	var fs := 13
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := Vector2((w - tw) * 0.5, r.end.y + 16.0)
	draw_string(_font, tp + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7))
	draw_string(_font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.95, 0.85).lerp(Color.WHITE, _flash))
