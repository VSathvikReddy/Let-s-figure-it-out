class_name DropEntry
extends Resource
## One line of a drop table: "this many coins, with this chance".

## 0..1 chance this line drops at all when the enemy dies.
@export_range(0.0, 1.0) var chance := 1.0
@export var min_count := 1
@export var max_count := 3
