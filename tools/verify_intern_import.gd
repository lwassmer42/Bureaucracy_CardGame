extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	var intern_stats := load("res://characters/Intern/intern.tres") as CharacterStats
	if player_scene == null or intern_stats == null:
		push_error("Missing player scene or Intern stats")
		get_tree().quit(1)
		return

	var player := player_scene.instantiate() as Player
	get_tree().root.add_child(player)
	player.stats = intern_stats.create_instance()
	await get_tree().process_frame

	var animated := player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var static_sprite := player.get_node("Sprite2D") as Sprite2D
	if animated == null or static_sprite == null:
		push_error("Player visual nodes missing")
		get_tree().quit(1)
		return
	if not animated.visible or static_sprite.visible:
		push_error("Intern did not switch from static to animated player visual")
		get_tree().quit(1)
		return
	if animated.sprite_frames.get_frame_count("idle") != 1:
		push_error("Intern idle frame count is wrong")
		get_tree().quit(1)
		return
	if animated.sprite_frames.get_frame_count("attack") != 6:
		push_error("Intern attack frame count is wrong")
		get_tree().quit(1)
		return
	if animated.sprite_frames.get_frame_count("death") != 8:
		push_error("Intern death frame count is wrong")
		get_tree().quit(1)
		return

	player.play_attack_animation()
	await get_tree().process_frame
	if animated.animation != &"attack":
		push_error("Intern attack animation did not start")
		get_tree().quit(1)
		return

	print("Intern import verification passed")
	get_tree().quit()
