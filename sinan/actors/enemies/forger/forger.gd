extends Node2D
## The Forger: the painter's ink shadow. Herobrine-style - he is gone most of
## the time, then turns up somewhere near you, does ONE thing and vanishes:
##   - GLIMPSE: just stands and watches. Get close or aim at him and he is gone.
##   - PORTAL (his main job): tears one or two rifts open, lingers a moment and
##     leaves. Portals are ONLY opened by him, and they stay open far longer than
##     his visit (the PortalDirector runs them).
##   - BLACK HOLE: void orbs gather around him, split up and fly at several of
##     the cleanest spots of the painting, tearing each into a black hole.
## He never animates his actions: he always stands still in his idle pose and
## faces the player. He arrives and leaves through a small black hole.
## Drag forger.tscn into a level once; he finds the player through the
## "player" group. Visuals are nodes in forger.tscn (a shadow copy of the player
## rig) so they follow your player art.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const Portal := preload("res://sinan/world/portals/portal.gd")
const BlackHole := preload("res://sinan/fx/blasts/black_hole.gd")
const TargetMarker := preload("res://sinan/actors/enemies/forger/target_marker.gd")
const PaintPicker := preload("res://sinan/painting/paint_picker.gd")
const ForgerOrb := preload("res://sinan/actors/enemies/forger/forger_orb.gd")
const SILHOUETTE := preload("res://sinan/shaders/shadow_silhouette.gdshader")

const RIG_FEET_Y := 62.0  # feet height in rig units (same rig as the player)

enum State { HIDDEN, APPEARING, GLIMPSE, PORTAL, CASTING, VANISHING }
enum Act { GLIMPSE, PORTAL, BLACK_HOLE }

## When he visits, how many portals he opens and what comes out of them:
## the Spawning / Forger Visits sections of game_data.tres.
@export var game_data: GameData = preload("res://sinan/systems/data/game_data.tres")

@export_group("Timing")
## He fades in / out inside a small black hole over these times.
@export var appear_time := 0.6
@export var vanish_time := 0.45
## Size of the small black hole he arrives and leaves through.
@export var entrance_hole_radius := 70.0

@export_group("Act Chances")
## Relative weights for what he does when he shows up.
@export var glimpse_weight := 0.6
@export var portal_weight := 4.0
@export var black_hole_weight := 1.2
## No black hole twice in a row; also needs this many appearances in between.
@export var black_hole_min_gap := 2

@export_group("Where He Appears")
## Distance from the player (left or right) he appears at.
@export var appear_distance_min := 220.0
@export var appear_distance_max := 480.0
## How far down to look for the floor at the chosen spot.
@export var floor_search := 1200.0

@export_group("Glimpse")
## Seconds he watches before vanishing on his own.
@export var glimpse_time := 2.5
## Vanishes instantly if the player comes this close...
@export var flee_distance := 150.0
## ...or puts the reticle this close to him.
@export var flee_aim_distance := 60.0

@export_group("Portal")
## Portal size, only used when the level has no PortalDirector.
@export var portal_height := 130.0
@export var portal_width := 60.0
## Where the portal opens relative to him (x is mirrored toward the player).
@export var portal_offset := Vector2(70, -85)
## Seconds he lingers after tearing them open before leaving.
@export var linger_after_portal := 2.5

@export_group("Black Hole")
## Orbs circle around him and charge for this long before launching.
@export var black_hole_windup := 1.6
## Black holes torn into the painting per attack (each needs its own clean spot).
@export var black_hole_count := 3
## Black holes keep at least this far apart (painting px).
@export var black_hole_spacing := 320.0
## Total orbs; they split evenly between the black holes.
@export var orb_count := 6
@export var orb_ring_radius := 70.0
@export var orb_size := 9.0
## Seconds between orbs launching (they leave one after another).
@export var orb_launch_interval := 0.12
@export var orb_fly_speed := 900.0
@export var orb_glow_color := Color(0.85, 0.9, 1.0)
## Smudge radius on the painting (painting layer px).
@export var smudge_radius := 200.0
## 1 = one detail level worse at the centre, 2 = two levels...
@export var smudge_strength := 1.5
## Size of the black hole effect itself.
@export var black_hole_visual_radius := 130.0
@export var black_hole_shake := 0.35

@export_group("Size")
## Scale his body to exactly match the player's (ignores the scale you give this node).
@export var match_player_size := true
## Extra size on top of that (1 = same as the player).
@export var size_multiplier := 1.15

@export_group("Float")
## How high he hovers above the floor (world px).
@export var hover_height := 38.0
## Up-and-down float (world px) and seconds per full bob. Eased by a sine.
@export var bob_amount := 7.0
@export var bob_period := 2.6
## Soft shadow on the floor under him.
@export var ground_shadow := true
@export var ground_shadow_size := 26.0
@export_range(0.0, 1.0) var ground_shadow_opacity := 0.45

@export_group("Floating Pose")
## Superman-style power pose, set in code (the AnimationPlayer is not used).
## Arm directions in degrees: 0 = straight forward, -90 = straight up, 180 = back.
@export var front_arm_angle := -22.0
@export var back_arm_angle := -158.0
## Gentle eased sway of the arms, head and legs (degrees), in sync with the bob.
@export var pose_sway := 4.0
## Chin up / lean back (degrees, negative = back).
@export var head_tilt := -8.0
@export var body_lean := -3.0
## Legs hang together, toes slightly back (degrees).
@export var front_leg_angle := 7.0
@export var back_leg_angle := 2.5
## Angle the arm is drawn at in the body-part image.
@export var arm_image_angle := -46.5

@export_group("Look")
## Hollow Knight shade look: a void-black body with a faint cold edge.
@export var shadow_color := Color(0.012, 0.012, 0.018)
## Soft, blurry border (texture pixels of the body parts) and how much it wavers.
@export var edge_blur := 9.0
@export var edge_wobble := 3.0
## Faint dark smoke just outside his body.
@export_range(0.0, 1.0) var edge_haze := 0.45
@export var eye_color := Color(1.0, 1.0, 1.0)
## Eyes flicker slightly; 0 = steady.
@export_range(0.0, 1.0) var eye_flicker := 0.15
## Subtractive light that darkens the world around him (0 = off).
@export var darkness_aura_strength := 0.8
@export var darkness_aura_size := 6.0
## Shadow wisps rising off his body.
@export var wisp_amount := 30
@export var smoke_color := Color(0.02, 0.02, 0.03)
@export var magic_color := Color(0.7, 0.35, 1.0)

@export_group("Animation Names")
@export var anim_idle := &"idle"

@onready var visual: Node2D = $Visual
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var eye: CanvasItem = $Visual/Body/Rig/Head/Eyes
@onready var _rig: Node2D = $Visual/Body/Rig

var _state := State.HIDDEN
var _act := Act.GLIMPSE
var _t := 0.0
var _wait := 0.0
var _since_black_hole := 99
var _face := 1.0
var _player
var _targets: Array[Dictionary] = []   # {layer, local, marker, orbs_left}
var _smoke: CPUParticles2D
var _orbs_left := 0
var _float_t := 0.0
var _aura: PointLight2D


func _ready() -> void:
	add_to_group("forger")
	anim.stop()
	z_index = 1
	visible = false
	_wait = game_data.forger_first_visit
	# every body part becomes a soft-edged living shadow (eyes stay bright)
	var mat := ShaderMaterial.new()
	mat.shader = SILHOUETTE
	mat.set_shader_parameter("fill_color", shadow_color)
	mat.set_shader_parameter("edge_blur", edge_blur)
	mat.set_shader_parameter("edge_wobble", edge_wobble)
	mat.set_shader_parameter("haze", edge_haze)
	for s in visual.find_children("*", "Sprite2D", true, false):
		if not eye.is_ancestor_of(s):
			(s as Sprite2D).material = mat
	eye.modulate = eye_color
	_smoke = FxLib.emitter({
		"one_shot": false, "amount": wisp_amount, "life": 1.2, "v_min": 15.0, "v_max": 45.0,
		"direction": Vector2.UP, "spread": 25.0, "gravity": Vector2(0, -60), "emit_radius": 20.0,
		"ramp": FxLib.gradient([[0.0, Color(smoke_color, 0.0)], [0.25, Color(smoke_color, 0.55)], [1.0, Color(smoke_color, 0.0)]]),
		"s_min": 0.2, "s_max": 0.55, "curve": FxLib.grow(),
	})
	_smoke.position = Vector2(0, -40 - hover_height)
	_smoke.show_behind_parent = true
	_smoke.z_index = -1
	_smoke.emitting = false
	add_child(_smoke)
	if darkness_aura_strength > 0.0:
		_aura = PointLight2D.new()
		_aura.texture = FxLib.glow()
		_aura.blend_mode = Light2D.BLEND_MODE_SUB
		_aura.energy = darkness_aura_strength
		_aura.texture_scale = darkness_aura_size
		_aura.position = Vector2(0, -50 - hover_height)
		add_child(_aura)


func _process(delta: float) -> void:
	_t += delta
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	match _state:
		State.HIDDEN:
			_wait -= delta
			if _wait <= 0.0 and is_instance_valid(_player) and _player.is_alive():
				_appear()
		State.APPEARING:
			modulate.a = clampf(_t / appear_time, 0.0, 1.0)
			if _t >= appear_time:
				_start_act()
		State.GLIMPSE:
			_face_player()
			if _t >= glimpse_time or _player_too_close():
				_vanish()
		State.PORTAL:
			_face_player()
			if _t >= linger_after_portal:
				_vanish()
		State.CASTING:
			_face_player()
			# waits for the orbs: the last one to land triggers the black hole
		State.VANISHING:
			modulate.a = 1.0 - clampf(_t / vanish_time, 0.0, 1.0)
			if _t >= vanish_time:
				_hide()
	if _state != State.HIDDEN:
		visual.scale = Vector2(_face, 1.0)
		_float_t += delta
		visual.position.y = -_lift()
		_apply_pose()
		queue_redraw()
		eye.modulate.a = 1.0 - eye_flicker * (0.5 + 0.5 * sin(_t * 9.0))


## Floating power pose with a slow eased sway (in sync with the bob).
func _apply_pose() -> void:
	var sway := sin(_float_t * TAU / maxf(bob_period, 0.1)) * deg_to_rad(pose_sway)
	var base := deg_to_rad(arm_image_angle)
	_rig.position = Vector2.ZERO
	_rig.rotation = deg_to_rad(body_lean)
	_rig.get_node("FrontArm").rotation = deg_to_rad(front_arm_angle) - base + sway
	_rig.get_node("BackArm").rotation = deg_to_rad(back_arm_angle) - base - sway
	_rig.get_node("Head").rotation = deg_to_rad(head_tilt) + sway * 0.5
	_rig.get_node("Torso").rotation = sway * 0.4
	_rig.get_node("FrontLeg").rotation = deg_to_rad(front_leg_angle) + sway * 0.6
	_rig.get_node("BackLeg").rotation = deg_to_rad(back_leg_angle) + sway * 0.6


## Current height above the floor: hover plus an eased sine bob.
func _lift() -> float:
	return hover_height + sin(_float_t * TAU / maxf(bob_period, 0.1)) * bob_amount


func _draw() -> void:
	if not ground_shadow or _state == State.HIDDEN:
		return
	# soft, flattened shadow that shrinks and fades as he rises
	var up := clampf((_lift() - hover_height + bob_amount) / maxf(bob_amount * 2.0, 0.01), 0.0, 1.0)
	var w := ground_shadow_size * lerpf(1.05, 0.85, up)
	var a := ground_shadow_opacity * lerpf(1.0, 0.7, up)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.22))
	for i in 4:
		var k := 1.0 - i * 0.22
		draw_circle(Vector2.ZERO, w * (1.0 + i * 0.35), Color(0, 0, 0, a * 0.35 * k))


func _set_state(s: State) -> void:
	_state = s
	_t = 0.0


# ---------------------------------------------------------------- appearing

func _appear() -> void:
	var spot: Variant = _find_spot()
	if spot == null:
		_wait = 1.0  # try again shortly
		return
	global_position = spot
	_match_player_size()
	_face_player()
	visible = true
	modulate.a = 0.0
	_smoke.emitting = true
	_entrance_hole()
	_set_state(State.APPEARING)
	anim.stop()  # the floating pose is set in code (_apply_pose)


## Make his body the same on-screen size as the player's rig.
func _match_player_size() -> void:
	if not match_player_size or not is_instance_valid(_player):
		return
	var player_body := _player.get_node_or_null("Visual/Body") as Node2D
	if player_body == null:
		return
	scale = Vector2.ONE  # effects and portal offsets are in world units
	var body := $Visual/Body as Node2D
	# player node scale x its Body scale (skips the flip / squash on its Visual)
	var k := absf((_player as Node2D).global_scale.y) * absf(player_body.scale.y) * size_multiplier
	body.scale = Vector2(k, k)
	body.position.y = -RIG_FEET_Y * k


## Floor point to the left or right of the player, or null.
func _find_spot() -> Variant:
	var space := get_world_2d().direct_space_state
	var p: Vector2 = _player.global_position
	for attempt in 6:
		var side := -1.0 if randf() < 0.5 else 1.0
		var x := p.x + side * randf_range(appear_distance_min, appear_distance_max)
		var from := Vector2(x, p.y - 300.0)
		var ex: Array[RID] = []
		if _player is CollisionObject2D:
			ex.append(_player.get_rid())
		var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(from, from + Vector2(0, floor_search), 1, ex))
		if not hit.is_empty():
			return hit.position
	return null


func _start_act() -> void:
	_act = _pick_act()
	match _act:
		Act.GLIMPSE:
			_set_state(State.GLIMPSE)
		Act.PORTAL:
			if _open_portals() == 0:
				_set_state(State.GLIMPSE)  # limit reached: he just watches
			else:
				_set_state(State.PORTAL)
		Act.BLACK_HOLE:
			_targets = _pick_painting_targets(black_hole_count)
			if _targets.is_empty():
				_set_state(State.GLIMPSE)
				return
			_since_black_hole = 0
			_set_state(State.CASTING)
			for i in _targets.size():
				_place_marker(i)
			_summon_orbs()


func _pick_act() -> Act:
	var w_portal := portal_weight if game_data.can_spawn(get_tree()) and _portal_room() else 0.0
	var w_hole := black_hole_weight if _since_black_hole >= black_hole_min_gap else 0.0
	_since_black_hole += 1
	var total := glimpse_weight + w_portal + w_hole
	var r := randf() * total
	if r < w_hole:
		return Act.BLACK_HOLE
	if r < w_hole + w_portal:
		return Act.PORTAL
	return Act.GLIMPSE


func _player_too_close() -> bool:
	if not is_instance_valid(_player):
		return false
	if global_position.distance_to(_player.global_position as Vector2) <= flee_distance:
		return true
	var aim: Variant = _player.call("aim_point") if _player.has_method("aim_point") else null
	return aim != null and (aim as Vector2).distance_to(global_position + Vector2(0, -50 - hover_height)) <= flee_aim_distance


func _face_player() -> void:
	if is_instance_valid(_player):
		var dx: float = _player.global_position.x - global_position.x
		if absf(dx) > 2.0:
			_face = signf(dx)


func _vanish() -> void:
	if _state == State.VANISHING or _state == State.HIDDEN:
		return
	_entrance_hole()
	_smoke.emitting = false
	_set_state(State.VANISHING)


## The small black hole he arrives and leaves through.
func _entrance_hole() -> void:
	var bh := BlackHole.new()
	bh.radius = entrance_hole_radius
	bh.rim_color = orb_glow_color
	bh.grow_time = 0.2
	bh.hold_time = maxf(appear_time, vanish_time)
	bh.collapse_time = 0.15
	var world := get_parent()
	bh.position = FxLib.to_parent_space(world, global_position + Vector2(0, -55 - hover_height))
	bh.particles = false
	world.add_child(bh)


func _hide() -> void:
	visible = false
	_set_state(State.HIDDEN)
	_wait = game_data.forger_away_time()


# ---------------------------------------------------------------- acts

func _director() -> Node:
	return get_tree().get_first_node_in_group("portal_director")


## True if another portal may open right now.
func _portal_room() -> bool:
	var d := _director()
	if d == null:
		return true
	var open := 0
	for c in get_parent().get_children():
		if c.get_script() == Portal:
			open += 1
	return open < d.portal_limit()


## Tear open 1-2 portals beside him (the director runs them). Returns how many opened.
func _open_portals() -> int:
	var count := game_data.portals_per_visit()
	var opened := 0
	for i in count:
		var side := _face if i == 0 else -_face  # first in front of him, second behind
		var at := global_position + Vector2(portal_offset.x * side * (1.0 + i * 0.6), portal_offset.y - hover_height * 0.5)
		if _open_portal_at(at):
			opened += 1
	return opened


func _open_portal_at(at: Vector2) -> bool:
	var d := _director()
	if d:
		return d.open_portal(at) != null
	# no director in the level: run the portal ourselves
	var p := Portal.new()
	p.height = portal_height
	p.max_width = portal_width
	p.spawn_duration = game_data.portal_duration()
	p.enemies_to_spawn = game_data.portal_enemy_count(p.spawn_duration)
	p.game_data = game_data
	p.glow_color = magic_color
	var world := get_parent()
	p.position = FxLib.to_parent_space(world, at)
	world.add_child(p)
	return true


## Up to `count` clean (restored) spots of the painting, spread apart.
func _pick_painting_targets(count: int) -> Array[Dictionary]:
	var vp := get_viewport()
	var view_to_world := vp.get_canvas_transform().affine_inverse()
	var view := vp.get_visible_rect()
	var candidates: Array[Dictionary] = []
	for attempt in 30:
		var screen := view.position + Vector2(randf_range(0.1, 0.9) * view.size.x, randf_range(0.08, 0.6) * view.size.y)
		var world_pos: Vector2 = view_to_world * screen
		var pick := PaintPicker.pick(get_parent(), world_pos)
		if pick.is_empty():
			continue
		var layer = pick["layer"]
		pick["value"] = layer.distortion_at(pick["local"]) if layer.has_method("distortion_at") else 0.0
		pick["world"] = world_pos
		candidates.append(pick)
	candidates.sort_custom(func(a, b): return a["value"] < b["value"])
	var chosen: Array[Dictionary] = []
	for c in candidates:
		var ok := true
		for o in chosen:
			if (c["world"] as Vector2).distance_to(o["world"]) < black_hole_spacing:
				ok = false
				break
		if ok:
			chosen.append({"layer": c["layer"], "local": c["local"], "world": c["world"], "orbs_left": 0, "marker": null})
			if chosen.size() >= count:
				break
	return chosen


## Void orbs gather around him, charge, then split up and fly to the targets.
func _summon_orbs() -> void:
	var world := get_parent()
	var n := maxi(orb_count, _targets.size())
	for i in n:
		var ti := i % _targets.size()
		_targets[ti]["orbs_left"] += 1
		var o := ForgerOrb.new()
		o.center = self
		o.center_offset = Vector2(0, -60 - hover_height)
		o.angle = TAU * i / n
		o.orbit_radius = orb_ring_radius
		o.charge_time = black_hole_windup
		o.launch_delay = i * orb_launch_interval
		o.fly_speed = orb_fly_speed
		o.orb_radius = orb_size
		o.glow_color = orb_glow_color
		o.target_layer = _targets[ti]["layer"]
		o.target_local = _targets[ti]["local"]
		o.on_arrive = _on_orb_arrived.bind(ti)
		o.position = FxLib.to_parent_space(world, global_position + Vector2(0, -60 - hover_height))
		world.add_child(o)


func _on_orb_arrived(ti: int) -> void:
	if ti >= _targets.size():
		return
	_targets[ti]["orbs_left"] -= 1
	get_tree().call_group("player", "add_trauma", 0.05, global_position)
	if _targets[ti]["orbs_left"] == 0:
		_unleash_black_hole(ti)
	var all_done := true
	for t in _targets:
		if t["orbs_left"] > 0:
			all_done = false
	if all_done and _state == State.CASTING:
		_vanish()


func _place_marker(ti: int) -> void:
	var layer: Node = _targets[ti]["layer"]
	var m := TargetMarker.new()
	m.radius = smudge_radius * 0.5
	m.color = magic_color
	m.position = _targets[ti]["local"]
	layer.add_child(m)
	_targets[ti]["marker"] = m


func _unleash_black_hole(ti: int) -> void:
	var t := _targets[ti]
	if is_instance_valid(t["marker"]):
		(t["marker"] as Node).queue_free()
	var layer = t.get("layer")
	if not is_instance_valid(layer):
		return
	var bh := BlackHole.new()
	bh.radius = black_hole_visual_radius
	bh.particles = false
	bh.rim_color = magic_color
	bh.position = t["local"]
	layer.add_child(bh)
	Paint.hit(self, layer, t["local"], smudge_radius, smudge_strength, Paint.Kind.SMUDGE, &"forger")
	get_tree().call_group("player", "add_trauma", black_hole_shake, global_position)


func _exit_tree() -> void:
	for t in _targets:
		if is_instance_valid(t.get("marker")):
			(t["marker"] as Node).queue_free()
