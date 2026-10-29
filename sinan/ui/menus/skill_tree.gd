extends CanvasLayer
## Skill tree screen. With a RunManager in the level it opens between runs
## (after the run summary) and closing it - Start Run, Enter, Esc, Q or Tab -
## starts the next run. Without one, Tab opens / closes it any time.
## The game is paused while it is open. The board itself is skill_graph.gd
## (%Graph, data from sinan/systems/progress/skill_tree.tres); this script opens
## and closes it, shows the coins and fills the weapon row (%Loadout).

@export var open_action := &"skills"
@export var open_key := KEY_TAB

@onready var root_control: Control = $Root
@onready var graph: SkillGraph = %Graph
@onready var coins_label: Label = %Coins
@onready var entropy_label: Label = %Entropy
@onready var loadout_box: HBoxContainer = %Loadout
@onready var start_button: Button = %StartRun

var _mouse_before := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("progress_listeners")
	add_to_group("skill_tree")
	start_button.pressed.connect(close)
	root_control.visible = false
	if not InputMap.has_action(open_action):
		InputMap.add_action(open_action)
		var e := InputEventKey.new()
		e.physical_keycode = open_key
		InputMap.action_add_event(open_action, e)
	graph.build(Progress.tree())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(open_action):
		if root_control.visible:
			close()
		elif not get_tree().paused and not _in_run():  # mid-run the tree waits for the run's end
			open()
		get_viewport().set_input_as_handled()
	elif root_control.visible and (event.is_action_pressed(&"ui_cancel") or (event is InputEventKey and event.pressed
			and not event.echo and event.physical_keycode in [KEY_Q, KEY_ENTER, KEY_KP_ENTER])):
		close()
		get_viewport().set_input_as_handled()


func _in_run() -> bool:
	return RunManager.current != null and RunManager.current.is_running()


func open() -> void:
	if root_control.visible:
		return
	start_button.visible = RunManager.current != null
	root_control.visible = true
	get_tree().paused = true
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	graph.reset_view()
	graph.grab_focus()


func close() -> void:
	root_control.visible = false
	get_tree().paused = false
	Input.mouse_mode = _mouse_before
	Progress.save_game()
	if RunManager.current and not RunManager.current.is_running():
		RunManager.current.start_run()


## Called through the "progress_listeners" group.
func on_progress_changed() -> void:
	if root_control.visible:
		_refresh()


func _refresh() -> void:
	coins_label.text = str(Progress.coins())
	entropy_label.text = str(Progress.entropy())
	_fill_loadout()


## One button per weapon: unlocked ones can be equipped, locked ones are greyed.
func _fill_loadout() -> void:
	var t := Progress.tree()
	if t == null:
		return
	for c in loadout_box.get_children():
		if c is Button:
			c.queue_free()
	for i in t.weapon_names.size():
		var unlock: StringName = t.weapon_unlock_stats[i] if i < t.weapon_unlock_stats.size() else &""
		var b := Button.new()
		b.text = t.weapon_names[i]
		b.toggle_mode = true
		b.button_pressed = i == Progress.equipped_weapon()
		b.disabled = not Progress.is_unlocked(unlock)
		b.focus_mode = Control.FOCUS_NONE
		if b.disabled:
			b.tooltip_text = "Unlock it in the skill tree"
		b.pressed.connect(func() -> void: Progress.equip(i, self))
		loadout_box.add_child(b)
