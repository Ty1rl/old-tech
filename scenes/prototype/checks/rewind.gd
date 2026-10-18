extends SceneTree

const Tuning = preload("res://scenes/prototype/tuning.gd")
var arena: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func key(code: Key, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	root.push_input(event, true)

func wheel(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	root.push_input(event, true)

func fresh() -> void:
	key(KEY_SPACE, false)
	arena.reset_arena()
	arena.director.clear()

func seed_history() -> void:
	fresh()
	arena.director.spawn(&"target", Vector3(0, 0, -5))
	for i in range(40):
		arena.player.position.x = float(i) * 0.05
		arena.history.record(0.05, arena.capture_state)
	arena.player.take_damage(70)
	arena.director.enemies[0].hit(90, Vector3.ZERO)
	arena.equipment.spend(&"ring", 8)
	arena.history.record(0.05, arena.capture_state)
	key(KEY_4)

func run() -> void:
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	var scenes := root.get_node("SceneManager")
	for tool in range(1, 5):
		fresh()
		key(KEY_1 + tool - 1)
		key(KEY_E)
		expect(not scenes.has_popup(), "Full tool %d ignores repair" % tool)
		key(KEY_E, false)
		arena.equipment.spend(arena.Weapons.TOOL_IDS[tool - 1], 1)
		key(KEY_E)
		expect(scenes.has_popup(&"Repair") and arena.equipment.repairing == arena.Weapons.TOOL_IDS[tool - 1], "E repairs selected tool %d" % tool)
		var clock_before: float = arena.player.slow_charge
		arena._physics_process(0.1)
		if tool < 4:
			expect(is_equal_approx(arena.player.world_scale, Tuning.SLOW.scale)
				and is_equal_approx(arena.player.slow_charge, clock_before - 0.1 * Tuning.SLOW.drain),
				"Tool %d repair automatically spends clock to slow world" % tool)
		else:
			expect(arena.player.world_scale == 1 and arena.player.slow_charge == clock_before,
				"Clock repair cannot power its own slow")
		key(KEY_E, false)
		await process_frame
		clock_before = arena.player.slow_charge
		arena._physics_process(0.1)
		expect(arena.player.world_scale == 1 and arena.player.slow_charge == clock_before,
			"E release stops automatic repair slow for tool %d" % tool)
		expect(not scenes.has_popup(&"Repair") and arena.equipment.repairing == &"", "Releasing E resumes tool %d" % tool)

	fresh()
	arena.equipment.spend(&"ring", 1)
	arena.equipment.spend(&"clock", arena.player.slow_charge)
	key(KEY_E)
	arena._physics_process(0.1)
	expect(arena.player.world_scale == 1 and scenes.has_popup(&"Repair"),
		"Empty clock leaves other equipment repair usable at normal speed")
	key(KEY_E, false)
	await process_frame

	seed_history()
	var present_position: Vector3 = arena.player.position
	var present_clock: float = arena.player.slow_charge
	key(KEY_SPACE)
	expect(arena.history.inspecting and not paused, "Clock Space starts inspection without pausing engine")
	Input.action_press("move_right")
	arena._physics_process(0.5)
	Input.action_release("move_right")
	expect(arena.player.position == present_position and arena.player.health == 30, "Inspection freezes movement and combat")
	expect(is_equal_approx(arena.player.slow_charge, present_clock - 0.1), "Inspection drains clock in real time")
	wheel(MOUSE_BUTTON_WHEEL_DOWN)
	wheel(MOUSE_BUTTON_WHEEL_DOWN)
	expect(arena.history.selected_seconds_ago > 0.4 and arena.player.health == 100, "Wheel selects an earlier undamaged state")
	expect(arena.director.enemies[0].health == 100 and arena.equipment.remaining(&"ring") == arena.equipment.capacity(&"ring"), "Preview restores enemy damage and other gear")
	var reserved_age: float = arena.history.selected_seconds_ago
	key(KEY_E)
	key(KEY_R)
	expect(arena.weapons.selected_tool == 4 and not scenes.has_popup() and arena.history.selected_seconds_ago == reserved_age, "Inspection blocks repair and debug actions; equip is tested as an explicit cancel")
	key(KEY_E, false)
	wheel(MOUSE_BUTTON_WHEEL_UP)
	wheel(MOUSE_BUTTON_WHEEL_UP)
	expect(arena.history.selected_seconds_ago == 0 and arena.player.health == 30, "Scrolling forward recovers exact present")
	wheel(MOUSE_BUTTON_WHEEL_DOWN)
	key(KEY_ESCAPE)
	expect(not arena.history.inspecting and not paused and arena.player.health == 30, "Escape cancels preview without changing outcomes or opening pause")
	expect(is_equal_approx(arena.player.slow_charge, present_clock - 0.1), "Cancellation retains inspection wear and charges no jump")

	key(KEY_SPACE, false)
	key(KEY_SPACE)
	arena._seek_inspection(0.75)
	var jump: float = arena.inspection_cost()
	arena._physics_process(0.5)
	var live_clock: float = arena.player.slow_charge
	key(KEY_SPACE, false)
	expect(not arena.history.inspecting and arena.player.health == 100, "Releasing Space commits the selected do-over")
	expect(is_equal_approx(arena.player.slow_charge, live_clock - jump), "Jump cost is paid once without refunding inspection wear")
	expect(arena.director.enemies[0].health == 100 and arena.equipment.remaining(&"ring") == arena.equipment.capacity(&"ring"), "Commit restores damage and other equipment condition")
	expect(arena.history.available_seconds < 1.6 and arena.weapons.selected_tool == 4, "Commit discards future while leaving clock equipped")

	seed_history()
	arena.equipment.spend(&"clock", arena.player.slow_charge - 0.3)
	key(KEY_SPACE)
	arena._seek_inspection(1.0)
	expect(arena.history.selected_seconds_ago == 0 and arena.player.health == 30,
		"Unaffordable selection leaves the prior preview unchanged")
	key(KEY_SPACE, false)
	expect(is_equal_approx(arena.player.slow_charge, 0.3), "Returning to NOW never refunds previously spent clock")

	seed_history()
	key(KEY_SPACE)
	arena._seek_inspection(1.0)
	arena._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(not arena.history.inspecting and arena.player.health == 30 and paused, "Focus loss cancels to present before pause")
	root.get_node("GameState").resume()
	await process_frame
	key(KEY_SPACE, false)

	seed_history()
	key(KEY_SPACE)
	arena._seek_inspection(0.5)
	arena._inspection_clock = 0.001
	arena._physics_process(1)
	expect(not arena.history.inspecting and arena.player.health == 30 and arena.player.slow_charge == 0, "Exhaustion returns to present, never forces a jump")

	seed_history()
	arena.player.health = 0
	arena.director.encounter_state = &"defeat"
	arena.history.record(0.05, arena.capture_state)
	var count: int = arena.history.snapshot_count
	arena._physics_process(10)
	expect(arena.history.snapshot_count == count, "Death preserves last live history instead of overwriting it")
	key(KEY_SPACE)
	arena._seek_inspection(0.5)
	key(KEY_SPACE, false)
	expect(arena.player.health == 100 and arena.director.encounter_state != &"defeat", "Rewind restores life and encounter state")

	fresh()
	key(KEY_3)
	key(KEY_SPACE)
	key(KEY_4)
	expect(arena.history.inspecting, "Equipping clock while Space held seamlessly starts inspection")
	key(KEY_SPACE, false)
	key(KEY_SPACE)
	expect(arena.history.inspecting, "Fresh Space after equipping clock starts inspection")
	key(KEY_SPACE, false)

	fresh()
	var victim: Node3D = arena.director.spawn(&"target", Vector3(0, 0, -3))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	arena.weapons.handle_event(click, arena.player, Vector3(-2, 0, -3))
	click.pressed = false
	arena.weapons.handle_event(click, arena.player, Vector3(2, 0, -3))
	arena.weapons.step(0.19, arena.player, Vector3.ZERO, arena.director.enemies)
	var cut_state: Dictionary = arena.capture_state()
	var hp_after_cut: float = victim.health
	expect(hp_after_cut < 100 and arena.weapons.ring_phase == "stroke", "Capture a real cutting ring after its first hit")
	victim.hit(1000, Vector3.ZERO)
	arena.director.step(0, arena.player)
	arena._restore_world(cut_state, arena.player.slow_charge)
	expect(arena.director.enemies.size() == 1 and arena.weapons.ring_phase == "stroke", "Restore revives killed enemy and in-flight attack together")
	arena.weapons.step(1, arena.player, Vector3.ZERO, arena.director.enemies)
	expect(arena.director.enemies[0].health == hp_after_cut, "Restored ring preserves once-per-launch hits across enemy recreation")

	fresh()
	for i in range(32):
		arena.director.spawn(&"swarmer", Vector3(i % 8 - 4, 0, -8 - i / 8))
	for frame in range(150):
		arena.history.record(0.05, arena.capture_state)
	expect(arena.history.snapshot_count <= 100 and arena.history.available_seconds <= 5, "Real arena snapshots retain bounded history")
	expect(arena.history.rejected_count == 0 and arena.history.encoded_bytes <= 6553600, "Real 32-enemy snapshots fit encoded memory cap")
	var bytes: int = arena.history.encoded_bytes
	arena.reset_arena()
	expect(arena.history.snapshot_count == 0 and not arena.history.inspecting, "Reset clears all rewind history")
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures, "real_32_enemy_history_bytes": bytes}))
	quit(0 if failures.is_empty() else 1)
