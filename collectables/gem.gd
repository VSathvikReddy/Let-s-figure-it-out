extends Area2D
class_name Gem

@export var gem_sound: AudioStream

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("collect_gem"):
		_spawn_explosion()
		var sfx_player = AudioStreamPlayer2D.new() #New Node
		sfx_player.stream = gem_sound #Assign Sound
		sfx_player.global_position = global_position #set pos
		get_tree().current_scene.add_child(sfx_player) #make it the sibling
		sfx_player.play() #play
		sfx_player.finished.connect(sfx_player.queue_free) #let it play and then kill it
		body.collect_gem(self) # if player collects, he despwans it, other may store it

func _spawn_explosion() -> void:
	var particles := CPUParticles2D.new()
	particles.global_position = global_position
	particles.one_shot = true
	particles.amount = 15
	particles.lifetime = 0.4
	particles.explosiveness = 1.0 # 1.0 means all particles burst out at once
	particles.spread = 180.0
	particles.gravity = Vector2(0, 200)
	particles.initial_velocity_min = 80.0
	particles.initial_velocity_max = 150.0
	particles.scale_amount_min = 4.0
	particles.scale_amount_max = 7.0
	particles.color = Color.WHITE
	
	# 1. Add to the scene root first
	get_tree().current_scene.add_child(particles)
	
	# 2. Trigger emitting AFTER adding to tree so one_shot fires correctly
	particles.emitting = true
	
	# 3. Clean up the particle node automatically after it finishes
	var timer := get_tree().create_timer(particles.lifetime + 0.1)
	timer.timeout.connect(particles.queue_free)
