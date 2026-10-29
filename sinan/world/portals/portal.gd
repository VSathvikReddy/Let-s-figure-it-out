extends Node2D
## Interdimensional tear the Forger cuts open. A white-hot line is slashed into
## the air, splits open into a jagged rift showing a dark swirling void, pours
## out enemies for `spawn_duration` seconds, then pinches shut.
## Everything is set by the Forger before it is added to the tree.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const WarpRipple := preload("res://sinan/fx/blasts/warp_ripple.gd")

enum Phase { CUT, OPEN, SPAWN, CLOSE }

var height := 120.0          # height of the tear
var max_width := 55.0        # how wide it opens
var cut_time := 0.7   # the line appears (grows from its centre, flickers) before it tears
var open_time := 0.45
var spawn_duration := 3.0
var close_time := 0.3
var enemies_to_spawn := 4
## Picks the enemies and holds the "how many alive" limit.
var game_data: GameData
var edge_color := Color(1.0, 0.95, 1.0)
var glow_color := Color(0.7, 0.35, 1.0)
var void_color := Color(0.03, 0.0, 0.06)
## Called when the portal snaps shut.
var on_closed: Callable

var _phase := Phase.CUT
var _t := 0.0
var _age := 0.0
var _spawned := 0
var _jag := PackedFloat32Array()   # random edge jitter
var _light: PointLight2D


func _ready() -> void:
	z_index = 1
	for i in 13:
		_jag.append(randf_range(0.6, 1.25))
	_light = PointLight2D.new()
	_light.texture = FxLib.glow()
	_light.color = glow_color
	_light.energy = 0.0
	_light.texture_scale = height / 40.0
	add_child(_light)
	get_tree().call_group("player", "add_trauma", 0.15, global_position)


func _process(delta: float) -> void:
	_t += delta
	_age += delta
	match _phase:
		Phase.CUT:
			if _t >= cut_time:
				_next(Phase.OPEN)
				FxLib.flash_light(get_parent(), global_position, edge_color, 1.6, height / 50.0, 0.2)
				var r := WarpRipple.new()
				r.radius = height * 0.8
				r.position = position
				get_parent().add_child(r)
		Phase.OPEN:
			if _t >= open_time:
				_next(Phase.SPAWN)
		Phase.SPAWN:
			var interval := spawn_duration / maxf(enemies_to_spawn, 1)
			# one per frame at most; while the level is full it waits (and tries
			# again) instead of using up the spawn
			if _spawned < enemies_to_spawn and _t >= _spawned * interval:
				_spawn_enemy()
			if _t >= spawn_duration:
				_next(Phase.CLOSE)
		Phase.CLOSE:
			if _t >= close_time:
				_snap_shut()
				return
	_light.energy = _openness() * 1.8 + 0.2 * sin(_age * 20.0)
	queue_redraw()


func _next(p: Phase) -> void:
	_phase = p
	_t = 0.0


## 0 = just a line, 1 = fully open.
func _openness() -> float:
	match _phase:
		Phase.CUT:
			return 0.0
		Phase.OPEN:
			var k := clampf(_t / open_time, 0.0, 1.0)
			return 1.0 - pow(1.0 - k, 3.0)
		Phase.SPAWN:
			return 1.0 + 0.04 * sin(_age * 9.0)
		Phase.CLOSE:
			return 1.0 - clampf(_t / close_time, 0.0, 1.0)
	return 0.0


func _spawn_enemy() -> void:
	if game_data == null or not game_data.can_spawn(get_tree()):
		return
	var scene := game_data.pick_enemy(get_tree())
	if scene == null:
		return
	_spawned += 1
	var e := scene.instantiate() as Node2D
	e.position = position + Vector2(randf_range(-max_width, max_width) * 0.3, height * 0.15)
	get_parent().add_child(e)
	if e is CharacterBody2D:
		(e as CharacterBody2D).velocity = Vector2(randf_range(-260.0, 260.0), randf_range(-420.0, -240.0))
	# ink splash as it tumbles out
	FxLib.burst(get_parent(), {
		"amount": 12, "life": 0.5, "v_min": 80.0, "v_max": 220.0, "gravity": Vector2(0, 600),
		"s_min": 0.08, "s_max": 0.18,
		"ramp": FxLib.gradient([[0.0, Color(0.1, 0.0, 0.2, 1.0)], [1.0, Color(0.1, 0.0, 0.2, 0.0)]]),
	}, e.global_position)
	FxLib.flash_light(get_parent(), e.global_position, glow_color, 1.5, 1.2, 0.2)


func _snap_shut() -> void:
	if on_closed.is_valid():
		on_closed.call()
	FxLib.burst(get_parent(), {
		"amount": 16, "life": 0.4, "v_min": 120.0, "v_max": 300.0,
		"texture": FxLib.streak(), "align": true, "angle_min": 0.0, "angle_max": 0.0,
		"spin_min": 0.0, "spin_max": 0.0, "s_min": 0.25, "s_max": 0.5,
		"ramp": FxLib.fade_ramp(glow_color), "additive": true,
	}, global_position)
	FxLib.flash_light(get_parent(), global_position, edge_color, 2.0, height / 50.0, 0.2)
	get_tree().call_group("player", "add_trauma", 0.12, global_position)
	queue_free()


func _draw() -> void:
	var h := height * 0.5
	if _phase == Phase.CUT:
		# a hairline appears in the air: grows out from its centre, then flickers
		# brighter and brighter until it tears
		var k := clampf(_t / maxf(cut_time, 0.001), 0.0, 1.0)
		var grow := 1.0 - pow(1.0 - clampf(k / 0.6, 0.0, 1.0), 3.0)
		var strain := clampf((k - 0.6) / 0.4, 0.0, 1.0)
		var flick := 0.75 + 0.25 * sin(_age * 60.0)
		var a := Vector2(-6.0, -h) * grow
		var b := Vector2(6.0, h) * grow
		draw_line(a, b, Color(glow_color, 0.35 * flick), 6.0 + 8.0 * strain, true)
		draw_line(a, b, Color(edge_color, flick), 1.5 + 1.5 * strain, true)
		if strain > 0.0:
			# tiny jagged cracks start to split off the line
			for i in 4:
				var u := (i + 0.5) / 4.0
				var p := a.lerp(b, u)
				var side := 1.0 if i % 2 == 0 else -1.0
				draw_line(p, p + Vector2(side * 6.0 * strain, -4.0), Color(edge_color, strain), 1.0, true)
		return
	var w := max_width * 0.5 * _openness()
	# jagged lens-shaped rift (wide in the middle, pointed at both ends)
	var right := PackedVector2Array()
	var left := PackedVector2Array()
	var n := _jag.size()
	for i in n:
		var u := float(i) / (n - 1)
		var y := lerpf(-h, h, u)
		var bulge := sin(PI * u) * w
		right.append(Vector2(bulge * _jag[i] + 6.0 * (u - 0.5) * 2.0, y))
		left.append(Vector2(-bulge * _jag[n - 1 - i] + 6.0 * (u - 0.5) * 2.0, y))
	left.reverse()
	var poly := right + left
	if w > 0.5:
		var glow := PackedVector2Array()
		for p in poly:
			glow.append(p * Vector2(1.5, 1.08))
		draw_colored_polygon(glow, Color(glow_color, 0.35))
		draw_colored_polygon(poly, void_color)
		# swirling specks inside the void
		for i in 10:
			var a := _age * (1.5 + i * 0.2) + i * 1.3
			var r := w * 0.6 * ((i % 4) + 1) / 4.0
			var p := Vector2(cos(a) * r, sin(a * 0.7) * h * 0.6)
			draw_circle(p, 1.5, Color(glow_color, 0.7))
	poly.append(poly[0])
	draw_polyline(poly, edge_color, 2.0, true)
