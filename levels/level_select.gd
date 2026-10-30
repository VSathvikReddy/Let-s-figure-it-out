extends Control

# Card layout settings (easy to tweak in the Inspector)
@export var card_size: Vector2 = Vector2(320, 400)
@export var card_spacing: float = 380.0
@export var swipe_threshold: float = 60.0 # Pixels needed to swipe to the next card
@export var slide_smoothness: float = 10.0

@onready var cards_pivot: Control = $CardsPivot

var selected_index: int = 0
var card_nodes: Array[PanelContainer] = []

# Swipe tracking variables
var is_dragging: bool = false
var drag_start_x: float = 0.0
var drag_offset_x: float = 0.0


func _ready() -> void:
	# Hide the debug win button while browsing the gallery
	LevelManager.debug_win_button.visible = false
	selected_index = LevelManager.current_level_index
	
	_create_painting_cards()


# Dynamically builds a placeholder Painting Card for each entry in LevelManager.levels
func _create_painting_cards() -> void:
	for i in range(LevelManager.levels.size()):
		var level_data: Dictionary = LevelManager.levels[i]
		
		# 1. Outer Painting Frame (Card)
		var card := PanelContainer.new()
		card.custom_minimum_size = card_size
		card.size = card_size
		card.pivot_offset = card_size / 2.0
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		
		# 2. Inner Layout
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 16)
		margin.add_theme_constant_override("margin_right", 16)
		margin.add_theme_constant_override("margin_top", 16)
		margin.add_theme_constant_override("margin_bottom", 16)
		card.add_child(margin)
		
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 12)
		margin.add_child(vbox)
		
		# 3. Placeholder Painting Canvas (ColorRect + Godot Icon placeholder)
		var painting_bg := ColorRect.new()
		painting_bg.color = level_data["preview_color"]
		painting_bg.custom_minimum_size = Vector2(280, 220)
		painting_bg.mouse_filter = Control.MOUSE_FILTER_PASS
		vbox.add_child(painting_bg)
		
		var placeholder_art := TextureRect.new()
		placeholder_art.texture = preload("res://icon.svg")
		placeholder_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		placeholder_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		placeholder_art.set_anchors_preset(Control.PRESET_FULL_RECT)
		placeholder_art.mouse_filter = Control.MOUSE_FILTER_PASS
		painting_bg.add_child(placeholder_art)
		
		# 4. Painting Title & Gem Objective Subtitle
		var title_label := Label.new()
		title_label.text = level_data["title"]
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(title_label)
		
		var sub_label := Label.new()
		sub_label.text = level_data["subtitle"]
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub_label.modulate = Color(0.75, 0.75, 0.85)
		vbox.add_child(sub_label)
		
		# 5. Play / Enter Painting Button
		var enter_button := Button.new()
		enter_button.text = "Enter Painting"
		enter_button.custom_minimum_size = Vector2(0, 42)
		enter_button.pressed.connect(func() -> void: _on_card_chosen(i))
		vbox.add_child(enter_button)
		
		cards_pivot.add_child(card)
		card_nodes.append(card)


func _process(delta: float) -> void:
	var screen_center: Vector2 = get_viewport_rect().size / 2.0
	
	# Smoothly glide each card into its carousel position
	for i in range(card_nodes.size()):
		var card: PanelContainer = card_nodes[i]
		var index_offset: int = i - selected_index
		
		var target_x: float = screen_center.x - (card_size.x / 2.0) + (index_offset * card_spacing) + drag_offset_x
		var target_y: float = screen_center.y - (card_size.y / 2.0)
		
		card.position.x = lerpf(card.position.x, target_x, slide_smoothness * delta)
		card.position.y = lerpf(card.position.y, target_y, slide_smoothness * delta)
		
		# Make the center card pop out and dim the side cards
		var is_center_card: bool = (i == selected_index)
		var target_scale: Vector2 = Vector2.ONE if is_center_card else Vector2(0.82, 0.82)
		var target_alpha: float = 1.0 if is_center_card else 0.45
		
		card.scale = card.scale.lerp(target_scale, slide_smoothness * delta)
		card.modulate.a = lerpf(card.modulate.a, target_alpha, slide_smoothness * delta)


# --- SWIPE & KEYBOARD INPUT HANDLING ---

func _input(event: InputEvent) -> void:
	# 1. Mouse / Touch Drag Start & End
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			drag_start_x = event.position.x
			drag_offset_x = 0.0
		else:
			if is_dragging:
				is_dragging = false
				_evaluate_swipe()
				
	# 2. Mouse / Touch Dragging Motion
	elif event is InputEventMouseMotion and is_dragging:
		drag_offset_x = event.position.x - drag_start_x
		
	# 3. Keyboard Navigation (A / D or Left / Right Arrows)
	elif event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
		_change_selection(selected_index + 1)
	elif event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
		_change_selection(selected_index - 1)


func _evaluate_swipe() -> void:
	# Swiped Left -> Next Card
	if drag_offset_x < -swipe_threshold:
		_change_selection(selected_index + 1)
	# Swiped Right -> Previous Card
	elif drag_offset_x > swipe_threshold:
		_change_selection(selected_index - 1)
		
	drag_offset_x = 0.0


func _change_selection(new_index: int) -> void:
	selected_index = clampi(new_index, 0, card_nodes.size() - 1)


func _on_card_chosen(card_index: int) -> void:
	# If the player clicks a side card, slide it to the center first
	if card_index != selected_index:
		_change_selection(card_index)
	else:
		# If it's already centered, fade out and load that painting level!
		LevelManager.load_level(card_index)
