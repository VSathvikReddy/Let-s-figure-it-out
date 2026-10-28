class_name HitInfo
## Extra facts a player attack passes to take_hit(amount, from_pos, info):
##   kind      SINGLE (pistol bullet, machete) or AREA (rocket blast, staff burst)
##   source    &"pistol", &"machete", &"rocket", ...
##   point     exact world point that was hit (bullets) - weak points use it
##   dir       direction the attack travelled
## Enemies decide from it whether a hit staggers them (see staggers()).

const SINGLE := &"single"
const AREA := &"area"


static func make(kind: StringName, source: StringName, point := Vector2.INF, dir := Vector2.ZERO) -> Dictionary:
	return {"kind": kind, "source": source, "point": point, "dir": dir}


static func is_area(info: Dictionary) -> bool:
	return info.get("kind", SINGLE) == AREA


## Damage a rocket blast at `pos` deals to something at `at`: full at the centre,
## falling to 35% at the edge, 0 out of reach (radius x 1.2).
static func blast_damage(at: Vector2, pos: Vector2, radius: float, damage: float) -> float:
	var reach := radius * 1.2
	var d := at.distance_to(pos)
	return 0.0 if d > reach else damage * clampf(1.0 - d / reach, 0.35, 1.0)


## True if a world point is within `radius` of a body's collision box (its
## first CollisionShape2D). Contact attacks use this, so they hit the player's
## whole body - head to feet - not just a point at its centre.
static func near_body(body: Node2D, point: Vector2, radius: float) -> bool:
	if body == null:
		return false
	for c in body.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape:
			var cs := c as CollisionShape2D
			var r := cs.shape.get_rect()
			var xf := cs.global_transform
			var a := xf * r.position
			var b := xf * r.end
			var box := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())
			var closest := Vector2(clampf(point.x, box.position.x, box.end.x), clampf(point.y, box.position.y, box.end.y))
			return closest.distance_to(point) <= radius
	return body.global_position.distance_to(point) <= radius


## HitInfo for a rocket blast centred at `pos`.
static func blast(pos: Vector2) -> Dictionary:
	return make(AREA, &"rocket", pos)


## A hit staggers (cancels windups, knocks back) when it is big enough.
## Single-target hits are scaled by single_mult (0 = they never stagger, e.g.
## the goblin shrugs off pistol shots); area hits always count in full.
static func staggers(info: Dictionary, amount: float, threshold: float, single_mult := 1.0) -> bool:
	if is_area(info):
		return amount >= threshold * 0.5
	return amount * single_mult >= threshold
