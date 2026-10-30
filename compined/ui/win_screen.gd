extends CanvasLayer
## Counts the gems the player picks up. When all of them are found, the game
## pauses and the win card fades in: Play Again, Next Painting, or back to the
## Paintings (the level selector). Esc also goes back to the Paintings.
## If the player falls out of the bottom of the painting, the same card says
## "You Fell!" instead, without Next Painting.

const Levels := preload("res://compined/levels/levels.gd")

@export var gems_to_win := 4

var won := false

@onready var gem_counter: Label = $GemCounter
@onready var force_win_button: Button = $ForceWinButton
@onready var win_card: Control = $WinCard
@onready var title: Label = $WinCard/Card/Margin/Rows/Title
@onready var summary: Label = $WinCard/Card/Margin/Rows/Summary
@onready var play_again_button: Button = $WinCard/Card/Margin/Rows/PlayAgainButton
@onready var next_button: Button = $WinCard/Card/Margin/Rows/NextButton
@onready var paintings_button: Button = $WinCard/Card/Margin/Rows/PaintingsButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the buttons must work while paused
	win_card.visible = false
	force_win_button.pressed.connect(_win)
	play_again_button.pressed.connect(Levels.restart_level.bind(get_tree()))
	next_button.pressed.connect(Levels.load_next_level.bind(get_tree()))
	paintings_button.pressed.connect(Levels.go_to_level_select.bind(get_tree()))
	_show_gems(0)

	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_signal("gem_collected"):
		player.gem_collected.connect(_on_gem_collected)
	if player and player.has_signal("fell_out"):
		player.fell_out.connect(_lose.bind("You Fell!", "You fell out of the painting."))
	if player and player.has_signal("died"):
		player.died.connect(_lose.bind("Defeated!", "The painting's guardians got you."))

	Levels.hide_team_overlay(get_tree(), true)
	Levels.remember_current_level(get_tree())


func _exit_tree() -> void:
	Levels.hide_team_overlay(get_tree(), false)


## Esc: back to the Paintings.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Levels.go_to_level_select(get_tree())


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

	title.text = "Painting Restored!"
	summary.text = "You found all %d gems!" % gems_to_win
	next_button.visible = true
	next_button.disabled = not Levels.has_next_level()
	next_button.text = "Next Painting" if Levels.has_next_level() else "All Paintings Clear!"
	_show_card()


## The level is lost: she fell out of the painting, or her health ran out.
func _lose(heading: String, reason: String) -> void:
	if won:
		return
	won = true   # the level is over either way
	get_tree().paused = true
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED
	title.text = heading
	summary.text = reason
	next_button.visible = false
	_show_card()


func _show_card() -> void:
	force_win_button.visible = false
	win_card.visible = true
	win_card.modulate.a = 0.0
	create_tween().tween_property(win_card, "modulate:a", 1.0, 0.3)

