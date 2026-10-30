class_name EnemySpawnEntry
extends Resource
## One kind of enemy an EnemySpawner can make, and its rules.
## In the spawner's Inspector: Spawn List -> Add Element -> New EnemySpawnEntry.

## The enemy scene (for example compined/enemies/bat/bat.tscn).
@export var enemy: PackedScene
## How likely this enemy is, compared to the others in the list
## (2 = twice as likely as an enemy with 1).
@export_range(0.0, 10.0, 0.1) var chance := 1.0
## Most of THIS enemy alive at the same time (0 = no limit of its own).
@export var max_alive := 0
## Seconds after the level starts before this enemy can appear.
@export var appears_after := 0.0
