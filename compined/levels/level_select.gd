extends Control
## The painting gallery: a carousel of cards, one per level in Levels.LIST,
## plus a last card to create your own painting (custom_level_card.gd).
##   - A / D, the arrow keys, or swiping with the mouse: move between cards
##   - "Enter Painting" on the centre card: play that level
##
## Copied from the team's levels/level_select.gd. Changes: the levels come from
## compined/levels/levels.gd, and each card shows the real painting.

const Levels := preload("res://compined/levels/levels.gd")
const CustomCard := preload("res://compined/levels/custom/custom_level_card.gd")

# Card layout (easy to tweak in the Inspector)
@export var card_size := Vector2(320, 400)
@export var card_spacing := 380.0
@export var swipe_threshold := 60.0      ## px you must drag to go to the next card
@export var slide_smoothness := 10.0

@onready var cards_pivot: Control = $CardsPivot

var selected_index := 0
var cards: Array[PanelContainer] = []
var custom_card: PanelContainer          # the "create your own" card at the end

# swiping
var is_dragging := false
var drag_start_x := 0.0
var drag_offset_x := 0.0


func _ready() -> void:
	Levels.hide_team_overlay(get_tree(), true)
	selected_index = clampi(Levels.current_index, 0, Levels.LIST.size())
	_create_painting_cards()
	_create_custom_card()


func _exit_tree() -> void:
	Levels.hide_team_overlay(get_tree(), false)


## One card per built-in painting: picture, title, one line, Enter button.
func _create_painting_cards() -> void:
	for i in Levels.LIST.size():
		var level: Dictionary = Levels.LIST[i]

		var card := PanelContainer.new()
		card.custom_minimum_size = card_size
		card.size = card_size
		card.pivot_offset = card_size / 2.0
		card.mouse_filter = Control.MOUSE_FILTER_PASS

		var margin := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 16)
		margin.mouse_filter = Control.MOUSE_FILTER_PASS
		card.add_child(margin)

		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 12)
		rows.mouse_filter = Control.MOUSE_FILTER_PASS
		margin.add_child(rows)

		# the painting itself, fitted into the frame
		var frame := ColorRect.new()
		frame.color = Color(0.08, 0.07, 0.07)
		frame.custom_minimum_size = Vector2(280, 220)
		frame.mouse_filter = Control.MOUSE_FILTER_PASS
		rows.add_child(frame)

		var picture := TextureRect.new()
		picture.texture = load(level["preview"])
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.clip_contents = true
		picture.set_anchors_preset(Control.PRESET_FULL_RECT)
		picture.mouse_filter = Control.MOUSE_FILTER_PASS
		frame.add_child(picture)

		var title := Label.new()
		title.text = level["title"]
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(title)

		var subtitle := Label.new()
		subtitle.text = level["subtitle"]
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		subtitle.modulate = Color(0.75, 0.75, 0.85)
		rows.add_child(subtitle)

		var enter := Button.new()
		enter.text = "Enter Painting"
		enter.custom_minimum_size = Vector2(0, 42)
		enter.pressed.connect(_on_card_chosen.bind(i))
		rows.add_child(enter)

		cards_pivot.add_child(card)
		cards.append(card)


## The last card: pick a PNG, choose frames / levels, Generate, then play it.
func _create_custom_card() -> void:
	custom_card = CustomCard.new(card_size)
	custom_card.play_requested.connect(_on_card_chosen.bind(Levels.custom_index()))
	cards_pivot.add_child(custom_card)
	cards.append(custom_card)


func _process(delta: float) -> void:
	var screen_center := get_viewport_rect().size / 2.0
	var glide := 1.0 - exp(-slide_smoothness * delta)

	# glide every card to its place; the centre card is big and bright
	for i in cards.size():
		var card := cards[i]
		var offset_from_center := i - selected_index
		var target := Vector2(
			screen_center.x - card_size.x / 2.0 + offset_from_center * card_spacing + drag_offset_x,
			screen_center.y - card_size.y / 2.0)
		card.position = card.position.lerp(target, glide)

		var is_center := i == selected_index
		card.scale = card.scale.lerp(Vector2.ONE if is_center else Vector2(0.82, 0.82), glide)
		card.modulate.a = lerpf(card.modulate.a, 1.0 if is_center else 0.45, glide)


# --- swiping and keys --------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			drag_start_x = event.position.x
			drag_offset_x = 0.0
		elif is_dragging:
			is_dragging = false
			_finish_swipe()
	elif event is InputEventMouseMotion and is_dragging:
		drag_offset_x = event.position.x - drag_start_x
	elif event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
		_select(selected_index + 1)
	elif event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
		_select(selected_index - 1)


func _finish_swipe() -> void:
	if drag_offset_x < -swipe_threshold:
		_select(selected_index + 1)    # swiped left: next card
	elif drag_offset_x > swipe_threshold:
		_select(selected_index - 1)    # swiped right: previous card
	drag_offset_x = 0.0


func _select(index: int) -> void:
	selected_index = clampi(index, 0, cards.size() - 1)


func _on_card_chosen(index: int) -> void:
	if index != selected_index:
		_select(index)                 # a side card: bring it to the centre first
	elif custom_card.is_busy():
		custom_card.show_busy_hint()   # don't leave while pictures are being made
	else:
		Levels.load_level(get_tree(), index)
