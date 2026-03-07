class_name CardVisualsFull
extends Control

const FRAME_CONFIG_PATH := "res://design/frame_bureaucracy.json"
const CARDS_DOC_PATH := "res://design/cards_bureaucracy.json"

@export var card: Card : set = set_card
@export_range(0.05, 2.0, 0.01) var display_scale := 1.0 : set = set_display_scale

@onready var frame_rect: TextureRect = $Frame
@onready var art_rect: TextureRect = $Art
@onready var name_label: Label = $Name
@onready var rarity_label: Label = $Rarity
@onready var cost_label: Label = $Cost
@onready var rules_label: RichTextLabel = $Rules

var _frame_cfg: Dictionary = {}
var _cards_doc: Dictionary = {}


func _ready() -> void:
	_frame_cfg = _read_json(FRAME_CONFIG_PATH)
	_cards_doc = _read_json(CARDS_DOC_PATH)
	_apply_layout_and_content()


func set_card(value: Card) -> void:
	card = value
	if not is_node_ready():
		await ready
	_apply_layout_and_content()


func set_display_scale(value: float) -> void:
	display_scale = clampf(value, 0.05, 2.0)
	if not is_node_ready():
		await ready
	_apply_layout_and_content()


func get_base_card_size() -> Vector2:
	if _frame_cfg.is_empty():
		_frame_cfg = _read_json(FRAME_CONFIG_PATH)
	var card_size = _frame_cfg.get("card_size", {})
	if typeof(card_size) == TYPE_DICTIONARY:
		return Vector2(float(card_size.get("w", 600)), float(card_size.get("h", 900)))
	return Vector2(600, 900)


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _find_design_card(id: String) -> Dictionary:
	var cards = _cards_doc.get("cards")
	if typeof(cards) != TYPE_ARRAY:
		return {}
	for c in cards:
		if typeof(c) == TYPE_DICTIONARY and String(c.get("id")) == id:
			return c
	return {}


func _pretty_name(raw_id: String) -> String:
	var cleaned := raw_id
	for prefix in ["bureaucracy_", "warrior_", "wizard_", "assassin_"]:
		if cleaned.begins_with(prefix):
			cleaned = cleaned.trim_prefix(prefix)
			break

	var parts := cleaned.split("_", false)
	for i in range(parts.size()):
		parts[i] = String(parts[i]).capitalize()
	return " ".join(parts)


func _get_rarity_text() -> String:
	if not card:
		return ""
	var keys := Card.Rarity.keys()
	if card.rarity >= 0 and card.rarity < keys.size():
		return String(keys[card.rarity])
	return "COMMON"


func _apply_layout_and_content() -> void:
	if _frame_cfg.is_empty():
		_frame_cfg = _read_json(FRAME_CONFIG_PATH)
	if _cards_doc.is_empty():
		_cards_doc = _read_json(CARDS_DOC_PATH)

	var design_card := _find_design_card(card.id) if card else {}
	var scale_factor := display_scale

	var frame_path := String(_frame_cfg.get("frame_texture", ""))
	if frame_path != "":
		if not frame_path.begins_with("res://"):
			frame_path = "res://" + frame_path
		frame_rect.texture = load(frame_path)
		frame_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	else:
		frame_rect.texture = null

	if card and card.icon:
		art_rect.texture = card.icon
		art_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if card.icon.get_width() >= 256 or card.icon.get_height() >= 256 else CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		art_rect.texture = null
		art_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	if card:
		name_label.text = String(design_card.get("name", _pretty_name(card.id)))
		rarity_label.text = String(design_card.get("rarity", _get_rarity_text())).to_upper()
		cost_label.text = str(design_card.get("cost", card.cost))
		var rules_text := String(design_card.get("rules_text", ""))
		if rules_text == "":
			rules_text = card.get_default_tooltip()
		rules_label.text = rules_text
	else:
		name_label.text = ""
		rarity_label.text = ""
		cost_label.text = ""
		rules_label.text = ""

	var card_size := get_base_card_size()
	var scaled_size := card_size * scale_factor
	size = scaled_size
	custom_minimum_size = scaled_size
	frame_rect.size = scaled_size

	var ar = _frame_cfg.get("art_rect", {})
	if typeof(ar) == TYPE_DICTIONARY:
		art_rect.position = Vector2(float(ar.get("x", 28)), float(ar.get("y", 202))) * scale_factor
		art_rect.size = Vector2(float(ar.get("w", 544)), float(ar.get("h", 366))) * scale_factor

	var nr = _frame_cfg.get("name_rect", {})
	if typeof(nr) == TYPE_DICTIONARY:
		name_label.position = Vector2(float(nr.get("x", 124)), float(nr.get("y", 136))) * scale_factor
		name_label.size = Vector2(float(nr.get("w", 332)), float(nr.get("h", 44))) * scale_factor

	var rr = _frame_cfg.get("rarity_rect", {})
	if typeof(rr) == TYPE_DICTIONARY:
		rarity_label.position = Vector2(float(rr.get("x", 468)), float(rr.get("y", 136))) * scale_factor
		rarity_label.size = Vector2(float(rr.get("w", 108)), float(rr.get("h", 32))) * scale_factor

	var rc = _frame_cfg.get("rules_rect", {})
	if typeof(rc) == TYPE_DICTIONARY:
		rules_label.position = Vector2(float(rc.get("x", 28)), float(rc.get("y", 632))) * scale_factor
		rules_label.size = Vector2(float(rc.get("w", 544)), float(rc.get("h", 180))) * scale_factor

	var cc = _frame_cfg.get("cost_center", {})
	if typeof(cc) == TYPE_DICTIONARY:
		var cost_size := Vector2(56, 72) * scale_factor
		var cx := float(cc.get("cx", 68)) * scale_factor
		var cy := float(cc.get("cy", 136)) * scale_factor
		cost_label.size = cost_size
		cost_label.position = Vector2(cx - cost_size.x / 2.0, cy - cost_size.y / 2.0)

	var fit := String(design_card.get("art_fit", "cover")).to_lower()
	art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if fit == "cover" else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
