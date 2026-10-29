class_name Progress
extends RefCounted
## Persistent incremental-game progress: coins, entropy (earned by restoring
## the painting), upgrade levels and the equipped
## weapon / staff. Saved to user://entropy_save.cfg. Everything is static, so
## any script can call Progress.coins(), Progress.stat(&"max_health"), ...
## Nodes in the "progress_listeners" group get on_progress_changed() whenever
## something changes (coins, a purchase, a new loadout).

const SAVE_PATH := "user://entropy_save.cfg"
const TREE_PATH := "res://sinan/systems/progress/skill_tree.tres"
const DIFFICULTY_PATH := "res://sinan/systems/run/difficulty.tres"

static var _loaded := false
static var _coins := 0
static var _entropy := 0
static var _levels := {}          # upgrade id -> level
static var _stats := {}           # stat key -> summed value (cleared when levels change)
static var _weapon := 0           # index into tree.weapon_scenes
static var _dirty := false        # coins changed since the last save
static var _tree: SkillTreeData
static var _best_clarity := 0.0   # most of the painting ever restored (0..1)
static var _coins_spent := 0      # in the skill tree, ever (a measure of strength)
static var _runs := 0
static var _difficulty: Difficulty


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


## Adds exactly `amount` coins. (Coin Value and the milestone bonus are not
## applied here: they make enemies DROP more coins - see coin_multiplier() - so
## every coin you see on the floor is worth exactly 1.)
static func add_coins(amount: int, tree_node: Node = null) -> int:
	_ensure()
	_coins += amount
	_dirty = true  # saved by save_if_dirty() (the HUD calls it), not on every coin
	_notify(tree_node)
	return amount


## How many more coins drop: Coin Value upgrade + painting milestones (1.3 = +30%).
static func coin_multiplier() -> float:
	return 1.0 + stat(&"coin_value") + milestone_bonus()


## Pay coins (saves and notifies). False if there are not enough.
static func spend(amount: int, tree_node: Node = null) -> bool:
	_ensure()
	if amount > _coins:
		return false
	_coins -= amount
	_coins_spent += amount
	save_game()
	_notify(tree_node)
	return true


static func entropy() -> int:
	_ensure()
	return _entropy


static func add_entropy(amount: int, tree_node: Node = null) -> void:
	_ensure()
	if amount <= 0:
		return
	_entropy += amount
	_dirty = true
	_notify(tree_node)


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


## Coins or entropy, whichever this upgrade is paid with.
static func wallet(u: UpgradeDef) -> int:
	return entropy() if u.uses_entropy() else coins()


static func can_buy(u: UpgradeDef) -> bool:
	if u == null or level(u.id) >= u.max_level:
		return false
	if u.requires != &"" and level(u.requires) < u.requires_level:
		return false
	return wallet(u) >= u.cost_for_level(level(u.id))


static func buy(u: UpgradeDef, tree_node: Node = null) -> bool:
	if not can_buy(u):
		return false
	var cost := u.cost_for_level(level(u.id))
	_levels[u.id] = level(u.id) + 1
	_stats.clear()
	if u.uses_entropy():
		_entropy -= cost
		save_game()
		_notify(tree_node)
		return true
	return spend(cost, tree_node)


# ---------------------------------------------------------------- runs

static func best_clarity() -> float:
	_ensure()
	return _best_clarity


static func coins_spent() -> int:
	_ensure()
	return _coins_spent


static func runs() -> int:
	_ensure()
	return _runs


## Remember how much of the painting is restored (keeps the best ever).
static func record_clarity(clarity: float) -> void:
	_ensure()
	if clarity > _best_clarity:
		_best_clarity = clarity
		_dirty = true


static func end_run() -> void:
	_ensure()
	_runs += 1
	save_game()


## Extra coin multiplier from the painting milestones reached (0.1 = +10%).
static func milestone_bonus() -> float:
	if _difficulty == null:
		_difficulty = load(DIFFICULTY_PATH)
	if _difficulty == null:
		return 0.0
	return _difficulty.milestones_reached(_best_clarity) * _difficulty.milestone_coin_bonus


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
	cfg.set_value("progress", "entropy", _entropy)
	cfg.set_value("progress", "levels", _levels)
	cfg.set_value("progress", "weapon", _weapon)
	cfg.set_value("progress", "best_clarity", _best_clarity)
	cfg.set_value("progress", "coins_spent", _coins_spent)
	cfg.set_value("progress", "runs", _runs)
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
	_entropy = int(cfg.get_value("progress", "entropy", 0))
	_levels = cfg.get_value("progress", "levels", {})
	_stats.clear()
	_weapon = int(cfg.get_value("progress", "weapon", 0))
	_best_clarity = float(cfg.get_value("progress", "best_clarity", 0.0))
	_coins_spent = int(cfg.get_value("progress", "coins_spent", 0))
	_runs = int(cfg.get_value("progress", "runs", 0))


## Wipe all progress (for testing), including the saved painting.
static func reset() -> void:
	_loaded = true
	_coins = 0
	_entropy = 0
	_levels = {}
	_stats.clear()
	_weapon = 0
	_best_clarity = 0.0
	_coins_spent = 0
	_runs = 0
	save_game()
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("painting_") and f.ends_with(".png"):
			DirAccess.remove_absolute("user://" + f)


static func _notify(tree_node: Node) -> void:
	if tree_node and tree_node.is_inside_tree():
		tree_node.get_tree().call_group("progress_listeners", "on_progress_changed")
