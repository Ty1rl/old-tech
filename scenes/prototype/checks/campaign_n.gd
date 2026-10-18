extends SceneTree

# Focused check suite for Round N / Round O Wave B (JAM-4 — Campaign + Teaching + Pacing):
# - Removal of health_recovery.gd and health_label; scene-authored Overlay/Tutorial/TitleLabel/RunHintLabel
# - Strictly 3-weapon acquisition order (2 -> 3 -> 1; no tool 4 pickup or selection)
# - Capability locks at campaign start (slow=false, rewind=false); pre-rewind depletion triggers retry_room without spending hidden charges
# - Early slow lesson in Room 1 (gallery Wave 4) with owned tools [2, 3], unlocking slow on frame 1 of practice
# - Staged full-restoration repair lesson on actual WeaponRepair tool model (all stages to 100%, stage hints per operation)
# - Staged >= 6.0 world-second rewind lesson (movement, attack, incoming shot, world-time measurement under slow, Enter prompt kept visible, earlier state required)
# - Continuous within-room ReplayHistory across wave transitions and atomic cross-wave campaign_wave + enemy restore

const Rooms = preload("res://scenes/prototype/rooms.gd")

var checks := 0
var failures: Array[String] = []
var arena: Node3D


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func tick(dt: float = 0.05) -> void:
	arena._physics_process(dt)


func run() -> void:
	# 1. Verify health_recovery.gd is removed and rooms.gd has only 3 tool pickups (2 -> 3 -> 1)
	expect(not ResourceLoader.exists("res://scenes/prototype/health_recovery.gd"), "health_recovery.gd is removed")

	var defs := Rooms.definitions(&"easy")
	var hard_defs := Rooms.definitions(&"hard")
	var scheduled_acquires: Array[int] = []
	for room_def: Dictionary in defs:
		for wave_def: Dictionary in room_def.waves:
			var acq := int(wave_def.get("acquire", 0))
			if acq > 0:
				scheduled_acquires.append(acq)
	expect(scheduled_acquires == [2, 3, 1], "Rooms schedule strictly three weapon pickups in 2 -> 3 -> 1 order")
	expect(int(hard_defs[3].waves[0].get("max_live", 0)) >= 11 and int(hard_defs[3].waves[0].get("count", 0)) > int(defs[3].waves[0].get("count", 0)), "Hard difficulty scales simultaneous max_live and wave counts above Easy")

	# 2. Instantiate campaign.tscn and verify scene-authored overlay composition + TimeController/ReplayHistory binding
	var game: Node = root.get_node("GameState")
	var prior_prefs: Dictionary = game.preferences().duplicate(true)
	game.set_setting("tutorial", true)
	root.get_node("SceneManager").params = {"difficulty": &"easy"}

	arena = load("res://scenes/prototype/campaign.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	game.start_game()

	expect(arena.get_node_or_null("Overlay") == arena.overlay and arena.overlay is CanvasLayer, "campaign.tscn authors Overlay CanvasLayer")
	expect(arena.get_node_or_null("Overlay/Tutorial") == arena.tutorial and arena.tutorial.get_script() == load("res://scenes/ui/tutorial.gd"), "campaign.tscn authors Overlay/Tutorial")
	expect(arena.get_node_or_null("Overlay/TitleLabel") == arena.title and arena.title is Label, "campaign.tscn authors Overlay/TitleLabel")
	expect(arena.get_node_or_null("Overlay/RunHintLabel") == arena.run_hint and arena.run_hint is Label, "campaign.tscn authors Overlay/RunHintLabel")
	expect(arena.get_node_or_null("Overlay/HealthLabel") == null and not ("health_label" in arena), "Campaign removes legacy health_label")

	expect(arena.time_controller is TimeController, "Campaign binds TimeController")
	expect(arena.emergency_rewind is EmergencyRewind, "Campaign binds EmergencyRewind")
	expect(arena.history is ReplayHistory, "Campaign uses ReplayHistory")
	arena.history.validate_snapshots = true

	# 3. Verify initial capability locks and pre-rewind depletion behavior
	expect(not arena.time_controller.slow_unlocked and not arena.time_controller.rewind_unlocked, "Fresh campaign starts with slow and rewind locked")
	expect(is_equal_approx(arena.time_controller.meter, 100.0) and arena.time_controller.charges_remaining == 3, "Room entry starts a fresh 3-charge attempt at full meter")
	expect(arena.history.has_checkpoint and arena.history.snapshot_count == 0, "Room entry seeds a safe checkpoint with empty rolling buffer")
	var cp_state: Dictionary = arena.history.checkpoint_state()
	expect(cp_state.get("player", {}).get("position", Vector3.ZERO).is_equal_approx(arena.room.player_spawn), "Seeded checkpoint captures the room's actual player_spawn after composition")
	expect(arena.history.rejected_count == 0, "Campaign capture_state passes ReplayHistory value-only validation")

	# Depleting before rewind is unlocked restarts the room without spending hidden charges or entering emergency rewind
	arena.time_controller.apply_hit(100.0)
	expect(not arena.is_emergency_active() and arena.time_controller.charges_remaining == 3 and arena.mode == &"title" and is_equal_approx(arena.time_controller.meter, 100.0), "Depletion before rewind is unlocked retries room without spending hidden charges")

	# Unlock rewind to verify empty rolling buffer seeded checkpoint fallback
	arena._rewind_unlocked = true
	arena._apply_time_capabilities()
	arena.player.position = arena.room.player_spawn + Vector3(4.0, 0.0, -2.0)
	arena.time_controller.apply_hit(100.0)
	expect(arena.is_emergency_active() and arena.time_controller.charges_remaining == 2, "Depleting hit with rewind unlocked and empty rolling buffer enters emergency and spends 1 charge")
	expect(arena.emergency_rewind.choice_count == 2 and is_equal_approx(arena.emergency_rewind.choice_age(1), EmergencyRewind.CHECKPOINT_AGE), "Empty rolling buffer offers NOW plus seeded checkpoint")
	arena.emergency_rewind.step_selection(1)
	arena.emergency_rewind.confirm()
	expect(not arena.is_emergency_active() and arena.player.position.is_equal_approx(arena.room.player_spawn), "Confirming checkpoint choice restores player to room spawn without softlocking")
	expect(arena.time_controller.meter >= arena.time_controller.settings.recovery_floor and arena.time_controller.protected, "Confirming emergency recovery grants recovery floor and grace protection")

	# Reset for fresh Room 1 progression
	arena.start_new_run(&"easy")
	expect(not arena.time_controller.slow_unlocked and not arena.time_controller.rewind_unlocked, "start_new_run resets capability locks")

	# 4. Verify immediate explanation -> practice transition (no mouse swallowing)
	tick(2.1)
	expect(arena.mode == &"pickup" and arena.museum.pickup_tool == 2, "Wave 0 offers yellow weapon pickup")
	arena.player.position = arena.museum.pickup_position + Vector3.UP * 0.55
	tick(0.01)
	expect(arena.lesson == &"shot" and arena.tutorial.blocking, "Collecting yellow opens blocking shot explanation")
	expect(arena.tutorial.mouse_filter == Control.MOUSE_FILTER_STOP and arena.tutorial.card.mouse_filter == Control.MOUSE_FILTER_STOP, "Blocking explanation stops mouse input on tutorial and card")

	arena.tutorial.request_practice()
	expect(not arena.tutorial.blocking and arena.tutorial.practicing, "request_practice immediately exits blocking mode")
	expect(arena.tutorial.mouse_filter == Control.MOUSE_FILTER_IGNORE and arena.tutorial.card.mouse_filter == Control.MOUSE_FILTER_IGNORE, "request_practice synchronously sets tutorial and card mouse_filter to IGNORE")
	expect(arena.tutorial.practice_button.focus_mode == Control.FOCUS_NONE and not arena.tutorial.practice_button.visible, "Hidden practice button releases focus and disables focus_mode")

	var shot_aim: Vector3 = arena.specimens[0].core_world_position()
	var click_down := InputEventMouseButton.new()
	click_down.button_index = MOUSE_BUTTON_LEFT
	click_down.pressed = true
	arena.weapons.handle_event(click_down, arena.player, shot_aim)
	expect(arena.weapons.flash.charging, "First mouse press after explanation immediately starts charging/arming beam")
	var click_up := InputEventMouseButton.new()
	click_up.button_index = MOUSE_BUTTON_LEFT
	click_up.pressed = false
	arena.weapons.handle_event(click_up, arena.player, shot_aim)
	expect(not arena.weapons.flash.pulses.is_empty(), "Releasing first click immediately launches quick-shot pulse")
	arena.weapons.step(0.6, arena.player, shot_aim, arena.director.enemies, 0.6)
	tick(0.02)
	expect(arena.tutorial.is_learned(&"shot") and arena.mode == &"pressure", "First shot input immediately after explanation hits specimen and completes lesson")

	# 5. Verify staged full-restoration repair lesson on actual WeaponRepair popup in Room 0 Wave 3
	arena.debug_start(0, 2)
	arena.tutorial.learned.erase(&"repair")
	arena.tutorial.learned.erase(&"slow")
	arena._slow_unlocked = false
	arena._rewind_unlocked = false
	arena._apply_time_capabilities()
	arena.director.clear()
	arena.wave_index = 2
	arena._begin_wave()
	expect(arena.wave_index == 3 and arena.lesson == &"repair" and arena.tutorial.blocking, "Room 0 Wave 3 opens repair explanation")
	arena.tutorial.request_practice()
	expect(arena._open_smart_repair() and root.get_node("SceneManager").has_popup(&"Repair"), "Opening repair during practice pushes WeaponRepair popup")
	var repair_popup: Node = root.get_node("SceneManager").get_popup(&"Repair")
	await process_frame
	var total_steps: int = arena.equipment.repair_steps
	expect(repair_popup != null and bool(repair_popup.get("_stage_hint_active")) and "Stage 1" in String(repair_popup.get("_stage_hint_prompt")), "Repair lesson activates Stage 1 hint on actual WeaponRepair popup")
	for step_i in range(total_steps):
		var expected_stage_label := "Stage %d / %d" % [step_i + 1, total_steps]
		expect(expected_stage_label in String(repair_popup.get("_stage_hint_prompt")), "Repair lesson demonstrates %s on WeaponRepair popup" % expected_stage_label)
		repair_popup.trace_stage = arena.equipment.stage(&"beam")
		expect(int(repair_popup._commit_steps(1)) == 1, "Completed repair step %d / %d on WeaponRepair popup" % [step_i + 1, total_steps])
		tick(0.02)
		if step_i + 1 < total_steps:
			expect(not arena.tutorial.is_learned(&"repair") and not arena.equipment.is_full(&"beam"), "Partial repair (%d / %d) does not complete full-restoration repair lesson" % [step_i + 1, total_steps])
	expect(arena.tutorial.is_learned(&"repair") and arena.equipment.is_full(&"beam"), "Full restoration across all %d stages on WeaponRepair completes repair lesson" % total_steps)
	tick(0.02)
	tick(0.4)

	# 6. Verify early Slow lesson in Room 0 Wave 4 (with owned tools [2, 3], before Blue Cutter 1 is acquired)
	expect(arena.room_index == 0 and arena.wave_index == 4 and arena.lesson == &"slow" and arena.tutorial.blocking, "Room 0 Wave 4 opens early slow lesson right after repair")
	expect(arena.acquired == [2, 3] and arena.weapons.selected_tool == 2 and not arena.time_controller.slow_unlocked, "Early slow lesson uses owned yellow flash [2, 3] and keeps slow locked during explanation")
	arena.tutorial.request_practice()
	expect(arena.time_controller.slow_unlocked and not arena.time_controller.rewind_unlocked, "Starting slow practice immediately unlocks slow capability while rewind remains locked")
	var space_press := InputEventKey.new()
	space_press.physical_keycode = KEY_SPACE
	space_press.pressed = true
	arena._input(space_press)
	expect(arena.time_controller.slow_requested, "First Space press after explanation immediately requests slow on TimeController")
	tick(0.1)
	expect(arena.time_controller.slow_active and arena.time_controller.world_scale < 0.3 and arena.time_controller.meter < 100.0, "Frame-1 Space press after explanation slows world time and drains TimeController meter")
	var slow_specimen: Node3D = arena.specimens[0]
	var slow_pt: Vector3 = slow_specimen.core_world_position()
	slow_specimen.receive_attack(&"beam", 100.0, slow_pt, {"segment_start": slow_pt - Vector3(0, 0, 4), "segment_end": slow_pt + Vector3(0, 0, 4), "radius": 0.35, "charge": 0.0})
	tick(0.02)
	var space_release := InputEventKey.new()
	space_release.physical_keycode = KEY_SPACE
	space_release.pressed = false
	arena._input(space_release)
	expect(arena.tutorial.is_learned(&"slow") and arena.mode == &"pressure" and not arena.director.enemies.is_empty(), "Shooting practice target while slowed completes early slow lesson and starts Wave 4 pressure")

	# 7. Verify staged >= 6.0 world-second Rewind lesson in Room 1 Wave 3 (including world-time measurement under slow and Enter prompt visibility)
	arena.debug_start(1, 3)
	arena.tutorial.learned.erase(&"rewind")
	arena._rewind_unlocked = false
	arena._apply_time_capabilities()
	arena.director.clear()
	arena.wave_index = 2
	arena._begin_wave()
	expect(arena.lesson == &"rewind" and arena.tutorial.blocking and not arena.time_controller.rewind_unlocked, "Room 1 Wave 3 opens rewind explanation with rewind locked")
	arena.tutorial.request_practice()
	expect(arena.time_controller.rewind_unlocked, "Starting rewind practice unlocks rewind capability")

	# Hold Space for 2.0 real seconds (~0.36 world seconds): verify it does NOT trigger depletion at 6 real seconds if world time < 6.0s
	arena._input(space_press)
	for i in range(40):
		tick(0.05)
	arena._input(space_release)
	expect(not arena.is_emergency_active() and arena._rewind_world_age < 1.5, "Rewind lesson measures pre-depletion staging in world time, not real time while slowed")

	# Advance remaining world time so movement, attack, and incoming shot occur across >= 6.0 world seconds
	for i in range(130):
		tick(0.05)
		if arena.is_emergency_active():
			break

	expect(arena._rewind_moved and arena._rewind_attack_seen and arena._rewind_projectile_spawned, "Rewind lesson stages movement, an attack, and a visible incoming projectile before depletion")
	expect(arena._injury_given and arena.is_emergency_active() and arena.history.age_of(0) >= 6.0, "Rewind lesson triggers forced emergency depletion only after >= 6.0 world seconds of history")
	expect("Enter" in arena.run_hint.text and "ENTER" in arena.tutorial.state_label.text, "Enter prompt is visible immediately when emergency rewind starts")

	# Pressing Enter at index 0 (NOW) must not complete the rewind lesson and must keep Enter prompt visible
	var enter_key := InputEventKey.new()
	enter_key.physical_keycode = KEY_ENTER
	enter_key.pressed = true
	arena._input(enter_key)
	expect(arena.is_emergency_active() and "Enter" in arena.run_hint.text, "Pressing Enter at index 0 (NOW) requires selecting an earlier moment first and keeps Enter prompt visible")

	arena.emergency_rewind.step_selection(8)
	expect(arena.emergency_rewind.selected_index == 8 and arena.emergency_rewind.choice_age(8) > 0.5, "Scrolling wheel down selects an earlier safe snapshot")
	expect("Enter" in arena.run_hint.text and "ENTER" in arena.tutorial.state_label.text, "Enter prompt remains visible throughout timeline selection")
	arena._input(enter_key)

	expect(not arena.is_emergency_active(), "Pressing Enter on an earlier snapshot confirms EmergencyRewind")
	expect(arena.time_controller.charges_remaining == 2, "Confirming EmergencyRewind does not refund the spent charge")
	expect(arena.time_controller.meter >= arena.time_controller.settings.recovery_floor and arena.time_controller.protected, "Confirming EmergencyRewind restores meter to recovery floor with grace protection")
	tick(0.02)
	expect(arena.tutorial.is_learned(&"rewind") and arena.mode == &"pressure", "Confirming earlier moment completes rewind lesson permanently and starts pressure")

	# 8. Verify continuous within-room ReplayHistory across wave transitions and atomic cross-wave restore
	arena.debug_start(2, 0)
	arena.tutorial.learned[&"zigzag"] = true
	expect(arena.room_index == 2 and arena.wave_index == 0 and arena.mode == &"pressure", "Started Room 2 Wave 0 pressure")
	for i in range(20):
		tick(0.1)
	var wave0_snap_count: int = arena.history.snapshot_count
	var wave0_pending: int = arena._pending
	var wave0_live: int = arena.director.enemies.size()
	expect(wave0_snap_count >= 15 and wave0_live > 0, "Recorded rolling snapshots during Room 2 Wave 0")

	# Clear Wave 0, advance through recovery into Wave 1, and verify ReplayHistory was NOT cleared
	for e in arena.director.enemies:
		e.health = 0
	arena.director._prune_dead_enemies()
	arena._pending = 0
	tick(0.05)
	expect(arena.mode == &"recovery" and arena.history.snapshot_count >= wave0_snap_count, "Entering recovery preserves rolling ReplayHistory within the room")
	tick(3.0)
	expect(arena.wave_index == 1 and arena.mode == &"pressure" and arena.history.snapshot_count > wave0_snap_count, "Advancing to Wave 1 preserves continuous within-room ReplayHistory")

	# Trigger emergency rewind in Wave 1 and scrub back to a Wave 0 snapshot
	arena.time_controller.apply_hit(100.0)
	expect(arena.is_emergency_active(), "Depletion in Wave 1 opens EmergencyRewind with cross-wave history")
	arena.emergency_rewind.select(arena.emergency_rewind.choice_count - 1)
	arena.emergency_rewind.confirm()
	expect(arena.wave_index == 0 and arena.mode == &"pressure" and arena._pending == wave0_pending and arena.director.enemies.size() == wave0_live, "Cross-wave rewind atomically restores Wave 0 scheduler and enemies")

	# 9. Verify attempt exhaustion restarts the current room cleanly while preserving capabilities
	arena.debug_start(2, 1)
	var learned_before: Dictionary = arena.tutorial.learned.duplicate()
	for charge_idx in range(3):
		arena.time_controller.apply_hit(100.0)
		arena.emergency_rewind.confirm()
		arena.time_controller.advance(arena.time_controller.settings.recovery_grace_seconds + 0.1)
	arena.time_controller.apply_hit(100.0)
	expect(arena.room_index == 2 and arena.mode == &"title" and not arena.is_emergency_active(), "Depleting with 0 charges left restarts current room cleanly")
	expect(arena.time_controller.slow_unlocked and arena.time_controller.rewind_unlocked and arena.acquired == [2, 3, 1] and arena.tutorial.learned == learned_before, "Room restart after exhaustion preserves capabilities, acquired weapons, and learned lessons")
	expect(arena.history.rejected_count == 0, "Zero snapshots rejected across full campaign_n check suite")

	root.get_node("SceneManager").clear_popups()
	game.start_game()
	for key in prior_prefs:
		game.set_setting(key, prior_prefs[key])
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
