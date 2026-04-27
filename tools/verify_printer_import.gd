extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var enemy_scene := load("res://scenes/enemy/enemy.tscn") as PackedScene
	var printer_stats := load("res://enemies/printer/printer_enemy.tres") as EnemyStats
	if enemy_scene == null or printer_stats == null:
		push_error("Missing enemy scene or printer stats")
		get_tree().quit(1)
		return

	var enemy := enemy_scene.instantiate() as Enemy
	get_tree().root.add_child(enemy)
	enemy.stats = printer_stats
	await get_tree().process_frame

	var animated := enemy.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var static_sprite := enemy.get_node("Sprite2D") as Sprite2D
	if animated == null or static_sprite == null:
		push_error("Enemy visual nodes missing")
		get_tree().quit(1)
		return
	if not animated.visible or static_sprite.visible:
		push_error("Printer did not switch from static to animated enemy visual")
		get_tree().quit(1)
		return
	if animated.sprite_frames.get_frame_count("idle") != 1:
		push_error("Printer idle frame count is wrong")
		get_tree().quit(1)
		return
	if animated.sprite_frames.get_frame_count("attack") != 6:
		push_error("Printer attack frame count is wrong")
		get_tree().quit(1)
		return
	if animated.sprite_frames.get_frame_count("death") != 6:
		push_error("Printer death frame count is wrong")
		get_tree().quit(1)
		return

	enemy.play_attack_animation()
	await get_tree().process_frame
	if animated.animation != &"attack":
		push_error("Printer attack animation did not start")
		get_tree().quit(1)
		return

	print("Printer import verification passed")
	get_tree().quit()
