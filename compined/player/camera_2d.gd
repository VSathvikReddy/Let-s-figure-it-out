extends Camera2D
## The player's camera. It is a child of the player but moves on its own:
##   - SIZE: it zooms so the screen shows `view_percent` % of the painting
##     (50 = half the painting's width and height). It reads the size from
##     the level bounds, so it fits ANY level and any painting by itself.
##   - FOLLOW: it glides after the player. The player can move inside a small
##     "dead zone" (a % of the screen) before the camera starts to follow.
##   - EDGES: it never shows anything outside the painting. Near an edge the
##     camera stops and the player keeps flying right up to the edge.

@export_group("How much of the painting you see")
## Part of the painting that fits on the screen, in percent.
@export_range(10.0, 100.0, 1.0, "suffix:%") var view_percent := 50.0:
	set(value):
		view_percent = value
		if is_inside_tree():
			fit_to_level()

@export_group("Following")
## How fast the camera catches up sideways (higher = faster).
@export_range(1.0, 30.0) var horizontal_smoothness := 10.0
## How fast it catches up when the player goes up.
@export_range(1.0, 30.0) var vertical_smoothness := 10.0
## How fast it catches up when the player falls (a bit faster feels better).
@export_range(1.0, 30.0) var fall_smoothness := 16.0
## How far the player can move before the camera follows, in % of the screen.
@export_range(0.0, 40.0, 0.5, "suffix:%") var dead_zone_percent := 3.0:
	set(value):
		dead_zone_percent = value
		if is_inside_tree():
			fit_to_level()

## Rounds the camera position to whole pixels (crisper pixel art).
@export var snap_to_pixels := true

@export_group("Shake")
## Strongest shake, in px (at shake strength 1).
@export var max_shake := 18.0
## How fast a shake calms down (strength lost per second).
@export var shake_recovery := 1.6

var player: Node2D
var level_rect := Rect2()        # the painting, in world space
var dead_zone := Vector2.ZERO    # in world pixels, worked out from the level size
var exact_position := Vector2.ZERO
var _shake_strength := 0.0       # 0..1, set by shake(), fades by itself


func _ready() -> void:
	top_level = true             # moves by itself instead of being glued to the player
	player = get_parent() as Node2D
	if player:
		exact_position = player.global_position
	get_viewport().size_changed.connect(fit_to_level)
	# the level builds its bounds in its own _ready, which runs after ours
	fit_to_level.call_deferred()


func _process(delta: float) -> void:
	if player == null:
		return
	_follow_player(delta)
	global_position = exact_position.round() if snap_to_pixels else exact_position
	_update_shake(delta)


## Shakes the screen (explosions call this). 0.3 = small bump, 1 = huge blast.
## Several shakes add up, but never above 1.
func shake(strength: float) -> void:
	_shake_strength = minf(_shake_strength + strength, 1.0)


func _update_shake(delta: float) -> void:
	_shake_strength = maxf(_shake_strength - shake_recovery * delta, 0.0)
	# squared, so small shakes stay gentle and big ones really kick
	var amount := _shake_strength * _shake_strength * max_shake
	offset = Vector2(randf_range(-amount, amount), randf_range(-amount, amount))


## Reads the level size and works out the zoom and the dead zone from it.
## Runs again whenever the window size or a setting changes.
func fit_to_level() -> void:
	var bounds := get_tree().get_first_node_in_group("level_bounds") as Control
	if bounds == null:
		return
	level_rect = bounds.get_global_rect()

	# zoom so the screen shows view_percent of the painting
	# (the larger zoom of the two keeps both width and height inside it)
	var screen := get_viewport_rect().size
	var wanted_view := level_rect.size * view_percent / 100.0
	var zoom_amount := maxf(screen.x / wanted_view.x, screen.y / wanted_view.y)
	zoom = Vector2(zoom_amount, zoom_amount)

	dead_zone = _visible_size() * dead_zone_percent / 100.0

	# the built-in limits are a safety net; _keep_inside_level does the real work
	limit_left = int(level_rect.position.x)
	limit_top = int(level_rect.position.y)
	limit_right = int(level_rect.end.x)
	limit_bottom = int(level_rect.end.y)

	if player:
		exact_position = _keep_inside_level(player.global_position)


func _follow_player(delta: float) -> void:
	var player_pos := player.global_position
	var target := exact_position

	# only move once the player leaves the dead zone, and then only by the
	# part outside it (no sudden jump)
	var offset_from_camera := player_pos - exact_position
	if absf(offset_from_camera.x) > dead_zone.x:
		target.x = player_pos.x - signf(offset_from_camera.x) * dead_zone.x
	if absf(offset_from_camera.y) > dead_zone.y:
		target.y = player_pos.y - signf(offset_from_camera.y) * dead_zone.y

	# glide toward the target; the same speed at any frame rate
	var falling := player_pos.y > exact_position.y
	var y_smoothness := fall_smoothness if falling else vertical_smoothness
	exact_position.x = lerpf(exact_position.x, target.x, 1.0 - exp(-horizontal_smoothness * delta))
	exact_position.y = lerpf(exact_position.y, target.y, 1.0 - exp(-y_smoothness * delta))

	# never look past the painting's edges
	exact_position = _keep_inside_level(exact_position)


## The camera centre may only go where the whole screen still shows painting.
## If the screen is bigger than the painting, it just stays in the middle.
func _keep_inside_level(point: Vector2) -> Vector2:
	if level_rect.size == Vector2.ZERO:
		return point
	var half_view := _visible_size() / 2.0
	var allowed := level_rect.grow_individual(-half_view.x, -half_view.y, -half_view.x, -half_view.y)
	if allowed.size.x < 0.0:
		point.x = level_rect.get_center().x
	else:
		point.x = clampf(point.x, allowed.position.x, allowed.end.x)
	if allowed.size.y < 0.0:
		point.y = level_rect.get_center().y
	else:
		point.y = clampf(point.y, allowed.position.y, allowed.end.y)
	return point


## How much of the world the screen shows right now.
func _visible_size() -> Vector2:
	return get_viewport_rect().size / zoom
