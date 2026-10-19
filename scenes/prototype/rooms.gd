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


const DifficultySpec = preload("res://scenes/prototype/settings/campaign_difficulty.gd")


static func get_room(room_id: StringName, difficulty: Variant = &"easy") -> Dictionary:
	var defs := definitions(difficulty)
	for room in defs:
		if room.get("id") == room_id:
			return room
	return defs[0]


# count is the finite pressure roster, excluding a harmless practice specimen.
# burst/interval/max_live stage arrivals through director.spawn_formation (flow warnings).
# acquire gates the beat behind a visible physical tool; empty lesson is combat only.
static func _make_wave(lesson: StringName, formation: StringName, enemies: Array[StringName], count: int, recovery: float, options: Dictionary = {}, spec: CampaignDifficulty = null) -> Dictionary:
	var wave := {"lesson": lesson, "formation": formation, "enemies": enemies.duplicate(),
		"count": count, "recovery": recovery, "burst": 3, "interval": 4.4, "refill_delay": 0.75, "max_live": 5}
	wave.merge(options, true)
	if spec != null:
		return _apply_difficulty(wave, spec)
	return wave


static func _apply_difficulty(wave: Dictionary, spec: CampaignDifficulty) -> Dictionary:
	var base_count := int(wave.get("count", 0))
	if base_count <= 0:
		return wave
	var enemies: Array[StringName] = []
	for kind in wave.get("enemies", []):
		enemies.append(StringName(kind))
	if spec.mixed_reinforcements:
		for extra in wave.get("hard_enemies", []):
			var extra_kind := StringName(extra)
			if not enemies.has(extra_kind):
				enemies.append(extra_kind)
	wave["enemies"] = enemies
	if bool(wave.get("boss", false)):
		wave["burst"] = 1
		wave["count"] = 1 + maxi(spec.boss_escort_count, 0)
		wave["max_live"] = clampi(1 + maxi(spec.boss_escort_count, 0), 1, 4)
		wave["interval"] = maxf(2.0, float(wave.get("interval", 6.5)) * spec.interval_scale)
		wave["refill_delay"] = maxf(0.2, float(wave.get("refill_delay", 0.75)) * spec.refill_delay_scale)
		if float(wave.get("recovery", 0.0)) > 0.0:
			wave["recovery"] = maxf(0.25, float(wave.get("recovery", 0.0)) * spec.recovery_scale)
		return wave
	if spec.id == &"hard" or spec.count_scale != 1.0 or spec.count_bonus != 0 or spec.burst_bonus != 0:
		wave["count"] = maxi(1, int(round(float(base_count) * spec.count_scale)) + spec.count_bonus)
		var tier: StringName = wave.get("tier", &"standard")
		var burst_extra := spec.burst_bonus + (1 if tier == &"sustained" and spec.burst_bonus > 0 else 0)
		wave["burst"] = clampi(int(wave.get("burst", 3)) + burst_extra, 1, 8)
		var base_max := int(wave.get("max_live", 5))
		if tier == &"early":
			wave["max_live"] = clampi(maxi(base_max, spec.early_max_live), 1, 32)
		elif tier == &"sustained":
			wave["max_live"] = clampi(maxi(base_max, spec.sustained_max_live + (1 if base_max >= 6 else 0)), 1, 32)
		else:
			wave["max_live"] = clampi(maxi(base_max, spec.early_max_live + 1 + (1 if base_max >= 5 else 0)), 1, 32)
		wave["interval"] = maxf(1.2, float(wave.get("interval", 4.4)) * spec.interval_scale)
		wave["refill_delay"] = maxf(0.15, float(wave.get("refill_delay", 0.75)) * spec.refill_delay_scale)
		wave["recovery"] = maxf(0.25, float(wave.get("recovery", 2.5)) * spec.recovery_scale)
	return wave


const GALLERY_LAYOUT := preload("res://scenes/rooms/gallery_layout.tres")
const COLLECTIONS_LAYOUT := preload("res://scenes/rooms/collections_layout.tres")
const RESTORATION_LAYOUT := preload("res://scenes/rooms/restoration_layout.tres")
const BURIAL_LAYOUT := preload("res://scenes/rooms/burial_layout.tres")


static func definitions(difficulty: Variant = &"easy") -> Array[Dictionary]:
	var spec: CampaignDifficulty = DifficultySpec.load_for(difficulty)
	# Room 1: Public Galleries (1 — LOOP ROUTES from 11.png)
	# Yellow aiming and charge, then orange heat, a deliberate wear-free -> empty full repair lesson, and early time slow.
	var gallery_geom: Dictionary = GALLERY_LAYOUT.to_geometry_dict()
	var gallery_lessons: Array[StringName] = [&"shot", &"charge", &"heat", &"repair", &"slow"]
	var gallery_waves: Array[Dictionary] = [
		_make_wave(&"shot", &"curve", [&"yellow"], 8, 1.4, {"acquire": 2, "burst": 2, "max_live": 4, "interval": 3.6, "tier": &"early"}, spec),
		_make_wave(&"charge", &"line", [&"yellow"], 10, 1.5, {"interval": 3.6, "tier": &"early"}, spec),
		_make_wave(&"heat", &"cluster", [&"orange"], 8, 1.5, {"acquire": 3, "interval": 3.8, "tier": &"early", "hard_enemies": [&"yellow"]}, spec),
		_make_wave(&"repair", &"line", [], 0, 0.35, {}, spec),
		_make_wave(&"slow", &"line", [&"ranged"], 8, 1.6, {"interval": 3.8, "tier": &"early", "hard_enemies": [&"yellow", &"orange"]}, spec),
		_make_wave(&"", &"mixed", [&"yellow", &"orange", &"ranged"], 10, 1.8, {"interval": 3.8, "tier": &"early"}, spec),
	]

	# Room 2: Connected Collections (blue cutter, guard openings, mid-room pressure, emergency rewind, loops, Loop Curator)
	var collections_geom: Dictionary = COLLECTIONS_LAYOUT.to_geometry_dict()
	var collections_lessons: Array[StringName] = [&"cut", &"opening", &"rewind", &"loop"]
	var collections_waves: Array[Dictionary] = [
		_make_wave(&"cut", &"curve", [&"blue"], 8, 1.6, {"acquire": 1, "interval": 3.8, "hard_enemies": [&"yellow", &"orange"]}, spec),
		_make_wave(&"opening", &"mixed", [&"side_guard", &"front_guard"], 8, 1.8, {"interval": 4.0, "hard_enemies": [&"blue", &"yellow"]}, spec),
		_make_wave(&"", &"curve", [&"blue", &"orange", &"side_guard", &"ranged"], 10, 1.8, {"interval": 4.0, "tier": &"sustained", "hard_enemies": [&"front_guard", &"yellow"]}, spec),
		_make_wave(&"rewind", &"line", [&"yellow", &"blue", &"side_guard", &"ranged"], 8, 1.8, {"interval": 4.0, "hard_enemies": [&"orange", &"front_guard"]}, spec),
		_make_wave(&"loop", &"curve", [&"loop"], 5, 2.0, {"burst": 2, "max_live": 4, "interval": 4.2, "hard_enemies": [&"blue", &"yellow"]}, spec),
		_make_wave(&"", &"cluster", [&"loop_boss", &"blue", &"yellow"], 3, 2.2, {"boss": true, "burst": 1, "max_live": 3, "interval": 6.0, "hard_enemies": [&"orange"]}, spec),
	]

	# Room 3: Restoration Rooms (2 — STAGGERED GALLERIES from 11.png)
	# Staggered workbenches introduce paired valves and zigzags before combined pressure and Sequence Warden.
	var restoration_geom: Dictionary = RESTORATION_LAYOUT.to_geometry_dict()
	var restoration_lessons: Array[StringName] = [&"pair", &"zigzag"]
	var restoration_waves: Array[Dictionary] = [
		_make_wave(&"pair", &"line", [&"pair"], 6, 1.8, {"burst": 2, "interval": 4.0, "hard_enemies": [&"yellow", &"front_guard"]}, spec),
		_make_wave(&"zigzag", &"curve", [&"zigzag"], 6, 1.8, {"burst": 2, "interval": 4.0, "hard_enemies": [&"blue", &"orange"]}, spec),
		_make_wave(&"", &"mixed", [&"pair", &"ranged", &"side_guard", &"zigzag"], 12, 2.2, {"interval": 4.2, "max_live": 6, "tier": &"sustained", "hard_enemies": [&"front_guard", &"orange", &"blue"]}, spec),
		_make_wave(&"", &"line", [&"sequence_boss", &"pair", &"zigzag"], 3, 2.4, {"boss": true, "burst": 1, "max_live": 3, "interval": 6.0, "hard_enemies": [&"ranged"]}, spec),
	]

	# Room 4: Burial Exhibition (3 — BOSS COURT from 11.png)
	# Wide-open central court for pattern execution, framed by four outer corner plinths and two perimeter partitions.
	var burial_geom: Dictionary = BURIAL_LAYOUT.to_geometry_dict()
	var burial_lessons: Array[StringName] = []
	var burial_waves: Array[Dictionary] = [
		_make_wave(&"", &"mixed", [&"pair", &"zigzag", &"loop", &"ranged", &"orange", &"front_guard"], 16, 2.5, {"interval": 4.2, "max_live": 6, "tier": &"sustained", "hard_enemies": [&"side_guard", &"blue", &"yellow"]}, spec),
		_make_wave(&"", &"cluster", [&"final_boss", &"side_guard", &"ranged"], 3, 0.0, {"boss": true, "burst": 1, "max_live": 3, "interval": 6.5, "hard_enemies": [&"pair", &"zigzag"]}, spec),
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
