class_name SkillTreeData
extends Resource
## Everything the skill tree and loadout show. Live data:
## sinan/progress/skill_tree.tres (select it, edit in the Inspector).

## Column order in the skill tree.
@export var branches: Array[StringName] = [&"Health", &"Weapons", &"Staff", &"Economy", &"Forger"]
@export var upgrades: Array[UpgradeDef] = []

@export_group("Loadout")
## Every weapon (guns and staffs). One is equipped at a time: left click fires
## it into the world, right click fires it into the painting.
@export var weapon_scenes: Array[PackedScene] = []
@export var weapon_names: PackedStringArray = []
## Stat that unlocks each weapon (empty = unlocked from the start).
@export var weapon_unlock_stats: Array[StringName] = []


func find(id: StringName) -> UpgradeDef:
	for u in upgrades:
		if u and u.id == id:
			return u
	return null
