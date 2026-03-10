class_name BattleUI
extends CanvasLayer

@export var char_stats: CharacterStats : set = _set_char_stats

@onready var hand: Hand = $Hand
@onready var mana_ui: ManaUI = $ManaUI
@onready var end_turn_button: Button = %EndTurnButton
@onready var draw_pile_button: CardPileOpener = %DrawPileButton
@onready var discard_pile_button: CardPileOpener = %DiscardPileButton
@onready var draw_pile_view: CardPileView = %DrawPileView
@onready var discard_pile_view: CardPileView = %DiscardPileView
@onready var backlog_button: Button = %BacklogButton

var player_handler: PlayerHandler


func _ready() -> void:
	player_handler = get_tree().get_first_node_in_group("player_handler") as PlayerHandler
	Events.player_hand_drawn.connect(_on_player_hand_drawn)
	end_turn_button.pressed.connect(_on_end_turn_button_pressed)
	draw_pile_button.pressed.connect(draw_pile_view.show_current_view.bind("Draw Pile", true))
	discard_pile_button.pressed.connect(discard_pile_view.show_current_view.bind("Discard Pile"))
	backlog_button.pressed.connect(_on_backlog_button_pressed)
	_refresh_backlog_button()


func initialize_card_pile_ui() -> void:
	char_stats.ensure_runtime_piles()
	draw_pile_button.card_pile = char_stats.draw_pile
	draw_pile_view.card_pile = char_stats.draw_pile
	discard_pile_button.card_pile = char_stats.discard
	discard_pile_view.card_pile = char_stats.discard
	if not char_stats.backlog.card_pile_size_changed.is_connected(_on_backlog_size_changed):
		char_stats.backlog.card_pile_size_changed.connect(_on_backlog_size_changed)
	_refresh_backlog_button()


func _set_char_stats(value: CharacterStats) -> void:
	char_stats = value
	char_stats.ensure_runtime_piles()
	if not char_stats.stats_changed.is_connected(_on_char_stats_changed):
		char_stats.stats_changed.connect(_on_char_stats_changed)
	mana_ui.char_stats = char_stats
	hand.char_stats = char_stats
	_refresh_backlog_button()


func _on_player_hand_drawn() -> void:
	end_turn_button.disabled = false
	_refresh_backlog_button()


func _on_end_turn_button_pressed() -> void:
	end_turn_button.disabled = true
	Events.player_turn_ended.emit()


func _on_backlog_button_pressed() -> void:
	if player_handler == null:
		return
	player_handler.draw_from_backlog()
	_refresh_backlog_button()


func _on_backlog_size_changed(_cards_amount: int) -> void:
	_refresh_backlog_button()


func _on_char_stats_changed() -> void:
	_refresh_backlog_button()


func _refresh_backlog_button() -> void:
	if not is_node_ready():
		return

	var backlog_count := 0
	if char_stats != null and char_stats.backlog != null:
		backlog_count = char_stats.backlog.cards.size()

	backlog_button.text = "Backlog\n%s file%s\nDraw\n3 mana" % [
		backlog_count,
		"" if backlog_count == 1 else "s",
	]
	backlog_button.disabled = backlog_count == 0 or player_handler == null or not player_handler.can_draw_from_backlog()
