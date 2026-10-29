class_name RunManager
extends Node
## One round = from "Start Run" until the player dies (or ends it from the pause
## menu). Then the run summary shows, then the skill tree, then the next round.
## It keeps the round's time and kills, turns restoring into Entropy as you
## clean, and works out from difficulty.tres:
##   THREAT  - from the round clock (calm 20 s, linear, accelerating,
##             exponential) and kills: spawn speed, Forger visits, toughness
##   CAP     - most enemies alive, from how much of the painting is restored
##   WANTED  - how many the game sends right now, from kills and threat (<= cap)
## Lives in game.tscn (with the UI), so every level gets it. A level played on
## its own, without game.tscn, just plays on forever.

signal run_started
signal run_ended(summary: Dictionary)

enum State { WAITING, RUNNING, ENDED }

## Round pacing, enemy numbers and entropy rate. Edit this while play-testing.
@export var difficulty: Difficulty = preload("res://sinan/systems/run/difficulty.tres")
## Show the round timer at the top of the screen.
@export var show_timer := true

static var current: RunManager

var state := State.WAITING
var run_time := 0.0
var kills := 0
var threat := 0.0
var parts := {}            # the threat's terms, for the debug overlay
var restored := 0.0        # painting restored now (0..1), refreshed twice a second
var entropy_run := 0       # entropy earned this round
var _coins_start := 0
var _restored_start := 0.0
var _entropy_frac := 0.0
var _check_t := 0.0
var _timer_label: Label


func _enter_tree() -> void:
	current = self
	add_to_group("run_manager")
	add_to_group("kill_listeners")


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	if show_timer:
		_make_timer()
	start_run.call_deferred()


func _process(delta: float) -> void:
	if state != State.RUNNING:
		return
	run_time += delta
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.5
		restored = Paint.restored(self)
		Progress.record_clarity(restored)
	_pay_entropy()
	parts = difficulty.threat_parts(run_time, kills, restored)
	threat = parts.total
	if _timer_label:
		_timer_label.text = "%02d:%02d" % [int(run_time) / 60, int(run_time) % 60]


## Restoring the painting pays Entropy as you go.
func _pay_entropy() -> void:
	_entropy_frac += Paint.take_restored(self) * 100.0 * difficulty.entropy_per_percent
	if _entropy_frac >= 1.0:
		var whole := floori(_entropy_frac)
		_entropy_frac -= whole
		entropy_run += whole
		Progress.add_entropy(whole, self)


## Called through the "kill_listeners" group by GameData for every kill.
func on_enemy_killed(_table: StringName) -> void:
	if state == State.RUNNING:
		kills += 1


func is_running() -> bool:
	return state == State.RUNNING


# ---------------------------------------------------------------- start / end

## Clear the level and start a fresh round (the painting, coins and entropy stay).
func start_run() -> void:
	var tree := get_tree()
	for g in [&"enemies", &"bat_flocks", &"enemy_projectiles"]:
		for n in tree.get_nodes_in_group(g):
			n.queue_free()
	tree.call_group("portal_director", "clear_portals")
	tree.call_group("forger", "reset_visit")
	tree.call_group("player", "reset_for_run")
	run_time = 0.0
	kills = 0
	entropy_run = 0
	_entropy_frac = 0.0
	Paint.take_restored(self)  # restoring between rounds does not count
	_coins_start = Progress.coins()
	restored = Paint.restored(self)
	_restored_start = restored
	parts = difficulty.threat_parts(0.0, 0, restored)
	threat = parts.total
	state = State.RUNNING
	tree.paused = false
	run_started.emit()


## End the round: reason is &"death" or &"abort". Shows the run summary.
func end_run(reason: StringName) -> void:
	if state != State.RUNNING:
		return
	_pay_entropy()
	state = State.ENDED
	restored = Paint.restored(self)
	var before_best := Progress.best_clarity()
	Progress.record_clarity(restored)
	get_tree().call_group("painting", "save_mask")
	var pay := int(Progress.stat(&"restore_pay") * maxf(restored - _restored_start, 0.0) * 100.0)
	if pay > 0:
		Progress.add_coins(pay)
	Progress.end_run()
	var best := Progress.best_clarity()
	var summary := {
		"reason": reason,
		"time": run_time,
		"kills": kills,
		"coins": Progress.coins() - _coins_start,
		"entropy": entropy_run,
		"restore_pay": pay,
		"clarity_start": _restored_start,
		"clarity": restored,
		"best": best,
		"new_milestones": difficulty.milestones_reached(best) - difficulty.milestones_reached(before_best),
		"next_milestone": difficulty.next_milestone(best),
		"threat": threat,
	}
	get_tree().paused = true
	Engine.time_scale = 1.0
	run_ended.emit(summary)
	var shown := false
	for s in get_tree().get_nodes_in_group("run_summary"):
		s.show_summary(summary)
		shown = true
	if not shown:  # no summary screen: straight to the tree
		get_tree().call_group("skill_tree", "open")


# ---------------------------------------------------------------- live numbers

## Most enemies that may be alive: the painting's cap (+ Horde upgrade).
func enemy_cap() -> int:
	return difficulty.enemy_cap(restored) + int(Progress.stat(&"horde"))


## How many enemies the game wants alive now (kills + threat), within the cap.
func max_enemies() -> int:
	return mini(difficulty.enemies_wanted(threat, kills), enemy_cap())


func max_portals() -> int:
	return maxi(1, difficulty.max_portals(threat))


func forger_away() -> float:
	# "Restless Forger" (enemy branch) makes him come more often
	return difficulty.forger_away(threat) * maxf(0.3, 1.0 - Progress.stat(&"rift_pace"))


func portals_per_visit() -> int:
	return maxi(1, difficulty.portals_per_visit(threat))


func spawn_interval() -> float:
	return maxf(0.15, difficulty.spawn_interval(threat))


func portal_duration() -> float:
	return difficulty.portal_duration(threat)


func enemy_health() -> float:
	return difficulty.enemy_health(threat)


func _make_timer() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	_timer_label = Label.new()
	_timer_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.offset_left = -130.0
	_timer_label.offset_right = -20.0
	_timer_label.offset_top = 12.0
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_timer_label.add_theme_font_size_override("font_size", 22)
	_timer_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	_timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_timer_label.add_theme_constant_override("outline_size", 5)
	_timer_label.text = "00:00"
	layer.add_child(_timer_label)
	add_child(layer)
