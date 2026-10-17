extends SceneTree

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func frames() -> void:
	await process_frame
	await process_frame


func open(scenes: Node, gear: RefCounted, tool: StringName) -> Control:
	var popup: Control = scenes.push_popup(&"Repair", {"equipment": gear, "tool": tool})
	await frames()
	return popup


func button(panel: Control, point: Vector2, pressed: bool, direct: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	var local: Vector2 = panel._board_offset() + point * panel._board_scale()
	event.position = local if direct else panel.board.get_global_transform_with_canvas() * local
	event.global_position = event.position
	if direct:
		panel._on_board_input(event)
	else:
		root.push_input(event, true)


func motion(panel: Control, point: Vector2, direct: bool = false, held: bool = true) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	var local: Vector2 = panel._board_offset() + point * panel._board_scale()
	event.position = local if direct else panel.board.get_global_transform_with_canvas() * local
	event.global_position = event.position
	if direct:
		panel._on_board_input(event)
	else:
		root.push_input(event, true)


func trace(panel: Control, points: Array[Vector2] = [], direct: bool = false) -> void:
	var path: Array[Vector2] = panel.route.duplicate() if points.is_empty() else points
	button(panel, path[0], true, direct)
	for point in path.slice(1):
		motion(panel, point, direct)
	button(panel, path[-1], false, direct)


func key(code: Key, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	root.push_input(event, true)


func run() -> void:
	var arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	var gear: RefCounted = arena.equipment
	var scenes := root.get_node("SceneManager")
	var state := root.get_node("GameState")
	gear.spend(&"ring", gear.capacity(&"ring"))
	var panel: Control = await open(scenes, gear, &"ring")
	expect(not paused and gear.repairing == &"ring", "Setup acquires repair session before ready without pausing world")
	expect(panel.progress.text.contains("0 / 4") and panel.heading.text.contains("Ring"), "UI identifies item, persistent stage and capacity")
	button(panel, Vector2(300, 20), true)
	button(panel, Vector2(300, 20), false)
	expect(not panel.dragging and gear.stage(&"ring") == 0, "Starting outside contact one does not award repair")
	trace(panel, [panel.route[0]])
	expect(gear.remaining(&"ring") == 0 and panel.trace_bad, "Short click fails without penalty or free capacity")
	trace(panel, [panel.route[0], panel.route[-1]])
	expect(gear.remaining(&"ring") == 0 and panel.trace_bad, "Sparse diagonal shortcut cannot skip route bends")
	button(panel, panel.route[0], true)
	for point in panel.route.slice(1):
		motion(panel, point)
	expect(gear.remaining(&"ring") == 0 and panel.dragging, "Finishing motion alone cannot complete a section")
	button(panel, panel.route[-1], false)
	expect(gear.stage(&"ring") == 1 and gear.remaining(&"ring") == gear.capacity(&"ring") / 4.0, "One deliberate valid release restores a quarter and advances one stage")
	button(panel, panel.route[-1], false)
	expect(gear.stage(&"ring") == 1, "Duplicate release cannot repair the next section")
	button(panel, panel.route[0], true)
	motion(panel, panel.route[1])
	key(KEY_E)
	await frames()
	expect(not scenes.has_popup(&"Repair") and gear.repairing == &"", "E closes repair and releases its session")
	expect(gear.stage(&"ring") == 1 and gear.remaining(&"ring") == 8, "Closing mid-gesture preserves only completed stage and capacity")
	panel = await open(scenes, gear, &"ring")
	expect(panel.route[1] == panel.ROUTES[1][1] and not panel.dragging, "Reopening resumes completed stage with a fresh unfinished gesture")
	trace(panel)
	expect(gear.stage(&"ring") == 2 and gear.remaining(&"ring") == 16, "Resumed next section continues prior progress")
	var player: CharacterBody3D = arena.player
	var origin: Vector3 = player.position
	Input.action_press("move_right")
	for tick in range(12):
		await physics_frame
		player.step(1.0 / float(Engine.physics_ticks_per_second), Vector3(10, 0, 0))
	Input.action_release("move_right")
	expect(player.position.x > origin.x + 0.5 and not paused, "WASD stays responsive while repair is open")
	button(panel, panel.route[0], true)
	motion(panel, panel.route[1])
	state.pause()
	expect(not panel.dragging and paused and scenes.has_popup(&"PauseMenu"), "Opening Pause above Repair cancels only unfinished gesture")
	trace(panel, [], true)
	expect(gear.stage(&"ring") == 2 and gear.remaining(&"ring") == 16, "Even direct synthetic board events cannot progress a paused repair")
	state.resume()
	await frames()
	trace(panel)
	expect(gear.stage(&"ring") == 3 and gear.remaining(&"ring") == 24, "Fresh trace works after pause resume")
	scenes.push_popup(&"PauseMenu")
	await frames()
	expect(not paused, "A popup alone does not pause GameState")
	trace(panel, [], true)
	expect(gear.stage(&"ring") == 3, "Pause popup above Repair blocks progress even when tree is unpaused")
	scenes.close_popup(&"PauseMenu")
	await frames()
	button(panel, panel.route[0], true)
	motion(panel, panel.route[1])
	panel._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(not panel.dragging and gear.stage(&"ring") == 3, "Focus loss discards current trace without erasing completed work")
	button(panel, panel.route[1], false)
	button(panel, panel.route[0], true)
	motion(panel, panel.route[1], false, false)
	expect(not panel.dragging and gear.stage(&"ring") == 3, "Lost button mask releases trace without stuck input or progress loss")
	button(panel, panel.route[1], false)
	trace(panel)
	expect(gear.remaining(&"ring") == gear.capacity(&"ring") and gear.stage(&"ring") == 0, "Fourth section reaches full capacity and resets persistent stage")
	expect(panel.progress.text.begins_with("Ready") and not panel.progress.text.contains("0 / 4"), "Full equipment shows Ready rather than a misleading zero-stage failure")
	trace(panel)
	expect(gear.remaining(&"ring") == gear.capacity(&"ring") and not panel.dragging, "Ready panel cannot overfill gear or accept further repair strokes")
	key(KEY_E, true)
	expect(scenes.has_popup(&"Repair"), "Key echo does not close repair")
	key(KEY_ESCAPE)
	await frames()
	expect(not scenes.has_popup() and not paused and state.is_playing(), "Escape closes Repair without opening PauseMenu")

	for tool: StringName in [&"ring", &"beam", &"cone", &"clock"]:
		gear.reset_state()
		gear.spend(tool, gear.capacity(tool))
		panel = await open(scenes, gear, tool)
		if tool == &"beam":
			expect(panel.heading.text.contains("Flash"), "Beam equipment ID is labeled Flash in repair UI")
		for stage in range(4):
			trace(panel)
			expect(is_equal_approx(gear.remaining(tool), gear.capacity(tool) * float(stage + 1) / 4.0), "Same shared puzzle repairs %s section %d" % [tool, stage + 1])
		expect(panel.progress.text.begins_with("Ready"), "Full %s reports Ready" % tool)
		scenes.close_popup(&"Repair")
		await frames()

	gear.reset_state()
	gear.spend(&"ring", 24)
	gear.spend(&"clock", 18)
	panel = await open(scenes, gear, &"ring")
	trace(panel)
	panel.setup({"equipment": gear, "tool": &"clock"})
	expect(gear.repairing == &"clock" and gear.stage(&"ring") == 1 and gear.remaining(&"ring") == 16, "Switching setup to clock keeps ring progress and replaces session")
	trace(panel)
	panel.setup({"equipment": gear, "tool": &"ring"})
	expect(gear.stage(&"clock") == 1 and gear.remaining(&"clock") == 12 and panel.route[1] == panel.ROUTES[1][1], "Switching back resumes each item's own progress")
	var old_panel: Control = panel
	var newer: Control = await open(scenes, gear, &"clock")
	trace(old_panel, [], true)
	expect(gear.stage(&"ring") == 1, "Covered stale panel cannot finish an obsolete session")
	old_panel.queue_free()
	await frames()
	expect(gear.repairing == &"clock", "Old panel exit token cannot cancel the newer clock repair")
	trace(newer)
	expect(gear.stage(&"clock") == 2 and gear.remaining(&"clock") == 18, "Newer session remains playable after old panel destruction")
	scenes.close_popup(&"Repair")
	await frames()

	gear.reset_state()
	gear.spend(&"ring", 24)
	panel = await open(scenes, gear, &"ring")
	trace(panel)
	button(panel, panel.route[0], true)
	motion(panel, panel.route[1])
	arena.director.clear()
	player.reset_state()
	arena.director.spawn(&"swarmer", Vector3.ZERO)
	var health_before: float = player.health
	arena._physics_process(0.1)
	await frames()
	expect(player.health < health_before and not scenes.has_popup(&"Repair"), "Actual arena enemy contact damage closes the repair popup")
	expect(gear.stage(&"ring") == 1 and gear.remaining(&"ring") == 16 and gear.repairing == &"", "Damage interruption preserves completed repair without leaving a lock")
	arena.director.clear()
	panel = await open(scenes, gear, &"ring")
	arena.reset_arena()
	await frames()
	expect(not scenes.has_popup() and gear.stage(&"ring") == 0 and gear.remaining(&"ring") == gear.capacity(&"ring"), "Explicit arena reset closes repair and fully resets equipment")
	expect(Engine.time_scale == 1.0, "Repair never changes global engine time or introduces its own clock")
	arena.queue_free()
	await frames()
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
