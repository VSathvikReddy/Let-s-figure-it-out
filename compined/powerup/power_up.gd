extends Area2D
class_name PowerUp
## A power-up token lying in the level. When the player touches it she takes
## its ability (it replaces the one she was holding) and the token vanishes.
## She uses the ability with Q (see player.gd).
##
## LOOKS: the "Icons" node has one Sprite2D per ability (Dash, Ghost, Trail,
## Shield, Veil). Only the one for this token's `type` is shown. To change how
## an ability looks, select its Sprite2D in power_up.tscn and change the
## texture - the top-right HUD slot uses the same picture.

enum PowerType {
	DASH = 0,     ## a quick burst toward the mouse, can't be hurt during it
	GHOST = 1,    ## summon friendly ghosts that clean the painting (hold Q)
	TRAIL = 2,    ## for a while, the painting is restored wherever she flies
	SHIELD = 3,   ## for a while, a bubble blocks every hit
	VEIL = 4,     ## open the veil (J closes it)
}

## Names shown in the HUD.
const NAMES := ["Dash", "Ghost Summon", "Magic Trail", "Shield", "Veil"]

@export var type: PowerType = PowerType.DASH
## Seconds before the token disappears by itself (0 = never). It blinks for
## the last 3 seconds.
@export var lifetime := 0.0

@onready var icons: Node2D = $Icons

var _age := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_enter)
	for icon in icons.get_children():
		icon.visible = icon.get_index() == type
	# float gently up and down
	var bob := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	bob.tween_property(icons, "position:y", -6.0, 0.8)
	bob.tween_property(icons, "position:y", 0.0, 0.8)


func _process(delta: float) -> void:
	if lifetime <= 0.0:
		return
	_age += delta
	if _age >= lifetime:
		queue_free()
	elif lifetime - _age < 3.0:
		visible = int(_age * 8.0) % 2 == 0   # blinking: about to vanish


## The picture of this token's ability (also shown in the HUD when picked up).
func icon_texture() -> Texture2D:
	var icon := icons.get_child(type) as Sprite2D
	return icon.texture if icon else null


func _on_body_enter(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("pick_up_power_up"):
		body.pick_up_power_up(type, icon_texture())
		queue_free()
