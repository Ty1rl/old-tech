extends Node3D

# Standalone preview scene for the four-room museum kit (gallery, collections, restoration, burial).
# Verifies visual layout, cover kit pieces, doorway cues, and collision/clipping agreement.

const Rooms = preload("res://scenes/prototype/rooms.gd")
const RoomEnvironment = preload("res://scenes/prototype/room_environment.gd")

var arena: Node3D
var room_env: Node3D
var room_definitions: Array[Dictionary] = []
var current_room_index: int = 0


func _ready() -> void:
	room_definitions = Rooms.definitions()
	var arena_scene := load("res://scenes/prototype/arena.tscn") as PackedScene
	arena = arena_scene.instantiate()
	add_child(arena)

	if arena.museum != null and is_instance_valid(arena.museum):
		arena.remove_child(arena.museum)
		arena.museum.free()

	room_env = RoomEnvironment.new()
	room_env.name = "RoomEnvironment"
	room_env.build(false)
	room_env.apply_to_arena(arena, true)
	arena.museum = room_env

	apply_room_by_index(0)


func apply_room_by_index(index: int) -> Dictionary:
	if room_definitions.is_empty():
		room_definitions = Rooms.definitions()
	current_room_index = posmod(index, room_definitions.size())
	var def: Dictionary = room_definitions[current_room_index]
	room_env.apply_room(def, arena.cover, arena)
	room_env.sync_cover_colliders(arena, def["cover"])
	if arena.player != null:
		arena.player.position = def.get("player_spawn", Vector3(0.0, 0.55, 13.5))
		arena.player.velocity = Vector3.ZERO
		arena.player.reset_physics_interpolation()
	return def


func apply_room_by_id(room_id: StringName) -> Dictionary:
	for i in range(room_definitions.size()):
		if room_definitions[i].get("id") == room_id:
			return apply_room_by_index(i)
	return apply_room_by_index(0)


func spawn_preview_cohort_for_room(room_id: StringName) -> void:
	if arena == null or arena.director == null:
		return
	arena.director.clear()
	match room_id:
		&"gallery":
			arena.director.spawn(&"blue", Vector3(-13.5, 0.0, -6.5))
			arena.director.spawn(&"blue", Vector3(-13.5, 0.0, -3.5))
			arena.director.spawn(&"yellow", Vector3(-2.0, 0.0, -2.0))
			arena.director.spawn(&"orange", Vector3(2.5, 0.0, -4.5))
		&"collections":
			arena.director.spawn(&"side_guard", Vector3(-3.5, 0.0, -3.0))
			arena.director.spawn(&"front_guard", Vector3(0.5, 0.0, -3.5))
			arena.director.spawn(&"yellow", Vector3(-1.5, 0.0, -7.0))
			arena.director.spawn(&"blue", Vector3(9.5, 0.0, -1.5))
		&"restoration":
			arena.director.spawn(&"blue", Vector3(-13.5, 0.0, -5.0))
			arena.director.spawn(&"side_guard", Vector3(-1.5, 0.0, -4.5))
			arena.director.spawn(&"orange", Vector3(5.5, 0.0, -5.5))
			arena.director.spawn(&"front_guard", Vector3(9.5, 0.0, 2.0))
		&"burial":
			# Central boss court stand-in + outer ring flankers
			arena.director.spawn(&"front_guard", Vector3(0.0, 0.0, -2.0))
			arena.director.spawn(&"blue", Vector3(-9.5, 0.0, -2.5))
			arena.director.spawn(&"blue", Vector3(9.5, 0.0, -2.5))
			arena.director.spawn(&"orange", Vector3(-4.5, 0.0, -9.5))
			arena.director.spawn(&"yellow", Vector3(4.5, 0.0, -9.5))
