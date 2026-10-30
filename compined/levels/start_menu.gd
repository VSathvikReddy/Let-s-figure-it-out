extends Control

# Drag and drop your 4 background images into this array in the Inspector!
# (If left empty, it uses icon.svg as a safe placeholder until you assign them)
@export var background_images: Array[Texture2D] = [
	preload("res://compined/levels/background paintings/scarry_night.png"),
	preload("res://compined/levels/background paintings/skull.png"),
	preload("res://compined/levels/background paintings/tsunami.png")
]
@export var crossfade_duration: float = 1.5

# --- NODE REFERENCES ---
@onready var bg_image_a: TextureRect = $BgImageA
@onready var bg_image_b: TextureRect = $BgImageB
@onready var slide_timer: Timer = $SlideTimer

@onready var menu_card: PanelContainer = $MenuCard
@onready var start_button: Button = $MenuCard/MarginContainer/VBoxContainer/StartButton
@onready var settings_button: Button = $MenuCard/MarginContainer/VBoxContainer/SettingsButton
@onready var credits_button: Button = $MenuCard/MarginContainer/VBoxContainer/CreditsButton
@onready var quit_button: Button = $MenuCard/MarginContainer/VBoxContainer/QuitButton

@onready var settings_popup: Control = $SettingsPopup
@onready var sound_toggle: CheckButton = $SettingsPopup/SettingsCard/MarginContainer/VBoxContainer/SoundToggleButton
@onready var close_settings_button: Button = $SettingsPopup/SettingsCard/MarginContainer/VBoxContainer/CloseSettingsButton

var current_image_index: int = 0
var showing_a: bool = true


func _ready() -> void:
	# Hide the debug win button while on the Start Menu
	if is_instance_valid(LevelManager.debug_win_button):
		LevelManager.debug_win_button.visible = false

	settings_popup.visible = false

	# Sync sound toggle button with Godot's Master Audio Bus mute state
	var master_bus_index: int = AudioServer.get_bus_index("Master")
	var is_muted: bool = AudioServer.is_bus_mute(master_bus_index)
	sound_toggle.button_pressed = not is_muted

	# Setup initial background image
	if background_images.size() > 0:
		bg_image_a.texture = background_images[0]
		bg_image_a.modulate.a = 1.0
		bg_image_b.modulate.a = 0.0

	# Connect Signals
	slide_timer.timeout.connect(_on_slide_timer_timeout)
	start_button.pressed.connect(_on_start_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	sound_toggle.toggled.connect(_on_sound_toggled)
	close_settings_button.pressed.connect(_on_close_settings_pressed)


# --- 10-SECOND BACKGROUND CROSSFADE ---

func _on_slide_timer_timeout() -> void:
	if background_images.size() <= 1:
		return

	current_image_index = (current_image_index + 1) % background_images.size()
	var next_texture: Texture2D = background_images[current_image_index]

	var tween: Tween = create_tween().set_parallel(true)
	if showing_a:
		bg_image_b.texture = next_texture
		tween.tween_property(bg_image_a, "modulate:a", 0.0, crossfade_duration)
		tween.tween_property(bg_image_b, "modulate:a", 1.0, crossfade_duration)
	else:
		bg_image_a.texture = next_texture
		tween.tween_property(bg_image_b, "modulate:a", 0.0, crossfade_duration)
		tween.tween_property(bg_image_a, "modulate:a", 1.0, crossfade_duration)

	showing_a = not showing_a


# --- MENU BUTTON HANDLERS ---

func _on_start_pressed() -> void:
	LevelManager.go_to_level_select()


func _on_credits_pressed() -> void:
	LevelManager.go_to_credits()


func _on_settings_pressed() -> void:
	menu_card.visible = false
	settings_popup.visible = true
	settings_popup.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(settings_popup, "modulate:a", 1.0, 0.2)


func _on_close_settings_pressed() -> void:
	menu_card.visible = true
	var tween: Tween = create_tween()
	tween.tween_property(settings_popup, "modulate:a", 0.0, 0.2)
	await tween.finished
	settings_popup.visible = false


func _on_sound_toggled(sound_enabled: bool) -> void:
	# Mutes or unmutes the global Master audio bus (affects all SFX and BGM)
	var master_bus_index: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(master_bus_index, not sound_enabled)


func _on_quit_pressed() -> void:
	get_tree().quit()
