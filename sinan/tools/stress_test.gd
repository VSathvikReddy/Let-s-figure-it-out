extends SceneTree
## Stress test: 100 enemies in the real level, prints the average frame time.
## Run from the project folder (the 60 fps budget is 16.6 ms per frame):
##   godot --path . --disable-vsync --fixed-fps 60 -s res://sinan/tools/stress_test.gd -- mix
## Instead of "mix": goblin, witch, bird, bats, priest, or none (just the level).
## Add --headless to measure the CPU side only (no rendering).
## The player is made untouchable so the workload stays the same every run.
var lvl
var frame := 0
var samples: Array[int] = []
var last := 0
var kind := ""
const WARM := 120
const FRAMES := 600
const ENEMIES := {
	"goblin": "res://sinan/actors/enemies/goblin/goblin.tscn",
	"witch": "res://sinan/actors/enemies/witch/witch.tscn",
	"bird": "res://sinan/actors/enemies/bird/bird.tscn",
	"bats": "res://sinan/actors/enemies/bat/bat_flock.tscn",
	"priest": "res://sinan/actors/enemies/priest/priest.tscn",
}
func _init():
	seed(12345)
	kind = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "mix"
	lvl = load("res://sinan/levels/level.tscn").instantiate()
	root.add_child(lvl)
	current_scene = lvl
	# no Forger / portals adding more
	for n in lvl.find_children("*", "", true, false):
		if n.is_in_group("forger") or n.is_in_group("portal_director"):
			n.queue_free()
func _spawn():
	var nav = get_first_node_in_group("nav_graph")
	var list := []
	if kind == "mix":
		for i in 100: list.append(["goblin","goblin","goblin","witch","bird","bats","priest"][i % 7])
	elif kind == "none":
		pass
	else:
		for i in (9 if kind == "bats" else 100): list.append(kind)
	for k in list:
		var e = load(ENEMIES[k]).instantiate()
		var s: Dictionary = nav.surfaces[randi() % nav.surfaces.size()]
		var p: Vector2 = (s["left"] as Vector2).lerp(s["right"], randf_range(0.1, 0.9)) + Vector2(0, -60)
		if k in ["bird", "bats", "priest"]: p.y -= 200
		e.position = lvl.to_local(p)
		lvl.add_child(e)
func _process(_d):
	frame += 1
	# the player is untouchable: no hit-stops or deaths changing the workload
	var pl = get_first_node_in_group("player")
	if pl:
		pl.set("_invuln", 1e9)
		pl.set("health", 1e9)
	Engine.time_scale = 1.0
	var now := Time.get_ticks_usec()
	if frame == 5:
		_spawn()
	if frame > 5 and OS.get_cmdline_user_args().size() > 1:
		var off: String = OS.get_cmdline_user_args()[1]
		for nd in lvl.find_children("*", "", true, false):
			if off == "anim" and nd is AnimationPlayer: nd.active = false
			elif off == "particles" and nd is CPUParticles2D: nd.emitting = false; nd.set_process(false); nd.visible = false
			elif off == "lights" and nd is PointLight2D: nd.enabled = false
			elif off == "lines" and nd is Line2D: nd.visible = false; nd.set_process(false)
	if frame > WARM and last > 0:
		samples.append(now - last)
	last = now
	if frame >= WARM + FRAMES:
		samples.sort()
		var sum := 0
		for s in samples: sum += s
		var units: int = get_nodes_in_group("enemies").size() - get_nodes_in_group("swarm").size() + get_nodes_in_group("bat_flocks").size()
		var cal := _calibrate()
		print("NORM %-7s %.2f  (avg %.2f ms, calibration %.2f ms)" % [kind, sum / 1000.0 / samples.size() / cal, sum / 1000.0 / samples.size(), cal])
		print("BENCH %-7s avg %.2f ms  p95 %.2f ms  worst %.2f ms  phys %.2f ms  proc %.2f ms  nodes %d  enemies %d  units %d" % [kind,
			sum / 1000.0 / samples.size(), samples[int(samples.size() * 0.95)] / 1000.0, samples[-1] / 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), get_nodes_in_group("enemies").size(), units])
		quit()
	return false

## A fixed CPU workload: the game's cost is reported relative to it, so a
## throttled (hot / power-saving) CPU does not skew the comparison.
func _calibrate() -> float:
	var best := INF
	for r in 5:
		var t0 := Time.get_ticks_usec()
		var acc := 0.0
		var v := Vector2.ONE
		for i in 200000:
			v = v.rotated(0.001) * 1.0000001
			acc += v.x * 0.5
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
	return best
