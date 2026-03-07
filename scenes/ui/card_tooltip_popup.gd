class_name CardTooltipPopup
extends Control

const CARD_VISUALS_FULL_SCENE := preload("res://scenes/ui/card_visuals_full.tscn")
const TOOLTIP_CARD_SCALE := 0.72

@export var background_color: Color = Color("000000b0")

@onready var background: ColorRect = $Background
@onready var tooltip_card: CenterContainer = %TooltipCard
@onready var card_description: RichTextLabel = %CardDescription


func _ready() -> void:
	_clear_cards()
	background.color = background_color


func show_tooltip(card: Card) -> void:
	_clear_cards()
	var new_card = CARD_VISUALS_FULL_SCENE.instantiate()
	tooltip_card.add_child(new_card)
	new_card.display_scale = TOOLTIP_CARD_SCALE
	new_card.card = card
	card_description.text = card.get_default_tooltip()
	show()


func hide_tooltip() -> void:
	if not visible:
		return

	_clear_cards()
	hide()


func _clear_cards() -> void:
	for child: Node in tooltip_card.get_children():
		child.queue_free()


func _on_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("left_mouse"):
		hide_tooltip()
