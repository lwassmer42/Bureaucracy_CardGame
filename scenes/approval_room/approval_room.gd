class_name ApprovalRoom
extends EventRoom

const CARD_MENU_UI = preload("res://scenes/ui/card_menu_ui.tscn")

@onready var title_label: Label = %TitleLabel
@onready var body_label: Label = %BodyLabel
@onready var cards: HBoxContainer = %Cards
@onready var leave_button: Button = %LeaveButton
@onready var stamp_button: Button = %StampButton
@onready var card_tooltip_popup: CardTooltipPopup = $CardTooltipPopup

var candidates: Array[Card] = []
var selected_card: Card


func _ready() -> void:
	leave_button.pressed.connect(_leave_room)
	stamp_button.pressed.connect(_stamp_selected_card)
	stamp_button.disabled = true


func setup() -> void:
	if not is_node_ready():
		await ready
	_populate_candidates()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		card_tooltip_popup.hide_tooltip()


func _clear_cards() -> void:
	for card_ui in cards.get_children():
		card_ui.queue_free()
	selected_card = null
	stamp_button.disabled = true
	card_tooltip_popup.hide_tooltip()


func _populate_candidates() -> void:
	_clear_cards()
	title_label.text = "Supervisor Approval"
	body_label.text = "Choose 1 of 3 cards to stamp. Stamped cards become 30% stronger for the rest of the run."
	leave_button.text = "Skip"

	if character_stats == null:
		body_label.text = "No character data was available."
		leave_button.text = "Continue"
		return

	character_stats.ensure_runtime_piles()
	var eligible: Array[Card] = []
	for card: Card in character_stats.deck.cards:
		if card != null and not card.stamped:
			eligible.append(card)

	eligible.shuffle()
	candidates = eligible.slice(0, min(3, eligible.size()))

	if candidates.is_empty():
		body_label.text = "Every card in your deck is already stamped."
		leave_button.text = "Continue"
		return

	for card: Card in candidates:
		var new_card := CARD_MENU_UI.instantiate() as CardMenuUI
		new_card.custom_minimum_size = Vector2(64, 78)
		var visuals := new_card.get_node("Visuals") as Control
		if visuals:
			visuals.scale = Vector2(2.35, 2.35)
		cards.add_child(new_card)
		new_card.card = card
		new_card.tooltip_requested.connect(_show_tooltip)


func _show_tooltip(card: Card) -> void:
	selected_card = card
	stamp_button.disabled = false
	card_tooltip_popup.show_tooltip(card)


func _stamp_selected_card() -> void:
	if selected_card == null:
		return
	if selected_card.apply_supervisor_stamp():
		_leave_room()


func _leave_room() -> void:
	card_tooltip_popup.hide_tooltip()
	Events.event_room_exited.emit()
	queue_free()
