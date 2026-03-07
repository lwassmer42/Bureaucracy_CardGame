extends Control

const VIEWPORT_PADDING := Vector2(10, 8)

@export var card_id: String = "bureaucracy_form_27b6"

@onready var card_visuals: Control = $CardVisualsFull


func _ready() -> void:
	var promoted_path := "res://common_cards/promoted/%s.tres" % card_id
	var promoted := load(promoted_path)
	if promoted is Card:
		card_visuals.card = promoted as Card
		_fit_card_to_viewport()
	else:
		push_warning("Missing promoted card resource for %s" % card_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_fit_card_to_viewport()


func _fit_card_to_viewport() -> void:
	var base_size: Vector2 = card_visuals.get_base_card_size()
	var viewport_size := get_viewport_rect().size - (VIEWPORT_PADDING * 2.0)
	var scale_factor := minf(viewport_size.x / base_size.x, viewport_size.y / base_size.y)
	scale_factor = clampf(scale_factor, 0.05, 1.0)
	card_visuals.display_scale = scale_factor
	card_visuals.position = (get_viewport_rect().size - card_visuals.size) * 0.5
