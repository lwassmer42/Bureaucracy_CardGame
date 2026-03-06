extends Control

@export var card_id: String = "bureaucracy_form_27b6"

@onready var frame_rect: TextureRect = $Frame
@onready var art_rect: TextureRect = $Art
@onready var name_label: Label = $Name
@onready var rarity_label: Label = $Rarity
@onready var cost_label: Label = $Cost
@onready var rules_label: RichTextLabel = $Rules


func _ready() -> void:
	_apply_layout_and_content()


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _find_design_card(cards_doc: Dictionary, id: String) -> Dictionary:
	var cards = cards_doc.get("cards")
	if typeof(cards) != TYPE_ARRAY:
		return {}
	for c in cards:
		if typeof(c) == TYPE_DICTIONARY and String(c.get("id")) == id:
			return c
	return {}


func _apply_layout_and_content() -> void:
	var frame_cfg := _read_json("res://design/frame_bureaucracy.json")
	var cards_doc := _read_json("res://design/cards_bureaucracy.json")
	var design_card := _find_design_card(cards_doc, card_id)

	# Frame
	var frame_path := String(frame_cfg.get("frame_texture", ""))
	if frame_path != "":
		if not frame_path.begins_with("res://"):
			frame_path = "res://" + frame_path
		frame_rect.texture = load(frame_path)

	# Inner art = the promoted icon texture
	var promoted_path := "res://common_cards/promoted/%s.tres" % card_id
	var promoted := load(promoted_path)
	if promoted is Card:
		var c := promoted as Card
		art_rect.texture = c.icon
		name_label.text = design_card.get("name", c.id)
		rarity_label.text = String(design_card.get("rarity", "COMMON")).to_upper()
		cost_label.text = str(design_card.get("cost", c.cost))
		rules_label.text = String(design_card.get("rules_text", ""))
	else:
		name_label.text = card_id
		rarity_label.text = "(missing promoted .tres)"
		cost_label.text = ""
		rules_label.text = ""

	# Layout
	var card_size = frame_cfg.get("card_size", {})
	if typeof(card_size) == TYPE_DICTIONARY:
		size = Vector2(float(card_size.get("w", 600)), float(card_size.get("h", 900)))
		custom_minimum_size = size
		frame_rect.size = size

	var ar = frame_cfg.get("art_rect", {})
	if typeof(ar) == TYPE_DICTIONARY:
		art_rect.position = Vector2(float(ar.get("x", 28)), float(ar.get("y", 202)))
		art_rect.size = Vector2(float(ar.get("w", 544)), float(ar.get("h", 366)))

	var nr = frame_cfg.get("name_rect", {})
	if typeof(nr) == TYPE_DICTIONARY:
		name_label.position = Vector2(float(nr.get("x", 124)), float(nr.get("y", 136)))
		name_label.size = Vector2(float(nr.get("w", 332)), float(nr.get("h", 44)))

	var rr = frame_cfg.get("rarity_rect", {})
	if typeof(rr) == TYPE_DICTIONARY:
		rarity_label.position = Vector2(float(rr.get("x", 468)), float(rr.get("y", 136)))
		rarity_label.size = Vector2(float(rr.get("w", 108)), float(rr.get("h", 32)))

	var rc = frame_cfg.get("rules_rect", {})
	if typeof(rc) == TYPE_DICTIONARY:
		rules_label.position = Vector2(float(rc.get("x", 28)), float(rc.get("y", 632)))
		rules_label.size = Vector2(float(rc.get("w", 544)), float(rc.get("h", 180)))

	var cc = frame_cfg.get("cost_center", {})
	if typeof(cc) == TYPE_DICTIONARY:
		# Cost label is a small box centered at cost_center
		var cx := float(cc.get("cx", 68))
		var cy := float(cc.get("cy", 136))
		cost_label.size = Vector2(56, 72)
		cost_label.position = Vector2(cx - cost_label.size.x / 2.0, cy - cost_label.size.y / 2.0)

	# Art fit
	var fit := String(design_card.get("art_fit", "cover")).to_lower()
	art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if fit == "cover" else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
