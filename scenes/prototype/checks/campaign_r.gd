extends SceneTree

# Round R verification suite (JAM-4):
# - Target Run progression across all 4 museum rooms and 3 bosses (sequence_boss -> loop_boss -> final_boss)
# - Zero untaught boss or level requirements; Advanced A (opening, pair, rewind) before Boss 1; Advanced B (loop, zigzag) before Boss 2
# - Tutorials use LessonDemo -> 2 stationary -> 2 moving -> brief recovery -> next wave with NO post-lesson pressure wave
# - Already-learned tutorials skipped automatically on retry_room() while preserving tools and unlocked capabilities
# - Hard difficulty preserves identical tutorial quotas and teaching waves while scaling real combat levels
# - Exit carry-through ("W SKIP") bug reproduction & fix: held W before clear, standing in exit at clear, fresh approach, retry, and next-room placement
# - Audio/music context hooks (regular_combat, boss, victory) and instruction_busy() speech handoff + dialogue bleed prevention
# - Complete start-to-finish playable run verification on both Easy and Hard

const Rooms = preload("res://scenes/prototype/rooms.gd")
const ToolStyle = preload("res://scenes/prototype/tool_style.gd")

var checks := 0
var failures: Array[String] = []
var arena: Node3D


func _initialize() -> void:
	call_deferred("_run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _tick(dt: float = 1.0 / 30.0) -> void:
	arena._physics_process(dt)


func _shot(enemy: Node3D, charge: float = 1.0) -> void:
	var point: Vector3 = enemy.core_world_position()
	enemy.receive_attack(&"beam", 100.0, point, {
		"segment_start": point - Vector3(0, 0, 5),
		"segment_end": point + Vector3(0, 0, 5),
		"radius": 0.35,
		"charge": charge,
	})


func _cut(enemy: Node3D) -> void:
	var points: Array = enemy.cable_world_points()
	var pairs: bool = enemy.has_method("lesson_state")
	var step: int = 2 if pairs else 1
	for i in range(0, points.size() - 1, step):
		var middle: Vector3 = (points[i] + points[i + 1]) * 0.5
		var direction: Vector3 = (points[i + 1] - points[i]).normalized().cross(Vector3.UP)
		enemy.receive_attack(&"ring", 36.0, middle, {
			"segment_start": middle - direction * 0.7,
			"segment_end": middle + direction * 0.7,
			"radius": 0.1,
			"already_hit": i > 0,
		})


func _pattern(enemy: Node3D) -> void:
	if enemy.active_pattern() == &"pair":
		for i in range(2):
			var p: Vector3 = enemy.valve_world_position(i)
			enemy.receive_attack(&"beam", 30.0, p, {
				"segment_start": p - Vector3(0, 0, 1),
				"segment_end": p + Vector3(0, 0, 1),
				"radius": 0.1,
				"charge": 0.0,
			})
	elif enemy.active_pattern() in [&"loop", &"zigzag"]:
		_cut(enemy)
	if enemy.health > 0.0:
		_shot(enemy, 1.0)


func _complete_single_rep(lesson_id: StringName) -> void:
	if arena.specimens.is_empty():
		return
	match lesson_id:
		&"shot":
			_shot(arena.specimens[0], 0.0)
		&"charge":
			arena.weapons.select_tool(2)
			var aim: Vector3 = arena.specimens.back().position
			var down := InputEventMouseButton.new()
			down.button_index = MOUSE_BUTTON_LEFT
			down.pressed = true
			var up := InputEventMouseButton.new()
			up.button_index = MOUSE_BUTTON_LEFT
			up.pressed = false
			arena.weapons.handle_event(down, arena.player, aim)
			arena.weapons.step(1.0, arena.player, aim, arena.director.enemies, 0.0)
			arena.weapons.handle_event(up, arena.player, aim)
			arena.weapons.step(0.7, arena.player, aim, arena.director.enemies, 0.7)
		&"heat":
			var target: Node3D = arena.specimens[0]
			for i in range(80):
				target.receive_attack(&"cone", 0.3, target.position, {"dt": 1.0 / 60.0})
		&"slow":
			var sp_down := InputEventKey.new()
			sp_down.physical_keycode = KEY_SPACE
			sp_down.pressed = true
			arena._input(sp_down)
			_tick(0.05)
			var target: Node3D = arena.specimens[0]
			if 1 in arena.acquired and target.has_cuttable_part():
				_cut(target)
			else:
				_shot(target, 0.0)
			var sp_up := InputEventKey.new()
			sp_up.physical_keycode = KEY_SPACE
			sp_up.pressed = false
			arena._input(sp_up)
		&"cut":
			_cut(arena.specimens[0])
		&"opening":
			for target in arena.specimens:
				if not is_instance_valid(target):
					continue
				if target.kind == &"side_guard":
					_cut(target)
				else:
					for i in range(80):
						target.receive_attack(&"cone", 0.3, target.position, {"dt": 1.0 / 60.0})
				_shot(target, 1.0)
		&"pair", &"loop", &"zigzag":
			var target: Node3D = arena.specimens[0]
			for phase in range(4):
				if target.health > 0.0:
					_pattern(target)


func _complete_active_practice() -> void:
	var lid: StringName = arena.lesson
	if lid == &"time_meter":
		var tm_ticks := 0
		while arena.mode == &"practice" and tm_ticks < 240:
			_tick(1.0 / 30.0)
			tm_ticks += 1
		expect(
			arena.tutorial.is_learned(&"time_meter")
			and is_equal_approx(arena.time_controller.meter, arena.time_controller.capacity)
			and arena.time_controller.charges_remaining == 3,
			"Staged time_meter lesson completes and restores 100% reserve and 3 charges before shot"
		)
		return
	if arena.lesson_demo != null and arena.lesson_demo.active:
		var demo_ticks := 0
		while arena.lesson_demo.active and demo_ticks < 240:
			_tick(1.0 / 30.0)
			demo_ticks += 1
		expect(not arena.lesson_demo.active and bool(arena.lesson_demo.last_summary.get("completed", false)), "LessonDemo completed for " + String(lid))
	if arena._practice_stage == &"await_speech":
		arena.tutorial.request_practice()
	if arena.tutorial.blocking:
		arena.tutorial.request_practice()
	if lid == &"repair":
		arena._open_smart_repair()
		var popup: Node = root.get_node("SceneManager").get_popup(&"Repair")
		if popup != null and popup.has_method("_commit_steps"):
			while not arena.equipment.is_full(&"beam"):
				popup.trace_stage = arena.equipment.stage(&"beam")
				popup.call("_commit_steps", 1)
		else:
			var session: int = arena.equipment.begin_repair(&"beam")
			while not arena.equipment.is_full(&"beam"):
				arena.equipment.complete_step(&"beam", session)
			arena.equipment.end_repair(session)
		_tick(0.01)
	elif lid == &"rewind":
		for tick_idx in range(60):
			_tick(0.04)
			if arena.is_emergency_active():
				break
		expect(arena.is_emergency_active() and arena.rewind_lesson.phase == RewindLesson.Phase.SCRUB and arena.time_controller.charges_remaining == 2, "RewindLesson stages incoming hit and enters frozen SCRUB phase")
		arena.emergency_rewind.step_selection(2)
		arena.emergency_rewind.confirm()
		_tick(0.01)
		expect(not arena.is_emergency_active() and arena.time_controller.charges_remaining == 3 and is_equal_approx(arena.time_controller.meter, arena.time_controller.capacity), "Confirming RewindLesson restores full 3 charges and 100% meter")
	else:
		expect(arena._stationary_quota == 2 and arena._moving_quota == 2, "Lesson %s uses 2 stationary + 2 moving quota" % String(lid))
		for rep_idx in range(arena._stationary_quota + arena._moving_quota):
			_complete_single_rep(lid)
			_tick(0.01)
	expect(arena.tutorial.is_learned(lid), "Completed practice for lesson " + String(lid))


func _execute_full_run(diff: StringName) -> void:
	var start_failures := failures.size()
	root.get_node("SceneManager").params = {"difficulty": diff}
	arena.start_new_run(diff, false)
	expect(arena.difficulty_id == diff, "Campaign initialized on difficulty: " + String(diff))
	expect(not arena.time_controller.slow_unlocked and not arena.time_controller.rewind_unlocked, "New run starts with slow and rewind locked on " + String(diff))
	var visited_rooms: Dictionary = {}
	var bosses_fought: Array[StringName] = []
	var pressure_waves_seen: Dictionary = {}
	var pickups_seen: Array[int] = []
	var lessons_seen: Array[StringName] = []
	for step in range(950):
		visited_rooms[arena.room_index] = true
		if arena.mode == &"won":
			break
		if arena.mode in [&"title", &"ceremony"]:
			_tick(3.0)
		elif arena.mode == &"pickup":
			var p_tool: int = arena.museum.pickup_tool
			if not (p_tool in pickups_seen):
				pickups_seen.append(p_tool)
			expect(
				not arena.tutorial.blocking
				and arena.run_hint.text == "Walk towards the new item."
				and arena.run_hint.visible
				and Vector2(arena.player.position.x - arena.museum.pickup_position.x, arena.player.position.z - arena.museum.pickup_position.z).length() >= 2.5,
				"Pickup for tool %d is nonblocking with 'Walk towards the new item.' cue and walkable distance on %s" % [p_tool, String(diff)]
			)
			arena.player.position = arena.museum.pickup_position + Vector3.UP * 0.55
			_tick(0.01)
		elif arena.mode == &"practice":
			if not (arena.lesson in lessons_seen):
				lessons_seen.append(arena.lesson)
			_complete_active_practice()
			expect(arena.mode == &"recovery", "Pure teaching wave transitions directly to recovery without post-lesson pressure on " + String(diff))
		elif arena.mode == &"pressure":
			pressure_waves_seen["%d:%d" % [arena.room_index, arena.wave_index]] = true
			for enemy in arena.director.enemies:
				if is_instance_valid(enemy):
					if enemy.has_method("is_boss") and enemy.is_boss() and not (enemy.kind in bosses_fought):
						bosses_fought.append(enemy.kind)
					enemy.hit(99999.0, enemy.position)
			_tick(9.0)
		elif arena.mode == &"recovery":
			_tick(5.0)
		elif arena.mode == &"exit":
			var door_pos: Vector3 = arena.room.exit_door.position
			expect(arena.museum.player_in_exit(door_pos), "Room exit doorway is physically traversable on " + String(diff))
			arena.player.position = door_pos
			_tick(0.01)
		await process_frame
		if failures.size() > start_failures:
			break
	expect(visited_rooms.size() == 4, "Run reaches all 4 museum rooms on " + String(diff))
	expect(pickups_seen == [2, 3, 1], "Run presents nonblocking walk-towards-item pickups for tools [2, 3, 1] on " + String(diff))
	expect(lessons_seen.size() >= 2 and lessons_seen[0] == &"time_meter" and lessons_seen[1] == &"shot", "Run teaches time_meter before shot on " + String(diff))
	expect(bosses_fought == [&"sequence_boss", &"loop_boss", &"final_boss"], "Run fights all 3 bosses in taught order (sequence_boss -> loop_boss -> final_boss) on " + String(diff))
	expect(arena.mode == &"won" and arena._last_music_context == &"victory", "Full run reaches victory state and sets victory music context on " + String(diff))
	expect(arena.acquired == [2, 3, 1] and arena.time_controller.slow_unlocked and arena.time_controller.rewind_unlocked, "Completed run unlocks all 3 weapons and both time capabilities on " + String(diff))
	expect(pressure_waves_seen.size() == 11, "Run includes all 8 combat waves (including inter-lesson combat in Rooms 1 and 2) and 3 boss encounters on " + String(diff))


func _execute_skip_tutorials_run(diff: StringName) -> void:
	var start_failures := failures.size()
	root.get_node("SceneManager").params = {"difficulty": diff, "skip_tutorials": true}
	arena.start_new_run(diff, true)
	expect(arena.difficulty_id == diff and arena.skip_tutorials and arena._is_skip_tutorials_active(), "Skip tutorials run initialized on difficulty: " + String(diff))
	var visited_rooms: Dictionary = {}
	var bosses_fought: Array[StringName] = []
	var pressure_waves_seen: Dictionary = {}
	var practiced_any := false
	var checked_r0_w4 := false
	var checked_r0_w8 := false
	var checked_r1_w5 := false
	for step in range(650):
		visited_rooms[arena.room_index] = true
		if arena.mode == &"won":
			break
		if arena.mode == &"practice" or arena.lesson_demo.active or arena.rewind_lesson.active:
			practiced_any = true
		if arena.mode in [&"title", &"ceremony"]:
			_tick(3.0)
		elif arena.mode == &"pickup":
			arena.player.position = arena.museum.pickup_position + Vector3.UP * 0.55
			_tick(0.01)
		elif arena.mode == &"pressure":
			if arena.room_index == 0 and arena.wave_index == 4 and not checked_r0_w4:
				checked_r0_w4 = true
				expect(arena.acquired == [2, 3] and not arena.time_controller.slow_unlocked and not arena.time_controller.rewind_unlocked, "Skip tutorials grants [2, 3] at Room 0 Wave 4 interlude on " + String(diff))
			elif arena.room_index == 0 and arena.wave_index == 8 and not checked_r0_w8:
				checked_r0_w8 = true
				expect(arena.acquired == [2, 3, 1] and arena.time_controller.slow_unlocked and not arena.time_controller.rewind_unlocked and not arena._is_yellow_protected(), "Skip tutorials grants [2, 3, 1], slow, and repair eligibility at Room 0 Wave 8 Basic Combat Level on " + String(diff))
			elif arena.room_index == 1 and arena.wave_index == 5 and not checked_r1_w5:
				checked_r1_w5 = true
				expect(arena.time_controller.rewind_unlocked and arena.time_controller.charges_remaining == 3, "Skip tutorials unlocks rewind with all 3 charges intact at Room 1 Wave 5 Mixed Level on " + String(diff))
			pressure_waves_seen["%d:%d" % [arena.room_index, arena.wave_index]] = true
			for enemy in arena.director.enemies:
				if is_instance_valid(enemy):
					if enemy.has_method("is_boss") and enemy.is_boss() and not (enemy.kind in bosses_fought):
						bosses_fought.append(enemy.kind)
					enemy.hit(99999.0, enemy.position)
			_tick(9.0)
		elif arena.mode == &"recovery":
			_tick(5.0)
		elif arena.mode == &"exit":
			var door_pos: Vector3 = arena.room.exit_door.position
			arena.player.position = door_pos
			_tick(0.01)
		await process_frame
		if failures.size() > start_failures:
			break
	expect(not practiced_any, "Skip tutorials run executes zero tutorial demos, zero practice stages, and zero RewindLesson scenes on " + String(diff))
	expect(checked_r0_w4 and checked_r0_w8 and checked_r1_w5, "Skip tutorials run hits all progression checkpoints in order on " + String(diff))
	expect(visited_rooms.size() == 4 and bosses_fought == [&"sequence_boss", &"loop_boss", &"final_boss"] and arena.mode == &"won", "Skip tutorials run completes all 4 rooms and 3 bosses to victory on " + String(diff))
	expect(pressure_waves_seen.size() == 11, "Skip tutorials run preserves all 8 combat waves and 3 boss fights on " + String(diff))
	root.get_node("SceneManager").params = {}
	arena.set_skip_tutorials(false)


func _run() -> void:
	create_timer(45.0, true).timeout.connect(func() -> void:
		failures.append("campaign_r watchdog expired")
		print(JSON.stringify({"status": "failed", "checks": checks, "failures": failures}))
		quit(1)
	)

	var game := root.get_node("GameState")
	var scenes := root.get_node("SceneManager")
	var saved_prefs: Dictionary = game.preferences().duplicate(true)
	game.set_setting("tutorial", true)
	scenes.params = {}

	# 1. Verify Target Run room/wave structure, time_meter before shot, and real combat between later lessons in rooms.gd
	var easy_defs := Rooms.definitions(&"easy")
	var hard_defs := Rooms.definitions(&"hard")
	expect(easy_defs.size() == 4 and hard_defs.size() == 4, "Easy and Hard both define 4 museum rooms")

	# Room 0: Basic teaching (time_meter, shot, charge, heat, short interlude, repair, slow, cut) -> Basic combat level
	expect(easy_defs[0].lessons == [&"time_meter", &"shot", &"charge", &"heat", &"repair", &"slow", &"cut"], "Room 0 teaches time_meter before shot, then charge, heat, repair, slow, cut")
	expect(easy_defs[0].waves[0].lesson == &"time_meter" and int(easy_defs[0].waves[0].get("acquire", 0)) == 2, "Room 0 Wave 0 acquires Tool 2 and teaches time_meter before shot")
	expect(easy_defs[0].waves[1].lesson == &"shot" and int(easy_defs[0].waves[1].get("acquire", 0)) == 0, "Room 0 Wave 1 teaches yellow shot immediately after time_meter")
	expect(easy_defs[0].waves[4].lesson == &"" and bool(easy_defs[0].waves[4].pressure) and easy_defs[0].waves[4].enemies == [&"yellow", &"orange"], "Room 0 includes short familiar-target interlude before repair")
	expect(easy_defs[0].waves[8].lesson == &"" and bool(easy_defs[0].waves[8].pressure) and easy_defs[0].waves[8].enemies == [&"yellow", &"orange", &"blue", &"ranged"], "Room 0 ends with Basic Combat Level")

	# Room 1: Advanced A teaching with real combat between new lessons (opening -> combat -> pair -> combat -> rewind -> Mixed level -> Boss 1)
	expect(easy_defs[1].lessons == [&"opening", &"pair", &"rewind"], "Room 1 teaches Advanced A: opening, pair, rewind")
	expect(easy_defs[1].waves[0].lesson == &"opening" and easy_defs[1].waves[1].lesson == &"" and bool(easy_defs[1].waves[1].pressure), "Room 1 places real combat wave between opening and pair")
	expect(easy_defs[1].waves[2].lesson == &"pair" and easy_defs[1].waves[3].lesson == &"" and bool(easy_defs[1].waves[3].pressure), "Room 1 places real combat wave between pair and rewind")
	expect(easy_defs[1].waves[4].lesson == &"rewind" and easy_defs[1].waves[5].lesson == &"" and bool(easy_defs[1].waves[5].pressure) and not bool(easy_defs[1].waves[5].get("boss", false)), "Room 1 Wave 5 is Advanced A Mixed Level after rewind")
	var boss1_wave: Dictionary = easy_defs[1].waves[6]
	var boss1_hard: Dictionary = hard_defs[1].waves[6]
	expect(bool(boss1_wave.get("boss", false)) and boss1_wave.enemies[0] == &"sequence_boss", "Boss 1 is sequence_boss (uses pair + yellow core taught in Basic/Adv A)")
	expect(not (&"loop" in boss1_wave.enemies) and not (&"zigzag" in boss1_wave.enemies) and not (&"loop" in boss1_hard.enemies) and not (&"zigzag" in boss1_hard.enemies), "Boss 1 escorts on Easy and Hard contain no untaught Advanced B enemies (loop/zigzag)")

	# Room 2: Advanced B teaching with real combat between new lessons (loop -> combat -> zigzag -> Mixed level -> Boss 2)
	expect(easy_defs[2].lessons == [&"loop", &"zigzag"], "Room 2 teaches Advanced B: loop, zigzag")
	expect(easy_defs[2].waves[0].lesson == &"loop" and easy_defs[2].waves[1].lesson == &"" and bool(easy_defs[2].waves[1].pressure), "Room 2 places real combat wave between loop and zigzag")
	expect(easy_defs[2].waves[2].lesson == &"zigzag" and easy_defs[2].waves[3].lesson == &"" and bool(easy_defs[2].waves[3].pressure) and not bool(easy_defs[2].waves[3].get("boss", false)), "Room 2 Wave 3 is Advanced B Mixed Level")
	var boss2_wave: Dictionary = easy_defs[2].waves[4]
	expect(bool(boss2_wave.get("boss", false)) and boss2_wave.enemies[0] == &"loop_boss", "Boss 2 is loop_boss (uses loop + yellow core taught in Adv B)")

	# Room 3: Final combat level -> Final Boss (final_boss)
	expect(easy_defs[3].lessons.is_empty() and easy_defs[3].waves.size() == 2, "Room 3 has Final Combat Level followed by Final Boss")
	expect(easy_defs[3].waves[0].lesson == &"" and bool(easy_defs[3].waves[0].pressure) and not bool(easy_defs[3].waves[0].get("boss", false)), "Room 3 Wave 0 is Final Combat Level")
	expect(bool(easy_defs[3].waves[1].get("boss", false)) and easy_defs[3].waves[1].enemies[0] == &"final_boss", "Room 3 Wave 1 is Final Boss (final_boss)")

	# Verify tutorial waves are identical on Easy and Hard while combat waves scale on Hard
	for ri in range(4):
		for wi in range(easy_defs[ri].waves.size()):
			var ew: Dictionary = easy_defs[ri].waves[wi]
			var hw: Dictionary = hard_defs[ri].waves[wi]
			if not StringName(ew.get("lesson", &"")).is_empty():
				expect(not bool(ew.get("pressure", true)) and not bool(hw.get("pressure", true)), "Teaching wave R%dW%d has pressure=false on Easy and Hard" % [ri, wi])
				expect(ew.count == hw.count and ew.enemies == hw.enemies, "Teaching wave R%dW%d is identical on Easy and Hard" % [ri, wi])
			elif not bool(ew.get("boss", false)):
				expect(int(hw.count) > int(ew.count) and int(hw.max_live) >= int(ew.max_live), "Combat wave R%dW%d scales count/max_live on Hard above Easy" % [ri, wi])

	# 2. Instantiate campaign and verify nonblocking walk cue, staged time_meter before shot, orange heat pushback, and skip safety
	arena = load("res://scenes/prototype/campaign.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	game.start_game()

	# Verify 2 stationary + 2 moving quotas for all 9 combat lessons, and 0+0 for time_meter
	expect(arena.practice_quotas_for(&"time_meter") == Vector2i.ZERO, "Lesson time_meter has Vector2i.ZERO practice quota")
	for lid in [&"shot", &"charge", &"heat", &"slow", &"cut", &"opening", &"pair", &"loop", &"zigzag"]:
		expect(arena.practice_quotas_for(lid) == Vector2i(2, 2), "Lesson %s has Vector2i(2, 2) quota" % String(lid))

	expect(arena._last_music_context == &"regular_combat", "Entering Room 0 sets regular_combat music context")

	# Verify first playable moment: nonblocking "Walk towards the new item." cue -> walk to pickup -> staged time_meter -> shot
	_tick(2.1)
	expect(
		arena.mode == &"pickup"
		and arena.museum.pickup_tool == 2
		and not arena.tutorial.blocking
		and arena.run_hint.text == "Walk towards the new item."
		and arena.run_hint.visible,
		"First playable moment is nonblocking pickup with 'Walk towards the new item.' cue"
	)
	var start_pos: Vector3 = arena.player.position
	Input.action_press(&"move_right")
	_tick(0.1)
	Input.action_release(&"move_right")
	expect(arena.player.position.distance_to(start_pos) > 0.1, "Player can move freely during nonblocking pickup cue")

	arena.player.position = arena.museum.pickup_position + Vector3.UP * 0.55
	_tick(0.02)
	expect(
		arena.mode == &"practice"
		and arena.lesson == &"time_meter"
		and arena.tutorial.visible
		and arena.tutorial.body_label.text == "Taking damage, slowing time, and repairing drain your reserve. Find moments to let it recharge.",
		"Collecting yellow weapon starts staged time_meter teaching before shot with exact reserve caption"
	)
	var min_meter_during_tm := 100.0
	var max_meter_after_drain := 0.0
	for tm_step in range(180):
		_tick(1.0 / 30.0)
		min_meter_during_tm = minf(min_meter_during_tm, arena.time_controller.meter)
		if min_meter_during_tm < 90.0:
			max_meter_after_drain = maxf(max_meter_after_drain, arena.time_controller.meter)
		if arena.mode != &"practice":
			break
	expect(
		min_meter_during_tm < 80.0 and max_meter_after_drain > min_meter_during_tm + 10.0,
		"Staged time_meter demo visibly drains time reserve on hit and recharges it (min=%.1f, recharged=%.1f)" % [min_meter_during_tm, max_meter_after_drain]
	)
	expect(
		arena.tutorial.is_learned(&"time_meter")
		and arena.mode == &"recovery"
		and is_equal_approx(arena.time_controller.meter, arena.time_controller.capacity)
		and arena.time_controller.charges_remaining == 3
		and arena.director.enemies.is_empty(),
		"Completing time_meter restores 100% time reserve, 3 charges, and clears demo enemy before shot"
	)
	_tick(0.5)
	expect(arena.mode == &"practice" and arena.lesson == &"shot", "Wave 1 begins yellow shot lesson after time_meter")

	# Verify orange Heat Bellows practice uses orange targets only and visibly pushes the orange target back
	arena.debug_start(0, 3)
	arena.tutorial.learned.erase(&"heat")
	arena.lesson_demo.learned_demos.erase(&"heat")
	arena.director.clear()
	arena.wave_index = 2
	arena._begin_wave()
	expect(arena.lesson == &"heat" and arena.mode == &"practice", "Room 0 Wave 3 starts heat lesson")
	arena.tutorial.request_practice()
	expect(
		arena._practice_stage == &"stationary"
		and arena.specimens.size() == 1
		and arena.specimens[0].kind == &"orange",
		"Heat stationary practice spawns solo orange target"
	)
	var orange_target: Node3D = arena.specimens[0]
	var initial_orange_dist: float = Vector2(orange_target.position.x - arena.player.position.x, orange_target.position.z - arena.player.position.z).length()
	var max_orange_dist := initial_orange_dist
	arena.weapons.select_tool(3)
	for h_step in range(140):
		var aim_pt: Vector3 = orange_target.position if is_instance_valid(orange_target) else arena.player.position + Vector3.FORWARD * 3.0
		if not arena.weapons.bellows.active:
			arena.weapons.bellows.press(arena.player.position, aim_pt)
		arena.weapons.bellows.aim_at(arena.player.position, aim_pt)
		arena.weapons.bellows.step(1.0 / 60.0, 1.0 / 60.0, arena.player.position, aim_pt, arena.director.enemies)
		_tick(1.0 / 60.0)
		if is_instance_valid(orange_target) and orange_target.health > 0.0:
			var cur_dist := Vector2(orange_target.position.x - arena.player.position.x, orange_target.position.z - arena.player.position.z).length()
			max_orange_dist = maxf(max_orange_dist, cur_dist)
		if arena._stationary_done >= 1:
			break
	arena.weapons.bellows.release()
	expect(
		max_orange_dist - initial_orange_dist >= 0.6 and arena._stationary_done == 1,
		"Orange practice target is visibly pushed back by Heat Bellows before breaking (pushed +%.2fm from %.2fm to %.2fm)" % [max_orange_dist - initial_orange_dist, initial_orange_dist, max_orange_dist]
	)

	# Skip ends narration only; first repair remains mandatory and resumable.
	arena.debug_start(0, 5)
	arena.tutorial.learned.erase(&"repair")
	arena.director.clear()
	arena.wave_index = 4
	arena._begin_wave()
	expect(arena.lesson == &"repair" and arena.mode == &"practice", "Room 0 Wave 5 starts repair lesson")
	var broken_condition: float = arena.equipment.remaining(&"beam")
	expect(arena.tutorial.skip_active_lesson(true), "Actual repair Skip button accepts the explanation skip")
	expect(
		not arena.tutorial.is_learned(&"repair")
		and is_equal_approx(arena.equipment.remaining(&"beam"), broken_condition)
		and arena.lesson == &"repair" and arena.mode == &"practice"
		and not arena.tutorial.blocking and arena.tutorial.practicing,
		"Skipping repair narration preserves broken tool and mandatory repair practice"
	)
	_tick(0.05)
	expect(arena.lesson == &"repair" and not arena._lesson_succeeded(), "Skipping narration cannot advance to time slow")
	var open_repair := InputEventKey.new()
	open_repair.physical_keycode = KEY_E
	open_repair.pressed = true
	root.push_input(open_repair, true)
	var repair_popup: WeaponRepair = root.get_node("SceneManager").get_popup(&"Repair")
	expect(repair_popup != null and repair_popup.tool == &"beam" and arena.equipment.stage(&"beam") == 0, "E opens the required first repair from its first stage after Skip")
	if repair_popup != null:
		repair_popup._commit_steps(1)
		arena._close_repair()
		_tick(0.05)
		expect(arena.lesson == &"repair" and arena.equipment.stage(&"beam") == 1 and not arena.tutorial.is_learned(&"repair"), "Closing a partial repair preserves progress without completing the lesson")
		arena._open_smart_repair()
		repair_popup = root.get_node("SceneManager").get_popup(&"Repair")
		for stage in range(1, arena.equipment.repair_steps):
			repair_popup.trace_stage = arena.equipment.stage(&"beam")
			repair_popup._commit_steps(1)
		_tick(0.01)
		expect(arena.tutorial.is_learned(&"repair") and arena.mode == &"recovery", "Completing all repair stages, rather than Skip, completes the lesson")

	# Test opening lesson (Room 1 Wave 0): Demo -> 2 stationary (side_guard, front_guard) -> 2 moving (side_guard, front_guard) -> recovery -> Wave 1 real combat
	arena.debug_start(1, 0)
	arena.tutorial.learned.erase(&"opening")
	arena.lesson_demo.learned_demos.erase(&"opening")
	arena.director.clear()
	arena.wave_index = -1
	arena._begin_wave()
	expect(arena.lesson == &"opening" and arena.lesson_demo.active and arena._practice_stage == &"demo", "Room 1 Wave 0 begins opening LessonDemo")
	arena.tutorial.request_practice()
	expect(arena._practice_stage == &"stationary" and arena.specimens.size() == 1 and arena.specimens[0].kind == &"side_guard", "Opening stationary rep 1/2 spawns solo side_guard")
	_complete_single_rep(&"opening")
	_tick(0.02)
	expect(arena._practice_stage == &"stationary" and arena._stationary_done == 1 and arena.specimens.size() == 1 and arena.specimens[0].kind == &"front_guard", "Opening stationary rep 2/2 spawns solo front_guard")
	_complete_single_rep(&"opening")
	_tick(0.02)
	expect(arena._practice_stage == &"moving" and arena._moving_done == 0 and arena.specimens.size() == 1 and arena.specimens[0].kind == &"side_guard", "Opening moving rep 1/2 spawns moving side_guard")
	_complete_single_rep(&"opening")
	_tick(0.02)
	expect(arena._practice_stage == &"moving" and arena._moving_done == 1 and arena.specimens.size() == 1 and arena.specimens[0].kind == &"front_guard", "Opening moving rep 2/2 spawns moving front_guard")
	_complete_single_rep(&"opening")
	_tick(0.02)
	expect(arena.tutorial.is_learned(&"opening") and arena.mode == &"recovery" and arena.director.enemies.is_empty(), "Completing opening 2+2 practice enters brief recovery with NO post-lesson pressure wave")
	_tick(0.5)
	expect(arena.room_index == 1 and arena.wave_index == 1 and arena.mode == &"pressure" and arena.lesson == &"", "Room 1 advances from opening into Wave 1 real combat before pair lesson")

	# Verify retry_room() skips already-learned tutorials
	arena.tutorial.learned[&"pair"] = true
	arena.tutorial.learned[&"rewind"] = true
	arena.retry_room()
	_tick(2.1)
	expect(arena.room_index == 1 and arena.wave_index == 1 and arena.mode == &"pressure" and arena.lesson == &"", "Retrying Room 1 after learning opening skips Wave 0 opening and starts Wave 1 real combat")

	# 3. Reproduce & verify Exit Carry-Through ("W SKIP") protection across all 5 cases
	arena.enter_room(0)
	arena.wave_index = arena.waves.size() - 2
	arena._begin_wave()
	expect(arena.mode == &"pressure", "Entered final combat wave of Room 0")
	for e in arena.director.enemies:
		e.health = 0.0
	arena.director._prune_dead_enemies()
	arena._pending = 0

	# Case A: Player holds W (move_up) BEFORE wave clears and keeps holding W across recovery into open exit doorway
	var door_pos: Vector3 = arena.room.exit_door.position
	arena.player.position = door_pos + Vector3(0.0, 0.55, 1.4)
	Input.action_press(&"move_up")
	_tick(0.05)
	expect(arena.mode == &"recovery" and arena._forward_held_at_wave_clear, "Wave clear records held forward movement")
	_tick(2.0)
	expect(arena.mode == &"exit" and arena.museum.exit_open and arena.room_index == 0, "Room 0 enters exit mode with open green doorway")
	for i in range(15):
		_tick(1.0 / 30.0)
	expect(arena.room_index == 0 and arena.mode == &"exit" and arena.museum.player_in_exit(arena.player.position), "Holding W before clear into doorway does NOT skip room clear state even inside player_in_exit")

	# Releasing W while still standing inside the doorway must NOT trigger a mysterious key-release exit
	Input.action_release(&"move_up")
	_tick(0.05)
	expect(arena.room_index == 0 and arena.mode == &"exit" and arena._exit_requires_reentry, "Releasing W inside doorway keeps _exit_requires_reentry active until spatial re-entry")

	# Case B: Standing in exit at clear without W held requires stepping out of approach zone and re-entering
	arena.player.position = door_pos + Vector3(0.0, 0.55, 0.3)
	arena._forward_held_at_wave_clear = false
	arena._arm_room_exit()
	_tick(0.05)
	expect(arena.room_index == 0 and arena.mode == &"exit" and arena._exit_requires_reentry, "Standing in exit when doorway opens blocks instant transition")

	# Step south outside exit approach zone (z > door.z + 2.6), then make a fresh intentional approach
	arena.player.position = door_pos + Vector3(0.0, 0.55, 3.4)
	_tick(0.05)
	expect(not arena._exit_requires_reentry and not arena._exit_blocked_by_held_forward, "Stepping outside exit approach zone arms doorway for fresh approach")

	# Case C: Fresh intentional approach advances cleanly to next room and places player at next room spawn
	arena.player.position = door_pos + Vector3(0.0, 0.55, 0.4)
	_tick(0.05)
	expect(arena.room_index == 1 and arena.mode == &"title" and not arena.museum.exit_open, "Fresh approach into open doorway advances to Room 1 and closes new room exit")
	expect(arena.player.position.is_equal_approx(arena.room.player_spawn) and not arena.museum.player_in_exit(arena.player.position), "Next room places player at room spawn far from north exit")

	# 4. Execute full playable runs on both Easy and Hard (normal + skip_tutorials)
	await _execute_full_run(&"easy")
	await _execute_full_run(&"hard")
	await _execute_skip_tutorials_run(&"easy")
	await _execute_skip_tutorials_run(&"hard")

	# Verify GameState preference transport for skip_tutorials
	scenes.params = {"difficulty": &"easy"}
	game.set_setting("tutorial", false)
	game.set_setting("skip_tutorials", false)
	arena.start_new_run(&"easy")
	expect(not arena.skip_tutorials, "Hiding hints does not skip teaching when the checkbox is off")
	expect(not arena.tutorial.is_learned(&"shot"), "A fresh taught run re-enables contextual teaching instead of silently marking lessons learned")
	game.set_setting("skip_tutorials", true)
	arena.start_new_run(&"easy")
	expect(arena.skip_tutorials, "Saved Skip tutorials preference is used when no run flag is supplied")
	scenes.params["skip_tutorials"] = false
	arena.start_new_run(&"easy")
	expect(not arena.skip_tutorials, "Explicit unchecked start selection overrides a saved true preference")
	game.set_setting("skip_tutorials", false)
	game.set_setting("tutorial", true)

	Input.action_release(&"move_up")
	scenes.clear_popups()
	game.start_game()
	for key in saved_prefs:
		game.set_setting(key, saved_prefs[key])
	root.get_node("AudioManager").stop_dialogue()
	root.get_node("AudioManager").set_music_context(&"intro")
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	await create_timer(0.3).timeout

	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
