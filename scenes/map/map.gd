class_name Map
extends Node2D

const SCROLL_SPEED := 90
const MAP_ROOM = preload("res://scenes/map/map_room.tscn")
const MAP_LINE = preload("res://scenes/map/map_line.tscn")

@onready var map_generator: MapGenerator = $MapGenerator
@onready var lines: Node2D = %Lines
@onready var rooms: Node2D = %Rooms
@onready var visuals: Node2D = $Visuals
@onready var camera_2d: Camera2D = $Camera2D

var map_data: Array[Array]
var floors_climbed: int
var last_room: Room
var camera_edge_y: float


func _ready() -> void:
	camera_edge_y = MapGenerator.Y_DIST * (MapGenerator.FLOORS - 1)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	
	if event.is_action_pressed("scroll_up"):
		camera_2d.position.y -= SCROLL_SPEED
	elif event.is_action_pressed("scroll_down"):
		camera_2d.position.y += SCROLL_SPEED

	camera_2d.position.y = clamp(camera_2d.position.y, -camera_edge_y, 0)


func generate_new_map() -> void:
	floors_climbed = 0
	map_data = map_generator.generate_map()
	create_map()


func load_map(map: Array[Array], floors_completed: int, last_room_climbed: Room) -> void:
	floors_climbed = floors_completed
	map_data = map
	last_room = last_room_climbed
	_upgrade_legacy_map_positions()
	create_map()
	
	if floors_climbed > 0:
		unlock_next_rooms()
	else:
		unlock_floor()


func create_map() -> void:
	for child: Node in lines.get_children():
		child.free()

	for child: Node in rooms.get_children():
		child.free()

	for current_floor: Array in map_data:
		for room: Room in current_floor:
			if room.next_rooms.size() > 0:
				_spawn_room(room)
	
	# Boss room has no next room but we need to spawn it
	var middle := floori(MapGenerator.MAP_WIDTH * 0.5)
	_spawn_room(map_data[MapGenerator.FLOORS-1][middle])
	_layout_visuals()


func _upgrade_legacy_map_positions() -> void:
	var max_x := 0.0

	for current_floor: Array in map_data:
		for room: Room in current_floor:
			max_x = max(max_x, room.position.x)

	if max_x >= 400.0:
		return

	var legacy_x_scale := MapGenerator.X_DIST / 30.0
	var legacy_y_scale := MapGenerator.Y_DIST / 25.0

	for current_floor: Array in map_data:
		for room: Room in current_floor:
			room.position.x *= legacy_x_scale
			room.position.y *= legacy_y_scale


func _layout_visuals() -> void:
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF

	for current_floor: Array in map_data:
		for room: Room in current_floor:
			if room.next_rooms.is_empty() and room.type != Room.Type.BOSS:
				continue

			min_x = min(min_x, room.position.x)
			max_x = max(max_x, room.position.x)
			min_y = min(min_y, room.position.y)
			max_y = max(max_y, room.position.y)

	var viewport_size := get_viewport_rect().size
	var map_width := max_x - min_x
	var bottom_padding := 110.0

	visuals.position.x = ((viewport_size.x - map_width) * 0.5) - min_x
	visuals.position.y = viewport_size.y - bottom_padding - max_y

	camera_edge_y = abs(min_y) + bottom_padding
	camera_2d.position.y = clampf(camera_2d.position.y, -camera_edge_y, 0.0)


func unlock_floor(which_floor: int = floors_climbed) -> void:
	for map_room: MapRoom in rooms.get_children():
		if map_room.room.row == which_floor:
			map_room.available = true


func unlock_next_rooms() -> void:
	for map_room: MapRoom in rooms.get_children():
		if last_room.next_rooms.has(map_room.room):
			map_room.available = true


func show_map() -> void:
	show()
	camera_2d.enabled = true


func hide_map() -> void:
	hide()
	camera_2d.enabled = false


func _spawn_room(room: Room) -> void:
	var new_map_room := MAP_ROOM.instantiate() as MapRoom
	rooms.add_child(new_map_room)
	new_map_room.room = room
	new_map_room.clicked.connect(_on_map_room_clicked)
	new_map_room.selected.connect(_on_map_room_selected)
	_connect_lines(room)
	
	if room.selected and room.row < floors_climbed:
		new_map_room.show_selected()


func _connect_lines(room: Room) -> void:
	if room.next_rooms.is_empty():
		return
		
	for next: Room in room.next_rooms:
		var new_map_line := MAP_LINE.instantiate() as Line2D
		new_map_line.add_point(room.position)
		new_map_line.add_point(next.position)
		lines.add_child(new_map_line)


func _on_map_room_clicked(room: Room) -> void:
	for map_room: MapRoom in rooms.get_children():
		if map_room.room.row == room.row:
			map_room.available = false


func _on_map_room_selected(room: Room) -> void:
	last_room = room
	floors_climbed += 1
	Events.map_exited.emit(room)
