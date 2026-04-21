class_name EnemyAction
extends Node

enum Type {CONDITIONAL, CHANCE_BASED}

@export var intent: Intent
@export var sound: AudioStream
@export var type: Type
@export_range(0.0, 10.0) var chance_weight := 0.0

@onready var accumulated_weight := 0.0

var enemy: Enemy
var target: Node2D


func is_performable() -> bool:
	return false


func perform_action() -> void:
	pass


func update_intent_text() -> void:
	intent.current_text = intent.base_text


func emit_action_completed() -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	Events.enemy_action_completed.emit(enemy)


func schedule_action_completed(delay_seconds: float) -> void:
	var tree := get_tree()
	if tree == null:
		emit_action_completed()
		return
	tree.create_timer(delay_seconds, false).timeout.connect(Callable(self, "emit_action_completed"))
