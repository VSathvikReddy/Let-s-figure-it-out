class_name View
extends RefCounted
## Is something on screen? The camera's view rectangle is worked out once per
## frame and shared by everyone who asks, so the check costs almost nothing.
## Used to skip work nobody can see: animation, visual effects and redraws.
## Gameplay (AI, movement, attacks) never depends on it.

static var _frame := -1
static var _rect := Rect2()


## The visible part of the world this frame (world coordinates).
static func rect(from: Node) -> Rect2:
	var f := Engine.get_process_frames()
	if f != _frame:
		_frame = f
		var vp := from.get_viewport()
		_rect = vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
	return _rect


## Is a world point on screen (or within `margin` px of it)?
static func sees(from: Node, pos: Vector2, margin := 200.0) -> bool:
	return from.is_inside_tree() and rect(from).grow(margin).has_point(pos)


## queue_redraw() for animated custom drawing - only while it is on screen,
## and with every > 1 only every n-th frame (staggered per node, so a crowd
## does not all redraw on the same frame). Its movement stays smooth: only the
## drawn shape updates less often.
static func redraw(ci: Node2D, every := 1, margin := 200.0) -> void:
	if every > 1 and (Engine.get_process_frames() + ci.get_instance_id()) % every != 0:
		return
	if sees(ci, ci.global_position, margin):
		ci.queue_redraw()


## Off-screen enemies think less often: true on the physics frames this node
## should run its full AI. Near the screen (within `margin`) that is every
## frame; further away every `every`-th frame, staggered per node so a crowd
## does not all think on the same frame. Movement still runs every frame.
static func think(node: Node2D, every := 4, margin := 400.0) -> bool:
	if sees(node, node.global_position, margin):
		return true
	return (Engine.get_physics_frames() + node.get_instance_id()) % every == 0


## For enemies: true if `node` is on screen. Its AnimationPlayer only runs then.
## (Also makes sure the LightBudget exists, which caps lights in big crowds.)
static func cull(node: Node2D, anim: AnimationMixer = null, margin := 200.0) -> bool:
	LightBudget.ensure(node)
	var on := sees(node, node.global_position, margin)
	if anim and anim.active != on:
		anim.active = on
	return on
