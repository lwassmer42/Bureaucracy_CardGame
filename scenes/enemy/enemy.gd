class_name Enemy
extends Area2D

const ARROW_OFFSET := 5
const WHITE_SPRITE_MATERIAL := preload("res://art/white_sprite_material.tres")

@export var stats: EnemyStats : set = set_enemy_stats

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var arrow: Sprite2D = $Arrow
@onready var stats_ui: StatsUI = $StatsUI
@onready var intent_ui: IntentUI = $IntentUI
@onready var status_handler: StatusHandler = $StatusHandler
@onready var modifier_handler: ModifierHandler = $ModifierHandler

var enemy_action_picker: EnemyActionPicker
var current_action: EnemyAction : set = set_current_action


func _ready() -> void:
	status_handler.status_owner = self


func set_current_action(value: EnemyAction) -> void:
	current_action = value
	update_intent()


func set_enemy_stats(value: EnemyStats) -> void:
	stats = value.create_instance()
	
	if not stats.stats_changed.is_connected(update_stats):
		stats.stats_changed.connect(update_stats)
		stats.stats_changed.connect(update_action)
	
	update_enemy()


func setup_ai() -> void:
	if enemy_action_picker:
		enemy_action_picker.queue_free()
		
	var new_action_picker := stats.ai.instantiate() as EnemyActionPicker
	add_child(new_action_picker)
	enemy_action_picker = new_action_picker
	enemy_action_picker.enemy = self


func update_stats() -> void:
	stats_ui.update_stats(stats)


func update_action() -> void:
	if not enemy_action_picker:
		return
	
	if not current_action:
		current_action = enemy_action_picker.get_action()
		return
	
	var new_conditional_action := enemy_action_picker.get_first_conditional_action()
	if new_conditional_action and current_action != new_conditional_action:
		current_action = new_conditional_action


func update_enemy() -> void:
	if not stats is Stats: 
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
		sprite_2d.position = Vector2.ZERO

	arrow.position = Vector2.RIGHT * (_get_active_visual_half_width() + ARROW_OFFSET)
	setup_ai()
	update_stats()


func update_intent() -> void:
	if current_action:
		current_action.update_intent_text()
		intent_ui.update_intent(current_action.intent)


func do_turn() -> void:
	stats.block = 0
	
	if not current_action:
		return
	
	current_action.perform_action()


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


func _get_active_visual_half_width() -> float:
	if animated_sprite_2d.visible and animated_sprite_2d.sprite_frames != null:
		var animation_name := animated_sprite_2d.animation
		if animation_name == StringName():
			animation_name = &"idle"
		if animated_sprite_2d.sprite_frames.has_animation(animation_name):
			var frame_texture := animated_sprite_2d.sprite_frames.get_frame_texture(animation_name, 0)
			if frame_texture != null:
				return frame_texture.get_size().x * animated_sprite_2d.scale.x * 0.5
	return sprite_2d.get_rect().size.x * 0.5


func _play_death_and_free() -> void:
	Events.enemy_died.emit(self)
	if animated_sprite_2d.visible and animated_sprite_2d.sprite_frames.has_animation("death"):
		animated_sprite_2d.play("death")
		await animated_sprite_2d.animation_finished
	queue_free()


func _on_area_entered(_area: Area2D) -> void:
	arrow.show()


func _on_area_exited(_area: Area2D) -> void:
	arrow.hide()
