extends CanvasLayer
## Counts the gems the player picks up. When all of them are found, the game
## pauses and the win card fades in, with a button to play the level again.

@export var gems_to_win := 4

var won := false

@onready var gem_counter: Label = $GemCounter
@onready var force_win_button: Button = $ForceWinButton
@onready var win_card: Control = $WinCard
@onready var summary: Label = $WinCard/Card/Margin/Rows/Summary
@onready var play_again_button: Button = $WinCard/Card/Margin/Rows/PlayAgainButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the buttons must work while paused
	win_card.visible = false
	force_win_button.pressed.connect(_win)
	play_again_button.pressed.connect(_play_again)
	_show_gems(0)

	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_signal("gem_collected"):
		player.gem_collected.connect(_on_gem_collected)

	# The team's LevelManager (a global autoload) draws its own buttons over
	# every scene. This level has its own, so hide theirs while we are here.
	_set_team_overlay_visible(false)


func _exit_tree() -> void:
	_set_team_overlay_visible(true)


func _set_team_overlay_visible(on: bool) -> void:
	var team_overlay := get_node_or_null("/root/LevelManager")
	if team_overlay is CanvasLayer:
		team_overlay.visible = on


func _on_gem_collected(total: int) -> void:
	_show_gems(total)
	if total >= gems_to_win:
		_win()


func _show_gems(count: int) -> void:
	gem_counter.text = "Gems  %d / %d" % [count, gems_to_win]


func _win() -> void:
	if won:
		return
	won = true
	get_tree().paused = true
	# the player keeps running while paused (for the veil), so stop it here
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED

	summary.text = "You found all %d gems!" % gems_to_win
	force_win_button.visible = false
	win_card.visible = true
	win_card.modulate.a = 0.0
	create_tween().tween_property(win_card, "modulate:a", 1.0, 0.3)


func _play_again() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
