class_name PromotedCards
extends Node

const PROMOTED_DIR := "res://common_cards/promoted"


static func load_all() -> Array[Card]:
	var cards: Array[Card] = []
	var entries: Array[Dictionary] = []
	var dir := DirAccess.open(PROMOTED_DIR)
	if dir == null:
		return cards

	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".tres"):
			var path := PROMOTED_DIR + "/" + filename
			entries.append({
				"path": path,
				"modified": FileAccess.get_modified_time(path),
			})
		filename = dir.get_next()
	dir.list_dir_end()

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("modified", 0)) > int(b.get("modified", 0)))
	for entry in entries:
		var res := load(String(entry.get("path", "")))
		if res is Card:
			cards.append(res)
	return cards


static func load_all_duplicates() -> Array[Card]:
	var out: Array[Card] = []
	for card: Card in load_all():
		out.append(card.create_instance_copy())
	return out
