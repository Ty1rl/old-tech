extends SceneTree

# Round P Wave B verification suite (JAM-4):
# - Mounted LessonDemo + RewindLesson + TutorialOverlay integration in campaign.gd
# - 4-step lesson progression: Real Demo -> Stationary Quota -> Moving Quota -> Finite Combat
# - Single-action quotas (2 stationary, 2 moving) and combination/pattern quotas (1 stationary, 1 moving)
# - Opt-in instruction visibility on CreatureVisual/PatternVisual/PartVisual during demo/practice only; clean in pressure combat
# - Repair lesson E key entry, active-step stage hint, and full restoration completion
# - Forced RewindLesson staged hit, frozen EmergencyRewindView scrub, non-stacking prompts, and 3-charge handoff
# - Isolated mechanic introduction waves + familiar consolidation waves + brisk early pacing in rooms.gd
# - Phase-specific final boss guidance across all 4 phases

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


func _enemy_instruction_visible(enemy: Node3D) -> bool:
	if not is_instance_valid(enemy):
		return false
	if "part_visual" in enemy and is_instance_valid(enemy.part_visual):
		return bool(enemy.part_visual.instruction_visible)
	if "pattern_visual" in enemy and is_instance_valid(enemy.pattern_visual):
		return bool(enemy.pattern_visual.instruction_visible)
	return false


func _complete_single_rep(lesson_id: StringName) -> void:
	if arena.specimens.is_empty():
		return
	match lesson_id:
		&"shot":
			var target: Node3D = arena.specimens[0]
			var pt: Vector3 = target.core_world_position()
			target.receive_attack(&"beam", 100.0, pt, {"segment_start": pt - Vector3(0, 0, 4), "segment_end": pt + Vector3(0, 0, 4), "radius": 0.35, "charge": 0.0})
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
			var pt: Vector3 = target.core_world_position()
			target.receive_attack(&"beam", 100.0, pt, {"segment_start": pt - Vector3(0, 0, 4), "segment_end": pt + Vector3(0, 0, 4), "radius": 0.35, "charge": 0.0})
			var sp_up := InputEventKey.new()
			sp_up.physical_keycode = KEY_SPACE
			sp_up.pressed = false
			arena._input(sp_up)
		&"cut":
			var target: Node3D = arena.specimens[0]
			var pts: Array = target.cable_world_points()
			var mid: Vector3 = (pts[0] + pts[1]) * 0.5
			var dir: Vector3 = (pts[1] - pts[0]).normalized().cross(Vector3.UP)
			target.receive_attack(&"ring", 36.0, mid, {"segment_start": mid - dir * 0.7, "segment_end": mid + dir * 0.7, "radius": 0.1})
		&"opening":
			for target in arena.specimens:
				if not is_instance_valid(target):
					continue
				if target.kind == &"side_guard":
					var pts: Array = target.cable_world_points()
					var mid: Vector3 = (pts[0] + pts[1]) * 0.5
					var dir: Vector3 = (pts[1] - pts[0]).normalized().cross(Vector3.UP)
					target.receive_attack(&"ring", 36.0, mid, {"segment_start": mid - dir * 0.7, "segment_end": mid + dir * 0.7, "radius": 0.1})
				else:
					for i in range(80):
						target.receive_attack(&"cone", 0.3, target.position, {"dt": 1.0 / 60.0})
				var pt: Vector3 = target.core_world_position()
				target.receive_attack(&"beam", 100.0, pt, {"segment_start": pt - Vector3(0, 0, 4), "segment_end": pt + Vector3(0, 0, 4), "radius": 0.35, "charge": 1.0})
		&"pair":
			var target: Node3D = arena.specimens[0]
			for idx in range(2):
				var vpos: Vector3 = target.valve_world_position(idx)
				target.receive_attack(&"beam", 30.0, vpos, {"segment_start": vpos - Vector3(0, 0, 1), "segment_end": vpos + Vector3(0, 0, 1), "radius": 0.1, "charge": 0.0})
			if target.health > 0.0:
				var pt: Vector3 = target.core_world_position()
				target.receive_attack(&"beam", 100.0, pt, {"segment_start": pt - Vector3(0, 0, 4), "segment_end": pt + Vector3(0, 0, 4), "radius": 0.35, "charge": 1.0})
		&"loop", &"zigzag":
			var target: Node3D = arena.specimens[0]
			var pts: Array = target.cable_world_points()
			for i in range(0, pts.size() - 1, 2):
				var mid: Vector3 = (pts[i] + pts[i + 1]) * 0.5
				var dir: Vector3 = (pts[i + 1] - pts[i]).normalized().cross(Vector3.UP)
				target.receive_attack(&"ring", 36.0, mid, {"segment_start": mid - dir * 0.7, "segment_end": mid + dir * 0.7, "radius": 0.1, "already_hit": i > 0})
			var pt: Vector3 = target.core_world_position()
			target.receive_attack(&"beam", 100.0, pt, {"segment_start": pt - Vector3(0, 0, 4), "segment_end": pt + Vector3(0, 0, 4), "radius": 0.35, "charge": 1.0})


func _run() -> void:
	create_timer(30.0, true).timeout.connect(func() -> void:
		failures.append("campaign_p watchdog expired")
		print(JSON.stringify({"status": "failed", "checks": checks, "failures": failures}))
		quit(1)
	)

	var game := root.get_node("GameState")
	var scenes := root.get_node("SceneManager")
	var saved_prefs: Dictionary = game.preferences().duplicate(true)
	game.set_setting("tutorial", true)
	scenes.params = {}

	# 1. Verify isolated mechanic introductions, familiar consolidation waves, and brisk early pacing in rooms.gd
	var easy_rooms: Array[Dictionary] = Rooms.definitions(&"easy")
	expect(easy_rooms.size() == 4, "Rooms.definitions(&'easy') returns 4 rooms")
	var familiar_waves := 0
	for ri in range(easy_rooms.size()):
		var r_waves: Array = easy_rooms[ri]["waves"]
		for wi in range(r_waves.size()):
			var w: Dictionary = r_waves[wi]
			var lid: StringName = w.get("lesson", &"")
			var elist: Array = w.get("enemies", [])
			if lid == &"":
				familiar_waves += 1
			elif lid in [&"shot", &"charge", &"heat", &"slow", &"cut", &"loop", &"pair", &"zigzag"]:
				expect(elist.size() == 1, "Room %d wave %d (%s) introduces its new mechanic in isolation with 1 enemy archetype (got %s)" % [ri, wi, String(lid), str(elist)])
			elif lid == &"opening":
				expect(elist == [&"side_guard", &"front_guard"], "Room %d wave %d (opening) isolates the guard family" % [ri, wi])
			if ri == 0 and int(w.get("count", 0)) > 0:
				expect(float(w.get("interval", 99.0)) <= 4.0 and float(w.get("recovery", 99.0)) <= 1.8, "Room 0 wave %d has brisk early interval and recovery" % wi)
	expect(familiar_waves >= 5, "Campaign schedule includes familiar mixed consolidation waves across rooms")

	# 2. Verify mounted LessonDemo, RewindLesson, and TutorialOverlay in campaign.tscn
	arena = load("res://scenes/prototype/campaign.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	game.start_game()

	expect(arena.lesson_demo is LessonDemo and arena.rewind_lesson is RewindLesson and arena.tutorial != null, "Campaign mounts LessonDemo, RewindLesson, and TutorialOverlay")

	# 3. Verify 4-step progression on single-action lesson (shot: Demo -> 2 Stationary -> 2 Moving -> Finite Combat)
	_tick(2.1)
	arena.player.position = arena.museum.pickup_position + Vector3.UP * 0.55
	_tick(0.01)
	expect(arena.mode == &"practice" and arena.lesson == &"shot" and arena._practice_stage == &"demo", "Collecting yellow weapon enters shot LessonDemo first")
	expect(arena.lesson_demo.active and arena.tutorial.visible and arena.tutorial.blocking and not arena.run_hint.visible, "During LessonDemo, tutorial card is visible/blocking and run_hint is hidden so prompts never stack")
	expect(not arena.specimens.is_empty() and _enemy_instruction_visible(arena.specimens[0]), "Demo specimen enables instruction_visible during demonstration")

	var demo_steps := 0
	while arena.lesson_demo.active and demo_steps < 180:
		_tick(1.0 / 30.0)
		demo_steps += 1

	expect(not arena.lesson_demo.active and bool(arena.lesson_demo.last_summary.get("completed", false)), "Shot LessonDemo plays through to completion")
	expect(arena.mode == &"practice" and arena._practice_stage == &"stationary" and not arena.tutorial.blocking and arena.tutorial.practicing, "Completed LessonDemo hands off automatically to stationary practice")
	expect(arena._stationary_quota == 2 and arena._moving_quota == 2 and arena._stationary_done == 0 and arena._moving_done == 0, "Single-action lesson shot uses 2 stationary + 2 moving quota")

	# Stationary rep 1/2
	expect(arena.specimens.size() == 1 and is_equal_approx(arena.specimens[0].move_speed, 0.0) and is_equal_approx(arena.specimens[0].contact_damage, 0.0) and _enemy_instruction_visible(arena.specimens[0]), "Stationary rep 1 specimen is stationary, harmless, and shows instruction caption")
	_complete_single_rep(&"shot")
	_tick(0.02)
	expect(arena.mode == &"practice" and arena._practice_stage == &"stationary" and arena._stationary_done == 1, "Completing stationary rep 1/2 advances to stationary rep 2/2")

	# Stationary rep 2/2 -> transitions to moving rep 1/2
	expect(arena.specimens.size() == 1 and is_equal_approx(arena.specimens[0].move_speed, 0.0), "Stationary rep 2 specimen is stationary")
	_complete_single_rep(&"shot")
	_tick(0.02)
	expect(arena.mode == &"practice" and arena._practice_stage == &"moving" and arena._stationary_done == 2 and arena._moving_done == 0, "Completing stationary quota transitions to moving practice stage")

	# Moving rep 1/2
	var mov_spec_1: Node3D = arena.specimens[0]
	var pos_before_move: Vector3 = mov_spec_1.position
	expect(mov_spec_1.move_speed > 1.2 and is_equal_approx(mov_spec_1.contact_damage, 0.0) and _enemy_instruction_visible(mov_spec_1), "Moving rep 1 specimen has positive move_speed, 0 contact_damage, and shows instruction caption")
	var nav: ExhibitNavigation = arena.director.navigation
	nav.sync_region()
	for i in range(60):
		await physics_frame
		if nav.ready_for(0.65):
			break
	for i in range(8):
		_tick(0.05)
		await physics_frame
	expect(mov_spec_1.position.distance_to(pos_before_move) > 0.05, "Moving practice specimen genuinely moves in the arena")
	_complete_single_rep(&"shot")
	_tick(0.02)
	expect(arena.mode == &"practice" and arena._practice_stage == &"moving" and arena._moving_done == 1, "Completing moving rep 1/2 advances to moving rep 2/2")

	# Moving rep 2/2 -> transitions to finite pressure combat
	_complete_single_rep(&"shot")
	_tick(0.02)
	expect(arena.mode == &"pressure" and arena.tutorial.is_learned(&"shot") and arena._practice_stage == &"", "Completing moving quota marks shot learned and starts finite pressure wave")
	expect(not arena.director.enemies.is_empty() and not _enemy_instruction_visible(arena.director.enemies[0]), "Normal pressure combat wave keeps instruction_visible disabled on enemies")

	# 4. Verify combination/pattern lesson quotas (1 stationary + 1 moving) on loop lesson
	var loop_wave_idx := 4
	arena.debug_start(1, loop_wave_idx)
	arena.tutorial.learned.erase(&"loop")
	arena.director.clear()
	arena.wave_index = loop_wave_idx - 1
	arena._begin_wave()
	expect(arena.lesson == &"loop" and arena.lesson_demo.active and arena._practice_stage == &"demo", "Unlearned loop wave starts LessonDemo")
	expect(arena._stationary_quota == 1 and arena._moving_quota == 1, "Combination/pattern lesson loop uses 1 stationary + 1 moving quota")
	arena.tutorial.request_practice()
	expect(not arena.lesson_demo.active and arena._practice_stage == &"stationary" and is_equal_approx(arena.specimens[0].move_speed, 0.0), "Skipping demo via Try it enters stationary rep 1/1")
	_complete_single_rep(&"loop")
	_tick(0.02)
	expect(arena.mode == &"practice" and arena._practice_stage == &"moving" and arena.specimens[0].move_speed > 1.2, "Completing 1 stationary loop rep transitions to 1 moving loop rep")
	_complete_single_rep(&"loop")
	_tick(0.02)
	expect(arena.mode == &"pressure" and arena.tutorial.is_learned(&"loop"), "Completing 1 moving loop rep transitions into finite pressure wave")

	# 5. Verify Repair lesson E key entry while blocking and full restoration
	arena.debug_start(0, 3)
	arena.tutorial.learned.erase(&"repair")
	arena.director.clear()
	arena.wave_index = 2
	arena._begin_wave()
	expect(arena.lesson == &"repair" and arena.tutorial.blocking and arena.tutorial.heading.text == "Press E to repair" and arena.tutorial.accent == ToolStyle.REPAIR_GUIDE, "Repair lesson shows 'Press E to repair' in ivory REPAIR_GUIDE accent")
	var e_press := InputEventKey.new()
	e_press.physical_keycode = KEY_E
	e_press.pressed = true
	arena._input(e_press)
	await process_frame
	var repair_popup: Node = scenes.get_popup(&"Repair")
	expect(not arena.tutorial.blocking and repair_popup != null, "Pressing E during repair explanation enters practice and opens WeaponRepair popup")
	while not arena.equipment.is_full(&"beam"):
		repair_popup.trace_stage = arena.equipment.stage(&"beam")
		repair_popup.call("_commit_steps", 1)
		_tick(0.02)
	expect(arena.tutorial.is_learned(&"repair") and arena.mode == &"pressure", "Restoring yellow to 100% completes repair lesson and advances")

	# 6. Verify Forced RewindLesson in campaign.gd
	arena.debug_start(1, 3)
	arena.tutorial.learned.erase(&"rewind")
	arena.rewind_lesson.reset_for_new_run()
	arena.director.clear()
	arena.wave_index = 2
	arena._begin_wave()
	expect(arena.lesson == &"rewind" and arena.rewind_lesson.active and arena.rewind_lesson.phase == RewindLesson.Phase.STAGING, "Rewind wave begins RewindLesson in STAGING phase")
	expect(not arena.tutorial.visible and not arena.run_hint.visible, "Tutorial card and run_hint are hidden during RewindLesson")
	for i in range(60):
		_tick(0.04)
		if arena.is_emergency_active():
			break
	expect(arena.is_emergency_active() and arena.rewind_lesson.phase == RewindLesson.Phase.SCRUB and arena.emergency_rewind.selected_index > 0, "RewindLesson stages unavoidable hit and opens EmergencyRewindView at safe pre-hit selection")
	arena.emergency_rewind.confirm()
	_tick(0.02)
	expect(arena.tutorial.is_learned(&"rewind") and arena.mode == &"pressure" and arena.time_controller.charges_remaining == 3 and is_equal_approx(arena.time_controller.meter, 100.0), "Confirming RewindLesson hands off to finite pressure with all 3 charges and 100% meter")
	arena.start_new_run()
	expect(not arena.rewind_lesson.is_completed and arena.rewind_lesson.completed_count == 0,
		"Starting another campaign resets the actual rewind completion latch and count")

	# 7. Verify phase-specific final boss guidance across all 4 phases
	var expected_phase_tokens := [
		["1/4", "valve A"],
		["2/4", "zigzag"],
		["3/4", "loop"],
		["4/4", "yellow core"],
	]
	for phase_idx in range(4):
		arena.debug_start(3, 1, phase_idx)
		var boss: Node3D = arena.director.enemies[0]
		var guide: Dictionary = arena._boss_phase_guidance(boss)
		var hint_str: String = arena.run_hint.text
		expect(expected_phase_tokens[phase_idx][0] in hint_str and expected_phase_tokens[phase_idx][1] in hint_str, "Final boss phase %d run_hint is phase-specific ('%s')" % [phase_idx + 1, hint_str])
		expect(not ("finish its marked mechanism" in hint_str) and not ("Open each lock" in String(guide.get("heading", ""))), "Final boss phase %d avoids generic mechanism/lock copy" % (phase_idx + 1))

	scenes.clear_popups()
	game.start_game()
	for key in saved_prefs:
		game.set_setting(key, saved_prefs[key])
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	await create_timer(0.3).timeout

	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
