extends Resource
## How hard each level is. Open difficulty.tres to change the numbers.
##
## Every setting has an EASY value (used by the first painting) and a HARD
## value (used by the last painting). The paintings in between are spread
## evenly between the two, so the difficulty rises in a straight line.
## With 3 paintings: Painting I = easy, Painting II = halfway, Painting III = hard.
##
## The level applies these when it starts (level.gd), on top of what you set
## on each enemy and spawner. A number of 1.0 means "as set in the Inspector".

@export_group("Enemies")
## Enemy health multiplier (bomber 6 -> 4 at 0.7, -> 10 at 1.6).
@export var enemy_health_easy := 0.7
@export var enemy_health_hard := 1.6
## Damage the player takes multiplier (a bomber blast does 3 -> 6 at 2.0).
@export var damage_taken_easy := 1.0
@export var damage_taken_hard := 2.0
## Part of the enemies placed by hand in the level that are kept (the rest are
## removed at random, so easy levels start calmer).
@export_range(0.0, 1.0) var placed_enemies_kept_easy := 0.5
@export_range(0.0, 1.0) var placed_enemies_kept_hard := 1.0

@export_group("Spawners")
## Most enemies alive at once, multiplier.
@export var spawn_max_alive_easy := 0.5
@export var spawn_max_alive_hard := 1.5
## How often waves come, multiplier (0.6 = waves come 40% less often).
@export var spawn_rate_easy := 0.6
@export var spawn_rate_hard := 1.5
## Enemies per wave, multiplier.
@export var spawn_per_wave_easy := 0.7
@export var spawn_per_wave_hard := 1.5
## Wait before the first wave, multiplier (easy levels give you more time).
@export var first_wave_wait_easy := 2.0
@export var first_wave_wait_hard := 0.7

@export_group("Custom Level")
## How hard the custom painting is: 0 = like the first painting, 1 = like the last.
@export_range(0.0, 1.0) var custom_level_difficulty := 0.5


## 0 for the first painting, 1 for the last, evenly spread in between.
func amount_for(level_index: int, level_count: int) -> float:
	if level_index >= level_count:
		return custom_level_difficulty
	if level_count <= 1:
		return 0.0
	return float(level_index) / float(level_count - 1)


func enemy_health(amount: float) -> float:
	return lerpf(enemy_health_easy, enemy_health_hard, amount)


func damage_taken(amount: float) -> float:
	return lerpf(damage_taken_easy, damage_taken_hard, amount)


func placed_enemies_kept(amount: float) -> float:
	return lerpf(placed_enemies_kept_easy, placed_enemies_kept_hard, amount)


func spawn_max_alive(amount: float) -> float:
	return lerpf(spawn_max_alive_easy, spawn_max_alive_hard, amount)


func spawn_rate(amount: float) -> float:
	return lerpf(spawn_rate_easy, spawn_rate_hard, amount)


func spawn_per_wave(amount: float) -> float:
	return lerpf(spawn_per_wave_easy, spawn_per_wave_hard, amount)


func first_wave_wait(amount: float) -> float:
	return lerpf(first_wave_wait_easy, first_wave_wait_hard, amount)
