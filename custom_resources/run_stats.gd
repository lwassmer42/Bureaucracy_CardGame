class_name RunStats
extends Resource

signal gold_changed
signal budget_changed

const STARTING_GOLD := 70
const STARTING_BUDGET := 1
const BASE_CARD_REWARDS := 3
const BASE_COMMON_WEIGHT := 6.0
const BASE_UNCOMMON_WEIGHT := 3.7
const BASE_RARE_WEIGHT := 0.3

@export var gold := STARTING_GOLD : set = set_gold
@export var budget := STARTING_BUDGET : set = set_budget
@export var card_rewards := BASE_CARD_REWARDS
@export_range(0.0, 10.0) var common_weight := BASE_COMMON_WEIGHT
@export_range(0.0, 10.0) var uncommon_weight := BASE_UNCOMMON_WEIGHT
@export_range(0.0, 10.0) var rare_weight := BASE_RARE_WEIGHT


func set_gold(new_amount: int) -> void:
	gold = new_amount
	gold_changed.emit()


func set_budget(new_amount: int) -> void:
	budget = max(new_amount, 0)
	budget_changed.emit()


func can_spend_budget(amount: int) -> bool:
	if amount <= 0:
		return true
	return budget >= amount


func spend_budget(amount: int) -> bool:
	if not can_spend_budget(amount):
		return false
	set_budget(budget - amount)
	return true


func gain_budget(amount: int) -> void:
	if amount <= 0:
		return
	set_budget(budget + amount)


func reset_weights() -> void:
	common_weight = BASE_COMMON_WEIGHT
	uncommon_weight = BASE_UNCOMMON_WEIGHT
	rare_weight = BASE_RARE_WEIGHT
