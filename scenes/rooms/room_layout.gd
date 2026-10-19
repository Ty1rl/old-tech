extends Resource

# Authored room geometry resource for Round O Wave A (JAM-2).
# Keeps geometry/layout separate from encounter rosters and teaching schedules.

@export var room_id: StringName = &"gallery"
@export var layout_scene_path: String = "res://scenes/rooms/room_gallery.tscn"
@export var player_spawn: Vector3 = Vector3(0.0, 0.55, 9.2)
@export var entrance_door: Dictionary = {"position": Vector3(0.0, 0.0, 19.2), "width": 4.4}
@export var exit_door: Dictionary = {"position": Vector3(0.0, 0.0, -19.5), "width": 4.4}
@export var floor_palette: Dictionary = {}
@export var lighting: Dictionary = {}
@export var cover: Array[Rect2] = []
@export var cover_pieces: Array[Dictionary] = []


func to_geometry_dict() -> Dictionary:
	return {
		"layout_scene": layout_scene_path,
		"player_spawn": player_spawn,
		"entrance_door": entrance_door.duplicate(true),
		"exit_door": exit_door.duplicate(true),
		"floor_palette": floor_palette.duplicate(true),
		"lighting": lighting.duplicate(true),
		"cover": cover.duplicate(),
		"cover_pieces": cover_pieces.duplicate(true),
	}
