extends SceneTree

const SPRITESHEET := "res://enemies/printer/spritesheet.png"
const SPRITE_FRAMES_OUTPUT := "res://enemies/printer/printer_sprite_frames.res"
const ENEMY_OUTPUT := "res://enemies/printer/printer_enemy.tres"
const FRAME_SIZE := 512
const ENEMY_HEALTH := 25
const ENEMY_SCALE := Vector2(0.03, 0.03)
const ENEMY_OFFSET := Vector2.ZERO

const ANIMATIONS := {
	"idle": {"row": 0, "frame_count": 1, "fps": 1.0, "loop": true},
	"attack": {"row": 1, "frame_count": 6, "fps": 14.0, "loop": false},
	"death": {"row": 2, "frame_count": 6, "fps": 10.0, "loop": false},
}


func _initialize() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(SPRITESHEET))
	if image == null or image.is_empty():
		push_error("Could not load %s" % SPRITESHEET)
		quit(1)
		return
	var spritesheet := ImageTexture.create_from_image(image)

	var sprite_frames := SpriteFrames.new()
	if sprite_frames.has_animation("default"):
		sprite_frames.remove_animation("default")

	for animation_name in ANIMATIONS:
		var animation: Dictionary = ANIMATIONS[animation_name]
		sprite_frames.add_animation(animation_name)
		sprite_frames.set_animation_speed(animation_name, float(animation["fps"]))
		sprite_frames.set_animation_loop(animation_name, bool(animation["loop"]))

		var row := int(animation["row"])
		for column in range(int(animation["frame_count"])):
			var frame := _build_frame_texture(spritesheet, column, row)
			sprite_frames.add_frame(animation_name, frame)

	var error := ResourceSaver.save(sprite_frames, SPRITE_FRAMES_OUTPUT, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		push_error("Could not save %s: %s" % [SPRITE_FRAMES_OUTPUT, error])
		quit(1)
		return

	var enemy_stats: EnemyStats = load("res://custom_resources/enemy_stats.gd").new()
	var stored_sprite_frames := load(SPRITE_FRAMES_OUTPUT) as SpriteFrames
	enemy_stats.ai = load("res://enemies/crab/crab_enemy_ai.tscn")
	enemy_stats.max_health = ENEMY_HEALTH
	enemy_stats.sprite_frames = stored_sprite_frames
	enemy_stats.sprite_animation_scale = ENEMY_SCALE
	enemy_stats.sprite_animation_offset = ENEMY_OFFSET

	error = ResourceSaver.save(enemy_stats, ENEMY_OUTPUT)
	if error != OK:
		push_error("Could not save %s: %s" % [ENEMY_OUTPUT, error])
		quit(1)
		return

	print("Imported Printer SpriteFrames to %s" % SPRITE_FRAMES_OUTPUT)
	print("Imported Printer EnemyStats to %s" % ENEMY_OUTPUT)
	quit()


func _build_frame_texture(spritesheet: Texture2D, column: int, row: int) -> AtlasTexture:
	var frame := AtlasTexture.new()
	frame.atlas = spritesheet
	frame.region = Rect2(
		column * FRAME_SIZE,
		row * FRAME_SIZE,
		FRAME_SIZE,
		FRAME_SIZE
	)
	return frame
