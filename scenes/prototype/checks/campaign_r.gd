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
	var saw_movement_cue := false
	var saw_tool_switch_cue := false
	for step in range(1100):
		visited_rooms[arena.room_index] = true
		if arena.mode == &"won":
			break
		if arena.mode in [&"title", &"ceremony"]:
			_tick(3.0)
		elif arena.mode == &"pickup":
			if arena._pickup_stage == &"movement_cue":
				saw_movement_cue = true
				expect(
					not arena.tutorial.blocking
					and arena.run_hint.text == "Mouse aims. WASD moves."
					and arena.run_hint.visible,
					"Movement cue precedes first pickup cue with nonblocking movement on " + String(diff)
				)
				_tick(1.0)
				continue
			if arena._pickup_stage == &"tool_switch_cue":
				saw_tool_switch_cue = true
				expect(
					not arena.tutorial.blocking
					and arena.run_hint.text == "Press Tab, one, two, or three; to select tools."
					and arena.run_hint.visible,
					"Tool-switch cue precedes second acquired item's explanation on " + String(diff)
				)
				_tick(2.4)
				continue
			if arena._pickup_stage == &"await_pickup_speech":
				_tick(2.4)
				continue
			var p_tool: int = arena.museum.pickup_tool
			if p_tool > 0 and not (p_tool in pickups_seen):
				pickups_seen.append(p_tool)
			if p_tool > 0:
				expect(
					not arena.tutorial.blocking
					and arena.run_hint.text == "Walk towards the new item."
					and arena.run_hint.visible
					and Vector2(arena.player.position.x - arena.museum.pickup_position.x, arena.player.position.z - arena.museum.pickup_position.z).length() >= 2.5,
					"Pickup for tool %d is nonblocking with 'Walk towards the new item.' cue and walkable distance on %s" % [p_tool, String(diff)]
				)
				arena.player.position = arena.museum.pickup_position + Vector3.UP * 0.55
				_tick(0.05)
			else:
				_tick(2.4)
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
	expect(saw_movement_cue and saw_tool_switch_cue, "Run presents both movement cue before first pickup and tool-switch cue before second item explanation on " + String(diff))
	expect(pickups_seen == [2, 3, 1], "Run presents nonblocking walk-towards-item pickups for tools [2, 3, 1] on " + String(diff))
	expect(lessons_seen.size() >= 2 and lessons_seen[0] == &"time_meter" and lessons_seen[1] == &"shot", "Run teaches time_meter before shot on " + String(diff))
	expect(bosses_fought == [&"sequence_boss", &"loop_boss", &"final_boss"], "Run fights all 3 bosses in taught order (sequence_boss -> loop_boss -> final_boss) on " + String(diff))
	expect(arena.mode == &"won" and arena._last_music_context == &"victory", "Full run reaches victory state and sets victory music context on " + String(diff))
	expect(arena.acquired == [2, 3, 1] and arena.time_controller.slow_unlocked and arena.time_controller.rewind_unlocked, "Completed run unlocks all 3 weapons and both time capabilities on " + String(diff))
	expect(pressure_waves_seen.size() == 15, "Run includes all 12 combat waves (including escalating pre-boss waves) and 3 boss encounters on " + String(diff))


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
	for step in range(750):
		visited_rooms[arena.room_index] = true
		if arena.mode == &"won":
			break
		if arena.mode == &"practice" or arena.lesson_demo.active or arena.rewind_lesson.active:
			practiced_any = true
		if arena.mode in [&"title", &"ceremony"]:
			_tick(3.0)
		elif arena.mode == &"pickup":
			arena.player.position = arena.museum.pickup_position + Vector3.UP * 0.55
			_tick(0.001)
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
	expect(pressure_waves_seen.size() == 15, "Skip tutorials run preserves all 12 combat waves and 3 boss fights on " + String(diff))
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
	var audio_mgr := root.get_node("AudioManager")
	var saved_prefs: Dictionary = game.preferences().duplicate(true)
	game.set_setting("sound", true)
	game.set_setting("volume", 0.8)
	game.set_setting("voice_volume", 0.9)
	game.set_setting("tutorial", true)
	game.set_setting("skip_tutorials", false)
	scenes.params = {}

	# 1. Verify Target Run room/wave structure, zero ranged in Room 0, slow yellow practice, and escalating pre-boss combat waves in rooms.gd
	var easy_defs := Rooms.definitions(&"easy")
	var hard_defs := Rooms.definitions(&"hard")
	expect(easy_defs.size() == 4 and hard_defs.size() == 4, "Easy and Hard both define 4 museum rooms")

	# Room 0: Basic teaching (time_meter, shot, charge, heat, short interlude, repair, slow, cut) -> two escalating small-fodder combat waves (zero ranged!)
	expect(easy_defs[0].lessons == [&"time_meter", &"shot", &"charge", &"heat", &"repair", &"slow", &"cut"], "Room 0 teaches time_meter before shot, then charge, heat, repair, slow, cut")
	expect(easy_defs[0].waves[0].lesson == &"time_meter" and int(easy_defs[0].waves[0].get("acquire", 0)) == 2, "Room 0 Wave 0 acquires Tool 2 and teaches time_meter before shot")
	expect(easy_defs[0].waves[1].lesson == &"shot" and int(easy_defs[0].waves[1].get("acquire", 0)) == 0, "Room 0 Wave 1 teaches yellow shot immediately after time_meter")
	expect(easy_defs[0].waves[4].lesson == &"" and bool(easy_defs[0].waves[4].pressure) and easy_defs[0].waves[4].enemies == [&"yellow", &"orange"], "Room 0 includes short familiar-target interlude before repair")
	expect(easy_defs[0].waves[6].lesson == &"slow" and easy_defs[0].waves[6].enemies == [&"yellow"], "Room 0 slow lesson uses familiar yellow enemy, not ranged or blue")
	expect(easy_defs[0].waves.size() == 10 and hard_defs[0].waves.size() == 10, "Room 0 has 10 waves ending with two escalating small-fodder combat waves")
	expect(
		easy_defs[0].waves[8].lesson == &"" and bool(easy_defs[0].waves[8].pressure)
		and easy_defs[0].waves[9].lesson == &"" and bool(easy_defs[0].waves[9].pressure)
		and int(easy_defs[0].waves[9].count) > int(easy_defs[0].waves[8].count),
		"Room 0 ends with two substantial escalating small-fodder combat waves"
	)
	var r0_has_ranged := false
	for w in easy_defs[0].waves:
		if &"ranged" in w.enemies:
			r0_has_ranged = true
	for w in hard_defs[0].waves:
		if &"ranged" in w.enemies:
			r0_has_ranged = true
	expect(not r0_has_ranged, "Room 0 contains zero ranged enemies across all lessons, practice, and combat waves on Easy and Hard")

	# Room 1: Advanced A teaching + deliberate ranged introduction + two escalating pre-boss waves -> Boss 1
	expect(easy_defs[1].lessons == [&"opening", &"pair", &"rewind"], "Room 1 teaches Advanced A: opening, pair, rewind")
	expect(easy_defs[1].waves[0].lesson == &"opening" and easy_defs[1].waves[1].lesson == &"" and bool(easy_defs[1].waves[1].pressure) and (&"ranged" in easy_defs[1].waves[1].enemies), "Room 1 deliberately introduces ranged in Wave 1 combat after Room 0")
	expect(easy_defs[1].waves[2].lesson == &"pair" and easy_defs[1].waves[3].lesson == &"" and bool(easy_defs[1].waves[3].pressure), "Room 1 places real combat wave between pair and rewind")
	expect(easy_defs[1].waves[4].lesson == &"rewind", "Room 1 Wave 4 teaches rewind")
	expect(
		easy_defs[1].waves[5].lesson == &"" and bool(easy_defs[1].waves[5].pressure) and not bool(easy_defs[1].waves[5].get("boss", false))
		and easy_defs[1].waves[6].lesson == &"" and bool(easy_defs[1].waves[6].pressure) and not bool(easy_defs[1].waves[6].get("boss", false))
		and int(easy_defs[1].waves[6].count) > int(easy_defs[1].waves[5].count),
		"Room 1 has two escalating pre-boss combat waves (Waves 5 and 6) before sequence_boss"
	)
	var boss1_wave: Dictionary = easy_defs[1].waves[7]
	var boss1_hard: Dictionary = hard_defs[1].waves[7]
	expect(bool(boss1_wave.get("boss", false)) and boss1_wave.enemies[0] == &"sequence_boss", "Boss 1 is sequence_boss at Room 1 Wave 7")
	expect(not (&"loop" in boss1_wave.enemies) and not (&"zigzag" in boss1_wave.enemies) and not (&"loop" in boss1_hard.enemies) and not (&"zigzag" in boss1_hard.enemies), "Boss 1 escorts on Easy and Hard contain no untaught Advanced B enemies (loop/zigzag)")

	# Room 2: Advanced B teaching with real combat between new lessons and ordinary pre-boss combat waves -> Boss 2
	expect(easy_defs[2].lessons == [&"loop", &"zigzag"], "Room 2 teaches Advanced B: loop, zigzag")
	expect(easy_defs[2].waves[0].lesson == &"loop" and easy_defs[2].waves[1].lesson == &"" and bool(easy_defs[2].waves[1].pressure), "Room 2 places real combat wave between loop and zigzag")
	expect(
		easy_defs[2].waves[2].lesson == &"zigzag"
		and easy_defs[2].waves[3].lesson == &"" and bool(easy_defs[2].waves[3].pressure) and not bool(easy_defs[2].waves[3].get("boss", false))
		and easy_defs[2].waves[4].lesson == &"" and bool(easy_defs[2].waves[4].pressure) and not bool(easy_defs[2].waves[4].get("boss", false))
		and int(easy_defs[2].waves[4].count) > int(easy_defs[2].waves[3].count),
		"Room 2 has two escalating combat waves before loop_boss"
	)
	var boss2_wave: Dictionary = easy_defs[2].waves[5]
	expect(bool(boss2_wave.get("boss", false)) and boss2_wave.enemies[0] == &"loop_boss", "Boss 2 is loop_boss at Room 2 Wave 5")

	# Room 3: Two escalating final combat waves -> Final Boss (final_boss)
	expect(easy_defs[3].lessons.is_empty() and easy_defs[3].waves.size() == 3, "Room 3 has two escalating Final Combat waves followed by Final Boss")
	expect(
		easy_defs[3].waves[0].lesson == &"" and bool(easy_defs[3].waves[0].pressure) and not bool(easy_defs[3].waves[0].get("boss", false))
		and easy_defs[3].waves[1].lesson == &"" and bool(easy_defs[3].waves[1].pressure) and not bool(easy_defs[3].waves[1].get("boss", false))
		and int(easy_defs[3].waves[1].count) > int(easy_defs[3].waves[0].count),
		"Room 3 Waves 0 and 1 are escalating Final Combat waves"
	)
	expect(bool(easy_defs[3].waves[2].get("boss", false)) and easy_defs[3].waves[2].enemies[0] == &"final_boss", "Room 3 Wave 2 is Final Boss (final_boss)")

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

	# 2. Instantiate campaign and verify movement cue -> pickup cue -> quick pickup speech guard -> time_meter -> shot
	arena = load("res://scenes/prototype/campaign.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	game.start_game()

	# Ensure tutorial.movement and tutorial.tool_switch have playable streams even before jam-6 library merge
	var had_move_clip: bool = audio_mgr.library != null and audio_mgr.library.clips.has(&"tutorial.movement")
	var had_switch_clip: bool = audio_mgr.library != null and audio_mgr.library.clips.has(&"tutorial.tool_switch")
	if audio_mgr.library != null and audio_mgr.library.clips.has(&"tutorial.pickup"):
		var sample_stream: Array = audio_mgr.library.clips[&"tutorial.pickup"]
		if not had_move_clip:
			audio_mgr.library.clips[&"tutorial.movement"] = sample_stream.duplicate()
		if not had_switch_clip:
			audio_mgr.library.clips[&"tutorial.tool_switch"] = sample_stream.duplicate()

	arena.start_new_run(&"easy", false)
	expect(arena.practice_quotas_for(&"time_meter") == Vector2i.ZERO, "Lesson time_meter has Vector2i.ZERO practice quota")
	for lid in [&"shot", &"charge", &"heat", &"slow", &"cut", &"opening", &"pair", &"loop", &"zigzag"]:
		expect(arena.practice_quotas_for(lid) == Vector2i(2, 2), "Lesson %s has Vector2i(2, 2) quota" % String(lid))

	expect(arena._last_music_context == &"regular_combat", "Entering Room 0 sets regular_combat music context")

	# Step past title into first playable moment: movement cue BEFORE first pickup cue
	_tick(2.1)
	expect(
		arena.mode == &"pickup"
		and arena._pickup_stage == &"movement_cue"
		and arena.museum.pickup_tool == 2
		and not arena.tutorial.blocking
		and arena.run_hint.text == "Mouse aims. WASD moves."
		and arena.run_hint.visible
		and audio_mgr.current_event == &"tutorial.movement",
		"First playable moment starts nonblocking movement cue ('Mouse aims. WASD moves.', tutorial.movement) before first pickup cue"
	)
	var start_pos: Vector3 = arena.player.position
	Input.action_press(&"move_right")
	_tick(0.1)
	Input.action_release(&"move_right")
	expect(arena.player.position.distance_to(start_pos) > 0.1 and arena._pickup_stage == &"movement_cue", "Player can move freely during movement cue without cutting off tutorial.movement")

	# Complete tutorial.movement naturally -> verify transition to tutorial.pickup ('Walk towards the new item.')
	audio_mgr.voice.stop()
	audio_mgr._finish_current(false)
	expect(
		arena.mode == &"pickup"
		and arena._pickup_stage == &"pickup_cue"
		and arena.run_hint.text == "Walk towards the new item."
		and arena.run_hint.visible
		and audio_mgr.current_event == &"tutorial.pickup",
		"Completing tutorial.movement transitions to first pickup cue ('Walk towards the new item.', tutorial.pickup)"
	)

	# Quick pickup while tutorial.pickup is still speaking must NOT cut off tutorial.pickup or start time_meter over it
	arena.player.position = arena.museum.pickup_position + Vector3.UP * 0.55
	_tick(0.05)
	expect(
		arena.acquired == [2]
		and arena.mode == &"pickup"
		and arena._pickup_stage == &"await_pickup_speech"
		and audio_mgr.current_event == &"tutorial.pickup",
		"Quick pickup during tutorial.pickup collects tool without cutting off tutorial.pickup or starting time_meter over it"
	)
	audio_mgr.voice.stop()
	audio_mgr._finish_current(false)
	expect(
		arena.mode == &"practice"
		and arena.lesson == &"time_meter"
		and arena.tutorial.visible
		and arena.tutorial.body_label.text == "Taking damage, slowing time, and repairing drain your reserve. Find moments to let it recharge."
		and audio_mgr.current_event == &"tutorial.time_meter",
		"Once tutorial.pickup finishes, staged time_meter demonstration begins with exact reserve caption"
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
	# Practice retains varied entrances, except the obscured bottom entrance.
	arena.lesson_demo.cancel()
	audio_mgr.stop_dialogue()
	arena.tutorial.dismiss()
	for practice_lesson: StringName in [&"shot", &"charge", &"cut", &"slow", &"opening", &"pair", &"loop", &"zigzag"]:
		arena.lesson = practice_lesson
		for rep in 4:
			arena._practice_stage = &"stationary"
			arena._stationary_done = rep
			var seed: int = arena.room_index * 37 + arena.wave_index * 13 + rep * 5 + arena._moving_done * 11
			var preferred_seed := seed + 1 if posmod(seed, 4) == 2 else seed
			var kind: StringName = &"yellow"
			if practice_lesson == &"cut": kind = &"blue"
			elif practice_lesson == &"opening": kind = &"side_guard" if rep % 2 == 0 else &"front_guard"
			elif practice_lesson in [&"pair", &"loop", &"zigzag"]: kind = practice_lesson
			var count := 3 if practice_lesson == &"charge" else 1
			var kinds: Array = []
			kinds.resize(count)
			kinds.fill(kind)
			var expected := CombatFlow.new().layout(&"line" if practice_lesson == &"charge" else &"curve", kinds, arena.player.position, arena.cover, preferred_seed, [])
			arena._spawn_practice()
			var matches: bool = not expected.is_empty() and arena.specimens.size() == expected.size()
			for index in mini(arena.specimens.size(), expected.size()):
				matches = matches and arena.specimens[index].position.is_equal_approx(expected[index].position)
			expect(matches, "%s practice %d keeps normal placement with bottom entrance excluded" % [practice_lesson, rep])

	# Verify second acquired item (Tool 3 in Room 0 Wave 3) plays tutorial.tool_switch BEFORE heat explanation
	arena.debug_start(0, 2)
	arena.tutorial.learned.erase(&"heat")
	arena.lesson_demo.learned_demos.erase(&"heat")
	arena.acquired.assign([2])
	arena._tool_switch_cue_done = false
	arena.director.clear()
	arena.wave_index = 2
	arena._begin_wave()
	expect(arena.mode == &"pickup" and arena._pickup_stage == &"pickup_cue" and arena.museum.pickup_tool == 3, "Wave 3 enters pickup mode for second item (Tool 3)")
	audio_mgr.stop_dialogue()
	arena.player.position = arena.museum.pickup_position + Vector3.UP * 0.55
	_tick(0.05)
	expect(
		arena.acquired == [2, 3]
		and arena.mode == &"pickup"
		and arena._pickup_stage == &"tool_switch_cue"
		and not arena.tutorial.blocking
		and arena.run_hint.text == "Press Tab, one, two, or three; to select tools."
		and arena.run_hint.visible
		and audio_mgr.current_event == &"tutorial.tool_switch",
		"Picking up second item triggers nonblocking tool_switch cue ('Press Tab, one, two, or three; to select tools.', tutorial.tool_switch) before heat explanation"
	)
	audio_mgr.voice.stop()
	audio_mgr._finish_current(false)
	expect(arena.lesson == &"heat" and arena.mode == &"practice" and audio_mgr.current_event == &"tutorial.heat", "Completing tutorial.tool_switch starts second item's explanation (heat)")

	# Verify orange Heat Bellows practice uses orange targets only and visibly pushes the orange target back
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

	# Verify slow lesson in Room 0 Wave 6 spawns familiar yellow target (not ranged or blue)
	arena.debug_start(0, 6)
	arena.tutorial.learned.erase(&"slow")
	arena.lesson_demo.learned_demos.erase(&"slow")
	arena.director.clear()
	arena.wave_index = 5
	arena._begin_wave()
	expect(arena.lesson == &"slow" and arena.mode == &"practice", "Room 0 Wave 6 starts slow lesson")
	arena.tutorial.request_practice()
	expect(
		arena._practice_stage == &"stationary"
		and arena.specimens.size() == 1
		and arena.specimens[0].kind == &"yellow"
		and arena.weapons.selected_tool == 2,
		"Slow practice in Room 0 spawns familiar yellow target with Tool 2 selected"
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

	# Verify post-rewind charge-statement lifetime (tutorial.rewind_charges): not cut off by 0.35s recovery
	arena.debug_start(1, 4)
	arena.tutorial.learned.erase(&"rewind")
	arena.rewind_lesson.reset_for_new_run()
	arena.director.clear()
	arena.wave_index = 3
	arena._begin_wave()
	expect(arena.lesson == &"rewind" and arena.rewind_lesson.active, "Room 1 Wave 4 starts RewindLesson")
	for r_tick in range(60):
		_tick(0.04)
		if arena.is_emergency_active():
			break
	expect(arena.is_emergency_active() and arena.rewind_lesson.phase == RewindLesson.Phase.SCRUB, "RewindLesson enters frozen SCRUB phase")
	var enter_down := InputEventKey.new()
	enter_down.physical_keycode = KEY_ENTER
	enter_down.keycode = KEY_ENTER
	enter_down.pressed = true
	arena._input(enter_down)
	expect(
		not arena.is_emergency_active()
		and arena.time_controller.charges_remaining == 3
		and is_equal_approx(arena.time_controller.meter, arena.time_controller.capacity)
		and arena.mode == &"recovery"
		and arena._awaiting_rewind_charges_speech
		and audio_mgr.current_event == &"tutorial.rewind_charges"
		and arena.run_hint.text == "Each room gives you three emergency rewinds.",
		"Confirming RewindLesson with Enter restores 3 charges and 100% reserve and starts tutorial.rewind_charges"
	)
	var enter_up := InputEventKey.new()
	enter_up.physical_keycode = KEY_ENTER
	enter_up.keycode = KEY_ENTER
	enter_up.pressed = false
	arena._input(enter_up)
	expect(not arena._suppress_enter_release, "Held Enter release after RewindLesson confirm is consumed cleanly without leaking")
	# Tick 0.6s (past the 0.35s recovery timer) and verify tutorial.rewind_charges is NOT cut off
	_tick(0.6)
	expect(
		arena.mode == &"recovery"
		and arena.wave_index == 4
		and arena._awaiting_rewind_charges_speech
		and audio_mgr.current_event == &"tutorial.rewind_charges",
		"0.35s recovery timer does NOT cut off tutorial.rewind_charges before it finishes"
	)
	# Natural completion of tutorial.rewind_charges advances immediately to Wave 5 without a second confirmation
	audio_mgr.voice.stop()
	audio_mgr._finish_current(false)
	expect(
		not arena._awaiting_rewind_charges_speech
		and arena.mode == &"pressure"
		and arena.wave_index == 5,
		"Completing tutorial.rewind_charges advances automatically to the next encounter without a second confirmation"
	)

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

	# 3. Verify Round T Reliable Exits: fresh threshold crossing works on first try with W held; standing inside threshold at open requires one step-out and re-entry
	arena.enter_room(0)
	arena.wave_index = arena.waves.size() - 2
	arena._begin_wave()
	expect(arena.mode == &"pressure", "Entered final combat wave of Room 0")
	for e in arena.director.enemies:
		e.health = 0.0
	arena.director._prune_dead_enemies()
	arena._pending = 0

	# Case A: Player already inside the open exit threshold when the exit opens needs one step-out and re-entry
	var door_pos: Vector3 = arena.room.exit_door.position
	arena.player.position = door_pos + Vector3(0.0, 0.55, 1.4)
	_tick(0.05)
	expect(arena.mode == &"recovery", "Wave clear enters recovery")
	_tick(2.0)
	expect(arena.mode == &"exit" and arena.museum.exit_open and arena.room_index == 0, "Room 0 enters exit mode with open green doorway")
	arena.player.position = door_pos + Vector3(0.0, 0.55, 0.3)
	arena._arm_room_exit()
	_tick(0.05)
	expect(arena.room_index == 0 and arena.mode == &"exit" and arena._exit_requires_reentry, "Player already inside threshold when exit opens requires one step-out before transition")

	# One step-out just outside the threshold (z = door.z + 1.4) clears _exit_requires_reentry even with W held
	Input.action_press(&"move_up")
	arena.player.position = door_pos + Vector3(0.0, 0.55, 1.4)
	_tick(0.05)
	expect(not arena._exit_requires_reentry, "Stepping just outside the exit threshold arms doorway immediately even with W held")

	# Re-entering the threshold with W held transitions on the first try
	arena.player.position = door_pos + Vector3(0.0, 0.55, 0.4)
	_tick(0.05)
	expect(arena.room_index == 1 and arena.mode == &"title" and not arena.museum.exit_open, "Re-entering threshold with W held advances to Room 1 on the first try")
	expect(arena.player.position.is_equal_approx(arena.room.player_spawn) and not arena.museum.player_in_exit(arena.player.position), "Next room places player at room spawn far from north exit")

	# Case B: Approaching from outside threshold with W held before wave clear works on the first try once exit opens
	arena.enter_room(0)
	arena.wave_index = arena.waves.size() - 2
	arena._begin_wave()
	for e in arena.director.enemies:
		e.health = 0.0
	arena.director._prune_dead_enemies()
	arena._pending = 0
	door_pos = arena.room.exit_door.position
	arena.player.position = door_pos + Vector3(0.0, 0.55, 2.2)
	Input.action_press(&"move_up")
	_tick(0.05)
	arena.player.position = door_pos + Vector3(0.0, 0.55, 1.4)
	_tick(2.0)
	expect(arena.mode == &"exit" and not arena._exit_requires_reentry, "Opening exit while player is outside threshold arms exit immediately even with W held")
	for i in range(10):
		_tick(1.0 / 30.0)
	expect(arena.room_index == 1 and arena.mode == &"title", "Approaching open threshold with W held transitions to Room 1 on the first try")
	Input.action_release(&"move_up")

	if not had_move_clip and audio_mgr.library != null:
		audio_mgr.library.clips.erase(&"tutorial.movement")
	if not had_switch_clip and audio_mgr.library != null:
		audio_mgr.library.clips.erase(&"tutorial.tool_switch")

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

	# 5. Round U: Verify Easy/Hard difficulty tuning, non-compounding rewind damage, stationary reserve depletion, and explicit Game Over on final depletion
	var easy_spec := CampaignDifficulty.load_for(&"easy")
	var hard_spec := CampaignDifficulty.load_for(&"hard")
	expect(
		is_equal_approx(easy_spec.enemy_damage_scale, 2.0)
		and is_equal_approx(easy_spec.melee_windup_seconds, 0.25)
		and is_equal_approx(easy_spec.melee_reach_padding, 0.35)
		and is_equal_approx(easy_spec.aim_turn_scale, 1.6),
		"Easy difficulty resource configures 2.0x damage (+100%), 0.25s melee windup, 0.35 reach padding, and 1.6x aim turn"
	)
	expect(
		is_equal_approx(hard_spec.enemy_damage_scale, 5.0)
		and is_equal_approx(hard_spec.melee_windup_seconds, 0.20)
		and is_equal_approx(hard_spec.melee_reach_padding, 0.55)
		and is_equal_approx(hard_spec.aim_turn_scale, 2.2),
		"Hard difficulty resource configures 5.0x damage (+400%), 0.20s melee windup, 0.55 reach padding, and 2.2x aim turn"
	)

	var base_yellow_dmg := float(arena.Tuning.ENEMIES["yellow"]["damage"])
	var base_ranged_dmg := float(arena.Tuning.ENEMIES["ranged"]["damage"])
	for diff_mode: StringName in [&"easy", &"hard"]:
		var expected_scale := 2.0 if diff_mode == &"easy" else 5.0
		var expected_windup := 0.25 if diff_mode == &"easy" else 0.20
		arena.set_difficulty(diff_mode)
		arena.enter_room(1)
		expect(is_equal_approx(arena.equipment.wear_scale, 1.2 if diff_mode == &"easy" else 2.0), "%s weapon wear remains configured after room entry" % diff_mode)
		arena.director.clear()
		arena.mode = &"pressure"
		arena._pending = 1
		arena.player.position = Vector3.ZERO
		arena.time_controller.begin_attempt()

		# Verify melee damage scaling, windup timing, non-compounding snapshot restore, and stationary reserve depletion > passive recharge
		var melee_enemy: CombatEnemy = arena.director.spawn(&"yellow", Vector3(0.0, 0.0, 1.0))
		melee_enemy.move_speed = 0.0
		expect(
			is_equal_approx(melee_enemy.contact_damage, base_yellow_dmg * expected_scale),
			"%s melee enemy scales base contact_damage once (%.2f)" % [String(diff_mode), melee_enemy.contact_damage]
		)
		var snap_data: Dictionary = arena.capture_state()
		arena.restore_campaign_state(snap_data)
		melee_enemy = arena.director.enemies[0] as CombatEnemy
		melee_enemy.move_speed = 0.0
		expect(
			is_equal_approx(melee_enemy.contact_damage, base_yellow_dmg * expected_scale),
			"%s snapshot restore preserves scaled contact_damage without compounding" % String(diff_mode)
		)
		melee_enemy.step_enemy(0.01, arena.player)
		expect(
			melee_enemy.attack_phase == &"windup" and is_equal_approx(melee_enemy.attack_timer, expected_windup),
			"%s melee windup starts at %.2fs" % [String(diff_mode), expected_windup]
		)
		# Simulate 2 full melee attack+recharge cycles against a stationary player
		var reserve_start: float = arena.time_controller.meter
		for step_i in range(260):
			var dt := 1.0 / 60.0
			arena.time_controller.advance(dt)
			melee_enemy.step_enemy(dt, arena.player)
		expect(
			arena.time_controller.meter < reserve_start - 10.0,
			"%s sustained melee pressure depletes stationary player reserve faster than passive recharge (%.1f -> %.1f)" % [String(diff_mode), reserve_start, arena.time_controller.meter]
		)

		# Verify ranged damage scaling and stationary reserve depletion > passive recharge
		arena.director.clear()
		arena.time_controller.begin_attempt()
		var ranged_enemy: CombatEnemy = arena.director.spawn(&"ranged", Vector3(0.0, 0.0, -6.5))
		ranged_enemy.facing = Vector3.BACK
		expect(
			is_equal_approx(ranged_enemy.contact_damage, base_ranged_dmg * expected_scale),
			"%s ranged enemy scales base projectile damage once (%.2f)" % [String(diff_mode), ranged_enemy.contact_damage]
		)
		var ranged_reserve_start: float = arena.time_controller.meter
		for step_i in range(280):
			var dt := 1.0 / 60.0
			arena.time_controller.advance(dt)
			arena.director.step(dt, arena.player)
			if arena.time_controller.emergency_active or arena.time_controller.exhausted:
				break
		expect(
			arena.time_controller.meter < ranged_reserve_start - 15.0 or arena.time_controller.emergency_active or arena.time_controller.exhausted,
			"%s sustained ranged pressure depletes stationary player reserve faster than passive recharge" % String(diff_mode)
		)

	# Verify 3rd charge is a usable emergency rewind, and 4th lethal hit (at 0 charges) triggers explicit Game Over RunResult
	scenes.clear_popups()
	game.start_game()
	arena.debug_start(2, 1)
	var saved_learned: Dictionary = arena.tutorial.learned.duplicate()
	var saved_acquired: Array[int] = arena.acquired.duplicate()
	expect(arena.room_index == 2 and arena.wave_index == 1 and arena.time_controller.charges_remaining == 3 and arena.time_controller.rewind_unlocked, "Room 2 Wave 1 starts with rewind unlocked and 3 charges")

	# Spend charges 1, 2, and 3: 3rd charge must enter EMERGENCY with 0 charges remaining (not Game Over)
	for charge_step in range(3):
		arena.time_controller.apply_hit(100.0)
		var expected_rem := 2 - charge_step
		expect(
			arena.is_emergency_active()
			and not arena.time_controller.exhausted
			and arena.time_controller.charges_remaining == expected_rem
			and not scenes.has_popup(&"RunResult")
			and arena.mode != &"game_over",
			"Depletion #%d spends charge and enters EMERGENCY with %d charges left (not Game Over)" % [charge_step + 1, expected_rem]
		)
		arena.emergency_rewind.confirm()
		arena.time_controller.advance(arena.time_controller.settings.recovery_grace_seconds + 0.1)

	# Open repair popup and hold Enter + LMB before the final lethal hit at 0 charges
	arena.equipment.spend(&"beam", 25.0)
	arena._open_smart_repair()
	expect(scenes.has_popup(&"Repair"), "Repair popup is open before final lethal hit")
	var held_enter := InputEventKey.new()
	held_enter.physical_keycode = KEY_ENTER
	held_enter.keycode = KEY_ENTER
	held_enter.pressed = true
	arena._input(held_enter)
	var held_lmb := InputEventMouseButton.new()
	held_lmb.button_index = MOUSE_BUTTON_LEFT
	held_lmb.pressed = true
	arena._input(held_lmb)
	arena.weapons.mouse_held = true

	var enemy_pos_at_death: Vector3 = arena.director.enemies[0].position if not arena.director.enemies.is_empty() else Vector3.ZERO
	arena.time_controller.apply_hit(100.0)
	var result_popup: Control = scenes.get_popup(&"RunResult") as Control
	expect(
		arena.time_controller.exhausted
		and not arena.is_emergency_active()
		and arena.mode == &"game_over"
		and game.is_game_over()
		and scenes.has_popup(&"RunResult")
		and result_popup != null
		and not result_popup.won
		and result_popup.retry.text == "Retry room"
		and not scenes.has_popup(&"Repair")
		and not arena.weapons.mouse_held
		and arena.room_index == 2
		and arena.wave_index == 1,
		"Lethal hit with 0 charges remaining closes Repair, cancels inputs, freezes gameplay in game_over mode, and opens RunResult without resetting room"
	)

	# Stepping _physics_process while Game Over is open must not move enemies or open duplicate popups
	expect(result_popup.title.text == "Game Over", "Final depletion clearly says Game Over")
	_tick(0.5)
	var enemy_pos_after_tick: Vector3 = arena.director.enemies[0].position if not arena.director.enemies.is_empty() else Vector3.ZERO
	expect(
		enemy_pos_after_tick.is_equal_approx(enemy_pos_at_death)
		and scenes._popups.size() == 1
		and arena.mode == &"game_over"
		and arena.wave_index == 1,
		"Gameplay remains frozen behind Game Over UI with no duplicate RunResult popups"
	)

	# Held Enter echo/release and held mouse release must NOT accidentally trigger Retry room
	var enter_echo := InputEventKey.new()
	enter_echo.physical_keycode = KEY_ENTER
	enter_echo.keycode = KEY_ENTER
	enter_echo.pressed = true
	enter_echo.echo = true
	result_popup._input(enter_echo)
	var enter_rel := InputEventKey.new()
	enter_rel.physical_keycode = KEY_ENTER
	enter_rel.keycode = KEY_ENTER
	enter_rel.pressed = false
	result_popup._input(enter_rel)
	arena._input(enter_rel)
	var lmb_rel := InputEventMouseButton.new()
	lmb_rel.button_index = MOUSE_BUTTON_LEFT
	lmb_rel.pressed = false
	result_popup._input(lmb_rel)
	arena._input(lmb_rel)
	expect(
		scenes.has_popup(&"RunResult") and arena.mode == &"game_over" and arena.wave_index == 1,
		"Held Enter echo/release and held LMB release from gameplay do not accidentally activate Retry room"
	)

	# Explicit user choice on Retry room restarts the current room while preserving learned tutorials, tools, and capabilities
	result_popup._on_retry()
	expect(
		not scenes.has_popup(&"RunResult")
		and game.is_playing()
		and arena.room_index == 2
		and arena.mode == &"title"
		and not arena.time_controller.exhausted
		and arena.time_controller.charges_remaining == 3
		and is_equal_approx(arena.time_controller.meter, arena.time_controller.capacity)
		and arena.acquired == saved_acquired
		and arena.tutorial.learned == saved_learned
		and arena.time_controller.slow_unlocked
		and arena.time_controller.rewind_unlocked,
		"Choosing Retry room from Game Over cleanly restarts current room with full reserve/charges while preserving tools, capabilities, and learned lessons"
	)

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
