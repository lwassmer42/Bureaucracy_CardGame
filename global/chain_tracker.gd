extends Node

var current_turn := 1
var active_chains: Dictionary = {}


func _ready() -> void:
	Events.player_turn_ended.connect(_on_player_turn_ended)


func reset() -> void:
	current_turn = 1
	active_chains.clear()


func register_play(card: Card) -> bool:
	if card == null or card.chain_id.is_empty() or card.chain_step <= 0:
		return false

	if card.chain_step == 1:
		active_chains[card.chain_id] = {
			"step": card.chain_step,
			"turn": current_turn,
		}
		return false

	var state: Dictionary = active_chains.get(card.chain_id, {})
	if state.is_empty():
		return false

	var previous_step := int(state.get("step", 0))
	var previous_turn := int(state.get("turn", -99))
	var turns_elapsed := current_turn - previous_turn
	var window := maxi(card.chain_window_turns, 0)
	var triggered := previous_step == card.chain_step - 1 and turns_elapsed <= window

	if triggered:
		active_chains[card.chain_id] = {
			"step": card.chain_step,
			"turn": current_turn,
		}

	return triggered


func _on_player_turn_ended() -> void:
	current_turn += 1
