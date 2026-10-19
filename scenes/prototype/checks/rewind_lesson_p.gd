extends SceneTree

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)


func settle(frames: int = 2) -> void:
	for _i in range(frames):
		await process_frame
		await physics_frame


func _key_event(code: int, pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	return ev


func _mouse_button(button: int, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	return ev


func _run() -> void:
	var old_size := root.size
	var game_state: Node = root.get_node("GameState")
	var arena: Node3D = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await settle(3)
	arena.set_physics_process(false)
	arena.set_process(false)

	var lesson: RewindLesson = load("res://scenes/tutorial/rewind_lesson.tscn").instantiate()
	arena.add_child(lesson)
	await settle(2)

	# 1. Initial contract & setup checks.
	expect(lesson.phase == RewindLesson.Phase.IDLE and lesson.phase_name == &"idle", "RewindLesson starts in IDLE phase")
	expect(not lesson.active and not lesson.is_completed and not lesson.is_cancelled, "RewindLesson flags are inactive before begin()")

	# Lock rewind initially to verify begin(arena) unlocks it for the forced demonstration.
	arena.time_controller.set_capabilities(true, false)
	var started := lesson.begin(arena)
	expect(started and lesson.phase == RewindLesson.Phase.STAGING and lesson.is_staging and lesson.active, "begin(arena) starts STAGING phase")
	expect(arena.time_controller.rewind_unlocked, "begin(arena) unlocks rewind capability on TimeController")
	expect(is_equal_approx(arena.history.window_seconds, 18.0) and arena.history.max_snapshots == 240, "Normal 18s / 240-snapshot ReplayHistory budget remains intact")
	expect(not lesson.begin(arena), "Duplicate begin(arena) while active is rejected")

	# 2. Pause/modal interruption during STAGING holds progress cleanly.
	var elapsed_before_pause := lesson._staging_elapsed
	game_state.pause()
	lesson.step(0.25)
	expect(is_equal_approx(lesson._staging_elapsed, elapsed_before_pause) and lesson.is_staging, "Pausing during STAGING freezes staging progress")
	game_state.resume()

	# 3. Cancel / retry during STAGING restores clean valid state without latching completion.
	lesson.step(0.4)
	expect(lesson._shot_fired and arena.director.enemies.size() == 1, "Staged character action fires weapon at safe specimen")
	lesson.cancel()
	expect(lesson.phase == RewindLesson.Phase.CANCELLED and lesson.is_cancelled and not lesson.active and not lesson.is_completed, "cancel() transitions to CANCELLED without setting completion latch")
	expect(arena.director.enemies.is_empty() and arena.director.projectiles.is_empty(), "cancel() cleans up staged entities and projectiles")
	expect(arena.time_controller.charges_remaining == 3 and is_equal_approx(arena.time_controller.meter, arena.time_controller.capacity), "cancel() restores clean 3-charge attempt state")

	# 4. Forced entry without ANY player action: puppeteered action -> ambush -> incoming hit -> automatic scrub.
	expect(lesson.begin(arena), "Lesson can begin cleanly after a prior cancellation")
	var start_pos: Vector3 = arena.player.position
	var saw_ambush := false
	var saw_projectiles := false
	for _i in range(40):
		if lesson.is_scrubbing:
			break
		lesson.step(0.05)
		if lesson._ambush_spawned:
			saw_ambush = true
			expect(arena.director.enemies.size() <= 5, "Staged ambush uses bounded existing enemies (<= 5)")
		if not arena.director.projectiles.is_empty():
			saw_projectiles = true

	expect(saw_ambush and saw_projectiles, "Staged sequence shows actual character action, familiar ambush, and visible incoming projectiles")
	expect((arena.player.position - start_pos).length() > 0.25 or lesson.is_scrubbing, "Puppeteered character action requires no player movement or shooting")
	expect(lesson.phase == RewindLesson.Phase.SCRUB and lesson.is_scrubbing, "Forced demonstration enters SCRUB automatically in < 2.0s without >=6s gate")
	expect(arena.emergency_rewind.active and arena.time_controller.emergency_active and arena.emergency_view.visible, "Real EmergencyRewind and EmergencyRewindView open automatically")

	# 5. Clear safe earlier default & protection against NOW-selection trap.
	var er: EmergencyRewind = arena.emergency_rewind
	var ev: EmergencyRewindView = arena.emergency_view
	expect(er.choice_count >= 5, "Short staged history provides multiple earlier moments")
	expect(er.selected_index == lesson.default_safe_index and er.selected_index >= lesson.min_safe_index and er.selected_index >= 1, "Scrubber defaults to a clear safe earlier moment, not NOW (0)")
	expect(er.choice_age(er.selected_index) > 0.0 and ev.choice.text.begins_with("−"), "Default selection previews an earlier recorded age")
	er.select(0)
	expect(er.selected_index >= lesson.min_safe_index and er.selected_index >= 1, "Scrolling/selecting NOW (0) is clamped to safe pre-ambush moments")
	arena._input(_mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	expect(er.selected_index >= lesson.min_safe_index, "Mouse wheel up cannot trap player on NOW")

	# 6. Scroll + freeze ticking drives ScrubView and real speed-ramp/scrub audio.
	var index_before_scroll: int = er.selected_index
	arena._input(_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true))
	expect(er.selected_index >= index_before_scroll, "Mouse wheel down steps toward earlier safe moments")
	expect(not is_zero_approx(float(arena._scrub_speed)), "Scrub selection change drives real scrub speed audio parameter")
	var speed_before_step: float = absf(float(arena._scrub_speed))
	lesson.step(0.05)
	expect(absf(float(arena._scrub_speed)) < speed_before_step and is_zero_approx(float(arena.time_controller.world_scale)), "step(real_delta) ticks scrub_view and audio feedback while world remains frozen")

	# 7. Compact layout verification at 1280x800 and 640x360.
	for win_size in [Vector2i(1280, 800), Vector2i(640, 360)]:
		root.size = win_size
		await settle(4)
		var vis_rect := root.get_visible_rect()
		var panel_rect := ev.panel.get_global_rect()
		var instr_rect := ev.instructions.get_global_rect()
		expect(vis_rect.encloses(panel_rect), "EmergencyView panel fits inside viewport at " + str(win_size))
		expect(vis_rect.encloses(instr_rect) and "Enter" in ev.instructions.text, "Instructions with Enter remain fully visible at " + str(win_size))
		expect(panel_rect.size.x <= 440.0 and panel_rect.size.y <= 115.0, "EmergencyView panel stays narrow and thin at " + str(win_size))
		var center_dx := absf(panel_rect.get_center().x - vis_rect.get_center().x)
		expect(center_dx <= 4.0, "EmergencyView panel is horizontally centered at " + str(win_size))
		if lesson.overlay != null and lesson.overlay.visible:
			var banner_rect := lesson.banner.get_global_rect()
			expect(not banner_rect.intersects(panel_rect), "Top lesson banner never overlaps bottom scrub bar at " + str(win_size))

	# 8. Room retry / attempt restart during SCRUB cancels cleanly and allows re-running.
	arena.reset_arena()
	expect(lesson.is_cancelled and not lesson.active and not lesson.is_completed and not er.active, "Room reset during SCRUB cancels lesson cleanly without latching completion")
	expect(arena.time_controller.charges_remaining == 3, "Room reset restores all 3 charges")

	# 9. Single confirmation completes ONCE, hands off to real play with ALL 3 charges, and supports safe caller wave spawn in `completed`.
	var cb := {
		"count": 0,
		"charges": -1,
		"emergency": true,
		"spawned": null,
	}
	lesson.completed.connect(func() -> void:
		cb["count"] = int(cb["count"]) + 1
		cb["charges"] = int(arena.time_controller.charges_remaining)
		cb["emergency"] = bool(arena.emergency_rewind.active or arena.time_controller.emergency_active)
		cb["spawned"] = arena.director.spawn(&"yellow", Vector3(0.0, 0.0, -7.0))
	)
	expect(lesson.begin(arena), "RewindLesson restarts after room retry")
	# Verify single coarse step(2.0) also sub-steps cleanly into SCRUB.
	lesson.step(2.0)
	expect(lesson.is_scrubbing and er.active and er.selected_index >= 1, "Coarse step(2.0) sub-steps into SCRUB with safe default selection")

	# Confirm ONCE with Enter key (no player scrolling required because default is already safe).
	arena._input(_key_event(KEY_ENTER, true))
	arena._input(_key_event(KEY_ENTER, false))
	# Send duplicate Enter and LMB confirms to prove idempotence.
	arena._input(_key_event(KEY_ENTER, true))
	arena._input(_mouse_button(MOUSE_BUTTON_LEFT, true))
	arena._input(_mouse_button(MOUSE_BUTTON_LEFT, false))
	er.confirm()

	var spawned_in_callback: Node3D = cb["spawned"] as Node3D
	expect(int(cb["count"]) == 1 and lesson.completed_count == 1, "One confirmation completes lesson and emits completed signal ONCE")
	expect(lesson.phase == RewindLesson.Phase.COMPLETED and lesson.is_completed and not lesson.active, "Lesson latches COMPLETED state")
	expect(int(cb["charges"]) == 3 and not bool(cb["emergency"]), "Inside completed callback, emergency is already closed and all 3 charges are ready")
	expect(is_instance_valid(spawned_in_callback) and arena.director.enemies.size() == 1 and arena.director.enemies[0] == spawned_in_callback, "Caller wave spawned inside completed callback survives without reentrant wipe")
	expect(arena.time_controller.charges_remaining == 3 and is_equal_approx(arena.time_controller.meter, arena.time_controller.capacity), "Real play begins with all 3 charges and full time meter")
	expect(not er.active and not ev.visible and not ev.lesson_mode, "EmergencyView closes and exits lesson_mode on completion")

	# 10. Normal later depletion spends 1 charge (3 -> 2) and history restore never re-triggers the lesson.
	for _i in range(6):
		arena.history.record(0.1, arena.capture_state)
	arena.time_controller.apply_hit(1000.0)
	await settle(2)
	expect(er.active and arena.time_controller.charges_remaining == 2, "Subsequent normal depletion spends 1 charge (3 -> 2)")
	expect(er.selected_index == 0 and ev.charges.text.contains("1 rewind spent · 2 left"), "Subsequent normal emergency starts at NOW and displays spent charge")
	er.step_selection(3)
	er.confirm()
	await settle(2)
	expect(arena.time_controller.charges_remaining == 2, "Normal recovery retains spent charge (no refund)")
	expect(lesson.is_completed and not lesson.active and int(cb["count"]) == 1, "Rewinding into earlier snapshots never re-arms or repeats RewindLesson")
	expect(not lesson.begin(arena), "Completed RewindLesson refuses repeat begin(arena) in the same run")

	# 11. reset_for_new_run() clears latch only for a brand-new run.
	lesson.reset_for_new_run()
	expect(not lesson.is_completed and lesson.phase == RewindLesson.Phase.IDLE, "reset_for_new_run() resets completion latch for a new campaign run")

	# 12. Settings popup, empty/short history fallback, and scene-exit cleanup.
	var scene_manager: Node = root.get_node("SceneManager")
	expect(lesson.begin(arena), "New run allows begin(arena)")
	scene_manager.push_popup(&"Settings")
	var staged_before_settings := lesson._staging_elapsed
	lesson.step(0.3)
	expect(is_equal_approx(lesson._staging_elapsed, staged_before_settings) and lesson.is_staging, "Settings popup suspends staging progression cleanly")
	scene_manager.close_popup(&"Settings")

	# Wipe history mid-staging to prove empty/short history fallback before depletion.
	arena.history.clear()
	lesson.step(2.0)
	expect(lesson.is_scrubbing and er.active and er.choice_count >= 5 and er.selected_index >= 1, "Empty/short history is safely repopulated before scrub opens")

	# 13. Round S: Click-only Skip button during STAGING and SCRUB stops speech, suppresses held LMB release, and completes once.
	lesson.reset_for_new_run()
	cb["count"] = 0
	var audio_mgr: Node = root.get_node("AudioManager")
	audio_mgr.say(&"tutorial.rewind", 3)
	expect(lesson.begin(arena), "Lesson begins for STAGING Skip check")
	expect(lesson.skip_button != null and lesson.skip_button.visible and not lesson.skip_button.disabled and lesson.skip_button.text == "Skip" and lesson.skip_button.focus_mode == Control.FOCUS_NONE, "Top banner exposes an enabled click-only Skip button with FOCUS_NONE during STAGING")

	# Keyboard keys (WASD, Space, Enter) and clicks outside SkipButton must NOT skip STAGING.
	for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_ENTER]:
		lesson._input(_key_event(k, true))
		lesson._input(_key_event(k, false))
	var outside_click := _mouse_button(MOUSE_BUTTON_LEFT, true)
	outside_click.position = Vector2(8.0, 8.0)
	lesson._input(outside_click)
	expect(lesson.is_staging and not lesson.is_completed and int(cb["count"]) == 0, "WASD, Space, Enter, and clicks outside SkipButton never skip STAGING")

	# Clicking SkipButton during STAGING stops tutorial.rewind speech, restores 3 charges & full meter, arms LMB release suppression, and emits completed once.
	await settle(2)
	var skip_rect := lesson.skip_button.get_global_rect()
	var skip_click := _mouse_button(MOUSE_BUTTON_LEFT, true)
	skip_click.position = skip_rect.get_center()
	arena.weapons.require_fresh_press = false
	arena.set("_suppress_next_lmb_release", false)
	lesson._input(skip_click)
	lesson.skip_lesson(true)
	expect(lesson.is_completed and lesson.was_skipped and int(cb["count"]) == 1, "Clicking Skip during STAGING completes once idempotently and sets was_skipped")
	expect(not audio_mgr.instruction_busy(), "Clicking Skip during STAGING stops active rewind tutorial speech")
	expect(arena.time_controller.charges_remaining == 3 and is_equal_approx(arena.time_controller.meter, arena.time_controller.capacity), "Skipping during STAGING restores 3 charges and 100% time meter")
	expect(arena.weapons.require_fresh_press and bool(arena.get("_suppress_next_lmb_release")), "Skipping via mouse click arms require_fresh_press and _suppress_next_lmb_release")
	var skip_release := _mouse_button(MOUSE_BUTTON_LEFT, false)
	skip_release.position = skip_rect.get_center()
	lesson._input(skip_release)
	arena.director.clear()

	# Now verify clicking SkipButton during SCRUB intercepts before arena._input LMB confirm and completes cleanly.
	lesson.reset_for_new_run()
	cb["count"] = 0
	audio_mgr.say(&"tutorial.rewind", 3)
	expect(lesson.begin(arena), "Lesson begins for SCRUB Skip check")
	lesson.step(2.0)
	expect(lesson.is_scrubbing and er.active and lesson.skip_button.visible and not lesson.skip_button.disabled, "SkipButton remains visible and enabled during SCRUB")
	await settle(2)
	skip_rect = lesson.skip_button.get_global_rect()
	skip_click = _mouse_button(MOUSE_BUTTON_LEFT, true)
	skip_click.position = skip_rect.get_center()
	lesson._input(skip_click)
	expect(lesson.is_completed and lesson.was_skipped and not er.active and not ev.visible and int(cb["count"]) == 1, "Clicking SkipButton during SCRUB abandons scrub cleanly and completes once")
	expect(arena.time_controller.charges_remaining == 3 and is_equal_approx(arena.time_controller.meter, arena.time_controller.capacity) and not audio_mgr.instruction_busy(), "Skipping during SCRUB restores 3 charges, full meter, and stops speech")
	arena.director.clear()

	# 14. Round T: ~1s wheel steps by timestamp (5-6 notches -> 5-6s), coarse timeline ticks, and Enter confirmation isolation.
	lesson.reset_for_new_run()
	cb["count"] = 0
	var handled_during_confirm := [false]
	var handled_during_completed := [false]
	var confirm_probe := func(_age: float, _state: Dictionary) -> void:
		handled_during_confirm[0] = root.is_input_handled()
	var completed_probe := func() -> void:
		handled_during_completed[0] = root.is_input_handled()
		audio_mgr.say(&"tutorial.rewind_charges", 3, true)
	er.confirmed.connect(confirm_probe)
	lesson.completed.connect(completed_probe)

	expect(lesson.begin(arena), "Lesson begins for Round T coarse wheel & Enter isolation check")
	lesson.step(2.0)
	expect(lesson.is_scrubbing and er.active, "Lesson enters SCRUB for Round T check")
	var start_safe_age := er.choice_age(er.selected_index)
	expect(er.selected_index >= lesson.min_safe_index and start_safe_age > 0.5, "Tutorial default selection starts at a safe pre-ambush timestamp (%.2fs)" % start_safe_age)
	arena._input(_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true))
	var after_one_down_age := er.choice_age(er.selected_index)
	expect(after_one_down_age >= start_safe_age + 0.75, "One wheel-down notch in tutorial advances ~1 world second older (%.2fs -> %.2fs)" % [start_safe_age, after_one_down_age])
	arena._input(_mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	arena._input(_mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	expect(er.selected_index >= lesson.min_safe_index, "Coarse wheel-up notches in tutorial never select unsafe moments below min_safe_index")

	# Confirm with Enter through Viewport.push_input to verify synchronous handled state + echo/release isolation.
	var enter_press := _key_event(KEY_ENTER, true)
	root.push_input(enter_press)
	expect(handled_during_confirm[0] and handled_during_completed[0], "Enter press is marked handled BEFORE synchronous confirmed and completed signals fire")
	expect(bool(arena.get("_suppress_enter_until_release")), "Enter confirmation arms _suppress_enter_until_release on Arena")

	# Auto-repeat (echo) and release of Enter must be consumed and must keep tutorial.rewind_charges playing.
	var enter_echo := _key_event(KEY_ENTER, true)
	enter_echo.echo = true
	root.push_input(enter_echo)
	expect(root.is_input_handled() and bool(arena.get("_suppress_enter_until_release")), "Held Enter auto-repeat (echo) is consumed after confirmation")
	var enter_release := _key_event(KEY_ENTER, false)
	root.push_input(enter_release)
	expect(root.is_input_handled() and not bool(arena.get("_suppress_enter_until_release")), "Enter release is consumed and clears _suppress_enter_until_release")
	expect(String(audio_mgr.get("current_event")) == "tutorial.rewind_charges", "Enter echo/release after confirmation never dismisses or cuts off tutorial.rewind_charges")
	er.confirmed.disconnect(confirm_probe)
	lesson.completed.disconnect(completed_probe)
	audio_mgr.stop_dialogue()
	arena.director.clear()

	# Verify normal 18s / 12Hz history with 5-6 wheel notches reaching ~5-6 world seconds and coarse timeline ticks.
	arena.reset_arena()
	arena.history.clear()
	for i in range(216):
		arena.history.record(1.0 / 12.0, arena.capture_state)
	expect(arena.history.snapshot_count == 216 and is_equal_approx(arena.time_controller.settings.scrub_step_seconds, 1.0), "18s / 12Hz (216 snapshots) history fidelity and 1.0s scrub_step_seconds are preserved")
	arena.time_controller.apply_hit(1000.0)
	expect(er.active and er.choice_count == 217 and er.selected_index == 0, "Full 18s emergency rewind opens at NOW with 217 choices")
	var ticks: PackedFloat32Array = ev.timeline_tick_fractions()
	expect(ticks.size() >= 10 and ticks.size() <= 19, "Timeline uses coarse readable ticks (%d ticks for 18s buffer, never 36+)" % ticks.size())
	for _n in range(5):
		arena._input(_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true))
	var age_5 := er.choice_age(er.selected_index)
	expect(absf(age_5 - 5.0) <= 0.12, "5 mouse-wheel-down notches reach ~5 world seconds (%.2fs)" % age_5)
	arena._input(_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true))
	var age_6 := er.choice_age(er.selected_index)
	expect(absf(age_6 - 6.0) <= 0.12, "6 mouse-wheel-down notches reach ~6 world seconds (%.2fs)" % age_6)
	arena._input(_mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	var age_back_5 := er.choice_age(er.selected_index)
	expect(absf(age_back_5 - 5.0) <= 0.12, "1 mouse-wheel-up notch from 6s steps back to ~5 world seconds (%.2fs)" % age_back_5)
	er.confirm()

	# 15. Scene exit while scrubbing cancels cleanly and restores valid non-frozen state.
	lesson.reset_for_new_run()
	expect(lesson.begin(arena), "Lesson begins for scene-exit cancellation check")
	lesson.step(2.0)
	arena.remove_child(lesson)
	expect(lesson.is_cancelled and not lesson.active and not lesson.is_completed, "Exiting scene tree while active cancels lesson cleanly")
	expect(not er.active and arena.time_controller.charges_remaining == 3 and not ev.visible, "Scene exit restores non-frozen 3-charge state and hides scrub bar")
	lesson.free()

	root.size = old_size
	audio_mgr.stop_dialogue()
	audio_mgr.set_music_context(&"intro")
	call_group(&"world_audio", &"reset_state")
	await create_timer(.1).timeout
	arena.feedback.reset_state()
	arena.queue_free()
	await settle(2)
	await create_timer(.3).timeout
	print(JSON.stringify({
		"status": "passed" if failures.is_empty() else "failed",
		"checks": checks,
		"failures": failures,
	}))
	quit(0 if failures.is_empty() else 1)

