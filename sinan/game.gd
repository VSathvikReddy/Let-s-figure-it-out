extends Node2D
## The game: everything that is NOT a level. Run this scene (game.tscn).
## It holds the round system (RunManager) and every screen - HUD, pause menu,
## skill tree, run summary - and loads `level` as the world underneath.
## A level is only the world: painting layers, player, platforms, Forger,
## PortalDirector. To make a new level, build a world scene like
## sinan/levels/level.tscn and point `level` at it (or call load_level()).

## The world to play in.
@export var level: PackedScene = preload("res://sinan/levels/level.tscn")

var _world: Node


func _ready() -> void:
	load_level(level)


## Swap in another level (the UI and progress stay).
func load_level(scene: PackedScene) -> void:
	if scene == null:
		return
	var swap := is_instance_valid(_world)
	if swap:
		_world.queue_free()
	_world = scene.instantiate()
	add_child(_world)
	move_child(_world, 0)  # under the screens
	if swap and RunManager.current:  # (the first round starts by itself)
		RunManager.current.start_run.call_deferred()
