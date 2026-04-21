# Player turn order:
# 1. START_OF_TURN Relics 
# 2. START_OF_TURN Statuses
# 3. Draw Hand
# 4. End Turn 
# 5. END_OF_TURN Relics 
# 6. END_OF_TURN Statuses
# 7. Discard Hand
class_name PlayerHandler
extends Node

const HAND_DRAW_INTERVAL := 0.25
const HAND_DISCARD_INTERVAL := 0.25
const BACKLOG_DRAW_COST := 3
const MISFILED_NOTICE := preload("res://common_cards/debuffs/bureaucracy_misfiled_notice.tres")

@export var relics: Node
@export var player: Player
@export var hand: Hand

var character: CharacterStats
var is_player_turn := false
var _emit_player_hand_drawn_after_draw := false


func _ready() -> void:
	Events.card_played.connect(_on_card_played)


func start_battle(char_stats: CharacterStats) -> void:
	character = char_stats
	is_player_turn = false
	character.ensure_runtime_piles()
	character.draw_pile = character.deck.custom_duplicate()
	character.draw_pile.shuffle()
	character.discard = CardPile.new()
	if _has_relic_handler():
		relics.relics_activated.connect(_on_relics_activated)
	player.status_handler.statuses_applied.connect(_on_statuses_applied)
	start_turn()


func start_turn() -> void:
	is_player_turn = true
	character.block = 0
	character.reset_mana()
	if _has_relic_handler():
		relics.activate_relics_by_type(Relic.Type.START_OF_TURN)


func end_turn() -> void:
	is_player_turn = false
	hand.disable_hand()
	if _has_relic_handler():
		relics.activate_relics_by_type(Relic.Type.END_OF_TURN)


func draw_card() -> void:
	reshuffle_deck_from_discard()
	if character.draw_pile.empty():
		return
	hand.add_card(character.draw_pile.draw_card())
	reshuffle_deck_from_discard()


func draw_cards(amount: int, is_start_of_turn_draw: bool = false) -> void:
	_emit_player_hand_drawn_after_draw = is_start_of_turn_draw
	var tween := create_tween()
	for i in range(amount):
		tween.tween_callback(draw_card)
		tween.tween_interval(HAND_DRAW_INTERVAL)
	
	tween.finished.connect(_on_draw_cards_finished)


func discard_cards() -> void:
	if hand.get_child_count() == 0:
		Events.player_hand_discarded.emit()
		return

	var tween := create_tween()
	for card_ui: CardUI in hand.get_children():
		tween.tween_callback(character.discard.add_card.bind(card_ui.card))
		tween.tween_callback(hand.discard_card.bind(card_ui))
		tween.tween_interval(HAND_DISCARD_INTERVAL)
	
	tween.finished.connect(_on_discard_cards_finished)


func reshuffle_deck_from_discard() -> void:
	if not character.draw_pile.empty():
		return

	while not character.discard.empty():
		character.draw_pile.add_card(character.discard.draw_card())

	character.draw_pile.shuffle()


func can_draw_from_backlog() -> bool:
	return (
		is_player_turn
		and character != null
		and character.backlog != null
		and not character.backlog.empty()
		and character.mana >= BACKLOG_DRAW_COST
	)


func draw_from_backlog() -> bool:
	if not can_draw_from_backlog():
		return false

	character.mana -= BACKLOG_DRAW_COST
	draw_cards_from_backlog(1)
	return true


func draw_cards_from_backlog(amount: int) -> int:
	if character == null or character.backlog == null or amount <= 0:
		return 0

	character.ensure_runtime_piles()

	var drawn := 0
	while drawn < amount and not character.backlog.empty():
		var stored_card := character.backlog.draw_card()
		if stored_card == null:
			break
		stored_card.reset_for_persistent_storage()
		if not character.deck.has_card_with_instance_uid(stored_card.instance_uid):
			character.deck.add_card(stored_card)
		hand.add_card(stored_card.create_instance_copy())
		drawn += 1

	if drawn > 0 and is_player_turn:
		hand.enable_hand()

	return drawn

func add_card_to_backlog(card: Card) -> bool:
	if character == null or card == null:
		return false

	character.ensure_runtime_piles()
	card.ensure_instance_uid()
	character.deck.remove_card_by_instance_uid(card.instance_uid)
	if character.backlog.has_card_with_instance_uid(card.instance_uid):
		return true

	var stored_card := card.create_instance_copy()
	stored_card.reset_for_persistent_storage()
	character.backlog.add_card(stored_card)
	return true

func add_misfiled_notice_to_backlog(amount: int = 1) -> bool:
	if amount <= 0:
		return false

	var added := false
	for _i in range(amount):
		added = add_card_to_backlog(MISFILED_NOTICE.create_distinct_instance_copy()) or added
	return added


func _on_card_played(card: Card) -> void:
	if card.file_to_backlog:
		add_card_to_backlog(card)
		return

	if card.exhausts or card.type == Card.Type.POWER:
		return
	
	character.discard.add_card(card)


func _on_statuses_applied(type: Status.Type) -> void:
	match type:
		Status.Type.START_OF_TURN:
			draw_cards(character.cards_per_turn, true)
		Status.Type.END_OF_TURN:
			discard_cards()


func _on_relics_activated(type: Relic.Type) -> void:
	match type:
		Relic.Type.START_OF_TURN:
			player.status_handler.apply_statuses_by_type(Status.Type.START_OF_TURN)
		Relic.Type.END_OF_TURN:
			player.status_handler.apply_statuses_by_type(Status.Type.END_OF_TURN)


func _on_draw_cards_finished() -> void:
	hand.enable_hand()
	if _emit_player_hand_drawn_after_draw:
		Events.player_hand_drawn.emit()
	_emit_player_hand_drawn_after_draw = false


func _on_discard_cards_finished() -> void:
	Events.player_hand_discarded.emit()


func _has_relic_handler() -> bool:
	return (
		relics != null
		and is_instance_valid(relics)
		and relics.has_method("activate_relics_by_type")
		and relics.has_signal("relics_activated")
	)

