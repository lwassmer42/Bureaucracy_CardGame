extends SceneTree

const SPRITESHEET := "res://characters/Intern/spritesheet.png"
const OUTPUT := "res://characters/Intern/intern_sprite_frames.tres"
const FRAME_SIZE := 512

const ANIMATIONS := {
	"idle": {"row": 0, "frame_count": 1, "fps": 1.0, "loop": true},
	"attack": {"row": 1, "frame_count": 6, "fps": 14.0, "loop": false},
	"death": {"row": 2, "frame_count": 8, "fps": 10.0, "loop": false},
}


func _initialize() -> void:
	var spritesheet := load(SPRITESHEET) as Texture2D
	if spritesheet == null:
		push_error("Could not load %s" % SPRITESHEET)
		quit(1)
		return

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
			var frame := AtlasTexture.new()
			frame.atlas = spritesheet
			frame.region = Rect2(
				column * FRAME_SIZE,
				row * FRAME_SIZE,
				FRAME_SIZE,
				FRAME_SIZE
			)
			sprite_frames.add_frame(animation_name, frame)

	var error := ResourceSaver.save(sprite_frames, OUTPUT)
	if error != OK:
		push_error("Could not save %s: %s" % [OUTPUT, error])
		quit(1)
		return

	print("Imported Intern SpriteFrames to %s" % OUTPUT)
	quit()
