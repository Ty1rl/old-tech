extends SceneTree

const ToolStyle = preload("res://scenes/prototype/tool_style.gd")


class MockSpeechAudioManager extends Node:
	signal speech_finished(event: String, interrupted: bool)

	var current_event: String = ""
	var queue: Array[String] = []
	var muted: bool = false

	func play_event(event: String, _context: Dictionary = {}) -> void:
		if muted:
			return
		if event.begins_with("tutorial.") or event.begins_with("story.") or event.begins_with("repair."):
			if current_event.is_empty():
				current_event = event
			else:
				queue.append(event)

	func is_speaking() -> bool:
		return not current_event.is_empty()

	func current_speech_event() -> String:
		return current_event

	func instruction_busy() -> bool:
		if current_event.begins_with("tutorial."):
			return true
		for queued in queue:
			if queued.begins_with("tutorial."):
				return true
		return false

	func finish_current(interrupted: bool = false) -> void:
		if current_event.is_empty():
			return
		var finished_ev := current_event
		current_event = ""
		if interrupted:
			queue.clear()
		elif not queue.is_empty():
			current_event = String(queue.pop_front())
		speech_finished.emit(finished_ev, interrupted)

	func stop_dialogue() -> void:
		queue.clear()
		if not current_event.is_empty():
			var prev := current_event
			current_event = ""
			speech_finished.emit(prev, true)


var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _settle(frames: int = 3) -> void:
	for i in range(frames):
		await process_frame


func _any_enemy_label_visible(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	var vroot := enemy.get("visual_root") as Node
	if is_instance_valid(vroot):
		var vinst := vroot.get("instruction") as Node3D
		if is_instance_valid(vinst) and vinst.visible:
			return true
	var pv := enemy.get("part_visual") as Node
	if is_instance_valid(pv):
		var pinst := pv.get("instruction") as Node3D
		if is_instance_valid(pinst) and pinst.visible:
			return true
	var patv := enemy.get("pattern_visual") as Node
	if is_instance_valid(patv):
		var cdown := patv.get("countdown") as Node3D
		if is_instance_valid(cdown) and cdown.visible:
			return true
	return false


func _run() -> void:
	create_timer(45.0, true).timeout.connect(func() -> void:
		failures.append("lesson_demo_r watchdog expired")
		print(JSON.stringify({"status": "failed", "checks": checks, "failures": failures}))
		quit(1)
	)

	var state := root.get_node("GameState")
	var scenes := root.get_node("SceneManager")
	var real_audio := root.get_node_or_null("AudioManager")
	var saved_prefs: Dictionary = state.preferences()
	state.set_setting("tutorial", true)
	scenes.fade_duration = 0.0

	var tutorial_packed: PackedScene = load("res://scenes/ui/tutorial.tscn")
	var demo_packed: PackedScene = load("res://scenes/tutorial/lesson_demo.tscn")
	expect(tutorial_packed != null and demo_packed != null, "Tutorial and LessonDemo scenes load cleanly")

	var arena: Node3D = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await _settle(6)
	arena.set_physics_process(false)
	arena.set_process(false)

	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 60
	arena.add_child(ui_layer)
	var tutorial: Control = tutorial_packed.instantiate() as Control
	ui_layer.add_child(tutorial)
	tutorial.setup(arena.player.camera)

	var demo: LessonDemo = demo_packed.instantiate() as LessonDemo
	arena.add_child(demo)
	await _settle(2)

	var mock_audio := MockSpeechAudioManager.new()
	arena.add_child(mock_audio)
	tutorial.audio_manager_override = mock_audio
	demo.audio_manager_override = mock_audio

	# 1. Verify all 9 visible action demonstrations: framing, sustained visuals, overhead label suppression, and accurate gesture overlays
	var saved_cam_pos: Vector3 = arena.player.camera.position
	for id: StringName in LessonDemo.SUPPORTED_LESSONS:
		tutorial.reset_run()
		demo.reset_run()
		mock_audio.stop_dialogue()
		arena.director.clear()

		var started := demo.begin(arena, id, tutorial)
		expect(started and demo.active and demo.lesson_id == id, "LessonDemo starts for %s" % String(id))
		expect(tutorial.demo_busy and not tutorial.can_dismiss_normally() and tutorial.practice_button.disabled, "Tutorial overlay blocks premature dismissal while %s demo is running" % String(id))
		expect(arena.player.camera.position.distance_to(saved_cam_pos) > 1.0 and arena.player.camera.position.y < saved_cam_pos.y, "Camera moves closer to frame %s demonstration clearly" % String(id))

		var saw_sustained_beam := false
		var saw_sustained_ring_preview := false
		var saw_active_cone := false
		var saw_slow_window := false
		var saw_overhead_label := false
		var saw_blue_trace := false
		var saw_yellow_phase_without_blue_trace := false

		var ticks := 0
		while demo.active and ticks < 260:
			demo.step(1.0 / 30.0)
			tutorial._process(1.0 / 30.0)
			ticks += 1

			for enemy in demo.demo_enemies:
				if _any_enemy_label_visible(enemy):
					saw_overhead_label = true

			if arena.weapons.flash.flash_timer > 0.05 and arena.weapons.flash.end_point != Vector3.ZERO:
				saw_sustained_beam = true
			if arena.weapons.ring.drawing and arena.weapons.ring.preview_points.size() >= 3:
				saw_sustained_ring_preview = true
			if arena.weapons.bellows.active:
				saw_active_cone = true
			if arena.time_controller.world_scale <= 0.45:
				saw_slow_window = true
			if not tutorial.ghost.is_empty():
				saw_blue_trace = true
			elif id in [&"opening", &"loop", &"zigzag"] and arena.weapons.selected_tool == 2:
				saw_yellow_phase_without_blue_trace = true

		expect(not demo.active and bool(demo.last_summary.get("completed", false)) and bool(demo.last_summary.get("target_killed", false)), "Demo %s completes and kills target" % String(id))
		expect(not saw_overhead_label, "Demo %s hides floating overhead enemy action labels so instructions stay in the tutorial overlay" % String(id))
		expect(arena.player.camera.position.distance_to(saved_cam_pos) < 0.01, "Camera position restores cleanly after %s demo" % String(id))

		match id:
			&"shot":
				expect(saw_sustained_beam and not saw_blue_trace, "Shot demo renders sustained yellow flash beam without any cutter trace")
			&"charge":
				expect(saw_sustained_beam and not saw_blue_trace and int(demo.last_summary.get("pierce_kills", 0)) >= 2, "Charge demo renders sustained piercing beam without any cutter trace")
			&"cut":
				expect(saw_sustained_ring_preview and saw_blue_trace, "Cut demo renders sustained blue ring cutter path and blue overlay gesture")
			&"heat":
				expect(saw_active_cone and not saw_blue_trace, "Heat demo renders sustained orange heat cone without any cutter trace")
			&"slow":
				expect(saw_slow_window and saw_sustained_beam and not saw_blue_trace, "Slow demo slows world time and renders visible yellow shot during slow window")
			&"opening":
				expect(saw_sustained_ring_preview and saw_sustained_beam and saw_blue_trace and saw_yellow_phase_without_blue_trace, "Opening demo shows blue trace during cut phase then switches cleanly to yellow shot phase without cutter trace")
			&"pair":
				expect(saw_sustained_beam and not saw_blue_trace, "Pair demo renders sustained yellow shots across both valves without cutter trace")
			&"loop":
				expect(saw_sustained_ring_preview and saw_sustained_beam and saw_blue_trace and saw_yellow_phase_without_blue_trace, "Loop demo shows blue loop trace during cut phase then switches to charged yellow finish")
			&"zigzag":
				expect(saw_sustained_ring_preview and saw_sustained_beam and saw_blue_trace and saw_yellow_phase_without_blue_trace, "Zigzag demo shows blue zigzag trace during cut phase then switches to charged yellow finish")

	# 2. Speech handoff contract: demo finishes before speech, repeats while speech is busy, and hands off immediately when speech finishes
	tutorial.reset_run()
	demo.reset_run()
	mock_audio.stop_dialogue()
	var ready_events: Array[StringName] = []
	var on_ready := func(done_id: StringName) -> void: ready_events.append(done_id)
	demo.ready_for_practice.connect(on_ready)

	mock_audio.play_event("tutorial.shot")
	expect(mock_audio.instruction_busy(), "Mock AudioManager reports instruction_busy() while tutorial.shot is playing")
	expect(demo.begin(arena, &"shot", tutorial), "Shot demo starts while tutorial.shot speech is active")

	for i in range(95):
		demo.step(1.0 / 30.0)
		tutorial._process(1.0 / 30.0)

	expect(demo.is_visual_pass_completed(), "Shot visual pass completes within 95 ticks")
	expect(demo.active and ready_events.is_empty(), "Shot demo stays active and does NOT emit ready_for_practice while tutorial.shot speech is still busy")
	expect(not tutorial.can_dismiss_normally() and tutorial.practice_button.disabled and tutorial.practice_button.text == "Listening...", "Tutorial button shows 'Listening...' and blocks normal dismissal while waiting on speech")

	# Queue follow-up tutorial.time_meter speech and finish tutorial.shot; demo must keep waiting until queued tutorial speech also finishes
	mock_audio.play_event("tutorial.time_meter")
	mock_audio.finish_current(false)
	expect(mock_audio.current_speech_event() == "tutorial.time_meter" and mock_audio.instruction_busy(), "Finishing tutorial.shot advances to queued tutorial.time_meter with instruction_busy() still true")
	demo.step(1.0 / 30.0)
	expect(demo.active and ready_events.is_empty(), "Demo continues waiting while queued tutorial.time_meter speech is still playing")

	# Now finish tutorial.time_meter; handoff must occur immediately via speech_finished without arbitrary extra delay
	mock_audio.finish_current(false)
	expect(not mock_audio.instruction_busy() and not demo.active and ready_events == [&"shot"], "Demo completes and emits ready_for_practice immediately when queued tutorial speech finishes")
	expect(not tutorial.blocking and tutorial.practicing, "Tutorial transitions to non-blocking practice as soon as both demo and speech finish")

	# 3. Speech finishes before visual demo pass: must still wait for visual demonstration to finish
	tutorial.reset_run()
	demo.reset_run()
	ready_events.clear()
	mock_audio.play_event("tutorial.charge")
	expect(demo.begin(arena, &"charge", tutorial), "Charge demo begins with tutorial.charge speech")
	for i in range(15):
		demo.step(1.0 / 30.0)
	mock_audio.finish_current(false)
	expect(not mock_audio.instruction_busy() and not demo.is_visual_pass_completed() and demo.active and ready_events.is_empty(), "When speech finishes early, demo stays active until visual pass completes")
	var rem_ticks := 0
	while demo.active and rem_ticks < 160:
		demo.step(1.0 / 30.0)
		rem_ticks += 1
	expect(not demo.active and ready_events == [&"charge"], "Charge demo emits ready_for_practice once visual pass completes")

	# 4. Muted / missing audio fallback: completes cleanly without lockup
	tutorial.reset_run()
	demo.reset_run()
	ready_events.clear()
	mock_audio.muted = true
	mock_audio.play_event("tutorial.cut")
	expect(not mock_audio.instruction_busy(), "Muted audio manager does not report instruction_busy()")
	expect(demo.begin(arena, &"cut", tutorial), "Cut demo begins when audio is muted")
	var cut_ticks := 0
	while demo.active and cut_ticks < 160:
		demo.step(1.0 / 30.0)
		cut_ticks += 1
	expect(not demo.active and ready_events == [&"cut"], "Cut demo completes normally when audio is muted")
	mock_audio.muted = false

	# 5. Cancel while waiting on speech and non-replay on retry
	tutorial.reset_run()
	demo.reset_run()
	ready_events.clear()
	mock_audio.play_event("tutorial.heat")
	expect(demo.begin(arena, &"heat", tutorial), "Heat demo begins for cancel-during-speech check")
	for i in range(100):
		demo.step(1.0 / 30.0)
	expect(demo.active and demo.is_visual_pass_completed(), "Heat demo is waiting on speech after visual pass")
	demo.cancel()
	mock_audio.stop_dialogue()
	expect(not demo.active and ready_events.is_empty(), "Cancelling demo while waiting on speech leaves no stuck waiters or false ready_for_practice emissions")
	tutorial.request_practice()
	tutorial.complete_lesson(&"heat")
	expect(not demo.begin(arena, &"heat", tutorial), "Completed lesson does not replay demonstration on retry")

	# 6. Held-input carryover blocking and clean click/Space transition with release suppression
	tutorial.reset_run()
	demo.reset_run()
	ready_events.clear()
	mock_audio.play_event("tutorial.shot")
	expect(demo.begin(arena, &"shot", tutorial), "Shot demo starts for input carryover test")

	# Simulate player holding W, Space, and LMB during active demo/speech
	var w_press := InputEventKey.new()
	w_press.pressed = true
	w_press.keycode = KEY_W
	w_press.physical_keycode = KEY_W
	tutorial._input(w_press)

	var space_press := InputEventKey.new()
	space_press.pressed = true
	space_press.keycode = KEY_SPACE
	space_press.physical_keycode = KEY_SPACE
	tutorial._input(space_press)

	var lmb_press := InputEventMouseButton.new()
	lmb_press.button_index = MOUSE_BUTTON_LEFT
	lmb_press.pressed = true
	tutorial._input(lmb_press)
	tutorial._on_practice_button_pressed()

	expect(demo.active and tutorial.blocking and not tutorial.practicing, "Held W, Space, LMB, and button press during busy demo/speech do not skip or dismiss tutorial")

	# Now test blocking card after demo/speech are ready: held inputs from busy state must not dismiss on release, while fresh press transitions and suppresses release fire
	demo.cancel()
	mock_audio.stop_dialogue()
	tutorial.reset_run()
	var test_targets: Array[Vector3] = [Vector3(0.0, 1.0, -4.0)]
	tutorial.show_known_lesson(&"shot", test_targets)
	tutorial.set_demo_busy(true)
	tutorial._input(lmb_press)
	tutorial._input(space_press)
	tutorial.set_demo_busy(false)
	expect(tutorial.can_dismiss_normally() and tutorial.blocking, "Card is now ready for normal dismissal")

	var lmb_release := InputEventMouseButton.new()
	lmb_release.button_index = MOUSE_BUTTON_LEFT
	lmb_release.pressed = false
	tutorial._input(lmb_release)
	var space_release := InputEventKey.new()
	space_release.pressed = false
	space_release.keycode = KEY_SPACE
	space_release.physical_keycode = KEY_SPACE
	tutorial._input(space_release)
	expect(tutorial.blocking and not tutorial.practicing, "Releasing LMB or Space that was held during busy state does not dismiss tutorial")

	# Fresh LMB press when ready transitions to practice and suppresses accidental weapon fire on release
	arena.weapons.require_fresh_press = false
	arena.set("_suppress_next_lmb_release", false)
	tutorial._input(lmb_press)
	expect(not tutorial.blocking and tutorial.practicing, "Fresh LMB press once demo and speech are finished transitions cleanly to practice")
	expect(arena.weapons.require_fresh_press and bool(arena.get("_suppress_next_lmb_release")), "Dismissing via click arms weapon fresh-press and release suppression so dismissing never fires a weapon")
	tutorial._input(lmb_release)

	# 7. Verify compatibility with real AudioManager autoload
	tutorial.audio_manager_override = null
	demo.audio_manager_override = null
	if real_audio != null and real_audio.has_method("stop_dialogue"):
		real_audio.call("stop_dialogue")

	demo.ready_for_practice.disconnect(on_ready)
	for key in saved_prefs:
		state.set_setting(key, saved_prefs[key])
	real_audio.set_music_context(&"intro")
	call_group(&"world_audio", &"reset_state")
	arena.queue_free()
	await _settle(2)
	await create_timer(0.3, true).timeout

	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
