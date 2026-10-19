extends SceneTree

const ToolStyle = preload("res://scenes/prototype/tool_style.gd")

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


func _run() -> void:
	create_timer(30.0, true).timeout.connect(func() -> void:
		failures.append("lesson_demo_p watchdog expired")
		print(JSON.stringify({"status": "failed", "checks": checks, "failures": failures}))
		quit(1)
	)

	var state := root.get_node("GameState")
	var scenes := root.get_node("SceneManager")
	var saved_prefs: Dictionary = state.preferences()
	state.set_setting("tutorial", true)
	scenes.fade_duration = 0.0

	# 1. Verify authored scenes and UI hierarchy
	var tutorial_packed: PackedScene = load("res://scenes/ui/tutorial.tscn")
	var demo_packed: PackedScene = load("res://scenes/tutorial/lesson_demo.tscn")
	expect(tutorial_packed != null, "scenes/ui/tutorial.tscn loads cleanly")
	expect(demo_packed != null, "scenes/tutorial/lesson_demo.tscn loads cleanly")

	var arena: Node3D = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await _settle(6)
	arena.set_physics_process(false)
	arena.set_process(false)

	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 60
	arena.add_child(ui_layer)
	var TutorialScript: Script = load("res://scenes/ui/tutorial.gd")
	var tutorial: Control = tutorial_packed.instantiate() as Control
	ui_layer.add_child(tutorial)
	tutorial.setup(arena.player.camera)

	var demo: LessonDemo = demo_packed.instantiate() as LessonDemo
	arena.add_child(demo)
	await _settle(2)

	expect(tutorial != null and demo != null, "Authored Tutorial and LessonDemo instantiate cleanly")
	expect(tutorial.get_node_or_null("Card") == tutorial.card, "Tutorial binds authored Card PanelContainer")
	expect(tutorial.get_node_or_null("Card/Column/StateLabel") == tutorial.state_label, "Tutorial binds authored StateLabel")
	expect(tutorial.get_node_or_null("Card/Column/HeadingLabel") == tutorial.heading, "Tutorial binds authored HeadingLabel")
	expect(tutorial.get_node_or_null("Card/Column/BodyLabel") == tutorial.body_label, "Tutorial binds authored BodyLabel")
	expect(tutorial.get_node_or_null("Card/Column/PracticeButton") == tutorial.practice_button, "Tutorial binds authored PracticeButton")

	# 2. Verify imperative verbs, tool colors, and blue-only drawing traces
	var expected_headings := {
		"shot": "Click to shoot",
		"charge": "Hold, then release",
		"cut": "Hold, draw, release",
		"heat": "Aim and hold",
		"slow": "Hold Space",
		"opening": "Cut or heat, then shoot",
		"pair": "Click A, then B",
		"loop": "Hold, draw, release",
		"zigzag": "Hold, draw, release",
	}
	var sample_targets: Array[Vector3] = [Vector3(-1.0, 1.0, -5.5), Vector3(1.0, 1.0, -5.5)]
	for key in expected_headings:
		var id := StringName(key)
		tutorial.reset_run()
		tutorial.show_known_lesson(id, sample_targets)
		tutorial._process(0.05)
		expect(tutorial.heading.text == expected_headings[key], "Imperative heading for %s is '%s'" % [key, expected_headings[key]])
		var is_draw: bool = bool(TutorialScript.is_drawing_lesson(id))
		expect(not tutorial.ghost.is_empty() if is_draw else tutorial.ghost.is_empty(), "Blue drawing line only appears on drawing lessons (%s)" % key)
		expect(tutorial.accent != ToolStyle.EXIT, "Lesson %s never uses green exit color for weapon/action indicator" % key)
		expect(tutorial.card.size.y > 60.0 and tutorial.card.size.y <= 260.0 and tutorial.card.size.y <= tutorial.size.y * 0.35, "Lesson %s card stays compact and never stretches vertically (got %s)" % [key, str(tutorial.card.size)])
	tutorial.reset_run()

	# 3. Verify all 9 real action demonstrations and complete run-state isolation
	for id: StringName in LessonDemo.SUPPORTED_LESSONS:
		tutorial.reset_run()
		demo.reset_run()
		arena.director.clear()
		var practice_specimen: Node3D = arena.director.spawn(&"blue", Vector3(2.5, 0.0, -6.0))
		var specimen_id := int(practice_specimen.rewind_id)
		var specimen_hp := float(practice_specimen.health)

		arena.equipment.set_training_protection([&"beam"])
		arena.equipment.restore_tool(&"ring", 1.0)
		arena.equipment.restore_tool(&"beam", 1.0)
		arena.equipment.restore_tool(&"cone", 1.0)
		arena.equipment.spend(&"ring", 4.0)
		arena.equipment.set_training_protection([])
		arena.equipment.spend(&"beam", 12.0)
		arena.equipment.spend(&"cone", 5.0)
		arena.equipment.set_training_protection([&"beam"])
		var ring_before: float = float(arena.equipment.remaining(&"ring"))
		var beam_before: float = float(arena.equipment.remaining(&"beam"))
		var cone_before: float = float(arena.equipment.remaining(&"cone"))

		var two_tools: Array[int] = [2, 3]
		arena.weapons.set_loadout(two_tools, 2)
		arena.player.position = Vector3(1.25, 0.55, 2.0)
		arena.time_controller.set_capabilities(false, false)
		arena.time_controller.set("_meter", 64.0)
		arena.time_controller.set("_charges", 2)
		arena.history.clear()
		arena.history.seed_checkpoint(arena.capture_state())
		var snap_count_before: int = int(arena.history.snapshot_count)

		var ready_signals: Array[StringName] = []
		var completed_signals: Array[StringName] = []
		var on_ready := func(done_id: StringName) -> void: ready_signals.append(done_id)
		var on_completed := func(done_id: StringName, _sum: Dictionary) -> void: completed_signals.append(done_id)
		demo.ready_for_practice.connect(on_ready)
		demo.demo_completed.connect(on_completed)

		var started := demo.begin(arena, id, tutorial)
		expect(started and demo.active and demo.lesson_id == id, "LessonDemo starts for %s" % String(id))
		expect(tutorial.visible and tutorial.blocking and tutorial.active_id == id, "TutorialOverlay is shown and blocking while %s demo starts" % String(id))

		var ticks := 0
		while demo.active and ticks < 240:
			demo.step(1.0 / 30.0)
			tutorial._process(1.0 / 30.0)
			ticks += 1

		expect(not demo.active and completed_signals == [id] and ready_signals == [id], "Demo %s completes and emits ready_for_practice exactly once" % String(id))
		expect(not tutorial.blocking and tutorial.practicing, "TutorialOverlay transitions cleanly to practice when %s demo completes" % String(id))

		var summary := demo.last_summary
		expect(bool(summary.get("completed", false)) and bool(summary.get("target_killed", false)) and bool(summary.get("isolated_restore_verified", false)), "Demo %s summary records real target completion and isolated restore" % String(id))

		match id:
			&"shot":
				expect(bool(summary.get("shot_fired", false)) and summary.get("tools_used") == [2], "Shot demo fires yellow FocusedFlash and kills target")
			&"charge":
				expect(bool(summary.get("charged_shot_fired", false)) and float(summary.get("max_charge", 0.0)) >= 1.0 and bool(summary.get("pierced", false)) and int(summary.get("pierce_kills", 0)) >= 2, "Charge demo charges to 100% and pierces two aligned yellow targets")
			&"cut":
				expect(bool(summary.get("ring_drawn", false)) and bool(summary.get("ring_launched", false)) and bool(summary.get("cable_cut", false)), "Cut demo draws and launches blue RingCutter across cable")
			&"heat":
				expect(bool(summary.get("cone_held", false)) and bool(summary.get("plate_broken", false)), "Heat demo holds orange HeatBellows until armor plate breaks")
			&"slow":
				expect(bool(summary.get("slow_engaged", false)) and float(summary.get("min_world_scale", 1.0)) <= 0.45 and bool(summary.get("shot_during_slow", false)) and bool(summary.get("slow_resumed", false)) and float(summary.get("max_world_scale_after_slow", 0.0)) >= 0.85, "Slow demo slows world time, shoots while slowed, and resumes full speed")
			&"opening":
				expect(bool(summary.get("ring_drawn", false)) and bool(summary.get("cable_cut", false)) and bool(summary.get("opened_before_finish", false)) and bool(summary.get("yellow_finished_after_open", false)) and summary.get("tools_used") == [1, 2], "Opening demo cuts blue link with tool 1 then switches to tool 2 to finish yellow core")
			&"pair":
				expect(bool(summary.get("opened_before_finish", false)) and bool(summary.get("yellow_finished_after_open", false)) and summary.get("tools_used") == [2], "Pair demo shoots valve A then valve B with tool 2")
			&"loop":
				expect(bool(summary.get("ring_drawn", false)) and bool(summary.get("cable_cut", false)) and bool(summary.get("opened_before_finish", false)) and bool(summary.get("charged_shot_fired", false)) and bool(summary.get("yellow_finished_after_open", false)) and summary.get("tools_used") == [1, 2], "Loop demo cuts all blue supports with tool 1 then finishes yellow core with charged tool 2")
			&"zigzag":
				expect(bool(summary.get("ring_drawn", false)) and bool(summary.get("cable_cut", false)) and bool(summary.get("opened_before_finish", false)) and bool(summary.get("charged_shot_fired", false)) and bool(summary.get("yellow_finished_after_open", false)) and summary.get("tools_used") == [1, 2], "Zigzag demo cuts all blue spans with tool 1 then finishes yellow core with charged tool 2")

		# Verify isolation of player run state
		expect(is_equal_approx(arena.equipment.remaining(&"ring"), ring_before) and is_equal_approx(arena.equipment.remaining(&"beam"), beam_before) and is_equal_approx(arena.equipment.remaining(&"cone"), cone_before), "Demo %s does not spend real equipment condition" % String(id))
		expect(arena.equipment.training_protection == [&"beam"], "Demo %s preserves equipment training_protection policy" % String(id))
		expect(is_equal_approx(arena.time_controller.meter, 64.0) and arena.time_controller.charges_remaining == 2 and not arena.time_controller.slow_unlocked and not arena.time_controller.rewind_unlocked, "Demo %s does not spend real time meter, charges, or mutate capability flags" % String(id))
		expect(arena.history.snapshot_count == snap_count_before, "Demo %s does not pollute ReplayHistory" % String(id))
		expect(arena.weapons.available_tools == two_tools and arena.weapons.selected_tool == 2 and arena.player.position.distance_to(Vector3(1.25, 0.55, 2.0)) < 0.01, "Demo %s restores player position and weapon loadout" % String(id))
		expect(arena.director.enemies.size() == 1 and int(arena.director.enemies[0].rewind_id) == specimen_id and is_equal_approx(float(arena.director.enemies[0].health), specimen_hp), "Demo %s restores caller's pre-existing enemies unharmed" % String(id))
		expect(not arena.weapons.mouse_held and not arena.weapons.require_fresh_press and not arena.weapons.flash.charging and not arena.weapons.ring.drawing and not arena.weapons.bellows.active and not arena.time_controller.slow_requested, "Demo %s hands off clean input state with no stuck held/release controls" % String(id))

		demo.ready_for_practice.disconnect(on_ready)
		demo.demo_completed.disconnect(on_completed)

	# 4. Verify pause/settings freeze, early skip ("Try it"), cancel, and non-repeating learned demos
	tutorial.reset_run()
	demo.reset_run()
	var handoff_events: Array[StringName] = []
	var cancel_events: Array[StringName] = []
	demo.ready_for_practice.connect(func(done_id: StringName) -> void: handoff_events.append(done_id))
	demo.demo_cancelled.connect(func(done_id: StringName) -> void: cancel_events.append(done_id))

	expect(demo.begin(arena, &"charge", tutorial), "Charge demo begins for pause/skip test")
	for i in range(6):
		demo.step(1.0 / 30.0)
	var elapsed_before_pause := demo.elapsed
	state.pause()
	var settings_popup: Control = scenes.push_popup(&"Settings")
	await _settle(2)
	for i in range(10):
		demo.step(1.0 / 30.0)
	expect(settings_popup != null and is_equal_approx(demo.elapsed, elapsed_before_pause) and demo.active and handoff_events.is_empty(), "Pause and Settings popup hold demo progression without advancing or stranding")
	scenes.close_popup(&"Settings")
	state.resume()
	await _settle(2)
	expect(not state.is_paused() and not scenes.has_popup(), "Resumed cleanly from pause/settings")

	# Early skip via TutorialOverlay.request_practice ("Try it" button)
	tutorial.request_practice()
	tutorial.request_practice()
	demo.skip_to_practice()
	expect(not demo.active and handoff_events == [&"charge"] and cancel_events.is_empty() and not arena.weapons.flash.charging and not arena.weapons.mouse_held, "Clicking Try it / skip_to_practice mid-charge clears held state and emits ready_for_practice once")

	# Complete lesson and verify learned demo does not repeat
	tutorial.complete_lesson(&"charge")
	expect(tutorial.is_learned(&"charge") and demo.is_demo_learned(&"charge", tutorial), "Completing lesson marks demo learned")
	expect(not demo.begin(arena, &"charge", tutorial) and not demo.active, "Learned demo does not repeat")

	# Cancel mid-demo without advancing to practice
	expect(demo.begin(arena, &"slow", tutorial), "Slow demo begins for cancel test")
	for i in range(12):
		demo.step(1.0 / 30.0)
	expect(arena.time_controller.slow_requested, "Slow demo engages slow_requested during active run")
	demo.cancel()
	demo.cancel()
	expect(not demo.active and cancel_events == [&"slow"] and handoff_events == [&"charge"] and not arena.time_controller.slow_requested and is_equal_approx(arena.time_controller.world_scale, 1.0), "Cancelling mid-slow demo clears slow_requested, restores world_scale, and does not emit ready_for_practice")

	for key in saved_prefs:
		state.set_setting(key, saved_prefs[key])
	arena.queue_free()
	await _settle(2)

	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
