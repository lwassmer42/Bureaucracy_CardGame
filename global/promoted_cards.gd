class_name PromotedCards
extends Node

const PROMOTED_DIR := "res://common_cards/promoted"


static func load_all() -> Array[Card]:
	var cards: Array[Card] = []
	var dir := DirAccess.open(PROMOTED_DIR)
	if dir == null:
		return cards

	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".tres"):
			var path := PROMOTED_DIR + "/" + filename
			var res := load(path)
			if res is Card:
				cards.append(res)
		filename = dir.get_next()
	dir.list_dir_end()
	return cards


static func load_all_duplicates() -> Array[Card]:
	var out: Array[Card] = []
	for card: Card in load_all():
		out.append(card.duplicate())
	return out
