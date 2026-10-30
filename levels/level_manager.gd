extends CanvasLayer

# Emitted when the player collects all 4 gems OR clicks the debug win button
signal won

# --- LEVEL DATABASE (Add your new level .tscn paths here) ---
var levels: Array[Dictionary] = [
	{
		"title": "Painting I: The Shattered Hill",
		"subtitle": "Collect 4 hidden gems behind the canvas",
		"scene_path": "res://demo.tscn", # Using your existing demo.tscn as Level 1
		"preview_color": Color(0.22, 0.45, 0.68)
	},
	{
		"title": "Painting II: Crimson Bastion",
		"subtitle": "Watch out for Heavy Bombers & Turrets",
		"scene_path": "res://demo.tscn", # Replace with level_2.tscn when ready
		"preview_color": Color(0.68, 0.22, 0.32)
	},
	{
		"title": "Painting III: The Void Gallery",
		"subtitle": "Toggle the Veil (J) to see unseen paths",
		"scene_path": "res://demo.tscn", # Replace with level_3.tscn when ready
		"preview_color": Color(0.42, 0.24, 0.68)
	},
	{
		"title": "Painting IV: Entropy's Edge",
		"subtitle": "Survive the final shifting architecture",
		"scene_path": "res://demo.tscn", # Ensure you create a level_4.tscn eventually!
		"preview_color": Color(0.25, 0.65, 0.45)
	}
]

const LEVEL_SELECT_PATH: String = "res://levels/LevelSelect.tscn"
const GEMS_TO_WIN: int = 4
const CUSTOM_LEVEL_SCENE_PATH: String = "res://levels/custom/CustomLevel.tscn"

# Folder (inside user://) of the generated custom level. The custom level's index is levels.size().
var custom_folder: String = ""

var current_level_index: int = 0
var current_gems: int = 0
var is_transitioning: bool = false
var level_already_won: bool = false

# --- NODE REFERENCES ---
@onready var fade_overlay: ColorRect = $FadeOverlay
@onready var debug_win_button: Button = $DebugWinButton
@onready var win_screen: Control = $WinScreen
@onready var gem_summary_label: Label = $WinScreen/CardPanel/MarginContainer/VBoxContainer/GemSummary
@onready var restart_button: Button = $WinScreen/CardPanel/MarginContainer/VBoxContainer/ButtonRow/RestartButton
@onready var next_level_button: Button = $WinScreen/CardPanel/MarginContainer/VBoxContainer/ButtonRow/NextLevelButton
@onready var menu_button: Button = $WinScreen/CardPanel/MarginContainer/VBoxContainer/ButtonRow/MenuButton


func _ready() -> void:
	# Start with overlays hidden
	fade_overlay.modulate.a = 0.0
	win_screen.visible = false
	
	# Connect the "won" signal to our win screen handler
	won.connect(_on_player_won)
	
	# Connect UI Buttons
	debug_win_button.pressed.connect(_on_debug_win_button_pressed)
	restart_button.pressed.connect(restart_current_level)
	next_level_button.pressed.connect(load_next_level)
	menu_button.pressed.connect(go_to_level_select)


# --- GEM COLLECTION & WIN CHECK ---

func register_gem_collected(total_collected_by_player: int) -> void:
	if level_already_won:
		return
		
	current_gems = total_collected_by_player
	print("[LevelManager] Gems collected: ", current_gems, " / ", GEMS_TO_WIN)
	
	if current_gems >= GEMS_TO_WIN:
		won.emit()


func _on_debug_win_button_pressed() -> void:
	if level_already_won:
		return
	current_gems = GEMS_TO_WIN
	print("[LevelManager] Debug Win Button clicked! Emitting 'won' signal...")
	won.emit()


func _on_player_won() -> void:
	if level_already_won:
		return
	level_already_won = true
	
	# 1. PAUSE THE GAMEPLAY IN THE BACKGROUND
	get_tree().paused = true
	# 2. Stop and freeze the player if they use PROCESS_MODE_ALWAYS
	var player: CharacterBody2D = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if is_instance_valid(player):
		player.velocity = Vector2.ZERO
		player.process_mode = Node.PROCESS_MODE_DISABLED # Disables player physics and input completely
	gem_summary_label.text = "%d / %d Gems Collected!" % [current_gems, GEMS_TO_WIN]
	
	var has_next_level: bool = (current_level_index + 1) < levels.size()
	next_level_button.disabled = not has_next_level
	next_level_button.text = "Next Painting" if has_next_level else "All Paintings Clear!"
	
	# Smooth pop-in animation for the Win Screen 
	# (Note: Using 'tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)' ensures the 
	# fade-in tween still plays even though the game tree is paused!)
	win_screen.visible = true
	win_screen.modulate.a = 0.0
	var tween: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(win_screen, "modulate:a", 1.0, 0.3)


# --- LEVEL LOADING & FADE TRANSITIONS ---

func load_level(level_index: int) -> void:
	var target_path: String
	if level_index == levels.size() and custom_folder != "":
		target_path = CUSTOM_LEVEL_SCENE_PATH
	elif level_index < 0 or level_index >= levels.size():
		push_warning("[LevelManager] Invalid level index: " + str(level_index))
		return
	else:
		target_path = levels[level_index]["scene_path"]
		
	current_level_index = level_index
	_transition_to_scene(target_path, true)


func restart_current_level() -> void:
	load_level(current_level_index)


func load_next_level() -> void:
	if current_level_index + 1 < levels.size():
		load_level(current_level_index + 1)
	else:
		go_to_level_select()


func go_to_level_select() -> void:
	_transition_to_scene(LEVEL_SELECT_PATH, false)


func _transition_to_scene(scene_path: String, is_gameplay_level: bool) -> void:
	if is_transitioning:
		return
	is_transitioning = true
	print("hi")
	# 2. ENSURE GAME IS UNPAUSED BEFORE CHANGING SCENES
	# (If the win screen was active, the tree was paused. We must unpause 
	# so change_scene_to_file and the fade tweens are allowed to process)
	get_tree().paused = false
	
	# 1. Fade Out to Black (using PAUSE_PROCESS just in case)
	var fade_out: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade_out.tween_property(fade_overlay, "modulate:a", 1.0, 0.35)
	await fade_out.finished
	
	# 2. Reset level state
	win_screen.visible = false
	level_already_won = false
	current_gems = 0
	
	# Hide the debug win button when inside the Level Select menu
	debug_win_button.visible = is_gameplay_level
	
	# 3. Switch the scene
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	
	# 4. Fade In from Black
	var fade_in: Tween = create_tween()
	fade_in.tween_property(fade_overlay, "modulate:a", 0.0, 0.35)
	await fade_in.finished
	
	is_transitioning = false
