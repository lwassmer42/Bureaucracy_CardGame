class_name SaveGame
extends Resource

const SAVE_PATH := "user://savegame.tres"
static var save_path_override := ""

@export var rng_seed: int
@export var rng_state: int
@export var run_stats: RunStats
@export var char_stats: CharacterStats
@export var current_deck: CardPile
@export var current_health: int
@export var relics: Array[Relic]
@export var map_data: Array[Array]
@export var last_room: Room
@export var floors_climbed: int
@export var was_on_map: bool


func save_data() -> void:
	var err := ResourceSaver.save(self, get_save_path())
	assert(err == OK, "Couldn't save the game!")


static func load_data() -> SaveGame:
	var save_path := get_save_path()
	if FileAccess.file_exists(save_path):
		return ResourceLoader.load(save_path) as SaveGame
	
	return null


static func delete_data() -> void:
	var save_path := get_save_path()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)


static func get_save_path() -> String:
	return save_path_override if not save_path_override.is_empty() else SAVE_PATH
