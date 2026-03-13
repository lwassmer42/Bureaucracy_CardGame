class_name CardTooltipPopup
extends Control

const CARD_VISUALS_FULL_SCENE := preload("res://scenes/ui/card_visuals_full.tscn")
const VIEWPORT_PADDING := Vector2(10, 8)

@export var background_color: Color = Color("000000b0")

@onready var background: ColorRect = $Background
@onready var tooltip_card: CenterContainer = %TooltipCard
@onready var card_description: RichTextLabel = %CardDescription


func _ready() -> void:
	_clear_cards()
	background.color = background_color
	card_description.visible = false


func show_tooltip(card: Card) -> void:
	_clear_cards()
	var new_card = CARD_VISUALS_FULL_SCENE.instantiate()
	tooltip_card.add_child(new_card)
	new_card.display_scale = _get_tooltip_card_scale(new_card.get_base_card_size())
	new_card.card = card
	card_description.text = _format_card_description(card)
	card_description.visible = true
	show()


func hide_tooltip() -> void:
	if not visible:
		return

	_clear_cards()
	hide()


func _clear_cards() -> void:
	for child: Node in tooltip_card.get_children():
		child.queue_free()
	card_description.text = ""


func _get_tooltip_card_scale(base_size: Vector2) -> float:
	var viewport_size := get_viewport_rect().size - (VIEWPORT_PADDING * 2.0)
	return clampf(minf(viewport_size.x / base_size.x, viewport_size.y / base_size.y), 0.05, 1.0)


func _format_card_description(card: Card) -> String:
	var text := card.tooltip_text
	if text.is_empty():
		text = card.get_default_tooltip()
	text = text.replace("[center]", "").replace("[/center]", "")
	return "[font_size=30]" + text + "[/font_size]"


func _on_gui_input(event: InputEvent) -> void:
	if not event.is_action_pressed("left_mouse"):
		return

	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null or hovered == self or hovered == background:
		hide_tooltip()
