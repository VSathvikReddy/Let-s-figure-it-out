## GameState.gd
## Where the menus send the player. It was an autoload in the original
## PAINTSCAPES project; here it is a plain script (an autoload would need a
## change in the shared project.godot), used like this:
##     const GameState := preload("res://compined/intro/scripts/GameState.gd")
##     GameState.start_new_game()
##
##   The main menu is the start menu (compined/levels/start_menu.tscn).
##   Start Game -> the story intro (CinematicIntro) the first time, then
##                 Painting I; after that it opens the painting gallery.
extends RefCounted

const Levels := preload("res://compined/levels/levels.gd")

const MAIN_MENU := "res://compined/levels/start_menu.tscn"
const INTRO := "res://compined/intro/scenes/CinematicIntro.tscn"
## Remembers that the story has been seen (so Continue can be used).
const SAVE_PATH := "user://artiste_save.cfg"


## True once the player has seen the intro / started a game before.
static func has_save() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(SAVE_PATH) == OK and cfg.get_value("progress", "started", false)


static func go_to_main_menu() -> void:
	_tree().change_scene_to_file(MAIN_MENU)


static func start_new_game() -> void:
	_tree().change_scene_to_file(INTRO)


## Continue: back to the painting gallery (or the story, the very first time).
static func continue_game() -> void:
	if has_save():
		Levels.go_to_level_select(_tree())
	else:
		start_new_game()


## After the story: remember it was seen, then play Painting I.
static func go_to_level1() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "started", true)
	cfg.save(SAVE_PATH)
	Levels.load_level(_tree(), 0)


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree
