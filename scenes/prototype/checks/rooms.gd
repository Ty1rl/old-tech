extends SceneTree

# Focused check suite for Round O Wave A (JAM-2 — Rooms / Physical Exits):
# - Authored reusable room kit scenes & layout resources under res://scenes/rooms/
# - Open tutorial and combat central floors with edge cover preserving multi-cut spawn clearance
# - Real top/north-wall exit opening at room boundary (closed/hidden until cleared, then opens with subtle green cue)
# - Physical StaticBody3D collision agreement: closed gate blocks player move_and_slide(), open gate allows player to walk through north-wall gap into player_in_exit()
# - Room-complete audio event hooks (room_completed, combat_event &"room_complete") and boss ceremony preservation

const Rooms = preload("res://scenes/prototype/rooms.gd")
const Cover = preload("res://scenes/prototype/cover.gd")
const Flow = preload("res://scenes/prototype/flow.gd")
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
	# 1. Verify authored kit scenes and room layout resources under res://scenes/rooms/
	var kit_paths := [
		"res://scenes/rooms/floor_slab.tscn",
		"res://scenes/rooms/display_island.tscn",
		"res://scenes/rooms/partition.tscn",
		"res://scenes/rooms/column.tscn",
		"res://scenes/rooms/bench.tscn",
		"res://scenes/rooms/plinth.tscn",
		"res://scenes/rooms/north_exit_doorway.tscn",
		"res://scenes/rooms/south_entrance_doorway.tscn",
		"res://scenes/rooms/floor_accents.tscn",
		"res://scenes/rooms/boss_court_ring.tscn",
		"res://scenes/rooms/perimeter_boundary.tscn",
		"res://scenes/rooms/tool_pickup_pedestal.tscn",
		"res://scenes/rooms/room_gallery.tscn",
		"res://scenes/rooms/room_collections.tscn",
		"res://scenes/rooms/room_restoration.tscn",
		"res://scenes/rooms/room_burial.tscn",
	]
	for path in kit_paths:
		var packed := load(path) as PackedScene
		expect(packed != null and packed.can_instantiate(), "Authored room kit scene loads: " + path)

	var layout_paths := [
		"res://scenes/rooms/gallery_layout.tres",
		"res://scenes/rooms/collections_layout.tres",
		"res://scenes/rooms/restoration_layout.tres",
		"res://scenes/rooms/burial_layout.tres",
	]
	for lpath in layout_paths:
		var res := load(lpath)
		expect(res != null and res.has_method("to_geometry_dict"), "Authored RoomLayout resource loads: " + lpath)

	# 2. Verify Cover default rectangles and configurable rectangle list
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
	cover.reset_rectangles()

	# 3. Verify Rooms.definitions() schema, open central floor, north-wall boundary exits, and multi-cut spawn clearance
	var defs := Rooms.definitions()
	expect(defs.size() == 4, "Rooms.definitions() returns 4 rooms")

	var expected_room_ids: Array[StringName] = [&"gallery", &"collections", &"restoration", &"burial"]
	var expected_lessons: Array[StringName] = [
		&"cut", &"heat", &"shot", &"slow", &"repair",
		&"charge", &"opening", &"pair", &"loop", &"zigzag", &"rewind"
	]
	var valid_enemies: Array[StringName] = [
		&"blue", &"yellow", &"orange", &"side_guard", &"front_guard",
		&"pair", &"loop", &"zigzag", &"ranged", &"loop_boss", &"sequence_boss", &"final_boss"
	]
	var valid_formations: Array[StringName] = [&"curve", &"line", &"cluster", &"mixed"]

	var seen_lessons: Dictionary = {}
	var seen_enemies: Dictionary = {}
	var seen_formations: Dictionary = {}
	var central_combat_circle := Rect2(-11.0, -14.0, 22.0, 22.0)

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

		var exit_pos: Vector3 = room.get("exit_door", {}).get("position", Vector3.ZERO)
		expect(exit_pos.z <= -19.0, "%s exit_door is at the north perimeter wall boundary (z <= -19.0), not an interior floor square" % String(rid))

		var spawn_clear := true
		var center_open := true
		for rect in r_cover:
			if rect.grow(1.5).has_point(Vector2(spawn.x, spawn.z)):
				spawn_clear = false
			if rect.intersects(central_combat_circle):
				center_open = false
			expect(
				rect.position.x >= -18.5 and rect.end.x <= 18.5 and rect.position.y >= -18.5 and rect.end.y <= 18.5,
				"%s cover rect %s stays inside [-18.5, 18.5] leaving perimeter lanes" % [String(rid), str(rect)]
			)
		expect(spawn_clear, "%s player_spawn has >= 1.5m clearance from all cover rectangles" % String(rid))
		expect(center_open, "%s moves decorative cases/props toward edges leaving central combat floor open" % String(rid))

		# Verify multi-cut pattern enemy and boss spawn clearance in this room's cover layout
		var room_cover := Cover.new()
		room_cover.set_rectangles(r_cover)
		var flow := Flow.new()
		for multi_kind: StringName in [&"loop", &"zigzag", &"loop_boss", &"sequence_boss", &"final_boss"]:
			var slots: Array = flow.layout(&"curve", [multi_kind], spawn, room_cover, 11 + i, [])
			expect(
				slots.size() == 1 and Flow.safe(slots[0].position, slots[0].radius, spawn, room_cover),
				"%s preserves multi-cut spawn clearance for %s" % [String(rid), String(multi_kind)]
			)

		var r_lessons: Array[StringName] = room.get("lessons", [])
		expect(not r_lessons.is_empty() or bool(room.get("is_boss_room", false)), "%s defines teaching or a final examination" % String(rid))
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

			expect((w_lesson == &"" or expected_lessons.has(w_lesson)), "%s wave %d has valid lesson ID" % [String(rid), w_idx])
			expect(valid_formations.has(w_form), "%s wave %d has valid formation ID" % [String(rid), w_idx])
			expect((not w_enemies.is_empty() and w_count >= 1) or (w_lesson == &"repair" and w_count == 0), "%s wave %d has positive count and enemies" % [String(rid), w_idx])
			expect(w_rec >= 0.0, "%s wave %d has non-negative recovery" % [String(rid), w_idx])
			if not w_lesson.is_empty():
				seen_lessons[w_lesson] = true
			seen_formations[w_form] = true
			for e_kind in w_enemies:
				expect(valid_enemies.has(e_kind), "%s wave %d enemy %s is valid" % [String(rid), w_idx, String(e_kind)])
				seen_enemies[e_kind] = true

	expect(seen_lessons.size() == expected_lessons.size(), "All required Lesson IDs are covered across the 4 rooms")
	expect(seen_enemies.size() == valid_enemies.size(), "All campaign Enemy IDs are scheduled across the 4 rooms")
	expect(seen_formations.size() == valid_formations.size(), "All 4 Formation IDs are used across the 4 rooms")

	# 4. Verify RoomEnvironment apply_room, visual/collider/clipping agreement, north-wall physical opening & traversal, audio hooks, and boss ceremony
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

		# Verify NorthWall perimeter panels at exit_door.position.x are opened (hidden) to form a real wall gap
		var exit_x: float = def["exit_door"]["position"].x
		var gap_opened := false
		for wall_child in room_env.walls_root.get_children():
			if wall_child is Node3D and wall_child.name.begins_with("NorthWall_") and absf(wall_child.position.x - exit_x) < 2.5:
				if not wall_child.visible:
					gap_opened = true
		expect(gap_opened, "Room %s opens a real gap in the NorthWall perimeter at x=%.1f" % [String(def["id"]), exit_x])

	# 5. Test physical exit collision agreement & room-complete audio event hooks in Gallery
	var gallery_def: Dictionary = preview.apply_room_by_id(&"gallery")
	await physics_frame
	await physics_frame

	var completed_rooms: Array[StringName] = []
	var audio_events: Array[StringName] = []
	room_env.room_completed.connect(func(rid: StringName) -> void: completed_rooms.append(rid))
	room_env.combat_event.connect(func(kind: StringName, _pt: Vector3, _str: float) -> void: audio_events.append(kind))

	expect(
		not room_env.exit_open
		and room_env._north_gate_left.visible
		and room_env._north_gate_right.visible
		and not room_env._exit_cue_root.visible
		and room_env.is_exit_physically_blocked(),
		"Gallery starts with North-wall exit gate closed, green cue hidden, and GateBlockerBody active"
	)

	# Attempt to walk player north through the CLOSED north-wall gate
	var player := preview.arena.player as CharacterBody3D
	var door_pos: Vector3 = gallery_def["exit_door"]["position"]
	player.position = Vector3(door_pos.x, 0.55, -16.8)
	player.velocity = Vector3.ZERO
	await physics_frame
	for step_i in range(45):
		player.velocity = Vector3(0.0, 0.0, -6.0)
		player.move_and_slide()
	expect(
		player.position.z > -18.55 and not room_env.player_in_exit(player.position),
		"Closed north-wall exit physically blocks player move_and_slide() before reaching exit threshold (stopped at z=%.2f)" % player.position.z
	)

	# Open the exit and verify audio hook + visual cue + physical traversal through the north-wall gap
	room_env.set_exit_open(true)
	await physics_frame
	expect(
		room_env.exit_open
		and not room_env._north_gate_left.visible
		and not room_env._north_gate_right.visible
		and room_env._exit_cue_root.visible
		and not room_env.is_exit_physically_blocked(),
		"set_exit_open(true) opens North-wall gate leaves, reveals subtle green cue, and disables GateBlockerBody"
	)
	expect(
		completed_rooms == [&"gallery"] and audio_events == [&"room_complete"],
		"set_exit_open(true) emits room_completed and combat_event(&'room_complete') audio hook"
	)

	for step_i in range(45):
		player.velocity = Vector3(0.0, 0.0, -6.0)
		player.move_and_slide()
	expect(
		player.position.z <= -19.2 and room_env.player_in_exit(player.position),
		"Open north-wall exit allows player to physically walk through the north wall gap into player_in_exit() (reached z=%.2f)" % player.position.z
	)

	# Verify solid north wall outside the doorway gap still blocks player
	player.position = Vector3(-9.0, 0.55, -16.8)
	player.velocity = Vector3.ZERO
	await physics_frame
	for step_i in range(45):
		player.velocity = Vector3(0.0, 0.0, -6.0)
		player.move_and_slide()
	expect(
		player.position.z > -18.55 and not room_env.player_in_exit(player.position),
		"North perimeter wall outside the doorway gap remains solid and blocks player (stopped at z=%.2f)" % player.position.z
	)

	# 6. Test Boss Entrance Ceremony in Burial Exhibition (closes gates -> short pause -> activation)
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
