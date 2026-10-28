extends Node2D
## Base for a weapon scene held by the player (put it in a player weapon slot).
## The player aims it (rotation + flip), calls fire(), and drives the `reload`
## and `spin` animation values. Art is drawn in code for now; to use sprites
## later, add Sprite2D children to the weapon scene and remove its _draw().

enum Preview { ARC, STRAIGHT }

## Recoil is multiplied by this when firing into the painting (feet planted).
const PAINT_RECOIL_MULT := 0.35

@export_group("Firing")
## Damage dealt to enemies (rockets: at the blast centre, falling off outward).
@export var damage := 1.0
## Hold the fire button to keep shooting (at the reload rate). Off = one shot per click.
@export var automatic := true
@export var reload_time := 0.5
@export var recoil_force := 300.0
## Aim preview in the studio: ARC simulates the rocket, STRAIGHT is a laser line.
@export var preview := Preview.STRAIGHT
## Muzzle tip in the weapon's local space (move it when you swap in a sprite).
@export var muzzle := Vector2(150, 0)

@export_group("Painting")
## Radius of the distortion mask stamp when this weapon hits the painting (layer px).
@export var impact_radius := 70.0
## How much a shot into the painting RESTORES it: 1 = brings back one detail
## level at the centre, 0.5 = two hits per level.
@export var distortion_strength := 1.0
## Arc height of a shot fired into the painting.
@export var paint_arc := 100.0

var recoil := 0.0  # animation: 1 right after firing, decays to 0
var reload := 1.0  # animation: 0 = just fired, 1 = ready
var spin := 0.0    # animation: swap twirl, tweened by the player
var recoil_recover := 4.5
var _t := 0.0


func muzzle_global() -> Vector2:
	return to_global(muzzle)


func kick() -> void:
	recoil = 1.0


func _process(delta: float) -> void:
	_t += delta
	recoil = move_toward(recoil, 0.0, delta * recoil_recover)
	queue_redraw()


## Override in each weapon. `player` is the CharacterBody2D firing it (has
## knock_back(), squash(), add_trauma()); `pick` comes from paint_picker.
func fire(_player, _aim: Vector2, _painting: bool, _pick: Dictionary, _target: Vector2) -> void:
	pass


## Studio aim preview. Override for custom trajectories (see orb_staff.gd).
func update_preview(guide, aim: Vector2, shooter: RID, ready_shot: bool) -> void:
	guide.update_path(muzzle_global(), aim, shooter, ready_shot, preview == Preview.ARC)
