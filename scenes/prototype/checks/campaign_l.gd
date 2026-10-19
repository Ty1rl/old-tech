extends SceneTree
var checks := 0
var failures: Array[String] = []
var arena: Node3D
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text)
func tick(dt: float = 0.01) -> void: arena._physics_process(dt)
func clear_roster() -> void:
	for enemy in arena.director.enemies: enemy.health = 0
	arena.director._prune_dead_enemies()
func mouse(down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	return event
func collect() -> void:
	arena.player.position = arena.museum.pickup_position + Vector3.UP * 0.55
	tick()
func run() -> void:
	var game: Node = root.get_node("GameState")
	var prior: Dictionary = game.preferences().duplicate(true)
	game.set_setting("tutorial", true)
	root.get_node("SceneManager").params = {}
	arena = load("res://scenes/prototype/campaign.tscn").instantiate()
	root.add_child(arena); current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	game.start_game()
	expect(arena.museum.get_script() == load("res://scenes/prototype/room_environment.gd"), "Campaign constructs its actual museum once through factory")
	expect(arena.acquired.is_empty() and arena.mode == &"title", "Fresh run has no acquired equipment")
	tick(2.1)
	expect(arena.mode == &"pickup" and arena.museum.pickup_tool == 2, "Yellow camera is the first physical exhibit")
	expect(is_instance_valid(arena.museum.pickup_root) and arena.director.enemies.is_empty(), "Pickup is visible in a safe museum")
	collect()
	expect(arena.acquired == [2] and arena.weapons.selected_tool == 2, "Walking into light acquires and selects yellow")
	expect(arena.lesson == &"shot" and arena.tutorial.blocking and arena.specimens.size() == 1, "Yellow has solo safe explanation before danger")
	arena.tutorial.request_practice()
	var specimen: Node3D = arena.specimens[0]
	expect(specimen.contact_damage == 0 and specimen.move_speed == 0, "Training specimen cannot chase or injure")
	# Exercise observed resolution across stationary and moving quotas.
	for rep_idx in range(arena._stationary_quota + arena._moving_quota):
		var rep_spec: Node3D = arena.specimens[0]
		rep_spec.health = 0
		arena._on_resolved_hit(&"beam", {"killed": true}, {}, rep_spec.rewind_id)
		arena.director._prune_dead_enemies()
		tick()
	expect(arena.tutorial.is_learned(&"shot") and arena.mode == &"pressure", "Observed quick-shot kills across stationary and moving quotas start sustained pressure")
	expect(arena.director.enemies.size() == 2 and arena._pending == 6, "First arrival is a bounded pair with finite reinforcement debt")
	clear_roster()
	tick(0.1)
	expect(arena.mode == &"pressure" and arena._pending == 6, "Clearing first pair does not skip queued reinforcements")
	var before: Dictionary = arena.capture_state()
	tick(8)
	expect(arena._pending == 4 and arena.director.enemies.size() == 2, "Timed reinforcement arrives through native formation flow")
	expect(not arena.director.flow.cohorts.is_empty(), "Reinforcement uses readable flow arrival warnings")
	arena._step_pressure(99)
	expect(arena.director.enemies.size() == 4 and arena._pending == 2, "Delayed arrivals fill the live cap without dropping pending enemies")
	arena._step_pressure(99)
	expect(arena.director.enemies.size() == 4 and arena._pending == 2, "Full live roster holds reinforcements rather than overflowing")
	arena.restore_campaign_state(before)
	expect(arena._pending == 6 and arena.director.enemies.is_empty(), "Rewind restores reinforcement debt alongside roster")
	expect(arena.acquired == [2] and arena.tutorial.is_learned(&"shot"), "Rewind preserves permanent tool and lesson progress")
	arena.retry_room()
	expect(arena.acquired == [2] and is_equal_approx(arena.time_controller.meter, arena.time_controller.capacity) and arena.time_controller.charges_remaining == 3 and arena.history.snapshot_count == 0, "Retry preserves learned loadout, restores attempt budget, and clears old room rolling history")
	# Fire the real charged traveling pulse through the authored teaching line across stationary and moving quotas.
	arena.tutorial.learned.erase(&"charge")
	arena.director.clear(); arena.wave_index = 0; arena._begin_wave()
	arena.tutorial.request_practice()
	var total_charge_reps: int = arena._stationary_quota + arena._moving_quota
	for rep_idx in range(total_charge_reps):
		var aim: Vector3 = arena.specimens.back().position
		arena.weapons.handle_event(mouse(true), arena.player, aim)
		arena.weapons.step(1, arena.player, aim, arena.director.enemies, 0)
		arena.weapons.handle_event(mouse(false), arena.player, aim)
		arena.weapons.step(0.7, arena.player, aim, arena.director.enemies, 0.7)
		if rep_idx == 0:
			expect(arena._charged_kills.size() >= 2 and arena._pierced, "Actual full-charge pulse pierces the safe yellow teaching line")
		tick()
	expect(arena.tutorial.is_learned(&"charge") and arena.mode == &"pressure", "Real charge practice across stationary and moving quotas releases the sustained charge battle")
	arena.debug_start(0, 2)
	expect(arena.acquired == [2, 3] and arena.mode == &"pressure", "Debug orange checkpoint includes exact prerequisites")
	arena.tutorial.learned.erase(&"repair")
	arena.wave_index = 2; arena.director.clear(); arena._begin_wave()
	expect(arena.lesson == &"repair" and arena.equipment.remaining(&"beam") == 0 and arena.weapons.selected_tool == 2, "One explicit repair lesson exhausts yellow")
	arena.tutorial.request_practice()
	var session: int = arena.equipment.begin_repair(&"beam")
	arena.equipment.complete_step(&"beam", session)
	tick()
	expect(not arena.tutorial.is_learned(&"repair") and not arena.equipment.is_full(&"beam"), "Single repair checkpoint does not prematurely finish full-restoration repair lesson")
	while not arena.equipment.is_full(&"beam"):
		arena.equipment.complete_step(&"beam", session)
	arena.equipment.end_repair(session)
	tick()
	expect(arena.tutorial.is_learned(&"repair") and arena.equipment.is_full(&"beam"), "Full restoration of yellow unlocks repair lesson")
	arena.debug_start(1, 0)
	expect(arena.acquired == [2, 3, 1] and not 4 in arena.weapons.available_tools, "Blue checkpoint has three weapons with no fourth tool")
	arena.weapons.select_tool(4)
	expect(arena.weapons.selected_tool != 4, "Fourth tool selection is rejected")
	arena.debug_start(1, 3)
	expect(arena.acquired == [2, 3, 1], "Acquisition order across campaign is strictly yellow orange blue")
	arena.tutorial.learned.erase(&"rewind")
	arena.rewind_lesson.reset_for_new_run()
	arena.director.clear(); arena.wave_index = 2; arena._begin_wave()
	for i in range(60):
		tick(0.04)
		if arena.is_emergency_active():
			break
	expect(arena.is_emergency_active() and arena.rewind_lesson.active and arena.rewind_lesson.phase == RewindLesson.Phase.SCRUB and arena.time_controller.charges_remaining == 2, "Forced RewindLesson stages incoming hit, freezes in SCRUB phase, and spends one charge during lesson")
	arena.emergency_rewind.step_selection(2)
	arena.emergency_rewind.confirm()
	tick()
	expect(arena.tutorial.is_learned(&"rewind") and is_equal_approx(arena.time_controller.meter, arena.time_controller.capacity) and arena.time_controller.charges_remaining == 3 and arena.mode == &"pressure", "Confirming RewindLesson restores full 3-charge attempt budget and transitions into pressure")
	for index in range(4):
		arena.enter_room(index)
		expect(arena.cover.rectangles == arena.museum.active_cover_rectangles, "Room %d uses matching visible and gameplay cover" % index)
		arena.wave_index = arena.waves.size() - 1
		if index < 3:
			arena._begin_wave()
			var door: Vector3 = arena.room.exit_door.position
			expect(arena.mode == &"exit" and arena.museum.exit_open, "Cleared room %d opens green doorway" % index)
			expect(arena.museum.player_in_exit(door + Vector3(1.8, 0, .6)), "Open doorway threshold is a valid exit region")
			expect(not arena.museum.player_in_exit(door + Vector3(2.4, 0, .6)), "Exit trigger stays inside the physical doorway")
	# Check each battle can drain only after every scheduled enemy actually arrives.
	var total_scheduled := 0
	for ri in range(4):
		var definitions: Array = arena.Rooms.definitions()
		for wi in range(definitions[ri].waves.size()):
			var wave: Dictionary = definitions[ri].waves[wi]
			if bool(wave.get("boss", false)): continue
			arena.debug_start(ri, wi)
			var arrived: int = arena.director.enemies.size()
			for iteration in range(30):
				if arena._pending == 0: break
				clear_roster()
				arena._step_pressure(20)
				arrived += arena.director.enemies.size()
				expect(arena.director.enemies.size() <= int(wave.max_live), "Reinforcements respect live cap")
			expect(arena._pending == 0 and arrived == int(wave.count), "Room %d wave %d delivers complete finite roster" % [ri, wi])
			total_scheduled += arrived
			clear_roster(); tick()
			expect(arena.mode == &"recovery", "Only full pressure clear enters repair interval")
	expect(total_scheduled >= 100, "Full route sustains substantial combat between lessons")
	for checkpoint: Array in [[1, 5, 3], [2, 3, 3], [3, 1, 4]]:
		for phase in range(int(checkpoint[2])):
			arena.debug_start(int(checkpoint[0]), int(checkpoint[1]), phase)
			var boss: Node3D = arena.director.enemies[0]
			expect(arena.mode == &"pressure" and boss.phase == phase, "Developer checkpoint launches requested playable boss phase")
			expect(is_equal_approx(boss.health, boss.max_health * float(boss.phase_count() - phase) / boss.phase_count()), "Boss checkpoint restores the correct remaining phase health")
			expect(boss.get_script() == load("res://scenes/prototype/pattern_enemy.gd"), "Boss checkpoint routes through PatternEnemy.handles")
	arena.debug_start(3, 1)
	expect(arena.mode == &"ceremony", "Final boss opens with actual gate ceremony")
	arena._physics_process(1.2)
	expect(arena.mode == &"pressure" and arena.director.enemies.size() == 1, "Ceremony activates exactly one real final boss")
	for c in range(3):
		arena.time_controller.apply_hit(100.0)
		arena.emergency_rewind.confirm()
		arena.time_controller.advance(2.0)
	arena.time_controller.apply_hit(100.0)
	expect(arena.mode == &"title" and arena.room_index == 3 and arena.time_controller.charges_remaining == 3, "Exhausting all charges restarts current room instead of allowing victory")
	# A dead shooter does not make its surviving bolt safe or erase healthy history.
	arena.debug_start(1,0)
	clear_roster();arena._pending=0
	arena.history.record(arena.history.sample_interval,arena.capture_state)
	arena.director.launch_projectile(Vector3(15,0,15),Vector3.LEFT,10,1)
	tick(.01)
	expect(arena.mode==&"pressure" and arena.history.snapshot_count>0,"Hostile bolts delay quiet recovery and preserve rewind")
	arena.director.projectiles.clear();tick(.01)
	expect(arena.mode==&"recovery","Quiet recovery begins after remaining bolts are gone")
	arena.debug_start(3,1)
	arena._space_action_held=true;arena.weapons.mouse_held=true;arena.weapons.bellows.active=true
	var release:=InputEventKey.new();release.physical_keycode=KEY_SPACE;release.pressed=false
	arena._input(release)
	var mouse_release:=mouse(false);arena._input(mouse_release)
	expect(not arena._space_action_held and not arena.weapons.mouse_held and not arena.weapons.bellows.active,"Boss entrance processes Space and mouse releases")
	root.get_node("SceneManager").clear_popups()
	game.start_game()
	for key in prior: game.set_setting(key, prior[key])
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
