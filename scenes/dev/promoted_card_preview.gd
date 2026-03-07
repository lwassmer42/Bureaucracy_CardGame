extends Control

@export var card_id: String = "bureaucracy_form_27b6"

@onready var card_visuals: Control = $CardVisualsFull


func _ready() -> void:
	var promoted_path := "res://common_cards/promoted/%s.tres" % card_id
	var promoted := load(promoted_path)
	if promoted is Card:
		card_visuals.card = promoted as Card
	else:
		push_warning("Missing promoted card resource for %s" % card_id)
