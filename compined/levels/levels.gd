extends RefCounted
## The list of paintings (levels), and moving between them.
##
## This replaces the team's LevelManager autoload for compined. An autoload
## would need a change in project.godot, so instead the data lives here in
## `static` variables: they are shared by every scene and survive scene
## changes. Use it from any script like this:
##
##     const Levels := preload("res://compined/levels/levels.gd")
##     Levels.load_level(get_tree(), 1)
##     Levels.go_to_level_select(get_tree())
##
## ADDING A LEVEL: make its scene (copy one of the existing ones) and add an
## entry to LIST. The level selector shows a card for it automatically.
##
## LOCKING: only the first painting is open at the start. Finishing a painting
## unlocks the next one; this is saved in user://compined_progress.cfg so it
## is remembered after closing the game. The custom painting is always open.
##
## DIFFICULTY: how hard each painting is comes from difficulty.tres - easy for
## the first painting, hard for the last, rising in a straight line.

const LEVEL_SELECT := "res://compined/levels/level_select.tscn"
const CUSTOM_LEVEL := "res://compined/levels/custom/custom_level.tscn"
const TRANSITION := preload("res://compined/levels/transition.gd")
const DIFFICULTY := preload("res://compined/levels/difficulty.tres")
const PROGRESS_FILE := "user://compined_progress.cfg"

## Every built-in painting, in order. The custom level comes after the last one.
##   title    - name on the card
##   subtitle - one line under it
##   scene    - the level scene
##   preview  - picture shown on the card (the full painting)
const LIST := [
	{
		"title": "Painting I: The Starry Night",
		"subtitle": "Find the 4 hidden gems. Bombers, a turret and a bird guard the sky.",
		"scene": "res://compined/scarry night.tscn",
		"preview": "res://compined/asset/scarry_night.jpg",
	},
	{
		"title": "Painting II: The Skull",
		"subtitle": "A swarm of mini bombers and two turrets. Watch your step.",
		"scene": "res://compined/levels/skull.tscn",
		"preview": "res://compined/asset/skull.jpg",
	},
	{
		"title": "Painting III: The Great Wave",
		"subtitle": "Birds and bats ride the wave. Some bats hide in the rocks.",
		"scene": "res://compined/levels/tsunami.tscn",
		"preview": "res://compined/asset/tsunami.jpg",
	},
]

## Which level is being played (LIST.size() = the custom level).
static var current_index := 0
## The painting the last win unlocked, or -1. The level selector shows it
## opening the next time it is shown, then sets this back to -1.
static var just_unlocked := -1
## How many built-in paintings are open (read from PROGRESS_FILE when first needed).
static var _open_count := -1


# --- locking -----------------------------------------------------------------

static func is_unlocked(index: int) -> bool:
	return index == custom_index() or index < _get_open_count()


## Called when a painting is won. Opens the next one (and saves it).
## Returns true if that opened a painting that was locked before.
static func finish_level(index: int) -> bool:
	var next := index + 1
	if index >= LIST.size() or next >= LIST.size() or is_unlocked(next):
		return false
	_open_count = next + 1
	just_unlocked = next
	_save_progress()
	return true


## Debug: opens every painting at once (and saves it).
static func unlock_all() -> void:
	_open_count = LIST.size()
	just_unlocked = -1
	_save_progress()


## Locks every painting except the first one again (and saves it).
static func lock_all_again() -> void:
	_open_count = 1
	just_unlocked = -1
	_save_progress()


static func _get_open_count() -> int:
	if _open_count < 0:
		var file := ConfigFile.new()
		file.load(PROGRESS_FILE)   # no file yet = nothing finished
		_open_count = clampi(file.get_value("paintings", "open", 1), 1, LIST.size())
	return _open_count


static func _save_progress() -> void:
	var file := ConfigFile.new()
	file.set_value("paintings", "open", _open_count)
	file.save(PROGRESS_FILE)


# --- difficulty --------------------------------------------------------------

## 0 = as easy as the first painting, 1 = as hard as the last (difficulty.tres).
static func difficulty_amount(index: int) -> float:
	return DIFFICULTY.amount_for(index, LIST.size())


## Gives an enemy the health that fits this difficulty. Its own max_health
## (as set in the Inspector) is the 1.0 value; it never goes below 1.
static func scale_enemy_health(enemy: Node, amount: float) -> void:
	if not is_instance_valid(enemy) or enemy.get("max_health") == null:
		return
	if not enemy.has_meta("base_max_health"):
		enemy.set_meta("base_max_health", enemy.max_health)
	var base: int = enemy.get_meta("base_max_health")
	enemy.max_health = maxi(1, roundi(base * DIFFICULTY.enemy_health(amount)))
	enemy.health = enemy.max_health
	var bar = enemy.get("health_bar")
	if bar:
		bar.setup(enemy.max_health)


## Index of the custom level card (it comes after the built-in paintings).
static func custom_index() -> int:
	return LIST.size()


static func load_level(tree: SceneTree, index: int) -> void:
	if index == custom_index():
		current_index = index
		_change_scene(tree, CUSTOM_LEVEL)
	elif index >= 0 and index < LIST.size():
		current_index = index
		if index == just_unlocked:
			just_unlocked = -1   # going straight in: no need to show it opening later
		_change_scene(tree, LIST[index]["scene"])
	else:
		push_warning("Levels: there is no level %d" % index)


## Plays the painting that is open right now again.
static func restart_level(tree: SceneTree) -> void:
	_change_scene(tree, tree.current_scene.scene_file_path)


## Every level calls this when it opens, so the game always knows which
## painting is being played - even when you start a level straight from the
## editor (F5 / F6) instead of from the level selector.
static func remember_current_level(tree: SceneTree) -> void:
	var path := tree.current_scene.scene_file_path
	if path == CUSTOM_LEVEL:
		current_index = custom_index()
		return
	for i in LIST.size():
		if LIST[i]["scene"] == path:
			current_index = i
			return


## True if there is an UNLOCKED built-in painting after the current one.
static func has_next_level() -> bool:
	return current_index + 1 < LIST.size() and is_unlocked(current_index + 1)


static func load_next_level(tree: SceneTree) -> void:
	if has_next_level():
		load_level(tree, current_index + 1)
	else:
		go_to_level_select(tree)


static func go_to_level_select(tree: SceneTree) -> void:
	_change_scene(tree, LEVEL_SELECT)


## The team's LevelManager (a global autoload) draws its own buttons over every
## scene. Compined has its own, so it hides theirs while a compined scene is open.
static func hide_team_overlay(tree: SceneTree, hide: bool) -> void:
	var team_overlay := tree.root.get_node_or_null("LevelManager")
	if team_overlay is CanvasLayer:
		team_overlay.visible = not hide


## Fades to black, switches the scene, fades back in.
static func _change_scene(tree: SceneTree, scene_path: String) -> void:
	var fade = TRANSITION.new()
	tree.root.add_child(fade)
	fade.go_to(scene_path)
