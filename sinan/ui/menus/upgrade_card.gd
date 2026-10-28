extends PanelContainer
## One upgrade in the skill tree (layout in upgrade_card.tscn). The tree calls
## setup() once and refresh() whenever coins or levels change.

signal bought

@export var maxed_color := Color(0.55, 0.9, 0.55)
@export var locked_color := Color(0.6, 0.55, 0.5)
@export var cant_afford_color := Color(1.0, 0.5, 0.45)

@onready var title_label: Label = %Title
@onready var desc_label: Label = %Description
@onready var level_bar: ProgressBar = %LevelBar
@onready var level_label: Label = %Level
@onready var buy_button: Button = %Buy

var def: UpgradeDef


func setup(upgrade: UpgradeDef) -> void:
	def = upgrade
	title_label.text = def.title
	desc_label.text = def.description
	level_bar.max_value = def.max_level
	buy_button.pressed.connect(_on_buy)
	refresh()


func refresh() -> void:
	if def == null:
		return
	var lvl := Progress.level(def.id)
	level_bar.value = lvl
	level_label.text = "%d / %d" % [lvl, def.max_level]
	modulate = Color.WHITE
	if lvl >= def.max_level:
		buy_button.text = "MAX"
		buy_button.disabled = true
		level_label.add_theme_color_override("font_color", maxed_color)
		return
	if def.requires != &"" and Progress.level(def.requires) < def.requires_level:
		var req := Progress.tree().find(def.requires)
		buy_button.text = "Needs %s %d" % [req.title if req else String(def.requires), def.requires_level]
		buy_button.disabled = true
		modulate = locked_color
		return
	var price := def.cost_for_level(lvl)
	buy_button.text = "Buy  %d" % price
	buy_button.disabled = Progress.coins() < price
	buy_button.add_theme_color_override("font_disabled_color", cant_afford_color)


func _on_buy() -> void:
	if Progress.buy(def, self):
		bought.emit()
		pivot_offset = size * 0.5
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2.ONE * 1.06, 0.06)
		tw.tween_property(self, "scale", Vector2.ONE, 0.15)
