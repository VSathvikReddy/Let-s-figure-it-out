class_name UpgradeDef
extends Resource
## One upgrade in the skill tree. Edit them in sinan/progress/skill_tree.tres.

@export var id := &""
## Branch it grows in (must match one of SkillTreeData.branches).
@export var branch := &"Health"
@export var title := "Upgrade"
## Icon on its tile (one of SkillIcons.NAMES: heart, bolt, coin, portal, ...).
@export var icon := &"bolt"
@export_multiline var description := ""
@export var max_level := 5
## What it is paid with: Coins (from enemies) or Entropy (from restoring the painting).
@export_enum("Coins", "Entropy") var currency := 0
## Cost of the first level; each next level costs cost_growth times more.
@export var base_cost := 20
@export var cost_growth := 1.6
## Stat this upgrade raises (read by the game through Progress.stat()).
@export var stat := &""
## How much each level adds to that stat.
@export var per_level := 1.0
## The upgrade it hangs off in the tree, and the level that one needs before this
## can be bought. Empty = it hangs off the centre (the start of its branch).
@export var requires := &""
@export var requires_level := 1


func uses_entropy() -> bool:
	return currency == 1


func cost_for_level(level: int) -> int:
	return int(round(base_cost * pow(cost_growth, level)))
