class_name CampaignRooms
extends RefCounted

# Full-game room route. The campaign owns scheduling and acquisition state.
# Four-stage museum progression data, cover kit footprints, and wave/lesson schedules.

const ROOM_IDS: Array[StringName] = [
	&"gallery",
	&"collections",
	&"restoration",
	&"burial",
]

const LESSON_IDS: Array[StringName] = [
	&"cut",
	&"heat",
	&"shot",
	&"slow",
	&"repair",
	&"charge",
	&"opening",
	&"pair",
	&"loop",
	&"zigzag",
	&"rewind",
]

const ENEMY_IDS: Array[StringName] = [
	&"blue",
	&"yellow",
	&"orange",
	&"side_guard",
	&"front_guard",
	&"pair",
	&"loop",
	&"zigzag",
	&"loop_boss",
	&"sequence_boss",
	&"ranged",
	&"final_boss",
]

const FORMATION_IDS: Array[StringName] = [
	&"curve",
	&"line",
	&"cluster",
	&"mixed",
]


static func room_ids() -> Array[StringName]:
	return ROOM_IDS.duplicate()


static func lesson_ids() -> Array[StringName]:
	return LESSON_IDS.duplicate()


static func enemy_ids() -> Array[StringName]:
	return ENEMY_IDS.duplicate()


static func formation_ids() -> Array[StringName]:
	return FORMATION_IDS.duplicate()


static func get_room(room_id: StringName) -> Dictionary:
	for room in definitions():
		if room.get("id") == room_id:
			return room
	return definitions()[0]


# count is the finite pressure roster, excluding a harmless practice specimen.
# burst/interval/max_live stage arrivals through director.spawn_formation (flow warnings).
# acquire gates the beat behind a visible physical tool; empty lesson is combat only.
static func _make_wave(lesson: StringName, formation: StringName, enemies: Array[StringName], count: int, recovery: float, options: Dictionary = {}) -> Dictionary:
	var wave := {"lesson": lesson, "formation": formation, "enemies": enemies.duplicate(),
		"count": count, "recovery": recovery, "burst": 3, "interval": 4.5, "refill_delay": 0.75, "max_live": 5}
	wave.merge(options, true)
	return wave


const GALLERY_LAYOUT := preload("res://scenes/rooms/gallery_layout.tres")
const COLLECTIONS_LAYOUT := preload("res://scenes/rooms/collections_layout.tres")
const RESTORATION_LAYOUT := preload("res://scenes/rooms/restoration_layout.tres")
const BURIAL_LAYOUT := preload("res://scenes/rooms/burial_layout.tres")


static func definitions() -> Array[Dictionary]:
	# Room 1: Public Galleries (1 — LOOP ROUTES from 11.png)
	# Yellow aiming and charge, then orange heat and a deliberate wear-free -> empty repair lesson.
	var gallery_geom: Dictionary = GALLERY_LAYOUT.to_geometry_dict()
	var gallery_lessons: Array[StringName] = [&"shot", &"charge", &"heat", &"repair"]
	var gallery_waves: Array[Dictionary] = [
		_make_wave(&"shot", &"curve", [&"yellow"], 8, 2.2, {"acquire": 2, "burst": 2, "max_live": 4, "interval": 4.2}),
		_make_wave(&"charge", &"line", [&"yellow"], 10, 2.4, {"interval": 4.2}),
		_make_wave(&"heat", &"cluster", [&"orange", &"yellow"], 9, 2.4, {"acquire": 3, "interval": 4.4}),
		_make_wave(&"repair", &"line", [], 0, 0.35),
		_make_wave(&"", &"mixed", [&"orange", &"yellow", &"ranged"], 12, 2.5, {"interval": 4.5}),
	]

	# Room 2: Connected Collections (blue cutter, time slow and emergency rewind, mixed enemies, Loop Curator)
	# Blue cutting and guard openings lead into time slow and emergency rewind, then loops and their boss.
	var collections_geom: Dictionary = COLLECTIONS_LAYOUT.to_geometry_dict()
	var collections_lessons: Array[StringName] = [&"cut", &"opening", &"slow", &"rewind", &"loop"]
	var collections_waves: Array[Dictionary] = [
		_make_wave(&"cut", &"curve", [&"blue", &"yellow", &"orange"], 9, 2.5, {"acquire": 1, "interval": 4.5}),
		_make_wave(&"opening", &"mixed", [&"side_guard", &"front_guard", &"yellow"], 9, 2.5, {"interval": 4.5}),
		_make_wave(&"slow", &"curve", [&"blue", &"orange", &"ranged"], 8, 2.5, {"interval": 4.5}),
		_make_wave(&"rewind", &"line", [&"yellow", &"blue", &"side_guard"], 7, 2.5, {"interval": 4.5}),
		_make_wave(&"loop", &"curve", [&"loop", &"blue", &"yellow"], 6, 3.2, {"burst": 2, "max_live": 4, "interval": 4.5}),
		_make_wave(&"", &"cluster", [&"loop_boss"], 1, 3.0, {"boss": true, "burst": 1}),
	]

	# Room 3: Restoration Rooms (2 — STAGGERED GALLERIES from 11.png)
	# Staggered workbenches introduce paired valves and zigzags before combined pressure and Sequence Warden.
	var restoration_geom: Dictionary = RESTORATION_LAYOUT.to_geometry_dict()
	var restoration_lessons: Array[StringName] = [&"pair", &"zigzag"]
	var restoration_waves: Array[Dictionary] = [
		_make_wave(&"pair", &"line", [&"pair", &"yellow", &"front_guard"], 8, 2.6, {"burst": 2, "interval": 4.5}),
		_make_wave(&"zigzag", &"curve", [&"zigzag", &"blue", &"orange"], 8, 2.6, {"burst": 2, "interval": 4.5}),
		_make_wave(&"", &"mixed", [&"pair", &"ranged", &"side_guard", &"zigzag"], 12, 3.5, {"interval": 4.8, "max_live": 6}),
		_make_wave(&"", &"line", [&"sequence_boss"], 1, 3.0, {"boss": true, "burst": 1}),
	]

	# Room 4: Burial Exhibition (3 — BOSS COURT from 11.png)
	# Wide-open central court for pattern execution, framed by four outer corner plinths and two perimeter partitions.
	var burial_geom: Dictionary = BURIAL_LAYOUT.to_geometry_dict()
	var burial_lessons: Array[StringName] = []
	var burial_waves: Array[Dictionary] = [
		_make_wave(&"", &"mixed", [&"pair", &"zigzag", &"loop", &"ranged", &"orange", &"front_guard"], 18, 4.0, {"interval": 4.8, "max_live": 6}),
		_make_wave(&"", &"cluster", [&"final_boss"], 1, 0.0, {"boss": true, "burst": 1}),
	]

	var rooms: Array[Dictionary] = [
		{
			"id": &"gallery",
			"title": "Public Galleries",
			"story": "The upper public halls have gone cold. Exhibit cases tremble as wires and glass lenses knit themselves into patrolling husks.",
			"layout_archetype": &"loop_routes",
			"layout_scene": gallery_geom["layout_scene"],
			"cover": gallery_geom["cover"],
			"cover_pieces": gallery_geom["cover_pieces"],
			"player_spawn": gallery_geom["player_spawn"],
			"lessons": gallery_lessons,
			"waves": gallery_waves,
			"is_boss_room": false,
			"floor_palette": gallery_geom["floor_palette"],
			"lighting": gallery_geom["lighting"],
			"entrance_door": gallery_geom["entrance_door"],
			"exit_door": gallery_geom["exit_door"],
		},
		{
			"id": &"collections",
			"title": "Connected Collections",
			"story": "Deeper in the archive wings, armored wardens and twin-valve mechanisms guard the sealed collection vaults.",
			"layout_archetype": &"connected_collections",
			"layout_scene": collections_geom["layout_scene"],
			"cover": collections_geom["cover"],
			"cover_pieces": collections_geom["cover_pieces"],
			"player_spawn": collections_geom["player_spawn"],
			"lessons": collections_lessons,
			"waves": collections_waves,
			"is_boss_room": false,
			"floor_palette": collections_geom["floor_palette"],
			"lighting": collections_geom["lighting"],
			"entrance_door": collections_geom["entrance_door"],
			"exit_door": collections_geom["exit_door"],
		},
		{
			"id": &"restoration",
			"title": "Restoration Rooms",
			"story": "In the basement restoration labs, half-wired spines and iron lungs are being stitched together on worktables.",
			"layout_archetype": &"staggered_galleries",
			"layout_scene": restoration_geom["layout_scene"],
			"cover": restoration_geom["cover"],
			"cover_pieces": restoration_geom["cover_pieces"],
			"player_spawn": restoration_geom["player_spawn"],
			"lessons": restoration_lessons,
			"waves": restoration_waves,
			"is_boss_room": false,
			"floor_palette": restoration_geom["floor_palette"],
			"lighting": restoration_geom["lighting"],
			"entrance_door": restoration_geom["entrance_door"],
			"exit_door": restoration_geom["exit_door"],
		},
		{
			"id": &"burial",
			"title": "Burial Exhibition",
			"story": "At the heart of the subterranean rotunda, the restored burial device pulses—drawing every mechanism into a single vessel.",
			"layout_archetype": &"boss_court",
			"layout_scene": burial_geom["layout_scene"],
			"cover": burial_geom["cover"],
			"cover_pieces": burial_geom["cover_pieces"],
			"player_spawn": burial_geom["player_spawn"],
			"lessons": burial_lessons,
			"waves": burial_waves,
			"is_boss_room": true,
			"floor_palette": burial_geom["floor_palette"],
			"lighting": burial_geom["lighting"],
			"entrance_door": burial_geom["entrance_door"],
			"exit_door": burial_geom["exit_door"],
		},
	]
	return rooms
