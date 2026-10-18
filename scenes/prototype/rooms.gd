extends RefCounted

# jam-4 owns rooms.gd.
# Four-stage museum progression data, cover kit footprints, and wave/lesson schedules.

const ROOM_IDS: Array[StringName] = [
	&"gallery",
	&"collections",
	&"restoration",
	&"burial",
]

const LESSON_IDS: Array[StringName] = [
	&"move",
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
	&"final",
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


static func _make_wave(
	lesson: StringName,
	formation: StringName,
	enemies: Array[StringName],
	count: int,
	recovery: float
) -> Dictionary:
	var typed_enemies: Array[StringName] = []
	for kind in enemies:
		typed_enemies.append(kind)
	return {
		"lesson": lesson,
		"formation": formation,
		"enemies": typed_enemies,
		"count": count,
		"recovery": recovery,
	}


static func definitions() -> Array[Dictionary]:
	# Room 1: Public Galleries (1 — LOOP ROUTES from 11.png)
	# Introduces movement around loop-route display islands/columns and simple blue/yellow/orange tools.
	var gallery_cover: Array[Rect2] = [
		Rect2(-8.5, -6.5, 6.0, 3.0),
		Rect2(3.0, 0.5, 6.0, 3.0),
		Rect2(-9.0, 2.0, 2.5, 2.5),
		Rect2(6.0, -7.0, 2.5, 2.5),
	]
	var gallery_pieces: Array[Dictionary] = [
		{"rect": gallery_cover[0], "kind": &"display_island", "height": 1.45, "label": "North-West Vitrine Island"},
		{"rect": gallery_cover[1], "kind": &"display_island", "height": 1.45, "label": "South-East Vitrine Island"},
		{"rect": gallery_cover[2], "kind": &"column", "height": 1.85, "label": "South-West Gallery Column"},
		{"rect": gallery_cover[3], "kind": &"column", "height": 1.85, "label": "North-East Gallery Column"},
	]
	var gallery_lessons: Array[StringName] = [&"move", &"cut", &"shot", &"heat"]
	var gallery_waves: Array[Dictionary] = [
		_make_wave(&"move", &"curve", [&"blue"], 2, 2.5),
		_make_wave(&"cut", &"curve", [&"blue"], 3, 2.5),
		_make_wave(&"shot", &"line", [&"yellow"], 2, 2.5),
		_make_wave(&"heat", &"cluster", [&"orange", &"blue"], 4, 3.0),
	]

	# Room 2: Connected Collections (Loop lanes + benches/plinths for guard openings, charged pierce, and A/B pair)
	# Introduces opening shielded wardens, piercing lines with full charge, and safe solo A/B pair before mixed pressure.
	var collections_cover: Array[Rect2] = [
		Rect2(-10.0, -4.0, 5.5, 2.2),
		Rect2(3.5, -6.5, 6.0, 3.0),
		Rect2(-2.2, -9.0, 2.6, 2.6),
		Rect2(4.0, 2.2, 5.2, 2.2),
	]
	var collections_pieces: Array[Dictionary] = [
		{"rect": collections_cover[0], "kind": &"bench", "height": 1.05, "label": "West Archive Bench"},
		{"rect": collections_cover[1], "kind": &"display_island", "height": 1.45, "label": "North-East Collection Case"},
		{"rect": collections_cover[2], "kind": &"plinth", "height": 1.65, "label": "North Relic Plinth"},
		{"rect": collections_cover[3], "kind": &"bench", "height": 1.05, "label": "South-East Gallery Bench"},
	]
	var collections_lessons: Array[StringName] = [&"opening", &"charge", &"pair", &"repair"]
	var collections_waves: Array[Dictionary] = [
		_make_wave(&"opening", &"cluster", [&"side_guard", &"front_guard"], 2, 2.5),
		_make_wave(&"charge", &"line", [&"yellow", &"side_guard"], 3, 2.5),
		_make_wave(&"pair", &"line", [&"pair"], 1, 3.0),
		_make_wave(&"repair", &"mixed", [&"pair", &"front_guard", &"blue"], 4, 3.0),
	]

	# Room 3: Restoration Rooms (2 — STAGGERED GALLERIES from 11.png)
	# Staggered low partitions and workbenches creating corner draw lanes; teaches loop then zigzag separately before combined pressure.
	var restoration_cover: Array[Rect2] = [
		Rect2(-10.5, -7.5, 6.2, 1.8),
		Rect2(-8.5, 0.2, 6.2, 1.8),
		Rect2(3.0, -8.0, 5.8, 2.0),
		Rect2(3.8, -1.2, 6.2, 1.8),
		Rect2(2.0, 4.2, 5.8, 2.8),
	]
	var restoration_pieces: Array[Dictionary] = [
		{"rect": restoration_cover[0], "kind": &"partition", "height": 1.50, "label": "North-West Staggered Partition"},
		{"rect": restoration_cover[1], "kind": &"partition", "height": 1.50, "label": "Mid-West Staggered Partition"},
		{"rect": restoration_cover[2], "kind": &"bench", "height": 1.05, "label": "North-East Restoration Table"},
		{"rect": restoration_cover[3], "kind": &"partition", "height": 1.50, "label": "Mid-East Staggered Partition"},
		{"rect": restoration_cover[4], "kind": &"display_island", "height": 1.45, "label": "South-East Specimen Case"},
	]
	var restoration_lessons: Array[StringName] = [&"loop", &"zigzag", &"slow", &"rewind"]
	var restoration_waves: Array[Dictionary] = [
		_make_wave(&"loop", &"curve", [&"loop"], 1, 3.0),
		_make_wave(&"zigzag", &"curve", [&"zigzag"], 1, 3.0),
		_make_wave(&"slow", &"cluster", [&"loop", &"orange"], 3, 3.0),
		_make_wave(&"rewind", &"mixed", [&"zigzag", &"loop", &"side_guard"], 4, 3.5),
	]

	# Room 4: Burial Exhibition (3 — BOSS COURT from 11.png)
	# Wide-open central court for pattern execution, framed by four outer corner plinths and two perimeter partitions.
	var burial_cover: Array[Rect2] = [
		Rect2(-12.0, -8.5, 2.8, 2.8),
		Rect2(9.2, -8.5, 2.8, 2.8),
		Rect2(-12.0, 4.2, 2.8, 2.8),
		Rect2(9.2, 4.2, 2.8, 2.8),
		Rect2(-12.5, -2.5, 1.8, 4.8),
		Rect2(10.7, -2.5, 1.8, 4.8),
	]
	var burial_pieces: Array[Dictionary] = [
		{"rect": burial_cover[0], "kind": &"plinth", "height": 1.70, "label": "North-West Bust Plinth"},
		{"rect": burial_cover[1], "kind": &"plinth", "height": 1.70, "label": "North-East Bust Plinth"},
		{"rect": burial_cover[2], "kind": &"plinth", "height": 1.70, "label": "South-West Bust Plinth"},
		{"rect": burial_cover[3], "kind": &"plinth", "height": 1.70, "label": "South-East Bust Plinth"},
		{"rect": burial_cover[4], "kind": &"partition", "height": 1.50, "label": "West Court Screen"},
		{"rect": burial_cover[5], "kind": &"partition", "height": 1.50, "label": "East Court Screen"},
	]
	var burial_lessons: Array[StringName] = [&"final"]
	var burial_waves: Array[Dictionary] = [
		_make_wave(&"final", &"mixed", [&"pair", &"zigzag", &"loop"], 3, 3.5),
		_make_wave(&"final", &"cluster", [&"final_boss"], 1, 0.0),
	]

	var rooms: Array[Dictionary] = [
		{
			"id": &"gallery",
			"title": "Public Galleries",
			"story": "The upper public halls have gone cold. Exhibit cases tremble as wires and glass lenses knit themselves into patrolling husks.",
			"layout_archetype": &"loop_routes",
			"cover": gallery_cover,
			"cover_pieces": gallery_pieces,
			"player_spawn": Vector3(0.0, 0.55, 8.5),
			"lessons": gallery_lessons,
			"waves": gallery_waves,
			"is_boss_room": false,
			"floor_palette": {
				"base": Color(0.20, 0.22, 0.24),
				"accent": Color(0.23, 0.25, 0.27),
				"border": Color(0.17, 0.19, 0.21),
				"style": &"aisle",
			},
			"lighting": {
				"light_color": Color(1.0, 0.96, 0.90),
				"light_energy": 1.05,
				"ambient_color": Color(0.86, 0.90, 0.96),
				"ambient_energy": 0.66,
				"wall_tint": Color(1.18, 1.12, 1.05),
			},
			"entrance_door": {"position": Vector3(0.0, 0.0, 12.2), "width": 6.4},
			"exit_door": {"position": Vector3(0.0, 0.0, -11.8), "width": 6.4},
		},
		{
			"id": &"collections",
			"title": "Connected Collections",
			"story": "Deeper in the archive wings, armored wardens and twin-valve mechanisms guard the sealed collection vaults.",
			"layout_archetype": &"connected_collections",
			"cover": collections_cover,
			"cover_pieces": collections_pieces,
			"player_spawn": Vector3(0.0, 0.55, 8.5),
			"lessons": collections_lessons,
			"waves": collections_waves,
			"is_boss_room": false,
			"floor_palette": {
				"base": Color(0.23, 0.21, 0.19),
				"accent": Color(0.26, 0.23, 0.20),
				"border": Color(0.18, 0.16, 0.15),
				"style": &"cross_hall",
			},
			"lighting": {
				"light_color": Color(1.0, 0.92, 0.82),
				"light_energy": 1.08,
				"ambient_color": Color(0.95, 0.88, 0.80),
				"ambient_energy": 0.64,
				"wall_tint": Color(1.24, 1.10, 0.96),
			},
			"entrance_door": {"position": Vector3(0.0, 0.0, 12.2), "width": 6.4},
			"exit_door": {"position": Vector3(0.0, 0.0, -11.8), "width": 6.4},
		},
		{
			"id": &"restoration",
			"title": "Restoration Rooms",
			"story": "In the basement restoration labs, half-wired spines and iron lungs are being stitched together on worktables.",
			"layout_archetype": &"staggered_galleries",
			"cover": restoration_cover,
			"cover_pieces": restoration_pieces,
			"player_spawn": Vector3(-6.5, 0.55, 8.5),
			"lessons": restoration_lessons,
			"waves": restoration_waves,
			"is_boss_room": false,
			"floor_palette": {
				"base": Color(0.18, 0.22, 0.21),
				"accent": Color(0.21, 0.25, 0.24),
				"border": Color(0.15, 0.18, 0.17),
				"style": &"work_bays",
			},
			"lighting": {
				"light_color": Color(0.88, 0.97, 1.0),
				"light_energy": 1.10,
				"ambient_color": Color(0.80, 0.92, 0.94),
				"ambient_energy": 0.65,
				"wall_tint": Color(1.06, 1.14, 1.12),
			},
			"entrance_door": {"position": Vector3(-6.5, 0.0, 12.2), "width": 6.0},
			"exit_door": {"position": Vector3(6.0, 0.0, -11.8), "width": 6.0},
		},
		{
			"id": &"burial",
			"title": "Burial Exhibition",
			"story": "At the heart of the subterranean rotunda, the restored burial device pulses—drawing every mechanism into a single vessel.",
			"layout_archetype": &"boss_court",
			"cover": burial_cover,
			"cover_pieces": burial_pieces,
			"player_spawn": Vector3(0.0, 0.55, 8.5),
			"lessons": burial_lessons,
			"waves": burial_waves,
			"is_boss_room": true,
			"floor_palette": {
				"base": Color(0.17, 0.18, 0.21),
				"accent": Color(0.21, 0.19, 0.18),
				"border": Color(0.14, 0.15, 0.18),
				"style": &"boss_court",
			},
			"lighting": {
				"light_color": Color(1.0, 0.89, 0.78),
				"light_energy": 1.12,
				"ambient_color": Color(0.82, 0.84, 0.94),
				"ambient_energy": 0.62,
				"wall_tint": Color(1.14, 1.04, 0.98),
			},
			"entrance_door": {"position": Vector3(0.0, 0.0, 12.2), "width": 6.8},
			"exit_door": {"position": Vector3(0.0, 0.0, -11.8), "width": 6.8},
		},
	]
	return rooms
