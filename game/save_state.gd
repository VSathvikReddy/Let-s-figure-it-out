extends Node

const SAVE_FILE_PATH := "user://save_game.json"
var saved_states: Dictionary = {}

func _ready() -> void:
	_load_game()

func set_state(id: String, data: Variant) -> void:
	assert(not id.is_empty(), "CRITICAL ERROR: Attempted to save state with an EMPTY ID! Every persistent object needs a unique identifier.")
	assert(data is Dictionary or data is Array, "CRITICAL ERROR: Save data for ID '" + id + "' must be a Dictionary or Array!")
	
	saved_states[id] = data
	_save_game()

func get_state(id: String) -> Variant:
	assert(not id.is_empty(), "CRITICAL ERROR: Tried to look up state using an EMPTY ID!")
	
	if saved_states.has(id):
		return saved_states[id]
	return null

func _save_game() -> void:
	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	assert(file != null, "CRITICAL ERROR: Failed to open save file for writing at '" + SAVE_FILE_PATH + "'. Error code: " + str(FileAccess.get_open_error()))
	
	var json_string := JSON.stringify(saved_states)
	file.store_string(json_string)

func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		return
	
	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	assert(file != null, "CRITICAL ERROR: Failed to open save file for reading at '" + SAVE_FILE_PATH + "'.")
	
	var text := file.get_as_text()
	var json := JSON.new()
	var error := json.parse(text)
	
	
	assert(error == OK, "FATAL ERROR: Save file is corrupted! JSON Parse Error at line " + str(json.get_error_line()) + ": " + json.get_error_message())
	
	var parsed_data = json.get_data()
	assert(parsed_data is Dictionary, "FATAL ERROR: Save file root structure is corrupted (expected a Dictionary, got " + str(typeof(parsed_data)) + ").")
	
	saved_states = parsed_data
