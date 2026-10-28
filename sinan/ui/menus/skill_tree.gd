extends CanvasLayer
## Skill tree + loadout screen. Tab opens / closes it (Esc also closes) and the
## game pauses while it is open. Layout is Control nodes in skill_tree.tscn;
## this script fills %Branches with one column per branch (cards from
## upgrade_card.tscn, data from sinan/progress/skill_tree.tres) and the two
## loadout pickers.

@export var open_action := &"skills"
@export var open_key := KEY_TAB
@export var card_scene: PackedScene = preload("res://sinan/ui/menus/upgrade_card.tscn")
@export var branch_title_color := Color(1.0, 0.82, 0.45)

@onready var root_control: Control = $Root
@onready var branches_box: HBoxContainer = %Branches
@onready var coins_label: Label = %Coins
@onready var close_button: Button = %Close
@onready var weapon_pick: OptionButton = %WeaponPick

var _cards: Array = []
var _mouse_before := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("progress_listeners")
	root_control.visible = false
	if not InputMap.has_action(open_action):
		InputMap.add_action(open_action)
		var e := InputEventKey.new()
		e.physical_keycode = open_key
		InputMap.action_add_event(open_action, e)
	close_button.pressed.connect(close)
	weapon_pick.item_selected.connect(_equip)
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(open_action):
		if root_control.visible:
			close()
		elif not get_tree().paused:  # don't open over the pause menu
			open()
		get_viewport().set_input_as_handled()
	elif root_control.visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_refresh()
	root_control.visible = true
	get_tree().paused = true
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	root_control.visible = false
	get_tree().paused = false
	Input.mouse_mode = _mouse_before
	Progress.save_game()


## Called through the "progress_listeners" group.
func on_progress_changed() -> void:
	if root_control.visible:
		_refresh()


func _build() -> void:
	var t := Progress.tree()
	if t == null:
		push_warning("Skill tree data missing: " + Progress.TREE_PATH)
		return
	for b in t.branches:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		var title := Label.new()
		title.text = String(b).to_upper()
		title.add_theme_font_size_override("font_size", 16)
		title.add_theme_color_override("font_color", branch_title_color)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(title)
		branches_box.add_child(col)  # in the tree first, so the cards' @onready nodes exist
		for u in t.upgrades:
			if u and u.branch == b:
				var card = card_scene.instantiate()
				col.add_child(card)
				card.setup(u)
				_cards.append(card)


func _refresh() -> void:
	coins_label.text = str(Progress.coins())
	for c in _cards:
		c.refresh()
	_fill_pick()


## Loadout dropdown: unlocked items are pickable, locked ones are shown greyed.
func _fill_pick() -> void:
	var t := Progress.tree()
	if t == null:
		return
	weapon_pick.clear()
	for i in t.weapon_names.size():
		var unlock: StringName = t.weapon_unlock_stats[i] if i < t.weapon_unlock_stats.size() else &""
		var open_ := Progress.is_unlocked(unlock)
		weapon_pick.add_item(t.weapon_names[i] if open_ else t.weapon_names[i] + "  (locked)", i)
		weapon_pick.set_item_disabled(i, not open_)
	weapon_pick.select(Progress.equipped_weapon())


func _equip(index: int) -> void:
	if weapon_pick.is_item_disabled(index):
		return
	Progress.equip(weapon_pick.get_item_id(index), self)
