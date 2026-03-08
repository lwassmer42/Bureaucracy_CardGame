class_name Card
extends Resource

enum Type {ATTACK, SKILL, POWER}
enum Rarity {COMMON, UNCOMMON, RARE}
enum Target {SELF, SINGLE_ENEMY, ALL_ENEMIES, EVERYONE}
enum Keyword {ARCHIVE, FILE, CHAIN, CURSE, BUDGET_MODE}

const DEFAULT_EXPOSED_STATUS := preload("res://statuses/exposed.tres")
const RARITY_COLORS := {
	Card.Rarity.COMMON: Color.GRAY,
	Card.Rarity.UNCOMMON: Color.CORNFLOWER_BLUE,
	Card.Rarity.RARE: Color.GOLD,
}

@export_group("Card Attributes")
@export var id: String
@export var type: Type
@export var rarity: Rarity
@export var target: Target
@export var cost: int
@export var exhausts: bool = false
@export var keywords: Array[Keyword] = []

@export_group("Card Effects")
@export var damage := 0
@export var block_amount := 0
@export var cards_to_draw := 0
@export var exposed_to_apply := 0
@export var budget_cost := 0
@export var budget_gain := 0

@export_group("Chain")
@export var chain_id := ""
@export_range(0, 10) var chain_step := 0
@export_range(0, 5) var chain_window_turns := 1
@export var chain_bonus_damage := 0
@export var chain_bonus_block := 0
@export var chain_bonus_cards_to_draw := 0
@export var chain_bonus_exposed_to_apply := 0

@export_group("Card Visuals")
@export var icon: Texture
@export_multiline var tooltip_text: String
@export var sound: AudioStream

@export_group("Card Runtime")
@export var instance_uid := ""
@export_range(0, 3) var upgrade_tier := 0
@export var reviewed_stacks := 0


func is_single_targeted() -> bool:
	return target == Target.SINGLE_ENEMY


func ensure_instance_uid() -> Card:
	if instance_uid.is_empty():
		instance_uid = "%s_%s_%s" % [id, Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	return self


func create_instance_copy() -> Card:
	var copy := duplicate() as Card
	copy.ensure_instance_uid()
	return copy


func can_play(char_stats: CharacterStats, run_stats: RunStats = null) -> bool:
	if char_stats == null or char_stats.mana < cost:
		return false
	if budget_cost <= 0:
		return true
	return run_stats != null and run_stats.can_spend_budget(budget_cost)


func _get_targets(targets: Array[Node]) -> Array[Node]:
	if not targets:
		return []
		
	var tree := targets[0].get_tree()
	
	match target:
		Target.SELF:
			return tree.get_nodes_in_group("player")
		Target.ALL_ENEMIES:
			return tree.get_nodes_in_group("enemies")
		Target.EVERYONE:
			return tree.get_nodes_in_group("player") + tree.get_nodes_in_group("enemies")
		_:
			return []


func play(targets: Array[Node], char_stats: CharacterStats, modifiers: ModifierHandler, run_stats: RunStats = null) -> bool:
	if not can_play(char_stats, run_stats):
		return false

	Events.card_played.emit(self)
	char_stats.mana -= cost
	if budget_cost > 0 and run_stats != null:
		run_stats.spend_budget(budget_cost)

	var resolved_targets := targets if is_single_targeted() else _get_targets(targets)
	var chain_bonus_active := ChainTracker.register_play(self)
	apply_effects(resolved_targets, modifiers)
	if chain_bonus_active:
		_apply_chain_bonus_effects(resolved_targets, modifiers)

	if budget_gain > 0 and run_stats != null:
		run_stats.gain_budget(budget_gain)
	return true


func apply_effects(targets: Array[Node], modifiers: ModifierHandler) -> void:
	_apply_effect_bundle(targets, modifiers, damage, block_amount, cards_to_draw, exposed_to_apply)


func _apply_chain_bonus_effects(targets: Array[Node], modifiers: ModifierHandler) -> void:
	_apply_effect_bundle(targets, modifiers, chain_bonus_damage, chain_bonus_block, chain_bonus_cards_to_draw, chain_bonus_exposed_to_apply)


func _apply_effect_bundle(targets: Array[Node], modifiers: ModifierHandler, damage_amount: int, block_value: int, draw_value: int, exposed_value: int) -> void:
	if damage_amount > 0:
		var damage_effect := DamageEffect.new()
		damage_effect.amount = modifiers.get_modified_value(damage_amount, Modifier.Type.DMG_DEALT)
		damage_effect.sound = sound
		damage_effect.execute(targets)

	if block_value > 0:
		var block_effect := BlockEffect.new()
		block_effect.amount = block_value
		block_effect.sound = sound
		block_effect.execute(targets)

	if draw_value > 0:
		var draw_effect := CardDrawEffect.new()
		draw_effect.cards_to_draw = draw_value
		draw_effect.execute(targets)

	if exposed_value > 0:
		var status_effect := StatusEffect.new()
		var exposed := DEFAULT_EXPOSED_STATUS.duplicate()
		exposed.duration = exposed_value
		status_effect.status = exposed
		status_effect.execute(targets)


func get_default_tooltip() -> String:
	return tooltip_text


func get_updated_tooltip(_player_modifiers: ModifierHandler, _enemy_modifiers: ModifierHandler) -> String:
	return tooltip_text
