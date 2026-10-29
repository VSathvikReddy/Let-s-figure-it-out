extends CanvasLayer
## The screen after a run (same old-monitor look as the skill tree): time,
## kills, coins, how much of the painting got restored and the next painting
## milestone. Continue (Enter / E / click) opens the skill tree.
## The RunManager finds it through the "run_summary" group.

const GOLD := Color(0.97, 0.79, 0.33)
const DIM := Color(0.62, 0.48, 0.21)
const GOOD := Color(0.6, 0.95, 0.55)

@onready var root_control: Control = $Root
@onready var lines_box: VBoxContainer = %Lines
@onready var milestone_bar: ProgressBar = %MilestoneBar
@onready var continue_button: Button = %Continue


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("run_summary")
	root_control.visible = false
	continue_button.pressed.connect(_continue)


func show_summary(s: Dictionary) -> void:
	for c in lines_box.get_children():
		c.queue_free()
	var title := "YOU DIED" if s.reason == &"death" else "RUN ENDED"
	_line(title, GOLD, 26)
	_line("", GOLD, 6)
	_line("Time      %02d:%02d" % [int(s.time) / 60, int(s.time) % 60], GOLD, 16)
	_line("Kills     %d" % s.kills, GOLD, 16)
	var coins := "Coins     +%d" % s.coins
	if s.restore_pay > 0:
		coins += "   (restorer's pay +%d)" % s.restore_pay
	_line(coins, GOLD, 16)
	_line("Entropy   +%d   (from restoring the painting)" % s.entropy, Color(0.78, 0.6, 1.0), 16)
	_line("", GOLD, 6)
	var gained: float = (s.clarity - s.clarity_start) * 100.0
	_line("Restored  %.1f%%  ->  %.1f%%   (%s%.1f%%)" % [s.clarity_start * 100.0, s.clarity * 100.0,
		"+" if gained >= 0.0 else "", gained], GOOD if gained > 0.0 else DIM, 16)
	if s.new_milestones > 0:
		_line("MILESTONE REACHED: the rift grows stronger, coins +%d%%" % roundi(
			s.new_milestones * RunManager.current.difficulty.milestone_coin_bonus * 100.0), GOOD, 14)
	var next: float = s.next_milestone
	if next > 0.0:
		_line("Next milestone: %d%% restored (best %.1f%%)" % [roundi(next * 100.0), s.best * 100.0], DIM, 13)
		milestone_bar.visible = true
		milestone_bar.value = clampf(s.best / next, 0.0, 1.0)
	else:
		_line("Every milestone reached.", GOOD, 13)
		milestone_bar.visible = false
	root_control.visible = true
	root_control.modulate.a = 0.0
	create_tween().tween_property(root_control, "modulate:a", 1.0, 0.25)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	continue_button.grab_focus()


func _line(text: String, color: Color, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	lines_box.add_child(l)


func _unhandled_input(event: InputEvent) -> void:
	if not root_control.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_E, KEY_SPACE]:
		_continue()
		get_viewport().set_input_as_handled()


func _continue() -> void:
	if not root_control.visible:
		return
	root_control.visible = false
	get_tree().call_group("skill_tree", "open")
