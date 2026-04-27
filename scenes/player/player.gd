class_name Player
extends Node2D

const WHITE_SPRITE_MATERIAL := preload("res://art/white_sprite_material.tres")

@export var stats: CharacterStats : set = set_character_stats

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var stats_ui: StatsUI = $StatsUI
@onready var status_handler: StatusHandler = $StatusHandler
@onready var modifier_handler: ModifierHandler = $ModifierHandler


func _ready() -> void:
	status_handler.status_owner = self
	Events.card_played.connect(_on_card_played)


func set_character_stats(value: CharacterStats) -> void:
	stats = value
	
	if not stats.stats_changed.is_connected(update_stats):
		stats.stats_changed.connect(update_stats)

	update_player()


func update_player() -> void:
	if not stats is CharacterStats: 
		return
	if not is_inside_tree(): 
		await ready

	if stats.sprite_frames != null:
		sprite_2d.hide()
		animated_sprite_2d.show()
		animated_sprite_2d.sprite_frames = stats.sprite_frames
		animated_sprite_2d.scale = stats.sprite_animation_scale
		animated_sprite_2d.position = stats.sprite_animation_offset
		animated_sprite_2d.play("idle")
	else:
		animated_sprite_2d.hide()
		sprite_2d.show()
		sprite_2d.texture = stats.art
	update_stats()


func update_stats() -> void:
	stats_ui.update_stats(stats)


func take_damage(damage: int, which_modifier: Modifier.Type) -> void:
	if stats.health <= 0:
		return
	
	var visual := _get_active_visual()
	visual.material = WHITE_SPRITE_MATERIAL
	var modified_damage := modifier_handler.get_modified_value(damage, which_modifier)
	
	var tween := create_tween()
	tween.tween_callback(Shaker.shake.bind(self, 16, 0.15))
	tween.tween_callback(stats.take_damage.bind(modified_damage))
	tween.tween_interval(0.17)
	
	tween.finished.connect(
		func():
			visual.material = null
			
			if stats.health <= 0:
				_play_death_and_free()
	)


func play_attack_animation() -> void:
	if not animated_sprite_2d.visible or not animated_sprite_2d.sprite_frames.has_animation("attack"):
		return

	animated_sprite_2d.play("attack")
	await animated_sprite_2d.animation_finished
	if is_inside_tree() and animated_sprite_2d.visible:
		animated_sprite_2d.play("idle")


func _get_active_visual() -> CanvasItem:
	if animated_sprite_2d.visible:
		return animated_sprite_2d
	return sprite_2d


func _on_card_played(card: Card) -> void:
	if card.type == Card.Type.ATTACK:
		play_attack_animation()


func _play_death_and_free() -> void:
	Events.player_died.emit()
	if animated_sprite_2d.visible and animated_sprite_2d.sprite_frames.has_animation("death"):
		animated_sprite_2d.play("death")
		await animated_sprite_2d.animation_finished
	queue_free()
