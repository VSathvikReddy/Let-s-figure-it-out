extends Node2D
## Batched coin drops, built for thousands of pieces at once.
##
## How it stays cheap:
##  - No node per piece: everything lives in packed arrays.
##  - Arrays are partitioned: [0, _n_active) = flying / being pulled (simulated
##    every frame), [_n_active, n) = resting on the floor (only a quarter of them
##    get a quick magnet check per frame).
##  - Each pickup kind has 2 MultiMeshes (active + resting, each with a glow
##    pass): one draw call each. The resting buffers are rebuilt at most a few
##    times a second; when a resting piece is collected only its slot is hidden.
##  - Bob and end-of-life blink run in the shader (pickup_piece.gdshader).
##
## Pieces burst out, spin, bounce like coins, settle, then fly to the player.
## Created automatically by GameData.spawn_drops(); add one to a level yourself
## to tweak the exports per level.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const PIECE_SHADER := preload("res://sinan/shaders/pickup_piece.gdshader")
const GLOW_SHADER := preload("res://sinan/shaders/pickup_glow.gdshader")

enum { WAITING, AIR, MAGNET, LANDED, REST, RIDE }
const STRIDE := 16  # 2D transform (8) + colour (4) + custom (4) floats per instance

@export var game_data: GameData = preload("res://sinan/systems/data/game_data.tres")

@export_group("Look")
## On-screen size of one piece (world px).
@export var piece_size := 24.0
## Flat (in-plane) tumble while flying, radians/second. The 3D coin flip is
## done by the shader (Coin Spin Speed).
@export var spin_speed := 0.0
## 3D flip of the coin around its vertical axis (turns per second).
@export var coin_spin_speed := 0.9
## Coin thickness (fraction of its radius) - the edge you see as it turns.
@export var coin_thickness := 0.24
## Soft additive glow behind every piece (one extra draw call per type/layer).
@export var draw_glow := true
@export var glow_size := 2.4
@export_range(0.0, 1.0) var glow_alpha := 0.6
## Glow of pieces lying on the floor (dimmer, so big piles don't turn into a white strip).
@export_range(0.0, 1.0) var rest_glow_alpha := 0.35
## Idle bob of pieces lying on the floor (done on the GPU).
@export var rest_bob := 2.0
@export var rest_bob_speed := 4.0
## Pieces ignore the level's darkening/lights and get this colour boost so they pop.
@export var brightness := 1.35
@export var saturation := 1.15

@export_group("Physics")
@export var fall_gravity := 1500.0
## Bounciness on the floor (0 = dead stop, 1 = no energy lost).
@export_range(0.0, 1.0) var bounce := 0.5
## Horizontal speed kept on each bounce.
@export_range(0.0, 1.0) var bounce_friction := 0.75
## Pieces stop bouncing below this vertical speed.
@export var settle_speed := 110.0

@export_group("Collect")
## Seconds before a piece can be picked up (so the burst reads).
@export var magnet_delay := 0.6
## When the player comes this close, the piece flies straight to them.
@export var magnet_range := 170.0
## Speed it starts flying at, and how fast that speed ramps up. It always moves
## in a straight line directly at the player, so it can never orbit.
@export var fly_start_speed := 350.0
@export var fly_speed_ramp := 2500.0
@export var collect_distance := 22.0
## Resting pieces are magnet-checked in this many groups (1 group per frame).
## Higher = cheaper with huge counts, but pieces react a frame or two later.
@export_range(1, 8) var rest_check_groups := 4

@export_group("Lifetime")
## Seconds before an uncollected piece vanishes (0 = never - coins stay until collected).
@export var lifetime := 0.0
@export var blink_time := 4.0

@export_group("Performance")
## How often newly landed pieces are moved into the resting buffers (seconds).
@export var rest_flush_interval := 0.2

@export_group("Feedback")
## Merges collected pieces into one "+N" popup per type every this many seconds.
@export var popup_interval := 0.3
@export var popup_font_size := 18
@export var sparkles := true
## Cap on sparkles per frame (keeps mass pickups cheap).
@export var max_sparkles_per_frame := 12

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _born := PackedFloat32Array()   # spawn time (in the future while waiting to pop out)
var _ride: Array = []                # RIDE: the board it lies on
var _ride_local := PackedVector2Array()  # RIDE: where on that board
var _rot := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _type := PackedInt32Array()
var _state := PackedInt32Array()
var _slot := PackedInt32Array()     # slot in its type's resting buffer, -1 if none
var _n_active := 0

var _act_mm: Array[MultiMesh] = []
var _act_glow: Array[MultiMesh] = []
var _rest_mm: Array[MultiMesh] = []
var _rest_glow: Array[MultiMesh] = []
var _piece_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
var _rest_hidden := 0
var _rest_total := 0
var _pending_land := 0
var _flush_t := 0.0

var _player
var _clock := 0.0
var _frame := 0
var _popup_t := 0.0
var _pending := {}  # type -> collected count waiting for a popup

# collect sparkles: a tiny pool drawn by this node
var _spark_pos := PackedVector2Array()
var _spark_t := PackedFloat32Array()
var _spark_col := PackedColorArray()
const SPARK_LIFE := 0.3


func _ready() -> void:
	add_to_group("pickup_field")
	z_index = 3
	_piece_mat = _make_material(PIECE_SHADER)
	_glow_mat = _make_material(GLOW_SHADER)
	for t in GameData.Pickup.size():
		var icon := game_data.piece_icon(t) if game_data else null
		_rest_mm.append(_make_layer(icon, false, t))
		_rest_glow.append(_make_layer(FxLib.glow(), true, t, rest_glow_alpha) if draw_glow else null)
		_act_mm.append(_make_layer(icon, false, t))
		_act_glow.append(_make_layer(FxLib.glow(), true, t, glow_alpha) if draw_glow else null)


func _make_material(shader: Shader) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("bob_amount", rest_bob)
	mat.set_shader_parameter("bob_speed", rest_bob_speed)
	mat.set_shader_parameter("blink_time", blink_time if lifetime > 0.0 else 0.0)
	mat.set_shader_parameter("brightness", brightness)
	mat.set_shader_parameter("saturation", saturation)
	mat.set_shader_parameter("spin_speed", coin_spin_speed)
	mat.set_shader_parameter("thickness", coin_thickness)
	return mat


func _make_layer(tex: Texture2D, glow: bool, t: int, alpha := 1.0) -> MultiMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * piece_size * (glow_size if glow else 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	# fixed bounds: the resting buffers are written rarely and Godot's lazily
	# computed bounds went stale, culling every settled coin (they "vanished")
	mm.custom_aabb = AABB(Vector3(-100000, -100000, -1), Vector3(200000, 200000, 2))
	mm.instance_count = 0
	var mmi := MultiMeshInstance2D.new()
	mmi.multimesh = mm
	mmi.texture = tex
	mmi.material = _glow_mat if glow else _piece_mat
	if glow:
		mmi.modulate = Color(game_data.piece_color(t) if game_data else Color.WHITE, alpha)
		mmi.show_behind_parent = true
	add_child(mmi)
	return mm


## Add one piece. pos is global; delay staggers the burst.
func add_piece(pos: Vector2, vel: Vector2, kind: int, delay := 0.0) -> void:
	_pos.append(to_local(pos))
	_vel.append(vel)
	_born.append(_clock + delay)
	_ride.append(null)
	_ride_local.append(Vector2.ZERO)
	_rot.append(0.0)  # upright: the shader does the 3D flip
	_spin.append(spin_speed * (1.0 if randf() < 0.5 else -1.0) * randf_range(0.6, 1.2))
	_type.append(kind)
	_state.append(WAITING if delay > 0.0 else AIR)
	_slot.append(-1)
	# new pieces join the active region
	_swap(_pos.size() - 1, _n_active)
	_n_active += 1


func count() -> int:
	return _pos.size()


func active_count() -> int:
	return _n_active


## Microseconds the last step took (for profiling).
var last_step_usec := 0


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_step(delta)
	last_step_usec = Time.get_ticks_usec() - t0


func _step(delta: float) -> void:
	_clock += delta
	_frame += 1
	_piece_mat.set_shader_parameter("now", _clock)
	_glow_mat.set_shader_parameter("now", _clock)
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	var alive: bool = is_instance_valid(_player) and (not _player.has_method("is_alive") or _player.is_alive())
	var ppos := to_local(_player.global_position) if alive else Vector2(INF, INF)
	var reach := magnet_range * (1.0 + Progress.stat(&"coin_magnet"))  # Magnetism upgrade
	var range2 := reach * reach
	var collect2 := collect_distance * collect_distance
	var collected := PackedInt32Array()
	collected.resize(GameData.Pickup.size())
	var sparkles_left := max_sparkles_per_frame if sparkles else 0
	var space := get_world_2d().direct_space_state
	var ex: Array[RID] = []
	if alive and _player is CollisionObject2D:
		ex.append(_player.get_rid())  # the player body shares the world layer

	# ---- 1. active pieces: full simulation
	var i := _n_active - 1
	while i >= 0:
		var st := _state[i]
		var age := _clock - _born[i]
		if st == WAITING:
			if age >= 0.0:
				_state[i] = AIR
			i -= 1
			continue
		if lifetime > 0.0 and age >= lifetime:
			_remove_active(i)
			i -= 1
			continue
		var p := _pos[i]
		var v := _vel[i]
		if st != MAGNET and age >= magnet_delay and p.distance_squared_to(ppos) <= range2:
			st = MAGNET
			if _state[i] == LANDED:
				_pending_land -= 1
		if st == AIR:
			v.y += fall_gravity * delta
			var next := p + v * delta
			var hit := {}
			if v.y > 0.0:
				# sweep along the real path (its bottom edge), so it lands where it
				# actually is - on the floor or on a board (rays hit one-way boards)
				var foot := Vector2(0, piece_size * 0.45)
				hit = space.intersect_ray(PhysicsRayQueryParameters2D.create(
					to_global(p + foot), to_global(next + foot), 1, ex))
			_rot[i] += _spin[i] * delta
			if hit.is_empty():
				p = next
			else:
				p = Vector2(next.x, to_local(hit.position).y - piece_size * 0.45)
				if absf(v.y) < settle_speed:
					v = Vector2.ZERO
					_rot[i] = 0.0
					var body: Object = hit.collider
					if body is Node and (body as Node).is_in_group("one_way_platforms"):
						# lies on a hanging board: rides it while it swings
						st = RIDE
						_ride[i] = body
						_ride_local[i] = (body as Node2D).to_local(to_global(p))
					else:
						st = LANDED
						_pending_land += 1
				else:
					v = Vector2(v.x * bounce_friction, -v.y * bounce)
					_spin[i] *= 0.6
			if p.y > 4000.0:  # fell out of the world
				_remove_active(i)
				i -= 1
				continue
		elif st == RIDE:
			var board = _ride[i]
			if is_instance_valid(board):
				p = to_local((board as Node2D).to_global(_ride_local[i]))
			else:
				st = AIR
		elif st == MAGNET:
			var to := ppos - p
			var d2 := to.length_squared()
			if d2 <= collect2:
				collected[_type[i]] += 1
				if sparkles_left > 0:
					sparkles_left -= 1
					_spark_pos.append(p)
					_spark_t.append(0.0)
					_spark_col.append(game_data.piece_color(_type[i]) if game_data else Color.WHITE)
				_remove_active(i)
				i -= 1
				continue
			# straight at the player, a bit faster every frame; never overshoots
			var dist := sqrt(d2)
			var speed := maxf(v.length(), fly_start_speed) + fly_speed_ramp * delta
			var step := speed * delta
			if step >= dist:
				p = ppos
			else:
				p += to / dist * step
			v = to / dist * speed
			_rot[i] = lerp_angle(_rot[i], 0.0, minf(1.0, 12.0 * delta))
		_state[i] = st
		_pos[i] = p
		_vel[i] = v
		i -= 1

	# ---- 2. resting pieces: one group per frame gets a magnet / lifetime check
	var n := _pos.size()
	if n > _n_active:
		var groups := maxi(rest_check_groups, 1)
		var first := _n_active + posmod(_frame - _n_active, groups)
		var wake := PackedInt32Array()
		var expire := PackedInt32Array()
		for j in range(first, n, groups):
			if lifetime > 0.0 and _clock - _born[j] >= lifetime:
				expire.append(j)
			elif _pos[j].distance_squared_to(ppos) <= range2:
				wake.append(j)
		if not wake.is_empty():
			for j in wake:  # ascending: safe while swapping into the active region
				_hide_rest_slot(j)
				_swap(j, _n_active)
				_state[_n_active] = MAGNET
				_n_active += 1
		else:
			for k in range(expire.size() - 1, -1, -1):
				_remove_rest(expire[k])

	# hand collected coins to the player in one call
	if alive and _player.has_method("add_coins"):
		for t in collected.size():
			if collected[t] > 0:
				_player.add_coins(collected[t])
				_pending[t] = int(_pending.get(t, 0)) + collected[t]
	_popup_t -= delta
	if _popup_t <= 0.0 and not _pending.is_empty() and alive:
		_popup_t = popup_interval
		var k := 0
		for t in _pending:
			_popup(_player.global_position + Vector2(-12, -34 - k * 18), "+%d" % _pending[t],
				game_data.piece_color(t) if game_data else Color.WHITE)
			k += 1
		_pending.clear()

	# ---- 3. move settled pieces into the resting buffers (throttled)
	_flush_t -= delta
	if _flush_t <= 0.0 and (_pending_land > 0 or _rest_hidden > _rest_total / 4 + 16):
		_flush_t = rest_flush_interval
		_flush_rest()

	# ---- 4. active buffers (only the pieces that move)
	_write_buffers(0, _n_active, _act_mm, _act_glow, false)
	if not _spark_t.is_empty():
		_update_sparks(delta)


# ---------------------------------------------------------------- bookkeeping

func _swap(a: int, b: int) -> void:
	if a == b:
		return
	var v2 := _pos[a]; _pos[a] = _pos[b]; _pos[b] = v2
	v2 = _vel[a]; _vel[a] = _vel[b]; _vel[b] = v2
	var f := _born[a]; _born[a] = _born[b]; _born[b] = f
	var o = _ride[a]; _ride[a] = _ride[b]; _ride[b] = o
	v2 = _ride_local[a]; _ride_local[a] = _ride_local[b]; _ride_local[b] = v2
	f = _rot[a]; _rot[a] = _rot[b]; _rot[b] = f
	f = _spin[a]; _spin[a] = _spin[b]; _spin[b] = f
	var n := _type[a]; _type[a] = _type[b]; _type[b] = n
	n = _state[a]; _state[a] = _state[b]; _state[b] = n
	n = _slot[a]; _slot[a] = _slot[b]; _slot[b] = n


func _shrink() -> void:
	var last := _pos.size() - 1
	_pos.resize(last)
	_vel.resize(last)
	_born.resize(last)
	_ride.resize(last)
	_ride_local.resize(last)
	_rot.resize(last)
	_spin.resize(last)
	_type.resize(last)
	_state.resize(last)
	_slot.resize(last)


func _remove_active(i: int) -> void:
	if _state[i] == LANDED:
		_pending_land -= 1
	_swap(i, _n_active - 1)               # removed piece -> end of active region
	_swap(_n_active - 1, _pos.size() - 1) # ... -> very end (a resting piece fills its place)
	_n_active -= 1
	_shrink()


func _remove_rest(i: int) -> void:
	_hide_rest_slot(i)
	_swap(i, _pos.size() - 1)
	_shrink()


func _hide_rest_slot(i: int) -> void:
	var slot := _slot[i]
	if slot < 0:
		return
	var t := _type[i]
	_rest_mm[t].set_instance_color(slot, Color(1, 1, 1, 0))
	if _rest_glow[t]:
		_rest_glow[t].set_instance_color(slot, Color(1, 1, 1, 0))
	_slot[i] = -1
	_rest_hidden += 1


func _flush_rest() -> void:
	var i := _n_active - 1
	while i >= 0:
		if _state[i] == LANDED:
			_state[i] = REST
			_swap(i, _n_active - 1)
			_n_active -= 1
		i -= 1
	_pending_land = 0
	_write_buffers(_n_active, _pos.size(), _rest_mm, _rest_glow, true)
	_rest_hidden = 0
	_rest_total = _pos.size() - _n_active


## Write pieces [from, to) into the given per-type MultiMeshes. A counting sort
## groups them by type; each type's buffer is one local array (no per-piece
## copies). Resting buffers also record each piece's slot for cheap hiding.
## Layout per instance: x.x, y.x, 0, origin.x, x.y, y.y, 0, origin.y,
##                      r, g, b, a, custom.x (1 = bob), custom.y (expiry time), 0, 0
func _write_buffers(from: int, to: int, mms: Array[MultiMesh], glows: Array[MultiMesh], resting: bool) -> void:
	var types := mms.size()
	var counts := PackedInt32Array()
	counts.resize(types)
	for i in range(from, to):
		if _state[i] != WAITING:
			counts[_type[i]] += 1
	var start := PackedInt32Array()
	start.resize(types)
	var acc := 0
	for t in types:
		start[t] = acc
		acc += counts[t]
	var order := PackedInt32Array()
	order.resize(acc)
	var fill := start.duplicate()
	for i in range(from, to):
		if _state[i] != WAITING:
			var ty := _type[i]
			order[fill[ty]] = i
			fill[ty] += 1
	for t in types:
		var n := counts[t]
		var b := PackedFloat32Array()
		b.resize(maxi(n, 1) * STRIDE)
		var o := 0
		for k in range(start[t], start[t] + n):
			var i := order[k]
			var p := _pos[i]
			var c := cos(_rot[i])
			var s := sin(_rot[i])
			# QuadMesh is built y-up; flip y so textures are the right way round in 2D
			b[o] = c
			b[o + 1] = s
			b[o + 3] = p.x
			b[o + 4] = s
			b[o + 5] = -c
			b[o + 7] = p.y
			b[o + 8] = 1.0
			b[o + 9] = 1.0
			b[o + 10] = 1.0
			b[o + 11] = 1.0
			b[o + 12] = 1.0 if (resting or _state[i] == LANDED or _state[i] == RIDE) else 0.0
			b[o + 13] = (_born[i] + lifetime) if lifetime > 0.0 else 0.0
			if resting:
				_slot[i] = k - start[t]
			o += STRIDE
		_apply(mms[t], n, b)
		if glows[t]:
			_apply(glows[t], n, b)


func _apply(mm: MultiMesh, n: int, buf: PackedFloat32Array) -> void:
	if mm.instance_count < n:
		mm.instance_count = int(max(n, mm.instance_count * 2, 64))
	if n > 0:
		var cap := mm.instance_count * STRIDE
		if buf.size() != cap:
			buf.resize(cap)
		mm.buffer = buf
	mm.visible_instance_count = n


# ---------------------------------------------------------------- feedback

func _update_sparks(delta: float) -> void:
	var j := _spark_t.size() - 1
	while j >= 0:
		_spark_t[j] += delta
		if _spark_t[j] >= SPARK_LIFE:
			var last := _spark_t.size() - 1
			_spark_pos[j] = _spark_pos[last]
			_spark_t[j] = _spark_t[last]
			_spark_col[j] = _spark_col[last]
			_spark_pos.resize(last)
			_spark_t.resize(last)
			_spark_col.resize(last)
		j -= 1
	queue_redraw()


func _draw() -> void:
	for j in _spark_t.size():
		var k := _spark_t[j] / SPARK_LIFE
		var c := Color(_spark_col[j].lightened(0.4), 1.0 - k)
		var r := piece_size * (0.3 + 0.7 * k)
		draw_arc(_spark_pos[j], r, 0.0, TAU, 16, c, 2.0, true)
		for q in 4:
			var d := Vector2.from_angle(q * PI / 2.0 + 0.4)
			draw_line(_spark_pos[j] + d * r * 0.6, _spark_pos[j] + d * r * 1.3, c, 1.5, true)


func _popup(at: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", popup_font_size)
	label.add_theme_color_override("font_color", color.lightened(0.35))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.z_index = 20
	get_parent().add_child(label)
	label.global_position = at
	var tw := label.create_tween().set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 30.0, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tw.chain().tween_callback(label.queue_free)
