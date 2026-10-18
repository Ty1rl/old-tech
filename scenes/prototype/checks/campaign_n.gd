extends SceneTree

# Focused check suite for Round N Wave 2 (JAM-4 — Campaign + Teaching):
# - Removal of health_recovery.gd and health_label; scene-authored Overlay/Tutorial/TitleLabel/RunHintLabel
# - Strictly 3-weapon acquisition order (2 -> 3 -> 1; no tool 4 pickup or selection)
# - TimeController attempt lifecycle on room entry, retry_room, and attempt_exhausted
# - ReplayHistory value-only validation and seeded room checkpoint fallback (no empty-buffer softlock)
# - Immediate explanation -> practice input transition (card mouse_filter IGNORE, frame-1 Space slow and weapon input)
# - Slow lesson driven by TimeController slow drain with cutter (1) equipped
# - Once-only forced depletion in rewind lesson after usable history is recorded, spending 1 real charge and completing on EmergencyRewind.confirm()

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

	var defs := Rooms.definitions()
	var scheduled_acquires: Array[int] = []
	for room_def: Dictionary in defs:
		for wave_def: Dictionary in room_def.waves:
			var acq := int(wave_def.get("acquire", 0))
			if acq > 0:
				scheduled_acquires.append(acq)
	expect(scheduled_acquires == [2, 3, 1], "Rooms schedule strictly three weapon pickups in 2 -> 3 -> 1 order")

	# 2. Instantiate campaign.tscn and verify scene-authored overlay composition + TimeController/ReplayHistory binding
	var game: Node = root.get_node("GameState")
	var prior_prefs: Dictionary = game.preferences().duplicate(true)
	game.set_setting("tutorial", true)
	root.get_node("SceneManager").params = {}

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

	# 3. Verify room entry attempt budget and seeded checkpoint after room composition
	expect(is_equal_approx(arena.time_controller.meter, 100.0) and arena.time_controller.charges_remaining == 3, "Room entry starts a fresh 3-charge attempt at full meter")
	expect(arena.history.has_checkpoint and arena.history.snapshot_count == 0, "Room entry seeds a safe checkpoint with empty rolling buffer")
	var cp_state: Dictionary = arena.history.checkpoint_state()
	expect(cp_state.get("player", {}).get("position", Vector3.ZERO).is_equal_approx(arena.room.player_spawn), "Seeded checkpoint captures the room's actual player_spawn after composition")
	expect(arena.history.rejected_count == 0, "Campaign capture_state passes ReplayHistory value-only validation")

	# Verify an immediate depletion on an empty rolling buffer uses the seeded checkpoint and never softlocks
	arena.player.position = arena.room.player_spawn + Vector3(4.0, 0.0, -2.0)
	arena.time_controller.apply_hit(100.0)
	expect(arena.is_emergency_active() and arena.time_controller.charges_remaining == 2, "Depleting hit with empty rolling buffer enters emergency and spends 1 charge")
	expect(arena.emergency_rewind.choice_count == 2 and is_equal_approx(arena.emergency_rewind.choice_age(1), EmergencyRewind.CHECKPOINT_AGE), "Empty rolling buffer offers NOW plus seeded checkpoint")
	arena.emergency_rewind.step_selection(1)
	arena.emergency_rewind.confirm()
	expect(not arena.is_emergency_active() and arena.player.position.is_equal_approx(arena.room.player_spawn), "Confirming checkpoint choice restores player to room spawn without softlocking")
	expect(arena.time_controller.meter >= arena.time_controller.settings.recovery_floor and arena.time_controller.protected, "Confirming emergency recovery grants recovery floor and grace protection")

	# Retry room resets attempt to 3 charges and full meter
	arena.retry_room()
	expect(arena.time_controller.charges_remaining == 3 and is_equal_approx(arena.time_controller.meter, 100.0), "retry_room starts a fresh 3-charge attempt")

	# 4. Verify immediate explanation -> practice transition (no mouse swallowing or Space release lock latency)
	tick(2.1)
	expect(arena.mode == &"pickup" and arena.museum.pickup_tool == 2, "Wave 0 offers yellow weapon pickup")
	arena.player.position = arena.museum.pickup_position + Vector3.UP * 0.55
	tick(0.01)
	expect(arena.lesson == &"shot" and arena.tutorial.blocking, "Collecting yellow opens blocking shot explanation")
	expect(arena.tutorial.mouse_filter == Control.MOUSE_FILTER_STOP and arena.tutorial.card.mouse_filter == Control.MOUSE_FILTER_STOP, "Blocking explanation stops mouse input on tutorial and card")

	arena.tutorial.request_practice()
	# Without calling tutorial._process, verify mouse_filter and focus are updated synchronously
	expect(not arena.tutorial.blocking and arena.tutorial.practicing, "request_practice immediately exits blocking mode")
	expect(arena.tutorial.mouse_filter == Control.MOUSE_FILTER_IGNORE and arena.tutorial.card.mouse_filter == Control.MOUSE_FILTER_IGNORE, "request_practice synchronously sets tutorial and card mouse_filter to IGNORE")
	expect(arena.tutorial.practice_button.focus_mode == Control.FOCUS_NONE and not arena.tutorial.practice_button.visible, "Hidden practice button releases focus and disables focus_mode")

	# Verify first mouse input on the very next call after request_practice works immediately
	var shot_aim: Vector3 = arena.specimens[0].core_world_position()
	var click_down := InputEventMouseButton.new()
	click_down.button_index = MOUSE_BUTTON_LEFT
	click_down.pressed = true
	arena.weapons.handle_event(click_down, arena.player, shot_aim)
	expect(arena.weapons.beam_charging, "First mouse press after explanation immediately starts charging/arming beam")
	var click_up := InputEventMouseButton.new()
	click_up.button_index = MOUSE_BUTTON_LEFT
	click_up.pressed = false
	arena.weapons.handle_event(click_up, arena.player, shot_aim)
	expect(not arena.weapons.beam_pulses.is_empty(), "Releasing first click immediately launches quick-shot pulse")
	arena.weapons.step(0.6, arena.player, shot_aim, arena.director.enemies, 0.6)
	tick(0.02)
	expect(arena.tutorial.is_learned(&"shot") and arena.mode == &"pressure", "First shot input immediately after explanation hits specimen and completes lesson")

	# 5. Verify Slow lesson in Room 2 Wave 2 uses TimeController slow drain with cutter (1) and no tool 4
	arena.debug_start(1, 2)
	expect(arena.acquired == [2, 3, 1] and not (4 in arena.acquired), "Room 2 Wave 2 has acquired [2, 3, 1] with no fourth weapon")
	var key4 := InputEventKey.new()
	key4.physical_keycode = KEY_4
	key4.pressed = true
	arena._input(key4)
	expect(arena.weapons.selected_tool != 4, "Pressing key 4 never selects a fourth weapon")

	arena.tutorial.learned.erase(&"slow")
	arena.director.clear()
	arena.wave_index = 1
	arena._begin_wave()
	expect(arena.lesson == &"slow" and arena.tutorial.blocking and arena.weapons.selected_tool == 1, "Slow lesson equips cutter (1) and opens explanation")

	# Dismiss explanation and immediately press Space on frame 1
	arena.tutorial.request_practice()
	var space_press := InputEventKey.new()
	space_press.physical_keycode = KEY_SPACE
	space_press.pressed = true
	arena._input(space_press)
	expect(arena.time_controller.slow_requested, "First Space press after explanation immediately requests slow on TimeController")
	tick(0.1)
	expect(arena.time_controller.slow_active and arena.time_controller.world_scale < 0.3 and arena.time_controller.meter < 100.0, "Frame-1 Space press after explanation slows world time and drains TimeController meter")

	# Cut the blue specimen while time is slowed
	var slow_specimen: Node3D = arena.specimens[0]
	var cable_pts: Array = slow_specimen.cable_world_points()
	var mid: Vector3 = (cable_pts[0] + cable_pts[1]) * 0.5
	var dir: Vector3 = (cable_pts[1] - cable_pts[0]).normalized().cross(Vector3.UP)
	slow_specimen.receive_attack(&"ring", 36.0, mid, {"segment_start": mid - dir * 0.7, "segment_end": mid + dir * 0.7, "radius": 0.1})
	tick(0.02)
	var space_release := InputEventKey.new()
	space_release.physical_keycode = KEY_SPACE
	space_release.pressed = false
	arena._input(space_release)
	expect(arena.tutorial.is_learned(&"slow") and arena.mode == &"pressure", "Cutting blue link during TimeController slow completes slow lesson")

	# 6. Verify once-only Rewind lesson in Room 2 Wave 3:
	# - Records usable history first
	# - Triggers forced depletion through TimeController spending 1 real charge
	# - Scrubs back and confirms via EmergencyRewind
	# - Never repeats on subsequent ticks or room retry
	arena.debug_start(1, 3)
	arena.tutorial.learned.erase(&"rewind")
	arena.director.clear()
	arena.wave_index = 2
	arena._begin_wave()
	expect(arena.lesson == &"rewind" and arena.tutorial.blocking, "Wave 3 opens rewind explanation")
	expect(arena.weapons.selected_tool in [1, 2, 3], "Rewind lesson keeps a valid 1..3 weapon selected")
	arena.tutorial.request_practice()

	# Move player during safe pre-depletion window so history records distinct positions
	var start_pos: Vector3 = arena.player.position
	for i in range(15):
		arena.player.position = start_pos + Vector3(float(i) * 0.1, 0.0, 0.0)
		tick(0.05)
	expect(not arena.is_emergency_active() and not arena._injury_given and arena.history.snapshot_count >= 10, "Rewind lesson records usable history before triggering forced depletion")

	# Advance past 2.0s to trigger the once-only forced depletion
	var pre_depletion_pos := start_pos + Vector3(3.0, 0.0, 0.0)
	arena.player.position = pre_depletion_pos
	for i in range(30):
		tick(0.05)
		if arena.is_emergency_active():
			break

	expect(arena._injury_given and arena.is_emergency_active(), "Rewind lesson triggers forced emergency depletion once history is ready")
	expect(arena.time_controller.charges_remaining == 2 and is_equal_approx(arena.time_controller.meter, 0.0) and is_equal_approx(arena.time_controller.world_scale, 0.0), "Forced teaching depletion spends 1 real charge and freezes world_scale to 0")
	expect(arena.emergency_rewind.choice_count >= 3, "EmergencyRewind offers NOW plus recorded snapshots")

	# Confirming NOW (index 0, age 0.0) would not rewind to an earlier moment; step selection to an older snapshot
	arena.emergency_rewind.step_selection(5)
	expect(arena.emergency_rewind.selected_index == 5 and arena.emergency_rewind.choice_age(5) > 0.1, "Scrolling wheel down selects an earlier recorded snapshot")
	arena.emergency_rewind.confirm()

	expect(not arena.is_emergency_active(), "Confirming EmergencyRewind ends emergency freeze")
	expect(arena.time_controller.charges_remaining == 2, "Confirming EmergencyRewind does not refund the spent charge")
	expect(arena.time_controller.meter >= arena.time_controller.settings.recovery_floor and arena.time_controller.protected, "Confirming EmergencyRewind restores meter to recovery floor with grace protection")
	tick(0.02)
	expect(arena.tutorial.is_learned(&"rewind") and arena.mode == &"pressure", "Confirming earlier moment completes rewind lesson permanently and starts pressure")

	# Retrying Room 2 must never repeat the rewind lesson or forced depletion
	arena.retry_room()
	expect(arena.tutorial.is_learned(&"rewind") and arena.acquired == [2, 3, 1], "Room retry preserves learned rewind lesson and acquired [2, 3, 1] weapons")
	expect(arena.time_controller.charges_remaining == 3 and is_equal_approx(arena.time_controller.meter, 100.0), "Room retry restores full 3-charge attempt budget")

	# 7. Verify attempt exhaustion (depleting with 0 charges left) restarts the current room cleanly
	arena.debug_start(2, 1)
	expect(arena.room_index == 2 and arena.mode == &"pressure" and arena.acquired == [2, 3, 1], "Entered Room 3 Wave 1 with full learned prerequisites")
	var learned_before: Dictionary = arena.tutorial.learned.duplicate()
	for charge_idx in range(3):
		arena.time_controller.apply_hit(100.0)
		expect(arena.is_emergency_active() and arena.time_controller.charges_remaining == 2 - charge_idx, "Depletion %d spends charge and enters emergency" % (charge_idx + 1))
		arena.emergency_rewind.confirm()
		# Advance past recovery grace so the next hit is not absorbed
		arena.time_controller.advance(arena.time_controller.settings.recovery_grace_seconds + 0.1)

	expect(arena.time_controller.charges_remaining == 0 and not arena.is_emergency_active(), "All 3 emergency charges spent")
	arena.time_controller.apply_hit(100.0)
	expect(arena.room_index == 2 and arena.mode == &"title" and not arena.is_emergency_active(), "Depleting with 0 charges left restarts current room cleanly")
	expect(arena.time_controller.charges_remaining == 3 and is_equal_approx(arena.time_controller.meter, 100.0) and not arena.time_controller.exhausted, "Restarted room after exhaustion begins a fresh 3-charge attempt")
	expect(arena.acquired == [2, 3, 1] and arena.tutorial.learned == learned_before, "Attempt exhaustion room restart preserves acquired weapons and learned lessons")
	expect(arena.history.rejected_count == 0, "Zero snapshots rejected across full campaign_n check suite")

	root.get_node("SceneManager").clear_popups()
	game.start_game()
	for key in prior_prefs:
		game.set_setting(key, prior_prefs[key])
	arena.feedback.reset_state()
	arena.free()
	await process_frame
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
