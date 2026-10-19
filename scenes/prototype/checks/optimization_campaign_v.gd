extends SceneTree

# Round V focused campaign readability & wave-transition check suite (JAM-4):
# - Verifies Skip tutorials full-kit start (bcc2d52) in Gallery (Room 0) with all 3 weapons, slow, and 3 rewinds
# - Verifies _skip_completed_teaching_waves() fast-forwards pure teaching waves while granting tools/unlocks
# - Verifies _complete_teaching_wave() recovery scheduling vs _wave_has_post_lesson_pressure() combat entry
# - Verifies _begin_wave() room completion (exit doorway vs final victory) and boss ceremony / pickup dispatch
# - Compares capture_state() and restore_campaign_state() saved-state values across the edited transition path

const Rooms = preload("res://scenes/prototype/rooms.gd")

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


func _run() -> void:
	var game: Node = root.get_node("GameState")
	var scenes: Node = root.get_node("SceneManager")
	var audio_mgr: Node = root.get_node("AudioManager")
	var saved_prefs: Dictionary = game.preferences().duplicate(true)

	scenes.clear_popups()
	game.start_game()

	var packed: PackedScene = load("res://scenes/prototype/campaign.tscn")
	arena = packed.instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	game.start_game()

	# 1. Verify Skip tutorials full-kit start (bcc2d52) in Gallery (Room 0)
	scenes.params = {"difficulty": &"easy", "skip_tutorials": true}
	arena.start_new_run(&"easy", true)
	expect(
		arena.skip_tutorials
		and arena.room_index == 0
		and arena.mode == &"title"
		and arena.acquired == [1, 2, 3]
		and arena.weapons.available_tools == [1, 2, 3]
		and arena.time_controller.slow_unlocked
		and arena.time_controller.rewind_unlocked
		and arena.time_controller.charges_remaining == 3
		and is_equal_approx(arena.time_controller.meter, arena.time_controller.capacity),
		"Skip tutorials starts in Gallery with all 3 weapons, slow unlocked, and 3 emergency rewinds"
	)
	var expected_skip_wave := 0
	for idx in arena.waves.size():
		if bool(arena.waves[idx].get("skip_tutorial_start", false)):
			expected_skip_wave = idx
			break
	expect(arena.wave_index == expected_skip_wave - 1, "Skip tutorials positions wave_index immediately before authored skip_tutorial_start wave")
	for lesson_id: StringName in Rooms.lesson_ids():
		expect(arena.tutorial.is_learned(lesson_id), "Skip tutorials marks lesson '%s' learned" % String(lesson_id))

	_tick(1.0 / 60.0)
	expect(
		arena.room_index == 0
		and arena.wave_index == expected_skip_wave
		and arena.mode == &"pressure"
		and arena.lesson == &""
		and not arena.director.enemies.is_empty(),
		"Skip tutorials enters Gallery full-kit combat on the first tick without a title wait"
	)
	var skip_snap: Dictionary = arena.capture_state()
	var skip_wave_state: Dictionary = skip_snap.get("campaign_wave", {})
	expect(
		int(skip_wave_state.get("room", -1)) == 0
		and int(skip_wave_state.get("wave", -1)) == expected_skip_wave
		and StringName(skip_wave_state.get("mode", &"")) == &"pressure"
		and StringName(skip_wave_state.get("lesson", &"x")) == &"",
		"capture_state preserves exact campaign_wave fields during Skip tutorials combat"
	)

	# 2. Verify normal taught-mode start and _skip_completed_teaching_waves() progression
	scenes.params = {"difficulty": &"easy", "skip_tutorials": false}
	game.set_setting("skip_tutorials", false)
	game.set_setting("tutorial", true)
	arena.start_new_run(&"easy", false)
	expect(
		not arena.skip_tutorials
		and arena.room_index == 0
		and arena.wave_index == -1
		and arena.acquired.is_empty()
		and not arena.time_controller.slow_unlocked
		and not arena.time_controller.rewind_unlocked,
		"Normal taught start begins at Room 0 Wave -1 with empty loadout and locked time powers"
	)
	_tick(2.1)
	expect(
		arena.wave_index == 0
		and arena.mode == &"pickup"
		and arena.museum.pickup_tool == 2
		and arena.lesson == &"time_meter",
		"_begin_wave() enters pickup mode for Tool 2 on Room 0 Wave 0 (time_meter) when unacquired"
	)

	# Mark Room 0 pure teaching waves learned and verify _skip_completed_teaching_waves() fast-forwards
	# Waves 0..3 -> Wave 4 (first combat wave), then Waves 5..7 -> Wave 8 (full-kit combat wave)
	arena.acquired.clear()
	arena._slow_unlocked = false
	arena._rewind_unlocked = false
	arena._apply_time_capabilities()
	for early_lesson: StringName in [&"time_meter", &"shot", &"charge", &"heat"]:
		arena.tutorial.learned[early_lesson] = true
		if arena.lesson_demo != null:
			arena.lesson_demo.mark_learned(early_lesson)
	arena.retry_room()
	_tick(2.1)
	expect(
		arena.room_index == 0
		and arena.wave_index == 4
		and arena.mode == &"pressure"
		and arena.acquired == [2, 3]
		and not arena.time_controller.slow_unlocked,
		"_skip_completed_teaching_waves() fast-forwards learned Waves 0..3 to Wave 4 while granting tools [2, 3]"
	)
	for mid_lesson: StringName in [&"repair", &"slow", &"cut"]:
		arena.tutorial.learned[mid_lesson] = true
		if arena.lesson_demo != null:
			arena.lesson_demo.mark_learned(mid_lesson)
	arena.equipment.spend(&"beam", 40.0)
	arena.equipment.spend(&"cone", 40.0)
	arena.director.clear()
	arena._begin_wave()
	expect(
		arena.room_index == 0
		and arena.wave_index == expected_skip_wave
		and arena.mode == &"pressure"
		and arena.acquired == [2, 3, 1]
		and arena.time_controller.slow_unlocked
		and not arena.time_controller.rewind_unlocked
		and arena.equipment.is_full(&"beam")
		and arena.equipment.is_full(&"cone"),
		"_skip_completed_teaching_waves() fast-forwards learned Waves 5..7 to Wave 8 while granting tool 1, restoring beam/cone, and unlocking slow"
	)

	# 3. Verify _spawn_wave() and _complete_teaching_wave() recovery scheduling vs post-lesson pressure
	arena.debug_start(0, 0)
	arena.director.clear()
	arena.wave_index = 0
	arena.lesson = &"shot"
	arena.tutorial.learned[&"shot"] = true
	arena._spawn_wave()
	var recovery_snap: Dictionary = arena.capture_state()
	var recovery_wave: Dictionary = recovery_snap.get("campaign_wave", {})
	expect(
		arena.mode == &"recovery"
		and arena.lesson == &""
		and arena._practice_stage == &""
		and arena._pending == 0
		and is_equal_approx(arena.timer, float(arena.waves[0].get("recovery", 0.35)))
		and StringName(recovery_wave.get("mode", &"")) == &"recovery"
		and int(recovery_wave.get("pending", -1)) == 0,
		"Already-learned teaching-only wave transitions via _complete_teaching_wave() into recovery and seeds checkpoint"
	)

	# Restore snapshot and verify recovery countdown advances to next wave
	arena.mode = &"pressure"
	arena.restore_campaign_state(recovery_snap)
	expect(
		arena.mode == &"recovery"
		and is_equal_approx(arena.timer, float(arena.waves[0].get("recovery", 0.35))),
		"restore_campaign_state restores recovery mode and timer accurately"
	)

	# 4. Verify room completion (exit mode in non-final room vs victory in final room)
	arena.enter_room(0)
	arena.wave_index = arena.waves.size() - 1
	arena._begin_wave()
	var exit_snap: Dictionary = arena.capture_state()
	expect(
		arena.mode == &"exit"
		and arena.museum.exit_open
		and StringName(exit_snap.get("campaign_wave", {}).get("mode", &"")) == &"exit",
		"Advancing past final wave of Room 0 enters exit mode, opens green doorway, and seeds exit checkpoint"
	)

	arena.enter_room(3)
	arena.wave_index = arena.waves.size() - 1
	arena._begin_wave()
	expect(
		arena.mode == &"won"
		and scenes.has_popup(&"RunResult")
		and game.is_game_over(),
		"Advancing past final wave of Room 3 finishes run in won mode and opens RunResult"
	)

	scenes.clear_popups()
	game.start_game()
	for key in saved_prefs:
		game.set_setting(key, saved_prefs[key])
	audio_mgr.stop_dialogue()
	audio_mgr.set_music_context(&"intro")
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	await create_timer(0.3).timeout

	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
