class_name Progress
extends RefCounted
## Persistent incremental-game progress: coins, upgrade levels and the equipped
## weapon / staff. Saved to user://entropy_save.cfg. Everything is static, so
## any script can call Progress.coins(), Progress.stat(&"max_health"), ...
## Nodes in the "progress_listeners" group get on_progress_changed() whenever
## something changes (coins, a purchase, a new loadout).

const SAVE_PATH := "user://entropy_save.cfg"
const TREE_PATH := "res://sinan/systems/progress/skill_tree.tres"

static var _loaded := false
static var _coins := 0
static var _levels := {}          # upgrade id -> level
static var _stats := {}           # stat key -> summed value (cleared when levels change)
static var _weapon := 0           # index into tree.weapon_scenes
static var _coin_fraction := 0.0  # leftover from coin_value multipliers
static var _dirty := false        # coins changed since the last save
static var _tree: SkillTreeData


static func tree() -> SkillTreeData:
	if _tree == null:
		_tree = load(TREE_PATH)
	return _tree


static func _ensure() -> void:
	if not _loaded:
		_loaded = true
		load_game()


# ---------------------------------------------------------------- coins

static func coins() -> int:
	_ensure()
	return _coins


## Adds coins, applying the coin_value upgrade. Returns the amount actually added.
static func add_coins(amount: int, tree_node: Node = null) -> int:
	_ensure()
	var exact := amount * (1.0 + stat(&"coin_value")) + _coin_fraction
	var whole := int(floor(exact))
	_coin_fraction = exact - whole
	_coins += whole
	_dirty = true  # saved by save_if_dirty() (the HUD calls it), not on every coin
	_notify(tree_node)
	return whole


## Pay coins (saves and notifies). False if there are not enough.
static func spend(amount: int, tree_node: Node = null) -> bool:
	_ensure()
	if amount > _coins:
		return false
	_coins -= amount
	save_game()
	_notify(tree_node)
	return true


# ---------------------------------------------------------------- upgrades

static func level(id: StringName) -> int:
	_ensure()
	return int(_levels.get(id, 0))


## Sum of every upgrade that raises this stat (level x per_level). Cached:
## some callers ask every frame.
static func stat(key: StringName) -> float:
	_ensure()
	if _stats.has(key):
		return _stats[key]
	var total := 0.0
	if tree() != null:
		for u in tree().upgrades:
			if u and u.stat == key:
				total += level(u.id) * u.per_level
	_stats[key] = total
	return total


static func can_buy(u: UpgradeDef) -> bool:
	if u == null or level(u.id) >= u.max_level:
		return false
	if u.requires != &"" and level(u.requires) < u.requires_level:
		return false
	return coins() >= u.cost_for_level(level(u.id))


static func buy(u: UpgradeDef, tree_node: Node = null) -> bool:
	if not can_buy(u):
		return false
	_levels[u.id] = level(u.id) + 1
	_stats.clear()
	return spend(u.cost_for_level(level(u.id) - 1), tree_node)


# ---------------------------------------------------------------- loadout

static func equipped_weapon() -> int:
	_ensure()
	return _weapon


static func is_unlocked(unlock_stat: StringName) -> bool:
	return unlock_stat == &"" or stat(unlock_stat) > 0.0


static func equip(index: int, tree_node: Node = null) -> void:
	_ensure()
	_weapon = index
	save_game()
	_notify(tree_node)


# ---------------------------------------------------------------- save / load

static func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "coins", _coins)
	cfg.set_value("progress", "levels", _levels)
	cfg.set_value("progress", "weapon", _weapon)
	cfg.save(SAVE_PATH)


static func save_if_dirty() -> void:
	if _dirty:
		_dirty = false
		save_game()


static func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	_coins = int(cfg.get_value("progress", "coins", 0))
	_levels = cfg.get_value("progress", "levels", {})
	_stats.clear()
	_weapon = int(cfg.get_value("progress", "weapon", 0))


## Wipe all progress (for testing).
static func reset() -> void:
	_coins = 0
	_levels = {}
	_stats.clear()
	_weapon = 0
	save_game()


static func _notify(tree_node: Node) -> void:
	if tree_node and tree_node.is_inside_tree():
		tree_node.get_tree().call_group("progress_listeners", "on_progress_changed")
