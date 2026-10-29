class_name SpawnEntry
extends Resource
## One line of the spawn table: "this enemy, this often".

## The enemy scene (a file path, not a direct link: the enemies load
## game_data.tres themselves, and a direct link would make a loading loop).
@export_file("*.tscn") var scene := ""
## Relative chance of being picked (goblin 3 + witch 1 = goblins come 3x as often).
@export var weight := 1.0
## At most this many of this enemy alive at once (0 = no own limit).
@export var max_alive := 0
