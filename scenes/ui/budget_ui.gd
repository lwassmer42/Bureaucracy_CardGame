class_name BudgetUI
extends HBoxContainer

@export var run_stats: RunStats : set = set_run_stats

@onready var label: Label = $Label


func _ready() -> void:
	label.text = "0"


func set_run_stats(new_value: RunStats) -> void:
	run_stats = new_value
	if run_stats == null:
		return
	if not run_stats.budget_changed.is_connected(_update_budget):
		run_stats.budget_changed.connect(_update_budget)
	_update_budget()


func _update_budget() -> void:
	label.text = str(run_stats.budget)
