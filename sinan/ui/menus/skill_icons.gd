class_name SkillIcons
extends RefCounted
## Line-art icons for the skill tree, drawn with CanvasItem draw calls (no image
## files). Every icon is designed on a 32 x 32 grid centred on (0, 0).
## Pick one per upgrade with UpgradeDef.icon.

const NAMES: PackedStringArray = [
	"core", "bolt", "bolt_burst", "clock", "rocket", "blade", "heart", "heart_plus",
	"heart_up", "shield", "brush", "circle_grow", "drop", "coin", "magnet", "target",
	"portal", "eye", "lock", "moon", "coin_portal", "wand", "chain", "twin", "crit", "pistol",
	"orb", "skull", "witch", "bird", "bat", "flame", "jetpack", "fuel", "gauge", "gyro", "wind",
	"coin_stack", "palette", "thorns", "revive",
]


## Draw icon `icon` centred at `at`, `size` px wide, in `color`. `bg` is the tile
## colour behind it (some icons cut shapes out of themselves with it).
static func draw(ci: CanvasItem, icon: StringName, at: Vector2, size: float, color: Color, bg: Color) -> void:
	var u := size / 32.0
	var w := maxf(1.5, 2.2 * u)
	var p := func(x: float, y: float) -> Vector2: return at + Vector2(x, y) * u
	match icon:
		&"core":
			ci.draw_circle(at, 14 * u, color, false, w, true)
			_bolt(ci, at, u * 0.8, color)
		&"bolt":
			_bolt(ci, at, u, color)
		&"bolt_burst":
			_bolt(ci, at + Vector2(0, -3) * u, u * 0.75, color)
			for x in [-9.0, 0.0, 9.0]:
				ci.draw_line(p.call(x * 0.8, 9), p.call(x * 1.3, 15), color, w, true)
		&"clock":
			ci.draw_circle(at, 12 * u, color, false, w, true)
			ci.draw_line(at, p.call(0, -8), color, w, true)
			ci.draw_line(at, p.call(6, 3), color, w, true)
			ci.draw_rect(Rect2(p.call(-3, -17), Vector2(6, 3) * u), color)
		&"rocket":
			_outline(ci, [p.call(0, -15), p.call(5, -7), p.call(5, 7), p.call(-5, 7), p.call(-5, -7)], color, w)
			_outline(ci, [p.call(-5, 2), p.call(-10, 10), p.call(-5, 8)], color, w)
			_outline(ci, [p.call(5, 2), p.call(10, 10), p.call(5, 8)], color, w)
			ci.draw_polyline(PackedVector2Array([p.call(-2.5, 10), p.call(0, 15), p.call(2.5, 10)]), color, w, true)
			ci.draw_circle(p.call(0, -3), 2 * u, color)
		&"blade":
			ci.draw_line(p.call(-13, 13), p.call(-7, 7), color, w * 1.8, true)
			ci.draw_line(p.call(-10, 4), p.call(-4, 10), color, w, true)
			_outline(ci, [p.call(-6, 6), p.call(10, -11), p.call(14, -14), p.call(12, -8), p.call(-3, 9)], color, w)
		&"heart":
			ci.draw_colored_polygon(_heart(at, u, 1.0), color)
		&"heart_plus":
			_outline(ci, _heart(at + Vector2(-2, 0) * u, u, 0.85), color, w)
			ci.draw_rect(Rect2(p.call(4, 4), Vector2(12, 12) * u), bg)
			ci.draw_line(p.call(10, 5), p.call(10, 15), color, w * 1.3)
			ci.draw_line(p.call(5, 10), p.call(15, 10), color, w * 1.3)
		&"heart_up":
			_outline(ci, _heart(at + Vector2(-2, 2) * u, u, 0.85), color, w)
			ci.draw_rect(Rect2(p.call(5, -16), Vector2(11, 14) * u), bg)
			ci.draw_line(p.call(10.5, -3), p.call(10.5, -14), color, w * 1.2)
			ci.draw_polyline(PackedVector2Array([p.call(6, -10), p.call(10.5, -15), p.call(15, -10)]), color, w * 1.2)
		&"shield":
			_outline(ci, [p.call(0, -14), p.call(12, -9), p.call(11, 3), p.call(0, 14), p.call(-11, 3), p.call(-12, -9)], color, w)
			ci.draw_line(p.call(0, -9), p.call(0, 9), color, w, true)
			ci.draw_line(p.call(-7, -2), p.call(7, -2), color, w, true)
		&"brush":
			ci.draw_line(p.call(-13, 13), p.call(2, -2), color, w * 1.6, true)
			ci.draw_line(p.call(0, -5), p.call(5, 0), color, w * 2.2, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(2, -6), p.call(6, -2), p.call(14, -14)]), color)
		&"circle_grow":
			ci.draw_circle(at, 6 * u, color, false, w, true)
			for i in 4:
				var d := Vector2.from_angle(PI / 4 + i * PI / 2)
				ci.draw_line(at + d * 9 * u, at + d * 15 * u, color, w, true)
				ci.draw_arc(at, 13 * u, i * PI / 2 - PI / 4 + 0.35, i * PI / 2 + PI / 4 - 0.35, 4, color, w * 0.6, true)
		&"drop":
			var pts := PackedVector2Array([p.call(0, -15)])
			for i in 13:
				pts.append(p.call(0, 4) + Vector2.from_angle(deg_to_rad(-30 + i * 20)) * 9 * u)
			_outline(ci, pts, color, w)
			ci.draw_arc(p.call(0, 4), 5 * u, PI * 0.6, PI * 0.95, 5, color, w, true)
		&"coin":
			ci.draw_circle(at, 12 * u, color, false, w, true)
			ci.draw_circle(at, 7.5 * u, color, false, w * 0.7, true)
			ci.draw_line(p.call(0, -4), p.call(0, 4), color, w, true)
		&"magnet":
			var arc := PackedVector2Array([p.call(-10, -12), p.call(-10, 0)])
			for i in 9:
				arc.append(at + Vector2.from_angle(PI - i * PI / 8) * 10 * u)
			arc.append(p.call(10, -12))
			ci.draw_polyline(arc, color, w * 2.2, true)
			ci.draw_rect(Rect2(p.call(-14, -15), Vector2(8, 4) * u), bg)
			ci.draw_rect(Rect2(p.call(6, -15), Vector2(8, 4) * u), bg)
			ci.draw_rect(Rect2(p.call(-14, -15), Vector2(8, 4) * u), color, false, w * 0.6)
			ci.draw_rect(Rect2(p.call(6, -15), Vector2(8, 4) * u), color, false, w * 0.6)
		&"target":
			ci.draw_circle(at, 10 * u, color, false, w, true)
			ci.draw_circle(at, 3 * u, color)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(at + d * 6 * u, at + d * 15 * u, color, w)
		&"portal":
			_ellipse(ci, at, Vector2(9, 14) * u, color, w)
			_ellipse(ci, at, Vector2(4, 8) * u, color, w * 0.8)
			ci.draw_line(p.call(12, -12), p.call(15, -15), color, w)
			ci.draw_line(p.call(-12, 12), p.call(-15, 15), color, w)
		&"eye":
			var top := PackedVector2Array()
			var bottom := PackedVector2Array()
			for i in 11:
				var x := -14.0 + i * 2.8
				var y := 8.0 * (1.0 - pow(x / 14.0, 2))
				top.append(p.call(x, -y))
				bottom.append(p.call(x, y))
			ci.draw_polyline(top, color, w, true)
			ci.draw_polyline(bottom, color, w, true)
			ci.draw_circle(at, 4.5 * u, color)
		&"lock":
			ci.draw_arc(p.call(0, -3), 6 * u, PI, TAU, 8, color, w * 1.2, true)
			ci.draw_line(p.call(-6, -3), p.call(-6, 1), color, w * 1.2)
			ci.draw_line(p.call(6, -3), p.call(6, 1), color, w * 1.2)
			ci.draw_rect(Rect2(p.call(-10, 1), Vector2(20, 13) * u), color)
			ci.draw_circle(p.call(0, 6), 2 * u, bg)
			ci.draw_line(p.call(0, 6), p.call(0, 10), bg, w)
		&"moon":
			ci.draw_circle(at, 12 * u, color)
			ci.draw_circle(p.call(6, -4), 10 * u, bg)
			ci.draw_circle(p.call(9, 9), 1.5 * u, color)
			ci.draw_circle(p.call(13, 2), 1.2 * u, color)
		&"coin_portal":
			_ellipse(ci, p.call(-3, -1), Vector2(8, 13) * u, color, w)
			ci.draw_circle(p.call(7, 8), 7 * u, bg)
			ci.draw_circle(p.call(7, 8), 6 * u, color, false, w, true)
			ci.draw_line(p.call(7, 5), p.call(7, 11), color, w * 0.8)
		&"wand":
			ci.draw_line(p.call(-13, 13), p.call(6, -6), color, w * 1.6, true)
			_star(ci, p.call(9, -9), 7 * u, color)
		&"chain":
			for c in [Vector2(-6, 6), Vector2(6, -6)]:
				var pts := PackedVector2Array()
				for i in 13:
					pts.append(p.call(c.x, c.y) + Vector2.from_angle(TAU * i / 12.0) * Vector2(9, 5).rotated(-PI / 4) * u)
				ci.draw_polyline(pts, color, w, true)
		&"twin":
			_bolt(ci, at + Vector2(-6, 0) * u, u * 0.6, color)
			_bolt(ci, at + Vector2(6, 0) * u, u * 0.6, color)
		&"crit":
			_star(ci, at, 14 * u, color)
			ci.draw_circle(at, 3 * u, bg)
		&"pistol":
			ci.draw_rect(Rect2(p.call(-13, -8), Vector2(26, 7) * u), color)
			ci.draw_colored_polygon(PackedVector2Array([p.call(-12, -2), p.call(-4, -2), p.call(-7, 12), p.call(-14, 11)]), color)
			ci.draw_arc(p.call(-1, 1), 4 * u, 0.0, PI, 6, color, w * 0.7)
		&"orb":
			ci.draw_circle(at, 11 * u, color, false, w, true)
			ci.draw_arc(at, 6 * u, 0.0, PI * 1.3, 8, color, w, true)
			ci.draw_circle(p.call(3, -2), 2 * u, color)
		&"skull":
			ci.draw_circle(p.call(0, -3), 11 * u, color)
			ci.draw_rect(Rect2(p.call(-6, 4), Vector2(12, 9) * u), color)
			ci.draw_circle(p.call(-4.5, -3), 3.2 * u, bg)
			ci.draw_circle(p.call(4.5, -3), 3.2 * u, bg)
			ci.draw_line(p.call(-2, 8), p.call(-2, 13), bg, w * 0.6)
			ci.draw_line(p.call(2, 8), p.call(2, 13), bg, w * 0.6)
		&"witch":
			ci.draw_colored_polygon(PackedVector2Array([p.call(-6, 6), p.call(2, -15), p.call(8, -11), p.call(6, 6)]), color)
			ci.draw_line(p.call(-14, 7), p.call(14, 7), color, w * 1.6, true)
			ci.draw_line(p.call(-5, 2), p.call(6, 2), bg, w)
		&"bird":
			ci.draw_polyline(PackedVector2Array([p.call(-15, -4), p.call(-7, -9), p.call(0, -1), p.call(7, -9), p.call(15, -4)]), color, w * 1.3, true)
			ci.draw_circle(p.call(0, 3), 4 * u, color)
			ci.draw_colored_polygon(PackedVector2Array([p.call(-2, 6), p.call(2, 6), p.call(0, 13)]), color)
		&"bat":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0, -4), p.call(-6, -8), p.call(-15, -6), p.call(-11, 0), p.call(-12, 6),
				p.call(-5, 3), p.call(0, 8), p.call(5, 3), p.call(12, 6), p.call(11, 0), p.call(15, -6), p.call(6, -8)]), color)
			ci.draw_line(p.call(-2, -4), p.call(-3, -9), color, w)
			ci.draw_line(p.call(2, -4), p.call(3, -9), color, w)
		&"flame":
			var pts := PackedVector2Array()
			for i in 17:
				var t := float(i) / 16.0 * TAU
				var r := 9.0 + 5.0 * maxf(0.0, -sin(t)) * (1.0 + 0.4 * sin(t * 3.0))
				pts.append(p.call(cos(t) * 9.0, 4.0 - sin(t) * r))
			ci.draw_colored_polygon(pts, color)
			ci.draw_circle(p.call(0, 7), 4 * u, bg)
		&"jetpack":
			ci.draw_rect(Rect2(p.call(-11, -13), Vector2(9, 20) * u), color)
			ci.draw_rect(Rect2(p.call(2, -13), Vector2(9, 20) * u), color)
			ci.draw_rect(Rect2(p.call(-2, -9), Vector2(4, 12) * u), color, false, w * 0.6)
			for x in [-6.5, 6.5]:
				ci.draw_colored_polygon(PackedVector2Array([p.call(x - 3, 8), p.call(x + 3, 8), p.call(x, 16)]), color)
		&"fuel":
			_outline(ci, [p.call(-10, -8), p.call(-4, -14), p.call(10, -14), p.call(10, 14), p.call(-10, 14)], color, w)
			ci.draw_line(p.call(-5, -2), p.call(5, 8), color, w, true)
			ci.draw_line(p.call(5, -2), p.call(-5, 8), color, w, true)
			ci.draw_rect(Rect2(p.call(-13, -16), Vector2(6, 5) * u), color)
		&"gauge":
			ci.draw_arc(p.call(0, 5), 13 * u, PI, TAU, 12, color, w, true)
			for i in 5:
				var d := Vector2.from_angle(PI + i * PI / 4)
				ci.draw_line(p.call(0, 5) + d * 9 * u, p.call(0, 5) + d * 13 * u, color, w * 0.7)
			ci.draw_line(p.call(0, 5), p.call(0, 5) + Vector2.from_angle(-PI * 0.3) * 10 * u, color, w * 1.2, true)
			ci.draw_circle(p.call(0, 5), 2.5 * u, color)
		&"gyro":
			ci.draw_circle(at, 12 * u, color, false, w, true)
			_ellipse(ci, at, Vector2(12, 4) * u, color, w * 0.8)
			ci.draw_line(p.call(0, -15), p.call(0, 15), color, w, true)
			ci.draw_circle(at, 3 * u, color)
		&"wind":
			ci.draw_polyline(PackedVector2Array([p.call(-14, -6), p.call(6, -6), p.call(10, -10), p.call(6, -13)]), color, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(-14, 1), p.call(10, 1), p.call(14, 5), p.call(10, 9)]), color, w, true)
			ci.draw_line(p.call(-10, 8), p.call(2, 8), color, w, true)
		&"coin_stack":
			for k in 3:
				_ellipse(ci, p.call(0, 8 - k * 7), Vector2(11, 4) * u, color, w)
		&"palette":
			ci.draw_circle(at, 13 * u, color)
			ci.draw_circle(p.call(5, 6), 3.5 * u, bg)
			for c in [Vector2(-6, -5), Vector2(1, -8), Vector2(-7, 3)]:
				ci.draw_circle(p.call(c.x, c.y), 2.3 * u, bg)
		&"thorns":
			ci.draw_circle(at, 7 * u, color)
			for i in 8:
				var d := Vector2.from_angle(TAU * i / 8.0)
				ci.draw_colored_polygon(PackedVector2Array([at + d.rotated(0.35) * 6 * u, at + d * 15 * u, at + d.rotated(-0.35) * 6 * u]), color)
		&"revive":
			_outline(ci, _heart(at + Vector2(0, 3) * u, u, 0.75), color, w)
			_ellipse(ci, p.call(0, -12), Vector2(8, 2.5) * u, color, w)
		_:
			ci.draw_circle(at, 4 * u, color)


static func _star(ci: CanvasItem, at: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		pts.append(at + Vector2.from_angle(-PI / 2 + i * PI / 4) * (r if i % 2 == 0 else r * 0.35))
	ci.draw_colored_polygon(pts, color)


static func _bolt(ci: CanvasItem, at: Vector2, u: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for v in [Vector2(4, -15), Vector2(-8, 2), Vector2(-1, 2), Vector2(-4, 15), Vector2(9, -3), Vector2(1, -3)]:
		pts.append(at + v * u)
	ci.draw_colored_polygon(pts, color)


static func _heart(at: Vector2, u: float, k: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 24:
		var t := TAU * i / 24.0
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(at + Vector2(x, y + 1.5) * 0.82 * k * u)
	return pts


static func _outline(ci: CanvasItem, pts: Array, color: Color, w: float) -> void:
	var line := PackedVector2Array(pts)
	line.append(line[0])
	ci.draw_polyline(line, color, w, true)


static func _ellipse(ci: CanvasItem, at: Vector2, radii: Vector2, color: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 21:
		pts.append(at + Vector2.from_angle(TAU * i / 20.0) * radii)
	ci.draw_polyline(pts, color, w, true)
