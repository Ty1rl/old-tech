extends SceneTree

# Focused check suite for Round K (JAM-4):
# - rooms.gd progression definitions, room IDs, lesson IDs, enemy IDs, formation IDs, teaching order
# - cover.gd configurable rectangles + segment clipping agreement
# - room_environment.gd apply_room(), rendered cover vs physics colliders vs Cover clipping
# - visible exit open/locked cues and boss entrance gate-close -> pause -> activation ceremony

const Rooms = preload("res://scenes/prototype/rooms.gd")
const Cover = preload("res://scenes/prototype/cover.gd")
const RoomEnvironment = preload("res://scenes/prototype/room_environment.gd")

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _rects_equal(a: Array[Rect2], b: Array[Rect2], eps: float = 0.05) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if (
			absf(a[i].position.x - b[i].position.x) > eps
			or absf(a[i].position.y - b[i].position.y) > eps
			or absf(a[i].size.x - b[i].size.x) > eps
			or absf(a[i].size.y - b[i].size.y) > eps
		):
			return false
	return true


func run() -> void:
	# 1. Verify Cover default rectangles and configurable rectangle list
	var cover := Cover.new()
	expect(
		_rects_equal(cover.rectangles, Cover.RECTANGLES),
		"Cover defaults to existing Cover.RECTANGLES"
	)
	var default_blocked := cover.clip_segment(Vector3(-8.0, 0.5, -4.5), Vector3(-2.0, 0.5, -4.5))
	expect(default_blocked.blocked, "Default Cover clips segment through Rect2(-6, -6, 2, 3)")

	var custom_rects: Array[Rect2] = [Rect2(-2.0, -2.0, 4.0, 4.0)]
	cover.set_rectangles(custom_rects)
	expect(
		_rects_equal(cover.get_rectangles(), custom_rects),
		"Cover.set_rectangles updates active rectangle list"
	)
	expect(
		not cover.clip_segment(Vector3(-8.0, 0.5, -4.5), Vector3(-2.5, 0.5, -4.5)).blocked,
		"Old default cover rectangle no longer blocks after set_rectangles"
	)
	expect(
		cover.clip_segment(Vector3(-5.0, 0.5, 0.0), Vector3(5.0, 0.5, 0.0)).blocked,
		"New custom cover rectangle blocks segment through origin"
	)
	cover.reset_rectangles()
	expect(
		_rects_equal(cover.rectangles, Cover.RECTANGLES),
		"Cover.reset_rectangles restores default RECTANGLES"
	)

	# 2. Verify Rooms.definitions() schema, IDs, lessons, formations, and safe teaching sequence
	var defs := Rooms.definitions()
	expect(defs.size() == 4, "Rooms.definitions() returns 4 rooms")

	var expected_room_ids: Array[StringName] = [&"gallery", &"collections", &"restoration", &"burial"]
	var expected_lessons: Array[StringName] = [
		&"move", &"cut", &"heat", &"shot", &"slow", &"repair",
		&"charge", &"opening", &"pair", &"loop", &"zigzag", &"rewind", &"final"
	]
	var valid_enemies: Array[StringName] = [
		&"blue", &"yellow", &"orange", &"side_guard", &"front_guard",
		&"pair", &"loop", &"zigzag", &"final_boss"
	]
	var valid_formations: Array[StringName] = [&"curve", &"line", &"cluster", &"mixed"]

	var seen_lessons: Dictionary = {}
	var seen_enemies: Dictionary = {}
	var seen_formations: Dictionary = {}

	for i in range(defs.size()):
		var room: Dictionary = defs[i]
		var rid: StringName = room.get("id", &"")
		expect(rid == expected_room_ids[i], "Room %d has id %s" % [i + 1, String(expected_room_ids[i])])
		expect(not String(room.get("title", "")).is_empty(), "%s has non-empty title" % String(rid))
		expect(not String(room.get("story", "")).is_empty(), "%s has non-empty story" % String(rid))

		var r_cover: Array[Rect2] = room.get("cover", [])
		expect(r_cover.size() >= 4, "%s defines at least 4 reusable cover rectangles" % String(rid))

		var spawn: Vector3 = room.get("player_spawn", Vector3.ZERO)
		expect(absf(spawn.x) < 16.0 and absf(spawn.z) < 16.0, "%s player_spawn is inside arena bounds" % String(rid))

		var spawn_clear := true
		for rect in r_cover:
			if rect.grow(1.5).has_point(Vector2(spawn.x, spawn.z)):
				spawn_clear = false
			expect(
				rect.position.x >= -18.5 and rect.end.x <= 18.5 and rect.position.y >= -18.5 and rect.end.y <= 18.5,
				"%s cover rect %s stays inside [-18.5, 18.5] leaving perimeter lanes" % [String(rid), str(rect)]
			)
		expect(spawn_clear, "%s player_spawn has >= 1.5m clearance from all cover rectangles" % String(rid))

		var r_lessons: Array[StringName] = room.get("lessons", [])
		expect(not r_lessons.is_empty(), "%s defines lessons list" % String(rid))
		for l_id in r_lessons:
			expect(expected_lessons.has(l_id), "%s lesson %s is in required lesson ID set" % [String(rid), String(l_id)])
			seen_lessons[l_id] = true

		var r_waves: Array[Dictionary] = room.get("waves", [])
		expect(r_waves.size() >= 2, "%s defines at least 2 waves" % String(rid))
		for w_idx in range(r_waves.size()):
			var w: Dictionary = r_waves[w_idx]
			var w_lesson: StringName = w.get("lesson", &"")
			var w_form: StringName = w.get("formation", &"")
			var w_enemies: Array[StringName] = w.get("enemies", [])
			var w_count: int = int(w.get("count", 0))
			var w_rec: float = float(w.get("recovery", -1.0))

			expect(expected_lessons.has(w_lesson), "%s wave %d has valid lesson ID" % [String(rid), w_idx])
			expect(valid_formations.has(w_form), "%s wave %d has valid formation ID" % [String(rid), w_idx])
			expect(not w_enemies.is_empty() and w_count >= 1, "%s wave %d has positive count and enemies" % [String(rid), w_idx])
			expect(w_rec >= 0.0, "%s wave %d has non-negative recovery" % [String(rid), w_idx])
			seen_lessons[w_lesson] = true
			seen_formations[w_form] = true
			for e_kind in w_enemies:
				expect(valid_enemies.has(e_kind), "%s wave %d enemy %s is valid" % [String(rid), w_idx, String(e_kind)])
				seen_enemies[e_kind] = true

	expect(seen_lessons.size() == expected_lessons.size(), "All 13 required Lesson IDs are covered across the 4 rooms")
	expect(seen_enemies.size() == valid_enemies.size(), "All 9 Enemy IDs are scheduled across the 4 rooms")
	expect(seen_formations.size() == valid_formations.size(), "All 4 Formation IDs are used across the 4 rooms")

	# Verify specific progression rules from PLAYTEST-BRIEF.txt:
	# - Room 1 (gallery): simple blue/orange/yellow only
	var r1_enemies: Dictionary = {}
	for w in defs[0]["waves"]:
		for e in w["enemies"]:
			r1_enemies[e] = true
	expect(
		r1_enemies.has(&"blue") and r1_enemies.has(&"yellow") and r1_enemies.has(&"orange") and r1_enemies.size() == 3,
		"Room 1 (gallery) uses only simple blue, yellow, and orange enemies"
	)

	# - Room 2 (collections): opening combos + A/B pair introduced solo before mixed wave
	var r2_waves: Array[Dictionary] = defs[1]["waves"]
	var pair_intro_solo := false
	for w in r2_waves:
		if w["lesson"] == &"pair" and w["enemies"] == [&"pair"] and int(w["count"]) == 1:
			pair_intro_solo = true
	expect(pair_intro_solo, "Room 2 (collections) introduces A/B pair solo (count=1) before crowding")

	# - Room 3 (restoration): loop then zigzag introduced separately before crowding
	var r3_waves: Array[Dictionary] = defs[2]["waves"]
	expect(
		r3_waves[0]["lesson"] == &"loop" and r3_waves[0]["enemies"] == [&"loop"] and int(r3_waves[0]["count"]) == 1,
		"Room 3 (restoration) Wave 1 introduces loop solo"
	)
	expect(
		r3_waves[1]["lesson"] == &"zigzag" and r3_waves[1]["enemies"] == [&"zigzag"] and int(r3_waves[1]["count"]) == 1,
		"Room 3 (restoration) Wave 2 introduces zigzag solo separately from loop"
	)

	# - Room 4 (burial): familiar pressure wave then ONE final_boss wave
	var r4_waves: Array[Dictionary] = defs[3]["waves"]
	expect(
		not r4_waves[0]["enemies"].has(&"final_boss") and r4_waves.back()["enemies"] == [&"final_boss"] and int(r4_waves.back()["count"]) == 1,
		"Room 4 (burial) leads with familiar pattern pressure then spawns ONE final_boss"
	)

	# 3. Verify RoomEnvironment apply_room, visual/collider/clipping agreement, exit cues, and boss entrance ceremony
	var preview_scene := load("res://scenes/room_preview/room_preview.tscn") as PackedScene
	var preview := preview_scene.instantiate()
	root.add_child(preview)
	current_scene = preview
	await physics_frame
	await physics_frame
	root.get_node("GameState").resume()
	preview.arena.set_physics_process(false)

	var room_env: Node3D = preview.room_env
	for i in range(defs.size()):
		var def: Dictionary = preview.apply_room_by_index(i)
		var expected_rects: Array[Rect2] = def["cover"]
		var rendered_rects: Array[Rect2] = room_env.get_cover_world_rectangles()
		var collider_rects: Array[Rect2] = room_env.get_collider_world_rectangles(preview.arena)
		var clipping_rects: Array[Rect2] = preview.arena.cover.get_rectangles()

		expect(
			_rects_equal(expected_rects, rendered_rects),
			"Room %s rendered cover footprints match definition['cover']" % String(def["id"])
		)
		expect(
			_rects_equal(expected_rects, collider_rects),
			"Room %s physics collider footprints match definition['cover']" % String(def["id"])
		)
		expect(
			_rects_equal(expected_rects, clipping_rects),
			"Room %s Cover clipping footprints match definition['cover']" % String(def["id"])
		)

		# Verify every cover rectangle actually blocks a ray through its center in arena.cover
		var all_rays_blocked := true
		for r in expected_rects:
			var c := r.get_center()
			var start := Vector3(c.x - r.size.x, 0.5, c.y)
			var finish := Vector3(c.x + r.size.x, 0.5, c.y)
			if not preview.arena.cover.clip_segment(start, finish).blocked:
				all_rays_blocked = false
		expect(all_rays_blocked, "Room %s Cover.clip_segment blocks rays across every cover piece" % String(def["id"]))

	# Test exit cue toggling in non-boss rooms
	preview.apply_room_by_id(&"gallery")
	expect(not room_env.exit_open and room_env._north_gate_left.visible, "Gallery starts with North exit gate closed")
	room_env.set_exit_open(true)
	expect(room_env.exit_open and not room_env._north_gate_left.visible, "set_exit_open(true) opens North exit gate and activates exit beacon")

	# Test Boss Entrance Ceremony in Burial Exhibition (closes gates -> short pause -> activation)
	preview.apply_room_by_id(&"burial")
	expect(room_env.boss_ceremony_state == &"closing_gates", "Burial room starts in closing_gates ceremony state")
	expect(not room_env.is_boss_active(), "Boss is not active while gates are closing")

	var gates_signal_count := [0]
	var active_signal_count := [0]
	room_env.gates_closed.connect(func(_id: StringName) -> void: gates_signal_count[0] += 1)
	room_env.boss_activated.connect(func(_id: StringName) -> void: active_signal_count[0] += 1)

	var status_mid_close: Dictionary = room_env.step_ceremony(0.30)
	expect(
		status_mid_close["state"] == &"closing_gates" and float(status_mid_close["gates_closed_ratio"]) > 0.4,
		"Stepping boss ceremony 0.30s advances gate closure"
	)

	var status_paused: Dictionary = room_env.step_ceremony(0.35)
	expect(
		status_paused["state"] == &"pause" and bool(status_paused["gates_closed"]) and gates_signal_count[0] == 1,
		"Completing gate closure transitions to short pause and emits gates_closed"
	)
	expect(
		room_env._north_gate_left.visible and room_env._south_gate_left.visible,
		"Both North and South doorway gates are visibly closed during boss pause"
	)

	var status_active: Dictionary = room_env.step_ceremony(0.55)
	expect(
		status_active["state"] == &"active" and bool(status_active["boss_active"]) and active_signal_count[0] == 1,
		"Completing pause transitions to active boss state and emits boss_activated"
	)

	preview.arena.feedback.reset_state()
	preview.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
