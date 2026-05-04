class_name EnemyStats
extends Stats

@export_group("Visuals")
@export var sprite_frames: SpriteFrames
@export var sprite_animation_scale := Vector2.ONE
@export var sprite_animation_offset := Vector2.ZERO

@export_group("Gameplay Data")
@export var ai: PackedScene
