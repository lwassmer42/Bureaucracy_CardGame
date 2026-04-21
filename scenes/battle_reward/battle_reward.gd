class_name BattleReward
extends Control

const CARD_REWARDS = preload("res://scenes/ui/card_rewards.tscn")
const REWARD_BUTTON = preload("res://scenes/ui/reward_button.tscn")
const GOLD_ICON := preload("res://art/gold.png")
const GOLD_TEXT := "%s gold"
const CARD_ICON := preload("res://art/rarity.png")
const CARD_TEXT := "Add New Card"

@export var run_stats: RunStats
@export var character_stats: CharacterStats
@export var relic_handler: Node

@onready var rewards: VBoxContainer = %Rewards



func _ready() -> void:
	for node: Node in rewards.get_children():
		node.queue_free()


func add_gold_reward(amount: int) -> void:
	var gold_reward := REWARD_BUTTON.instantiate() as RewardButton
	gold_reward.reward_icon = GOLD_ICON
	gold_reward.reward_text = GOLD_TEXT % amount
	gold_reward.pressed.connect(_on_gold_reward_taken.bind(amount))
	rewards.add_child.call_deferred(gold_reward)


func add_card_reward() -> void:
	var card_reward := REWARD_BUTTON.instantiate() as RewardButton
	card_reward.reward_icon = CARD_ICON
	card_reward.reward_text = CARD_TEXT
	card_reward.pressed.connect(_show_card_rewards)
	rewards.add_child.call_deferred(card_reward)


func add_relic_reward(relic: Relic) -> void:
	if not relic:
		return

	var relic_reward := REWARD_BUTTON.instantiate() as RewardButton
	relic_reward.reward_icon = relic.icon
	relic_reward.reward_text = relic.relic_name
	relic_reward.pressed.connect(_on_relic_reward_taken.bind(relic))
	rewards.add_child.call_deferred(relic_reward)


func _show_card_rewards() -> void:
	if not run_stats or not character_stats:
		return
	
	var card_rewards := CARD_REWARDS.instantiate() as CardRewards
	add_child(card_rewards)
	card_rewards.card_reward_selected.connect(_on_card_reward_taken)
	
	var available_cards: Array[Card] = PromotedCards.load_all_duplicates()
	if available_cards.is_empty():
		card_rewards.queue_free()
		return

	var card_reward_array: Array[Card] = []
	var reward_count: int = mini(run_stats.card_rewards, available_cards.size())
	for _i in range(reward_count):
		var picked_card: Card = RNG.array_pick_random(available_cards)
		card_reward_array.append(picked_card)
		available_cards.erase(picked_card)

	card_rewards.rewards = card_reward_array
	card_rewards.show()

func _on_gold_reward_taken(amount: int) -> void:
	if not run_stats:
		return
	
	run_stats.gold += amount


func _on_card_reward_taken(card: Card) -> void:
	if not character_stats or not card:
		return
		
	character_stats.deck.add_card(card)


func _on_relic_reward_taken(relic: Relic) -> void:
	if not relic or relic_handler == null or not relic_handler.has_method("add_relic"):
		return
		
	relic_handler.add_relic(relic)


func _on_back_button_pressed() -> void: 
	Events.battle_reward_exited.emit()

