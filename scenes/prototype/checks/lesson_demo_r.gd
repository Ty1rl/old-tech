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
		expect(tutorial.demo_busy and not tutorial.can_dismiss_normally() and not tutorial.practice_button.disabled and tutorial.practice_button.text == "Skip" and tutorial.practice_button.focus_mode == Control.FOCUS_NONE, "Tutorial overlay exposes enabled click-only Skip button with FOCUS_NONE while %s demo is running" % String(id))
		expect(arena.player.camera.position.distance_to(saved_cam_pos) > 1.0 and arena.player.camera.position.y < saved_cam_pos.y, "Camera moves closer to frame %s demonstration clearly" % String(id))

		var saw_sustained_beam := false
		var saw_sustained_ring_preview := false
		var saw_active_cone := false
		var saw_slow_window := false
		var saw_overhead_label := false
		var saw_blue_trace := false
		var saw_yellow_phase_without_blue_trace := false
		var saw_yellow_enemy := false

		var ticks := 0
		while demo.active and ticks < 260:
			demo.step(1.0 / 30.0)
			tutorial._process(1.0 / 30.0)
			ticks += 1

			for enemy in demo.demo_enemies:
				if _any_enemy_label_visible(enemy):
					saw_overhead_label = true
				if is_instance_valid(enemy) and enemy.get("kind") == &"yellow":
					saw_yellow_enemy = true

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
		expect(not tutorial.blocking and tutorial.practicing, "Demo %s hands off automatically to practice without a Try it step" % String(id))
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
				expect(saw_active_cone and not saw_blue_trace and not saw_yellow_enemy, "Heat demo renders sustained orange heat cone without any cutter trace or yellow enemy")
				expect(bool(demo.last_summary.get("heat_knockback_seen", false)) and float(demo.last_summary.get("heat_knockback_distance", 0.0)) >= 0.65, "Heat demo visibly knocks back the orange enemy before stripping its armor plate")
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

	# 1b. Verify standalone time_meter demo AND automatic time_meter pre-stage before shot
	tutorial.reset_run()
	demo.reset_run()
	mock_audio.stop_dialogue()
	arena.director.clear()
	expect(LessonDemo.handles(&"time_meter"), "LessonDemo.handles supports standalone time_meter lesson")
	mock_audio.play_event("tutorial.time_meter")
	expect(demo.begin(arena, &"time_meter", tutorial), "Standalone time_meter demo starts cleanly")
	expect(tutorial.body_label.text == "Taking damage, slowing time, and repairing drain your reserve. Find moments to let it recharge.", "Standalone time_meter lesson uses exact spoken reserve caption")
	var tm_min_meter: float = float(arena.time_controller.meter)
	var tm_max_enemies := 0
	for _i in range(95):
		demo.step(1.0 / 30.0)
		tutorial._process(1.0 / 30.0)
		tm_min_meter = minf(tm_min_meter, float(arena.time_controller.meter))
		tm_max_enemies = maxi(tm_max_enemies, demo.demo_enemies.size())
	mock_audio.finish_current(false)
	expect(not demo.active and tm_max_enemies >= 2 and int(demo.last_summary.get("time_meter_hits", 0)) >= 2 and tm_min_meter <= arena.time_controller.capacity * 0.6, "Standalone time_meter demo stages multiple enemies hitting player and visibly drains purple reserve bar")
	expect(is_equal_approx(arena.time_controller.meter, arena.time_controller.capacity) and arena.time_controller.charges_remaining == 3, "Standalone time_meter demo restores full time reserve and all 3 charges on completion")
	expect(tutorial.is_learned(&"time_meter") and demo.is_demo_learned(&"time_meter", tutorial), "Standalone time_meter demo marks time_meter learned")

	# 2. Speech handoff + automatic time_meter pre-stage before yellow shot when tutorial.shot + tutorial.time_meter are queued
	tutorial.reset_run()
	demo.reset_run()
	mock_audio.stop_dialogue()
	var ready_events: Array[StringName] = []
	var on_ready := func(done_id: StringName) -> void: ready_events.append(done_id)
	demo.ready_for_practice.connect(on_ready)

	mock_audio.play_event("tutorial.shot")
	mock_audio.play_event("tutorial.time_meter")
	expect(mock_audio.instruction_busy(), "Mock AudioManager reports instruction_busy() while tutorial.shot + tutorial.time_meter are queued")
	expect(demo.begin(arena, &"shot", tutorial), "Shot demo starts with automatic time_meter pre-stage when time_meter is unlearned")
	expect(demo.substage == &"time_meter", "Shot demo begins in time_meter pre-stage when time_meter is unlearned")

	var prestage_min_meter: float = float(arena.time_controller.meter)
	var saw_shot_substage := false
	var saw_time_meter_caption := false
	for i in range(180):
		demo.step(1.0 / 30.0)
		tutorial._process(1.0 / 30.0)
		if demo.substage == &"time_meter":
			prestage_min_meter = minf(prestage_min_meter, float(arena.time_controller.meter))
		elif demo.substage == &"shot" and not saw_shot_substage:
			saw_shot_substage = true
			expect(is_equal_approx(arena.time_controller.meter, arena.time_controller.capacity), "Time reserve is restored to 100% before the yellow shot demo begins")
		if i == 80:
			# Advance from tutorial.shot to queued tutorial.time_meter speech
			mock_audio.finish_current(false)
		if tutorial.body_label.text == "Taking damage, slowing time, and repairing drain your reserve. Find moments to let it recharge.":
			saw_time_meter_caption = true

	expect(prestage_min_meter <= arena.time_controller.capacity * 0.6 and saw_shot_substage, "Automatic time_meter pre-stage visibly drains reserve from multiple enemy hits then transitions to yellow shot demo")
	expect(saw_time_meter_caption, "Tutorial card displays exact time_meter caption while tutorial.time_meter speech is active")
	expect(demo.is_visual_pass_completed(), "Pre-staged time_meter + shot visual pass completes within 180 ticks")
	expect(demo.active and ready_events.is_empty(), "Demo stays active and does NOT emit ready_for_practice while tutorial.time_meter speech is still busy")
	expect(not tutorial.can_dismiss_normally() and not tutorial.practice_button.disabled and tutorial.practice_button.text == "Skip", "Skip button remains enabled with text 'Skip' while waiting on speech")

	# Finish tutorial.time_meter; handoff must occur immediately and automatically without a 'Try it' confirmation step
	mock_audio.finish_current(false)
	expect(not mock_audio.instruction_busy() and not demo.active and ready_events == [&"shot"], "Demo completes and emits ready_for_practice immediately when queued tutorial speech finishes")
	expect(not tutorial.blocking and tutorial.practicing, "Tutorial transitions automatically to non-blocking practice as soon as both demo and speech finish")
	expect(is_equal_approx(arena.time_controller.meter, arena.time_controller.capacity) and arena.time_controller.charges_remaining == 3, "Player enters shot practice with full reserve and all 3 charges")

	# 3. Speech finishes before visual demo pass: must still wait for visual demonstration to finish, then auto-handoff
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
	expect(not demo.active and ready_events == [&"charge"] and not tutorial.blocking and tutorial.practicing, "Charge demo emits ready_for_practice and auto-transitions to practice once visual pass completes")

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
	expect(not demo.active and ready_events == [&"cut"] and not tutorial.blocking and tutorial.practicing, "Cut demo completes and auto-transitions to practice when audio is muted")
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

	# 6. Click-only Skip contract: WASD, Space, Enter, and clicks outside Skip button never skip; clicking Skip stops speech, finishes once, and suppresses held LMB release
	tutorial.reset_run()
	demo.reset_run()
	ready_events.clear()
	tutorial.complete_lesson(&"time_meter")
	mock_audio.play_event("tutorial.shot")
	expect(demo.begin(arena, &"shot", tutorial), "Shot demo starts for click-only Skip test")
	await _settle(2)

	for keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_ENTER]:
		var k_press := InputEventKey.new()
		k_press.pressed = true
		k_press.keycode = keycode
		k_press.physical_keycode = keycode
		tutorial._input(k_press)
		var k_rel := InputEventKey.new()
		k_rel.pressed = false
		k_rel.keycode = keycode
		k_rel.physical_keycode = keycode
		tutorial._input(k_rel)

	var outside_lmb := InputEventMouseButton.new()
	outside_lmb.button_index = MOUSE_BUTTON_LEFT
	outside_lmb.pressed = true
	outside_lmb.position = Vector2(12.0, 12.0)
	tutorial._input(outside_lmb)
	var outside_lmb_rel := InputEventMouseButton.new()
	outside_lmb_rel.button_index = MOUSE_BUTTON_LEFT
	outside_lmb_rel.pressed = false
	outside_lmb_rel.position = Vector2(12.0, 12.0)
	tutorial._input(outside_lmb_rel)

	expect(demo.active and tutorial.blocking and not tutorial.practicing and mock_audio.instruction_busy(), "WASD, Space, Enter, and clicks outside Skip button never skip or dismiss tutorial")

	# Now click directly on the Skip button (practice_button) while demo and speech are busy
	arena.weapons.require_fresh_press = false
	arena.set("_suppress_next_lmb_release", false)
	var skip_center: Vector2 = tutorial.practice_button.get_global_rect().get_center()
	var skip_press := InputEventMouseButton.new()
	skip_press.button_index = MOUSE_BUTTON_LEFT
	skip_press.pressed = true
	skip_press.position = skip_center
	tutorial._input(skip_press)
	# Duplicate skip invocation must be idempotent
	tutorial.skip_active_lesson(true)
	demo.skip_to_practice()

	expect(not demo.active and ready_events == [&"shot"] and not tutorial.blocking and tutorial.practicing, "Clicking Skip button finishes demo once idempotently and hands off to practice")
	expect(not mock_audio.instruction_busy(), "Clicking Skip button stops active segment speech immediately")
	expect(arena.weapons.require_fresh_press and bool(arena.get("_suppress_next_lmb_release")), "Clicking Skip arms weapon fresh-press and release suppression so releasing LMB never fires a weapon")

	var skip_release := InputEventMouseButton.new()
	skip_release.button_index = MOUSE_BUTTON_LEFT
	skip_release.pressed = false
	skip_release.position = skip_center
	tutorial._input(skip_release)

	# 7. Card-only repair lesson: auto-handoff when speech finishes AND click-only Skip while speech is active
	tutorial.reset_run()
	mock_audio.stop_dialogue()
	mock_audio.play_event("tutorial.repair")
	var repair_targets: Array[Vector3] = [Vector3(0.0, 1.0, -4.0)]
	tutorial.show_known_lesson(&"repair", repair_targets)
	expect(tutorial.blocking and not tutorial.practicing and tutorial.practice_button.text == "Skip" and not tutorial.practice_button.disabled, "Card-only repair lesson shows enabled click-only Skip button")
	mock_audio.finish_current(false)
	tutorial._process(1.0 / 30.0)
	expect(not tutorial.blocking and tutorial.practicing, "Card-only repair lesson auto-transitions to practice when speech finishes")

	tutorial.reset_run()
	mock_audio.play_event("tutorial.repair")
	tutorial.show_known_lesson(&"repair", repair_targets)
	tutorial.skip_active_lesson(true)
	expect(not tutorial.blocking and tutorial.practicing and not mock_audio.instruction_busy(), "Clicking Skip on card-only repair lesson stops speech and transitions to practice")

	# 8. Detached-scene cancellation reproduction (errors.txt): removing arena while demo and speech are active must not touch world transforms outside the tree
	tutorial.reset_run()
	demo.reset_run()
	ready_events.clear()
	var cancel_events: Array[StringName] = []
	var on_cancelled := func(canc_id: StringName) -> void: cancel_events.append(canc_id)
	demo.demo_cancelled.connect(on_cancelled)
	mock_audio.play_event("tutorial.slow")
	expect(demo.begin(arena, &"slow", tutorial), "Slow demo starts for detached-scene teardown check")
	for i in range(15):
		demo.step(1.0 / 30.0)
	# Simulate SceneManager._change removing arena from root while speech_finished(event, true) fires during tree_exiting
	arena.tree_exiting.connect(func() -> void: mock_audio.stop_dialogue(), CONNECT_ONE_SHOT)
	root.remove_child(arena)
	expect(not demo.active and cancel_events == [&"slow"] and ready_events.is_empty(), "Detached-scene removal cancels demo once without emitting ready_for_practice or touching outside-tree transforms")
	root.add_child(arena)
	current_scene = arena
	await _settle(2)
	demo.demo_cancelled.disconnect(on_cancelled)

	# 9. Verify compatibility with real AudioManager autoload
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
