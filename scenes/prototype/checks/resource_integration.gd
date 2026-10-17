extends SceneTree

const Tuning = preload("res://scenes/prototype/tuning.gd")

var checks: int = 0
var failures: Array[String] = []
var arena: Node3D


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: " + description)


func frames() -> void:
	await process_frame
	await process_frame


func mouse_button(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return event


func mouse_motion(held: bool = true) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	return event


func key_event(code: Key, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	return event


func open_repair(scenes: Node, gear: RefCounted, tool: StringName) -> Control:
	var popup: Control = scenes.push_popup(&"Repair", {"equipment": gear, "tool": tool})
	await frames()
	return popup


func board_button(panel: Control, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	var local: Vector2 = panel._board_offset() + point * panel._board_scale()
	event.position = panel.board.get_global_transform_with_canvas() * local
	event.global_position = event.position
	root.push_input(event, true)


func board_motion(panel: Control, point: Vector2, held: bool = true) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	var local: Vector2 = panel._board_offset() + point * panel._board_scale()
	event.position = panel.board.get_global_transform_with_canvas() * local
	event.global_position = event.position
	root.push_input(event, true)


func trace_section(panel: Control, points: Array[Vector2] = []) -> void:
	var path: Array[Vector2] = panel.route.duplicate() if points.is_empty() else points
	board_button(panel, path[0], true)
	for point in path.slice(1):
		board_motion(panel, point, true)
	board_button(panel, path[-1], false)


func fresh_target(location: Vector3 = Vector3(0, 0, -4)) -> Node3D:
	arena.director.clear()
	return arena.director.spawn(&"target", location)


func weapon_tick(delta: float, aim: Vector3) -> void:
	arena.weapons.step(delta, arena.player, aim, arena.director.enemies)


func run() -> void:
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)

	var gear: RefCounted = arena.equipment
	var player: CharacterBody3D = arena.player
	var weapons: Node3D = arena.weapons
	var scenes: Node = root.get_node("SceneManager")
	var state: Node = root.get_node("GameState")

	var ring_cap: float = float(Tuning.GEAR.ring.capacity)
	var beam_cap: float = float(Tuning.GEAR.beam.capacity)
	var cone_cap: float = float(Tuning.GEAR.cone.capacity)
	var clock_cap: float = float(Tuning.GEAR.clock.capacity)
	var steps: int = int(Tuning.REPAIR_STEPS)
	var burst_cost: float = float(Tuning.CONTROL.burst_cost)
	var min_ring_len: float = float(Tuning.RING.minimum_length)

	# 1. Shared equipment binding & invalid/cancelled stroke costs
	arena.reset_arena()
	arena.director.clear()
	expect(player.equipment == gear and weapons.equipment == gear,
		"Arena binds the same shared equipment instance to player and weapons")

	# Single click (zero-length stroke) does not spend ring capacity
	weapons.select_tool(1)
	weapons.handle_event(mouse_button(true), player, Vector3(0, 0, -4))
	weapons.handle_event(mouse_button(false), player, Vector3(0, 0, -4))
	expect(is_equal_approx(gear.remaining(&"ring"), ring_cap) and weapons.ring_phase == "idle",
		"Zero-length ring click does not launch or spend ring capacity")

	# Sub-minimum stroke (< minimum_length) does not spend ring capacity
	var short_end := Vector3(min_ring_len * 0.5, 0, -4)
	weapons.handle_event(mouse_button(true), player, Vector3(0, 0, -4))
	weapons.handle_event(mouse_motion(true), player, short_end)
	weapons.handle_event(mouse_button(false), player, short_end)
	expect(is_equal_approx(gear.remaining(&"ring"), ring_cap) and weapons.ring_phase == "idle",
		"Short ring stroke below minimum_length is rejected without spending capacity")

	# Cancelled stroke via tool switch while drawing costs 0 capacity
	weapons.handle_event(mouse_button(true), player, Vector3(-2, 0, -4))
	weapons.handle_event(mouse_motion(true), player, Vector3(2, 0, -4))
	expect(weapons.ring_drawing and weapons.preview_length >= min_ring_len,
		"Ring preview accumulates valid stroke length while mouse held")
	weapons.select_tool(2)
	weapons.handle_event(mouse_button(false), player, Vector3(2, 0, -4))
	expect(is_equal_approx(gear.remaining(&"ring"), ring_cap) and weapons.ring_phase == "idle",
		"Cancelling ring draw by switching tools spends zero ring capacity")

	# Cancelled stroke via opening Repair popup while drawing costs 0 capacity
	weapons.select_tool(1)
	weapons.handle_event(mouse_button(true), player, Vector3(-2, 0, -4))
	weapons.handle_event(mouse_motion(true), player, Vector3(2, 0, -4))
	var panel: Control = await open_repair(scenes, gear, &"ring")
	weapons.handle_event(mouse_button(false), player, Vector3(2, 0, -4))
	scenes.close_popup(&"Repair")
	await frames()
	expect(is_equal_approx(gear.remaining(&"ring"), ring_cap) and not weapons.ring_drawing and weapons.ring_phase == "idle",
		"Cancelling ring draw by opening repair popup spends zero ring capacity")

	# 2. Shared wear consumption across Ring, Beam (Flash), Cone, and Clock
	# Ring wear: 1 launch per valid release
	weapons.select_tool(1)
	weapons.handle_event(mouse_button(true), player, Vector3(-2, 0, -4))
	weapons.handle_event(mouse_button(false), player, Vector3(2, 0, -4))
	expect(is_equal_approx(gear.remaining(&"ring"), ring_cap - 1.0) and weapons.ring_phase == "outbound",
		"Valid ring launch spends exactly 1 launch unit from shared equipment")
	# Attempt press while ring is in flight costs nothing
	weapons.handle_event(mouse_button(true), player, Vector3(-2, 0, -4))
	weapons.handle_event(mouse_button(false), player, Vector3(2, 0, -4))
	expect(is_equal_approx(gear.remaining(&"ring"), ring_cap - 1.0),
		"Pressing while ring is already in flight does not spend extra capacity")
	weapon_tick(2.0, Vector3.ZERO)
	expect(weapons.ring_phase == "idle", "Launched ring finishes outbound/stroke/return cycle")

	# Spend remaining ring capacity and verify empty ring refuses to draw or launch
	gear.spend(&"ring", gear.remaining(&"ring"))
	weapons.handle_event(mouse_button(true), player, Vector3(-2, 0, -4))
	expect(not weapons.ring_drawing and weapons.ring_phase == "idle",
		"Exhausted ring cannot start drawing or launch")
	weapons.handle_event(mouse_button(false), player, Vector3(2, 0, -4))

	# Beam (Flash) wear: 1 shot per valid fire, cooldown blocks extra spend, empty blocks fire
	var target: Node3D = fresh_target(Vector3(0, 0, -5))
	weapons.select_tool(2)
	weapons.handle_event(mouse_button(true), player, target.position)
	weapons.handle_event(mouse_button(false), player, target.position)
	weapon_tick(0.05, target.position)
	expect(is_equal_approx(gear.remaining(&"beam"), beam_cap - 1.0) and is_equal_approx(target.health, float(Tuning.ENEMIES.target.health) - float(Tuning.BEAM.damage)),
		"Valid beam shot spends 1 shot unit and damages real target")
	# Click during cooldown does not spend
	weapons.handle_event(mouse_button(true), player, target.position)
	weapons.handle_event(mouse_button(false), player, target.position)
	weapon_tick(0.05, target.position)
	expect(is_equal_approx(gear.remaining(&"beam"), beam_cap - 1.0),
		"Beam click during cooldown does not spend shot capacity")
	weapon_tick(float(Tuning.BEAM.cooldown), target.position)
	gear.spend(&"beam", gear.remaining(&"beam"))
	var hp_before_empty_beam: float = target.health
	weapons.handle_event(mouse_button(true), player, target.position)
	weapons.handle_event(mouse_button(false), player, target.position)
	weapon_tick(0.05, target.position)
	expect(is_equal_approx(target.health, hp_before_empty_beam) and is_equal_approx(gear.remaining(&"beam"), 0.0),
		"Exhausted beam does not fire or deal damage")

	# Cone wear: burst_cost on press when ready + continuous seconds, partial final tick scaling
	target = fresh_target(Vector3(0, 0, -3))
	weapons.select_tool(3)
	weapons.handle_event(mouse_button(true), player, target.position)
	weapon_tick(0.5, target.position)
	expect(is_equal_approx(gear.remaining(&"cone"), cone_cap - burst_cost - 0.5),
		"Cone initial press spends burst_cost plus firing delta from shared equipment")
	weapons.handle_event(mouse_button(false), player, target.position)

	# Leave 0.25s in cone while burst is on cooldown, then step 1.0s to verify partial final tick
	gear.spend(&"cone", gear.remaining(&"cone") - 0.25)
	target = fresh_target(Vector3(0, 0, -3))
	weapons.handle_event(mouse_button(true), player, target.position)
	weapon_tick(1.0, target.position)
	var expected_partial_dmg: float = float(Tuning.CONE.damage_per_second) * 0.25
	expect(is_equal_approx(gear.remaining(&"cone"), 0.0) and not weapons.cone_active,
		"Cone spends only remaining capacity on final tick and deactivates when empty")
	expect(is_equal_approx(float(Tuning.ENEMIES.target.health) - target.health, expected_partial_dmg),
		"Cone scales final-tick damage to actual afforded time")
	weapons.handle_event(mouse_button(false), player, target.position)

	# Clock wear: real-time drain, no passive regeneration, partial final tick world_scale
	player._step_slow(0.05, false)
	player._step_slow(1.5, true)
	expect(is_equal_approx(gear.remaining(&"clock"), clock_cap - 1.5 * float(Tuning.SLOW.drain)) and is_equal_approx(player.slow_charge, gear.remaining(&"clock")),
		"Clock drains in real seconds and player.slow_charge mirrors shared bank")
	expect(is_equal_approx(player.world_scale, float(Tuning.SLOW.scale)),
		"Active slow sets player.world_scale to Tuning.SLOW.scale")
	var clock_after_use: float = gear.remaining(&"clock")
	player._step_slow(3.0, false)
	expect(is_equal_approx(gear.remaining(&"clock"), clock_after_use) and is_equal_approx(player.world_scale, 1.0),
		"Releasing slow restores normal world_scale with zero passive clock regeneration")

	# Partial final tick on clock
	gear.spend(&"clock", gear.remaining(&"clock") - 0.4)
	player._step_slow(0.05, false)
	player._step_slow(1.0, true)
	var expected_scale: float = lerpf(1.0, float(Tuning.SLOW.scale), 0.4 / 1.0)
	expect(is_equal_approx(gear.remaining(&"clock"), 0.0) and is_equal_approx(player.world_scale, expected_scale),
		"Clock partial final tick spends remaining charge and blends world_scale proportionally")

	# 3. Repair restores usable capacity across all four tools
	for tool: StringName in [&"ring", &"beam", &"cone", &"clock"]:
		var cap: float = gear.capacity(tool)
		var quarter: float = cap / float(steps)
		expect(is_equal_approx(gear.remaining(tool), 0.0) and not gear.can_use(tool),
			"%s starts depleted before repair check" % String(tool))
		panel = await open_repair(scenes, gear, tool)
		expect(gear.repairing == tool and not gear.can_use(tool),
			"Opening repair locks %s as actively repairing" % String(tool))
		trace_section(panel)
		expect(gear.stage(tool) == 1 and is_equal_approx(gear.remaining(tool), quarter),
			"One completed repair trace immediately restores 1/%d capacity for %s" % [steps, String(tool)])
		scenes.close_popup(&"Repair")
		await frames()
		expect(gear.repairing == &"" and gear.can_use(tool),
			"Closing repair unlocks %s with restored capacity ready for use" % String(tool))

	# Verify each repaired 1/4 capacity actually works in gameplay
	target = fresh_target(Vector3(0, 0, -4))
	weapons.select_tool(1)
	weapons.handle_event(mouse_button(true), player, Vector3(-2, 0, -4))
	weapons.handle_event(mouse_button(false), player, Vector3(2, 0, -4))
	weapon_tick(0.5, target.position)
	expect(is_equal_approx(gear.remaining(&"ring"), ring_cap / float(steps) - 1.0) and target.health < float(Tuning.ENEMIES.target.health),
		"Repaired ring launches and hits target enemy")
	weapon_tick(2.0, target.position)

	target = fresh_target(Vector3(0, 0, -4))
	weapons.select_tool(2)
	weapons.handle_event(mouse_button(true), player, target.position)
	weapons.handle_event(mouse_button(false), player, target.position)
	weapon_tick(0.05, target.position)
	expect(is_equal_approx(gear.remaining(&"beam"), beam_cap / float(steps) - 1.0) and target.health < float(Tuning.ENEMIES.target.health),
		"Repaired beam fires and damages target enemy")

	target = fresh_target(Vector3(0, 0, -3))
	weapons.select_tool(3)
	weapons.cone_burst_cooldown = 0.0
	weapons.handle_event(mouse_button(true), player, target.position)
	weapon_tick(0.2, target.position)
	weapons.handle_event(mouse_button(false), player, target.position)
	expect(gear.remaining(&"cone") < cone_cap / float(steps) and target.health < float(Tuning.ENEMIES.target.health),
		"Repaired cone fires and damages target enemy")

	player._step_slow(0.05, false)
	player._step_slow(0.5, true)
	expect(is_equal_approx(player.world_scale, float(Tuning.SLOW.scale)) and is_equal_approx(gear.remaining(&"clock"), clock_cap / float(steps) - 0.5),
		"Repaired clock slows world time and spends restored charge")
	player._step_slow(0.05, false)

	# 4. Interrupted popup preserves completed steps (invalid gesture, manual close, pause, enemy damage)
	arena.reset_arena()
	arena.director.clear()
	gear.spend(&"ring", ring_cap)
	panel = await open_repair(scenes, gear, &"ring")
	trace_section(panel)
	expect(gear.stage(&"ring") == 1 and is_equal_approx(gear.remaining(&"ring"), ring_cap / float(steps)),
		"First section completed before interruptions")

	# Start second gesture then leave corridor (invalid trace)
	board_button(panel, panel.route[0], true)
	board_motion(panel, Vector2(300, 5), true)
	board_button(panel, Vector2(300, 5), false)
	expect(panel.trace_bad and not panel.dragging and gear.stage(&"ring") == 1 and is_equal_approx(gear.remaining(&"ring"), ring_cap / float(steps)),
		"Invalid trace clears only unfinished gesture and preserves completed stage and capacity")

	# Start second gesture then close with E mid-trace
	board_button(panel, panel.route[0], true)
	board_motion(panel, panel.route[1], true)
	expect(panel.dragging, "Second gesture is in progress before closing popup")
	root.push_input(key_event(KEY_E), true)
	await frames()
	expect(not scenes.has_popup(&"Repair") and gear.repairing == &"" and gear.stage(&"ring") == 1 and is_equal_approx(gear.remaining(&"ring"), ring_cap / float(steps)),
		"Closing popup mid-trace preserves completed steps and releases repair lock")

	# Reopen, complete section 2, start section 3, then interrupt via actual enemy contact damage in arena._physics_process
	panel = await open_repair(scenes, gear, &"ring")
	expect(panel.route[1] == panel.ROUTES[1][1], "Reopened repair resumes at stage 1 route")
	trace_section(panel)
	expect(gear.stage(&"ring") == 2 and is_equal_approx(gear.remaining(&"ring"), ring_cap * 2.0 / float(steps)),
		"Second section completes after reopen")
	board_button(panel, panel.route[0], true)
	board_motion(panel, panel.route[1], true)
	arena.director.clear()
	player.reset_state()
	arena.director.spawn(&"swarmer", Vector3.ZERO)
	var hp_before_hit: float = player.health
	arena._physics_process(0.1)
	await frames()
	expect(player.health < hp_before_hit and not scenes.has_popup(&"Repair") and gear.repairing == &"",
		"Enemy contact damage during arena tick closes repair popup and clears repairing lock")
	expect(gear.stage(&"ring") == 2 and is_equal_approx(gear.remaining(&"ring"), ring_cap * 2.0 / float(steps)),
		"Enemy damage interruption preserves all previously completed repair steps and capacity")
	arena.director.clear()

	# 5. Own-clock repair disables slow, while repairing another tool permits slow
	arena.reset_arena()
	arena.director.clear()
	gear.spend(&"clock", clock_cap * 0.5)
	var clock_mid: float = gear.remaining(&"clock")
	panel = await open_repair(scenes, gear, &"clock")
	player._step_slow(0.05, false)
	player._step_slow(0.5, true)
	expect(is_equal_approx(player.world_scale, 1.0) and is_equal_approx(gear.remaining(&"clock"), clock_mid),
		"Clock cannot power time slow while its own repair session is active")
	expect(player.status_text().contains("clock repair"),
		"Player status_text explains slow is disabled during clock repair")
	scenes.close_popup(&"Repair")
	await frames()

	# Repairing another tool (e.g. ring) permits time slow
	gear.spend(&"ring", ring_cap * 0.5)
	panel = await open_repair(scenes, gear, &"ring")
	expect(gear.repairing == &"ring", "Ring is currently being repaired")
	player._step_slow(0.05, false)
	player._step_slow(0.5, true)
	expect(is_equal_approx(player.world_scale, float(Tuning.SLOW.scale)) and is_equal_approx(gear.remaining(&"clock"), clock_mid - 0.5 * float(Tuning.SLOW.drain)),
		"Repairing another tool still permits slowing world time with the clock")
	player._step_slow(0.05, false)
	scenes.close_popup(&"Repair")
	await frames()

	# 6. Close/switch doesn't leave ghost firing (require_fresh_press & popup open/close)
	arena.reset_arena()
	target = fresh_target(Vector3(0, 0, -3))
	weapons.select_tool(3)
	weapons.handle_event(mouse_button(true), player, target.position)
	weapon_tick(0.1, target.position)
	expect(weapons.cone_active and weapons.mouse_held, "Cone is firing while mouse button is held")

	# Switch from Cone (3) to Beam (2) while mouse held -> stops cone, does not fire beam until fresh press
	var beam_before_switch: float = gear.remaining(&"beam")
	var cone_before_switch: float = gear.remaining(&"cone")
	weapons.handle_event(key_event(KEY_2), player, target.position)
	weapon_tick(0.2, target.position)
	expect(weapons.selected_tool == 2 and not weapons.cone_active and weapons.require_fresh_press,
		"Switching tool while holding LMB stops cone and requires a fresh mouse press")
	expect(is_equal_approx(gear.remaining(&"beam"), beam_before_switch) and is_equal_approx(gear.remaining(&"cone"), cone_before_switch),
		"Held mouse across tool switch does not ghost-fire new tool or drain old tool")

	# Switch to Ring (1) while still holding mouse -> moving & releasing mouse does not draw or launch ring
	weapons.handle_event(key_event(KEY_1), player, target.position)
	weapons.handle_event(mouse_motion(true), player, Vector3(2, 0, -3))
	weapons.handle_event(mouse_button(false), player, Vector3(2, 0, -3))
	expect(not weapons.ring_drawing and weapons.ring_phase == "idle" and is_equal_approx(gear.remaining(&"ring"), ring_cap),
		"Held mouse across switch to Ring does not ghost-draw or launch on release")

	# Popup open/close while holding Cone cancels firing and blocks ghost firing after popup closes
	weapons.select_tool(3)
	weapons.handle_event(mouse_button(true), player, target.position)
	weapon_tick(0.1, target.position)
	expect(weapons.cone_active, "Cone active before opening repair popup")
	var cone_at_open: float = gear.remaining(&"cone")
	panel = await open_repair(scenes, gear, &"ring")
	expect(not weapons.cone_active and weapons.require_fresh_press,
		"Opening repair popup cancels active cone and requires fresh press")
	scenes.close_popup(&"Repair")
	await frames()
	weapon_tick(0.25, target.position)
	weapons.handle_event(mouse_motion(true), player, target.position)
	expect(not weapons.cone_active and is_equal_approx(gear.remaining(&"cone"), cone_at_open),
		"Closing repair popup while mouse remains held does not resume ghost cone firing")
	weapons.handle_event(mouse_button(false), player, target.position)

	# Popup open/close while drawing Ring cancels preview and prevents ghost launch on release after close
	weapons.select_tool(1)
	weapons.handle_event(mouse_button(true), player, Vector3(-2, 0, -4))
	weapons.handle_event(mouse_motion(true), player, Vector3(2, 0, -4))
	expect(weapons.ring_drawing, "Ring drawing active before opening repair popup")
	panel = await open_repair(scenes, gear, &"beam")
	expect(not weapons.ring_drawing and weapons.preview_points.is_empty(),
		"Opening repair popup cancels in-progress ring drawing")
	scenes.close_popup(&"Repair")
	await frames()
	weapons.handle_event(mouse_button(false), player, Vector3(2, 0, -4))
	expect(weapons.ring_phase == "idle" and is_equal_approx(gear.remaining(&"ring"), ring_cap),
		"Releasing mouse after closing repair popup does not ghost-launch cancelled ring")

	# Already-launched ring continues flight across tool switch
	weapons.handle_event(mouse_button(true), player, Vector3(-2, 0, -4))
	weapons.handle_event(mouse_button(false), player, Vector3(2, 0, -4))
	expect(weapons.ring_phase == "outbound", "Ring launched before tool switch")
	weapons.select_tool(2)
	weapon_tick(2.0, Vector3.ZERO)
	expect(weapons.ring_phase == "idle", "Already-launched ring completes its flight after switching tools")

	# 7. R clears active state (popup, partial repair stage, wear, active weapons, slow, health, roster)
	gear.spend(&"ring", 20.0)
	gear.spend(&"beam", 15.0)
	gear.spend(&"cone", 10.0)
	gear.spend(&"clock", 8.0)
	panel = await open_repair(scenes, gear, &"ring")
	trace_section(panel)
	expect(gear.stage(&"ring") == 1 and scenes.has_popup(&"Repair"), "Dirty repair state prepared before R reset")
	scenes.close_popup(&"Repair")
	await frames()

	weapons.select_tool(3)
	weapons.handle_event(mouse_button(true), player, Vector3(0, 0, -3))
	weapon_tick(0.1, Vector3(0, 0, -3))
	player.take_damage(35.0)
	player._step_slow(0.05, false)
	player._step_slow(0.2, true)
	panel = await open_repair(scenes, gear, &"cone")

	arena._unhandled_input(key_event(KEY_R))
	await frames()
	expect(not scenes.has_popup(&"Repair") and gear.repairing == &"",
		"R closes open repair popup and clears repairing session")
	for tool: StringName in [&"ring", &"beam", &"cone", &"clock"]:
		expect(is_equal_approx(gear.remaining(tool), gear.capacity(tool)) and gear.stage(tool) == 0,
			"R restores full capacity and stage 0 for %s" % String(tool))
	expect(weapons.selected_tool == 1 and not weapons.cone_active and not weapons.ring_drawing and weapons.ring_phase == "idle" and not weapons.require_fresh_press,
		"R resets weapon selection, active firing, ring flight, and input latches")
	expect(is_equal_approx(player.health, float(Tuning.PLAYER.health)) and is_equal_approx(player.world_scale, 1.0) and is_equal_approx(player.slow_charge, clock_cap),
		"R restores player health, normal world_scale, and full clock charge")
	expect(state.is_playing() and Engine.time_scale == 1.0,
		"GameState remains playing and Engine.time_scale stays 1.0")

	arena.queue_free()
	await frames()
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
