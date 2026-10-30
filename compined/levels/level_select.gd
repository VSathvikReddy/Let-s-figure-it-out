extends Control
## The painting gallery: a carousel of cards, one per level in Levels.LIST,
## plus a last card to create your own painting (custom_level_card.gd).
##   - A / D, the arrow keys, or swiping with the mouse: move between cards
##   - "Enter Painting" on the centre card: play that level
##   - Locked paintings are dark with a padlock; finishing the painting before
##     them opens them. Right after a painting was unlocked, the gallery slides
##     to it and plays the unlock animation.
##   - Debug buttons (bottom right): "Unlock all (debug)" opens every painting,
##     "Lock paintings again" resets the progress.
##
## Copied from the team's levels/level_select.gd. Changes: the levels come from
## compined/levels/levels.gd, and each card shows the real painting.

const Levels := preload("res://compined/levels/levels.gd")
const CustomCard := preload("res://compined/levels/custom/custom_level_card.gd")
const LockIcon := preload("res://compined/levels/lock_icon.gd")

## Darkness of a locked painting (1 = normal).
const LOCKED_BRIGHTNESS := 0.25

# Card layout (easy to tweak in the Inspector)
@export var card_size := Vector2(320, 400)
@export var card_spacing := 380.0
@export var swipe_threshold := 60.0      ## px you must drag to go to the next card
@export var slide_smoothness := 10.0

@onready var cards_pivot: Control = $CardsPivot

var selected_index := 0
var cards: Array[PanelContainer] = []
var custom_card: PanelContainer          # the "create your own" card at the end
## Parts of each painting card that change when it is locked or unlocked.
var card_parts: Array[Dictionary] = []

# swiping
var is_dragging := false
var drag_start_x := 0.0
var drag_offset_x := 0.0


func _ready() -> void:
	Levels.hide_team_overlay(get_tree(), true)
	selected_index = clampi(Levels.current_index, 0, Levels.LIST.size())
	_create_painting_cards()
	_create_custom_card()
	_create_debug_buttons()
	if Levels.just_unlocked >= 0:
		_show_new_unlock(Levels.just_unlocked)


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

		var lock := LockIcon.new()
		frame.add_child(lock)

		cards_pivot.add_child(card)
		cards.append(card)
		card_parts.append({"picture": picture, "subtitle": subtitle, "enter": enter, "lock": lock})
		# a painting that is about to be shown opening starts out locked too
		_set_locked(i, not Levels.is_unlocked(i) or i == Levels.just_unlocked)


## Locked: dark picture, padlock, a hint instead of the description, no Enter.
func _set_locked(index: int, locked: bool) -> void:
	var parts := card_parts[index]
	parts["picture"].modulate = Color(LOCKED_BRIGHTNESS, LOCKED_BRIGHTNESS, LOCKED_BRIGHTNESS) if locked else Color.WHITE
	parts["lock"].visible = locked
	parts["enter"].disabled = locked
	parts["enter"].text = "Locked" if locked else "Enter Painting"
	if locked and index > 0:
		parts["subtitle"].text = "Finish %s to unlock." % Levels.LIST[index - 1]["title"]
	else:
		parts["subtitle"].text = Levels.LIST[index]["subtitle"]


## Right after a win: start on the painting that was finished, slide to the
## new one, open its lock and light it up.
func _show_new_unlock(index: int) -> void:
	Levels.just_unlocked = -1
	selected_index = maxi(index - 1, 0)
	await get_tree().create_timer(0.7).timeout
	_select(index)
	await get_tree().create_timer(0.5).timeout
	var parts := card_parts[index]
	await parts["lock"].play_unlock()
	_set_locked(index, false)
	parts["lock"].visible = false
	# the painting brightens from dark and the card gives a little bounce
	parts["picture"].modulate = Color(LOCKED_BRIGHTNESS, LOCKED_BRIGHTNESS, LOCKED_BRIGHTNESS)
	var light_up := create_tween()
	light_up.tween_property(parts["picture"], "modulate", Color(1.4, 1.3, 1.1), 0.35)
	light_up.tween_property(parts["picture"], "modulate", Color.WHITE, 0.4)
	var card := cards[index]
	card.scale = Vector2.ONE * 1.12


## Two small buttons in the bottom right corner, for testing:
##   Unlock all (debug)    - every painting open
##   Lock paintings again  - only the first painting open
func _create_debug_buttons() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.modulate = Color(1, 1, 1, 0.6)
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(row)

	var unlock := Button.new()
	unlock.text = "Unlock all (debug)"
	unlock.pressed.connect(func() -> void:
		Levels.unlock_all()
		get_tree().reload_current_scene())
	row.add_child(unlock)

	var lock := Button.new()
	lock.text = "Lock paintings again"
	lock.pressed.connect(func() -> void:
		Levels.lock_all_again()
		Levels.current_index = 0
		get_tree().reload_current_scene())
	row.add_child(lock)


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

func _input(event: InputEvent) -> void:
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
	elif not Levels.is_unlocked(index):
		return                         # locked: the button is disabled anyway
	elif custom_card.is_busy():
		custom_card.show_busy_hint()   # don't leave while pictures are being made
	else:
		Levels.load_level(get_tree(), index)
