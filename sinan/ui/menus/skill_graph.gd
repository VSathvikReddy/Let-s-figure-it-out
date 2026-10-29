@tool
class_name SkillGraph
extends Control
## The skill tree board, Nodebuster style: tiles on a square grid, every link
## straight up / down / left / right, so a tile links to at most 4 others (the
## one it needs + up to 3 that need it). The centre tile has the 4 core tiles
## (one per branch, in SkillTreeData.branches order: up, right, down, left) and
## the tree grows outward ring by ring, each tile taking the free neighbouring
## cells closest to the centre - so the whole tree stays a round blob and each
## branch keeps its own quarter. Adding an upgrade in the .tres places it.
## A violet diamond on a tile = it is paid with Entropy (from restoring the
## painting) instead of coins.
## Fog: you see what you own and the tiles right after it - buying a tile
## reveals only its own children (at most 3).
## In the editor (skill_tree.tscn) the whole tree is shown, without fog.
##
## Mouse: hover selects, click buys, drag pans, wheel zooms.
## Keys: WASD / arrows move between tiles, E buys.

const TILE := 54.0       ## tile size (world px)
const CELL := 92.0       ## grid spacing (world px)
const ZOOM_MIN := 0.4
const ZOOM_MAX := 1.8

const GOLD := Color(0.97, 0.79, 0.33)
const GOLD_DIM := Color(0.62, 0.48, 0.21)
const LOCKED := Color(0.32, 0.28, 0.21)
const TILE_BG := Color(0.085, 0.085, 0.09)
const INK := Color(0.11, 0.085, 0.04)
const WARN := Color(1.0, 0.45, 0.35)

enum State { CORE, LOCKED, AVAILABLE, OWNED, MAXED }
enum Seen { HIDDEN, MYSTERY, KNOWN }

## One entry per tile: {def: UpgradeDef (null = centre), pos, cell, parent, root, line}
var _tiles: Array[Dictionary] = []
var _tree: SkillTreeData
var _cells := {}         # Vector2i grid cell -> tile index (-1 = a link passes through)
var _selected := 0
var _cam := Vector2.ZERO          # world point in the middle of the board
var _cam_target := Vector2.ZERO
var _zoom := 1.0
var _time := 0.0
var _press_pos := Vector2.ZERO
var _pressed := false
var _dragging := false
var _flash := {}                  # tile index -> seconds left (bought)
var _shake := {}                  # tile index -> seconds left (could not buy)
var _floaters: Array[Dictionary] = []  # {pos, text, color, t}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	if Engine.is_editor_hint():  # preview the whole tree in the scene editor
		build(load(Progress.TREE_PATH))
		reset_view.call_deferred()


# ------------------------------------------------------------------ layout

## Lay the tiles out from the data. Call again if the data changes.
func build(tree: SkillTreeData) -> void:
	_tree = tree
	_tiles = [{"def": null, "pos": Vector2.ZERO, "cell": Vector2i.ZERO, "parent": -1, "root": 0}]
	_cells = {Vector2i.ZERO: 0}
	if tree == null:
		return
	# the core tiles, in branch order: up, right, down, left
	var roots: Array[UpgradeDef] = []
	for b in tree.branches:
		for u in _kids(&""):
			if u.branch == b and not u in roots:
				roots.append(u)
	for u in _kids(&""):
		if not u in roots:
			roots.append(u)
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var queue: Array[int] = []
	for k in roots.size():
		# two cells out, so the four branches have room between them
		var d: Vector2i = dirs[k % 4] * (1 + k / 4)
		_cells[d] = -1
		queue.append(_add(roots[k], 0, d * 2))
	# grow ring by ring: every tile seats its children next to itself
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var kids := _kids(_tiles[i].def.id)
		kids.sort_custom(func(a: UpgradeDef, b: UpgradeDef) -> bool: return _size(a) > _size(b))
		for k in kids:
			queue.append(_add(k, i, _free_cell(i, _size(k))))
	for i in range(1, _tiles.size()):
		_tiles[i].line = _wobbly_line(i)
	_selected = clampi(_selected, 0, _tiles.size() - 1)
	queue_redraw()


func _add(def: UpgradeDef, parent: int, cell: Vector2i) -> int:
	var i := _tiles.size()
	_tiles.append({"def": def, "pos": Vector2(cell) * CELL, "cell": cell, "parent": parent,
		"root": i if parent == 0 else _tiles[parent].root})
	_cells[cell] = i
	return i


## The best free cell for a child of tile i with a family of `family` tiles:
## one or two cells away in a straight line (never back toward its parent),
## close to the centre (keeps the tree round), away from other branches, and
## straight ahead for big families (they need room to grow).
func _free_cell(i: int, family: int) -> Vector2i:
	var here: Vector2i = _tiles[i].cell
	var ahead: Vector2i = (here - _tiles[_tiles[i].parent].cell).clampi(-1, 1)
	var best := Vector2i.MAX
	var best_score := INF
	for d in [ahead, Vector2i(ahead.y, -ahead.x), Vector2i(-ahead.y, ahead.x)]:
		for dist in [1, 2]:
			var c: Vector2i = here + d * dist
			if _cells.has(c) or (dist == 2 and _cells.has(here + d)):
				continue
			var score := Vector2(c).length() + (0.7 if dist == 2 else 0.0)
			if family >= 3 and d == ahead:
				score -= 0.8
			for n in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var o: int = _cells.get(c + n, -1)
				if o > 0 and _tiles[o].root != _tiles[i].root:
					score += 2.5  # touching another branch
			if score < best_score:
				best_score = score
				best = c
	if best != Vector2i.MAX:
		if (best - here).length_squared() == 4:
			_cells[here + (best - here) / 2] = -1  # keep the long link's middle clear
		return best
	# boxed in (rare): the nearest free cell around it
	for r in range(2, 8):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if not _cells.has(here + Vector2i(x, y)):
					return here + Vector2i(x, y)
	return here + ahead * 8


func _kids(parent_id: StringName) -> Array[UpgradeDef]:
	var out: Array[UpgradeDef] = []
	for u in _tree.upgrades:
		if u and u.requires == parent_id:
			out.append(u)
	return out


## How many tiles a family has (the upgrade plus everything after it).
func _size(def: UpgradeDef) -> int:
	var n := 1
	for k in _kids(def.id):
		n += _size(k)
	return n


## A slightly shaky line from the parent tile to tile i (hand-drawn look).
func _wobbly_line(i: int) -> PackedVector2Array:
	var a: Vector2 = _tiles[_tiles[i].parent].pos
	var d: Vector2 = _tiles[i].pos
	var side := (d - a).orthogonal().normalized()
	var pts := PackedVector2Array()
	for s in 13:
		var f := s / 12.0
		pts.append(a.lerp(d, f) + side * sin(f * PI * 3.0 + i * 1.7) * 1.3 * sin(f * PI))
	return pts


## What the fog lets you see of tile i: what you own, and the tiles right
## after something you own.
func _seen(i: int) -> Seen:
	var def: UpgradeDef = _tiles[i].def
	if Engine.is_editor_hint() or def == null or def.requires == &"":
		return Seen.KNOWN
	if Progress.level(def.id) > 0 or Progress.level(def.requires) > 0:
		return Seen.KNOWN
	return Seen.HIDDEN


# ------------------------------------------------------------------ state

func _state(i: int) -> State:
	var def: UpgradeDef = _tiles[i].def
	if def == null:
		return State.CORE
	if Engine.is_editor_hint():
		return State.AVAILABLE
	var lvl := Progress.level(def.id)
	if lvl >= def.max_level:
		return State.MAXED
	if lvl > 0:
		return State.OWNED
	if def.requires != &"" and Progress.level(def.requires) < def.requires_level:
		return State.LOCKED
	return State.AVAILABLE


func _can_buy(i: int) -> bool:
	return not Engine.is_editor_hint() and _tiles[i].def != null and _seen(i) == Seen.KNOWN and Progress.can_buy(_tiles[i].def)


func select(i: int, scroll := false) -> void:
	if i < 0 or i >= _tiles.size():
		return
	_selected = i
	if scroll:  # keep the selected tile (and its info box) on screen
		var margin := Vector2(TILE + 40.0, TILE + 30.0) / _zoom
		var half := size * 0.5 / _zoom - margin
		var p: Vector2 = _tiles[i].pos
		_cam_target.x = clampf(_cam_target.x, p.x - half.x + 150.0 / _zoom, p.x + half.x)
		_cam_target.y = clampf(_cam_target.y, p.y - half.y, p.y + half.y)
	queue_redraw()


## Buy the next level of the selected tile (with feedback either way).
func buy_selected() -> void:
	var def: UpgradeDef = _tiles[_selected].def
	if def == null:
		return
	if _seen(_selected) != Seen.KNOWN:
		_shake[_selected] = 0.3
		_floaters.append({"pos": _tiles[_selected].pos, "text": "???", "color": WARN, "t": 0.0})
		return
	var cost := def.cost_for_level(Progress.level(def.id))
	if Progress.buy(def, self):
		_flash[_selected] = 0.35
		_floaters.append({"pos": _tiles[_selected].pos, "text": "-%d" % cost,
			"color": EntropyIcon.COLOR if def.currency == 1 else GOLD, "t": 0.0})
	else:
		_shake[_selected] = 0.3
		var why := "MAX" if _state(_selected) == State.MAXED else ("LOCKED" if _state(_selected) == State.LOCKED else "NEED %d" % cost)
		_floaters.append({"pos": _tiles[_selected].pos, "text": why, "color": WARN, "t": 0.0})


## Fit everything you can see on screen and select the centre.
func reset_view() -> void:
	var box := Rect2()
	for i in _tiles.size():
		if _seen(i) != Seen.HIDDEN:
			box = box.expand(_tiles[i].pos)
	box = box.grow(TILE)
	var fit := (size - Vector2(80, 150)) / box.size
	_zoom = clampf(minf(fit.x, fit.y), ZOOM_MIN, 1.15)
	_cam = box.get_center() + Vector2(0, -10) / _zoom
	_cam_target = _cam
	_selected = 0
	queue_redraw()


# ------------------------------------------------------------------ input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_dragging = false
				_press_pos = mb.position
				grab_focus()
			else:
				_pressed = false
				if not _dragging:
					var i := _tile_at(mb.position)
					if i >= 0:
						select(i)
						buy_selected()
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var before := _to_world(mb.position)
			_zoom = clampf(_zoom * (1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.12), ZOOM_MIN, ZOOM_MAX)
			_cam = before - (mb.position - size * 0.5) / _zoom  # keep the point under the mouse still
			_cam_target = _cam
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pressed and (_dragging or mm.position.distance_to(_press_pos) > 6.0):
			_dragging = true
			_cam -= mm.relative / _zoom
			_cam_target = _cam
		else:
			var i := _tile_at(mm.position)
			if i >= 0 and i != _selected:
				select(i)


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_pressed():
		return
	var key := (event as InputEventKey).physical_keycode
	var dir := Vector2.ZERO
	match key:
		KEY_W, KEY_UP: dir = Vector2.UP
		KEY_S, KEY_DOWN: dir = Vector2.DOWN
		KEY_A, KEY_LEFT: dir = Vector2.LEFT
		KEY_D, KEY_RIGHT: dir = Vector2.RIGHT
		KEY_E:
			if not event.is_echo():
				buy_selected()
			get_viewport().set_input_as_handled()
			return
		_:
			return
	select(_nearest(dir), true)
	get_viewport().set_input_as_handled()


## The tile that lies best in direction `dir` from the selected one.
func _nearest(dir: Vector2) -> int:
	var from: Vector2 = _tiles[_selected].pos
	var best := _selected
	var best_score := INF
	for i in _tiles.size():
		var v: Vector2 = _tiles[i].pos - from
		var ahead := v.dot(dir)
		if i == _selected or ahead < 10.0 or _seen(i) == Seen.HIDDEN:
			continue
		var score := v.length() + absf(v.cross(dir)) * 1.5
		if score < best_score:
			best_score = score
			best = i
	return best


func _tile_at(screen: Vector2) -> int:
	var w := _to_world(screen)
	for i in _tiles.size():
		if _seen(i) != Seen.HIDDEN and Rect2(_tiles[i].pos - Vector2.ONE * TILE * 0.5, Vector2.ONE * TILE).grow(6).has_point(w):
			return i
	return -1


func _to_world(screen: Vector2) -> Vector2:
	return _cam + (screen - size * 0.5) / _zoom


func _to_screen(world: Vector2) -> Vector2:
	return size * 0.5 + (world - _cam) * _zoom


# ------------------------------------------------------------------ drawing

func _process(delta: float) -> void:
	if not is_visible_in_tree() or Engine.is_editor_hint():
		return
	_time += delta
	_cam = _cam.lerp(_cam_target, 1.0 - exp(-12.0 * delta))
	for d in [_flash, _shake]:
		for k in d.keys():
			d[k] -= delta
			if d[k] <= 0.0:
				d.erase(k)
	for f in _floaters:
		f.t += delta
	_floaters = _floaters.filter(func(f: Dictionary) -> bool: return f.t < 0.9)
	queue_redraw()  # lines pulse, so the board redraws while it is open


func _draw() -> void:
	if _tiles.is_empty():
		return
	draw_set_transform(size * 0.5 - _cam * _zoom, 0.0, Vector2.ONE * _zoom)
	var seen: Array[Seen] = []
	for i in _tiles.size():
		seen.append(_seen(i))
	for i in range(1, _tiles.size()):
		if seen[i] != Seen.HIDDEN:
			_draw_line_to(i, seen[i] == Seen.MYSTERY)
	for i in _tiles.size():
		if seen[i] == Seen.KNOWN:
			_draw_tile(i)
		elif seen[i] == Seen.MYSTERY:
			_draw_mystery(i)
	_draw_brackets(_selected)
	draw_set_transform(Vector2.ZERO)
	for f in _floaters:
		var fade: float = 1.0 - f.t / 0.9
		var col: Color = f.color
		col.a = fade
		var at := _to_screen(f.pos) + Vector2(-30, -TILE * 0.6 * _zoom - 26.0 * f.t * 2.0)
		draw_string(_font(), at, f.text, HORIZONTAL_ALIGNMENT_CENTER, 60, 15, col)
	_draw_info(_selected)


func _draw_line_to(i: int, mystery := false) -> void:
	var state := _state(i)
	var col := LOCKED
	if mystery:
		col = Color(LOCKED, 0.5)
	elif state == State.OWNED or state == State.MAXED:
		col = GOLD
	elif state == State.AVAILABLE:
		col = GOLD_DIM
	var line: PackedVector2Array = _tiles[i].line
	draw_polyline(line, col, 1.5 if mystery else 2.5, true)
	if _can_buy(i):  # a spark runs along the line to tiles you can buy right now
		var f := fmod(_time * 0.7 + i * 0.37, 1.0)
		var at := line[int(f * (line.size() - 1))]
		draw_circle(at, 3.5, Color(1, 0.95, 0.7))
		draw_circle(at, 7.0, Color(GOLD, 0.25))


func _draw_tile(i: int) -> void:
	var t: Dictionary = _tiles[i]
	var def: UpgradeDef = t.def
	var state := _state(i)
	var pos: Vector2 = t.pos
	if _shake.has(i):
		pos.x += sin(_shake[i] * 70.0) * 5.0 * _shake[i] / 0.3
	var r := Rect2(pos - Vector2.ONE * TILE * 0.5, Vector2.ONE * TILE)

	var filled := state in [State.CORE, State.OWNED, State.MAXED]
	var edge := GOLD if state != State.LOCKED else LOCKED
	if state == State.AVAILABLE and not _can_buy(i):
		edge = GOLD_DIM
	if _can_buy(i):  # gentle pulse on everything you can afford
		draw_rect(r.grow(4), Color(GOLD, 0.12 + 0.1 * sin(_time * 4.0 + i)), false, 3.0)

	draw_rect(r, GOLD if filled else TILE_BG)
	draw_rect(r, edge, false, 2.0)
	if state == State.MAXED:
		draw_rect(r.grow(4), GOLD, false, 1.0)
	var icon: StringName = &"core" if def == null else def.icon
	SkillIcons.draw(self, icon, pos, TILE * 0.62, INK if filled else edge, GOLD if filled else TILE_BG)
	if def != null and def.currency == 1:  # paid with Entropy
		EntropyIcon.draw(self, r.position + Vector2(TILE - 2.0, 2.0), 7.0)

	if _flash.has(i):
		draw_rect(r.grow(2), Color(1, 1, 0.9, _flash[i] / 0.35 * 0.8))
		draw_rect(r.grow(6 + (0.35 - _flash[i]) * 60.0), Color(GOLD, _flash[i] / 0.35), false, 2.0)

	# level bar under the tile
	if def != null and def.max_level > 1:
		var lvl := Progress.level(def.id)
		var bar := Rect2(r.position.x, r.end.y + 5.0, TILE, 4.0)
		draw_rect(bar, Color(TILE_BG, 0.9))
		if lvl > 0:
			draw_rect(Rect2(bar.position, Vector2(TILE * lvl / def.max_level, 4.0)), GOLD)
		draw_rect(bar, Color(edge, 0.6), false, 1.0)


## A tile still in the fog: a dim box with a "?".
func _draw_mystery(i: int) -> void:
	var pos: Vector2 = _tiles[i].pos
	if _shake.has(i):
		pos.x += sin(_shake[i] * 70.0) * 5.0 * _shake[i] / 0.3
	var r := Rect2(pos - Vector2.ONE * TILE * 0.5, Vector2.ONE * TILE)
	draw_rect(r, Color(TILE_BG, 0.85))
	draw_rect(r, Color(LOCKED, 0.8), false, 1.5)
	draw_string(_font(), pos + Vector2(-TILE * 0.5, 9.0), "?", HORIZONTAL_ALIGNMENT_CENTER, TILE, 26, Color(LOCKED, 0.9))


## [ ] corner marks around the selected tile.
func _draw_brackets(i: int) -> void:
	var r := Rect2(_tiles[i].pos - Vector2.ONE * TILE * 0.5, Vector2.ONE * TILE).grow(9.0 + sin(_time * 5.0) * 1.5)
	var l := 10.0
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if c.x < r.get_center().x else -1.0
		var sy := 1.0 if c.y < r.get_center().y else -1.0
		draw_polyline(PackedVector2Array([c + Vector2(0, l * sy), c, c + Vector2(l * sx, 0)]), GOLD, 2.0)


## The info box next to the selected tile.
func _draw_info(i: int) -> void:
	if Engine.is_editor_hint():
		return
	var def: UpgradeDef = _tiles[i].def
	var font := _font()
	var lines: Array = []  # [text, color, size]
	if def == null:
		lines = [
			["ENTROPY CORE", GOLD, 16],
			["Every path starts here.", Color(0.85, 0.8, 0.7), 13],
			["Coins: %d     Entropy: %d" % [Progress.coins(), Progress.entropy()], GOLD_DIM, 13],
			["Entropy is earned by restoring the painting; tiles with a violet diamond cost Entropy.", Color(0.75, 0.7, 0.62), 12],
		]
	elif _seen(i) != Seen.KNOWN:
		var parent: UpgradeDef = _tiles[_tiles[i].parent].def
		lines = [
			["???", GOLD_DIM, 16],
			["Buy %s to reveal this." % (parent.title if parent else "the tile before it"), Color(0.75, 0.7, 0.62), 13],
		]
	else:
		var state := _state(i)
		var lvl := Progress.level(def.id)
		var tag := "MAX" if state == State.MAXED else ("LOCKED" if state == State.LOCKED else "Lv %d/%d" % [lvl, def.max_level])
		lines.append(["%s  (%s)" % [def.title, tag], GOLD if state != State.LOCKED else GOLD_DIM, 16])
		lines.append([String(def.branch).to_upper(), GOLD_DIM, 11])
		lines.append([def.description, Color(0.88, 0.84, 0.76), 13])
		lines.append([_now_text(def, lvl), Color(0.8, 0.76, 0.66), 13])
		if state == State.MAXED:
			lines.append(["Fully upgraded", GOLD, 13])
		elif state == State.LOCKED:
			var need := Progress.tree().find(def.requires)
			lines.append(["Needs %s Lv %d" % [need.title if need else String(def.requires), def.requires_level], WARN, 13])
		else:
			var cost := def.cost_for_level(lvl)
			var money := "entropy" if def.currency == 1 else "coins"
			var have := Progress.entropy() if def.currency == 1 else Progress.coins()
			if have >= cost:
				lines.append(["[E] Unlock  -  %d %s" % [cost, money], EntropyIcon.COLOR if def.currency == 1 else GOLD, 13])
			else:
				lines.append(["Need %d %s (have %d)" % [cost, money, have], WARN, 13])

	var width := 270.0
	var height := 14.0
	for l in lines:
		height += font.get_multiline_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, width, l[2]).y + 3.0
	var tile := _to_screen(_tiles[i].pos)
	var half := TILE * 0.5 * _zoom
	var box := Rect2(tile + Vector2(half + 22.0, -half), Vector2(width + 20.0, height))
	# on the side facing away from the centre (so it covers its own branch's
	# outer tiles, not the rest of the tree); the centre's box goes top-left
	var left: bool = _tiles[i].pos.x < 0.0
	if def == null:
		box.position = Vector2(20.0, 70.0)
	elif (left and tile.x - half - 22.0 - box.size.x > 10.0) or box.end.x > size.x - 10.0:
		box.position.x = tile.x - half - 22.0 - box.size.x
	box.position.y = clampf(box.position.y, 60.0, size.y - box.size.y - 40.0)

	if def != null:
		draw_line(Vector2(tile.x + (half + 9.0 if box.position.x > tile.x else -half - 9.0), tile.y), Vector2(box.position.x if box.position.x > tile.x else box.end.x, tile.y), GOLD_DIM, 1.0)
	draw_rect(box, Color(0.05, 0.05, 0.055, 0.94))
	draw_rect(box, GOLD_DIM, false, 1.0)
	var y := box.position.y + 8.0
	for l in lines:
		var s := font.get_multiline_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, width, l[2])
		draw_multiline_string(font, Vector2(box.position.x + 10.0, y + font.get_ascent(l[2])), l[0], HORIZONTAL_ALIGNMENT_LEFT, width, l[2], -1, l[1])
		y += s.y + 3.0


## "What you have now" line, e.g. "Now: +30%" or "Now: +2".
func _now_text(def: UpgradeDef, lvl: int) -> String:
	var total := lvl * def.per_level
	if def.max_level == 1:
		return "Unlocked" if lvl > 0 else "Not unlocked yet"
	if def.description.contains("%"):
		return "Now: +%d%%" % roundi(total * 100.0)
	return "Now: +%s" % String.num(total, 2)


func _font() -> Font:
	return get_theme_default_font()
