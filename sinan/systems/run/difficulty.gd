class_name Difficulty
extends Resource
## How a round plays out. Live values: sinan/systems/run/difficulty.tres - edit
## them while play-testing. F3 in game shows every number below, live.
##
## A round is meant to last ~40 s for an average player:
##   0-20 s   calm      - few, slow enemies: time to clean the painting
##   20-40 s  linear    - pressure rises steadily
##   40-80 s  accelerate - it rises faster and faster
##   80 s+    exponential - it explodes; you will not last long
## That clock (plus kills) is the THREAT, which sets how fast portals pour out
## enemies, how often the Forger comes and how tough enemies are.
##
## How MANY enemies may be alive:
##   cap    = set by how much of the painting is restored (more painting = more room)
##   wanted = start + kills x per_kill + threat x per_threat   (never above cap)

@export_group("Round Pacing")
## Threat reached at the end of the calm part.
@export var calm_seconds := 20.0
@export var calm_threat := 0.4
## Linear part: threat added per second until `linear_until`.
@export var linear_until := 40.0
@export var linear_rate := 0.06
## Accelerating part (until `exponential_from`): threat += acceleration x t².
@export var exponential_from := 80.0
@export var acceleration := 0.0025
## Exponential part: the threat grows by this fraction per second.
@export var exponential_rate := 0.035
## Threat added per kill in this round, up to `kill_threat_max`.
@export var kill_threat := 0.03
@export var kill_threat_max := 2.0
## Threat at which every output below reaches its "end" value.
@export var threat_max := 10.0

@export_group("Enemies Alive")
## The CAP, from how much of the painting is restored (0..1): start at a fresh
## painting, end at a fully restored one (curve optional).
@export var cap_start := 4
@export var cap_end := 40
@export var cap_curve: Curve
## How many the game WANTS alive (never above the cap).
@export var wanted_start := 2.0
@export var wanted_per_kill := 0.25
@export var wanted_per_threat := 2.5

@export_group("Entropy")
## Entropy earned for every 1% of the painting restored (live, while you clean).
@export var entropy_per_percent := 4.0

@export_group("Painting Milestones")
## Restored fractions of the painting (best ever). Each one reached gives
## `milestone_coin_bonus` more coins forever (0.1 = +10%).
@export var milestones: PackedFloat32Array = [0.10, 0.15, 0.20, 0.30, 0.40, 0.55, 0.70, 0.85, 1.0]
@export var milestone_coin_bonus := 0.1

@export_group("Forger Visits")
## Seconds the Forger stays away between visits.
@export var forger_away_start := 20.0
@export var forger_away_end := 4.0
@export var forger_away_curve: Curve
## Portals he opens per visit, and how many may be open at once.
@export var portals_per_visit_start := 1
@export var portals_per_visit_end := 4
@export var portals_per_visit_curve: Curve
@export var max_portals_start := 1
@export var max_portals_end := 5
@export var max_portals_curve: Curve

@export_group("Portals")
## Seconds between enemies coming out of a portal.
@export var spawn_interval_start := 5.0
@export var spawn_interval_end := 0.6
@export var spawn_interval_curve: Curve
## Seconds a portal stays open.
@export var portal_duration_start := 24.0
@export var portal_duration_end := 40.0
@export var portal_duration_curve: Curve

@export_group("Enemy Strength")
## Health multiplier for enemies coming out of portals.
@export var enemy_health_start := 1.0
@export var enemy_health_end := 3.0
@export var enemy_health_curve: Curve

@export_group("Custom Rule")
## Optional script with `func threat(ctx: Dictionary) -> float`. When set, its
## result replaces the threat above. ctx: run_time, kills, restored, parts.
@export var rule_script: Script

var _rule: Object


## Threat from the round clock alone (see the table at the top).
func clock_threat(t: float) -> float:
	if t <= calm_seconds:
		return calm_threat * t / maxf(calm_seconds, 0.01)
	var v := calm_threat + linear_rate * (minf(t, exponential_from) - calm_seconds)
	if t > linear_until:
		v += acceleration * pow(minf(t, exponential_from) - linear_until, 2.0)
	if t > exponential_from:
		v *= exp(exponential_rate * (t - exponential_from))
	return v


## The threat and its parts: {clock, kills, total}.
func threat_parts(run_time: float, kills: int, restored: float) -> Dictionary:
	var parts := {"clock": clock_threat(run_time), "kills": minf(kills * kill_threat, kill_threat_max)}
	parts.total = parts.clock + parts.kills
	if rule_script:
		if _rule == null or _rule.get_script() != rule_script:
			_rule = rule_script.new()
		parts.total = float(_rule.threat({"run_time": run_time, "kills": kills, "restored": restored, "parts": parts.duplicate()}))
	return parts


## Most enemies that may be alive, from the painting restored (0..1).
func enemy_cap(restored: float) -> int:
	var k := clampf(restored, 0.0, 1.0)
	return roundi(lerpf(cap_start, cap_end, cap_curve.sample(k) if cap_curve else k))


## How many enemies the game wants alive right now (before the cap).
func enemies_wanted(threat: float, kills: int) -> int:
	return floori(wanted_start + kills * wanted_per_kill + threat * wanted_per_threat)


func milestones_reached(clarity: float) -> int:
	var n := 0
	for m in milestones:
		if clarity >= m - 0.0001:
			n += 1
	return n


## The next milestone above `clarity` (or -1 when all are reached).
func next_milestone(clarity: float) -> float:
	for m in milestones:
		if clarity < m - 0.0001:
			return m
	return -1.0


func forger_away(threat: float) -> float:
	return _out(threat, forger_away_start, forger_away_end, forger_away_curve)


func portals_per_visit(threat: float) -> int:
	return roundi(_out(threat, portals_per_visit_start, portals_per_visit_end, portals_per_visit_curve))


func max_portals(threat: float) -> int:
	return roundi(_out(threat, max_portals_start, max_portals_end, max_portals_curve))


func spawn_interval(threat: float) -> float:
	return _out(threat, spawn_interval_start, spawn_interval_end, spawn_interval_curve)


func portal_duration(threat: float) -> float:
	return _out(threat, portal_duration_start, portal_duration_end, portal_duration_curve)


func enemy_health(threat: float) -> float:
	return _out(threat, enemy_health_start, enemy_health_end, enemy_health_curve)


func _out(threat: float, from: float, to: float, curve: Curve) -> float:
	var k := clampf(threat / maxf(threat_max, 0.01), 0.0, 1.0)
	return lerpf(from, to, curve.sample(k) if curve else k)
