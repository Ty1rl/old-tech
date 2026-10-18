extends SceneTree

const Gestures = preload("res://scenes/prototype/repair_gestures.gd")

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


func click_point(panel: Control, point: Vector2, direct: bool = false) -> void:
	button(panel, point, true, direct)
	button(panel, point, false, direct)


func click_connect_pair(panel: Control, pair_index: int, direct: bool = false) -> void:
	var pairs: Array = panel.active_op["pairs"]
	var pair: Dictionary = pairs[pair_index]
	click_point(panel, pair["a"], direct)
	click_point(panel, pair["b"], direct)


func trace(panel: Control, points: Array[Vector2] = [], direct: bool = false) -> void:
	var path: Array[Vector2] = panel.route.duplicate() if points.is_empty() else points
	button(panel, path[0], true, direct)
	for point in path.slice(1):
		motion(panel, point, direct)
	button(panel, path[-1], false, direct)


func key(code: Key, echo: bool = false, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	root.push_input(event, true)


func has_button_child(node: Node) -> bool:
	if node is Button:
		return true
	for child in node.get_children():
		if has_button_child(child):
			return true
	return false


func run() -> void:
	# 0. Verify pure RepairGestures specifications and tool operation sequences
	var ring_ops: Array = Gestures.tool_spec(&"ring")["operations"]
	var beam_ops: Array = Gestures.tool_spec(&"beam")["operations"]
	var cone_ops: Array = Gestures.tool_spec(&"cone")["operations"]
	var clock_ops: Array = Gestures.tool_spec(&"clock")["operations"]
	expect(ring_ops[0]["kind"] == &"spin" and ring_ops[1]["kind"] == &"connect" and ring_ops[2]["kind"] == &"trace",
		"Blue (ring) repair order is cassette spin -> matching contacts -> blade alignment trace")
	expect(beam_ops[0]["kind"] == &"spin" and beam_ops[1]["kind"] == &"connect" and beam_ops[2]["kind"] == &"trace",
		"Yellow (beam/Flash) repair order is lens ring spin -> top ceramic terminals -> bellows trace")
	expect(cone_ops[0]["kind"] == &"spin" and cone_ops[1]["kind"] == &"trace" and cone_ops[2]["kind"] == &"connect"
		and bool(Gestures.tool_spec(&"cone").get("open_cover_and_grille", false)),
		"Orange (cone/Bellows) repair order is fan spin -> leather trace -> heating-coil contacts with open cover/grille")
	expect(clock_ops[0]["kind"] == &"spin" and clock_ops[1]["kind"] == &"trace" and clock_ops[2]["kind"] == &"connect",
		"Purple (clock/Time Device) repair order is side-key spin -> pendulum trace -> cassette matching contacts")

	root.size = Vector2i(960, 600)
	var arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	var gear: RefCounted = arena.equipment
	var scenes := root.get_node("SceneManager")
	var state := root.get_node("GameState")

	# 1. Compact, offset layout at 960x600 with tool-matched 3D SubViewport backdrop and no Resume button
	gear.spend(&"ring", gear.capacity(&"ring"))
	var panel: Control = await open(scenes, gear, &"ring")
	expect(not paused and gear.repairing == &"ring", "Setup acquires repair session before ready without pausing world")
	expect(panel.progress.text.contains("0 / 4") and panel.heading.text.contains("Ring"), "UI identifies item, derived stage and capacity")
	expect(panel.active_op_index == 0 and panel.active_kind == &"spin", "Depleted ring starts at Operation 1 (cassette Spin)")
	expect(panel.model_instances["ring"].visible and not panel.model_instances["beam"].visible,
		"3D SubViewport backdrop matches the selected Ring tool model")
	expect(not has_button_child(panel), "Repair panel has no Resume/Close button ceremony")
	var view_rect: Rect2 = root.get_visible_rect()
	var panel_rect: Rect2 = panel.panel.get_global_rect()
	expect(view_rect.encloses(panel_rect) and panel_rect.get_area() < view_rect.get_area() * 0.32,
		"Repair panel is readable and fits within the actual viewport")
	expect(not panel_rect.has_point(view_rect.get_center()),
		"Repair panel is offset so player surroundings at viewport center remain visible")
	var holder_dim_alpha := 0.0
	for sibling in panel.get_parent().get_children():
		if sibling is ColorRect:
			holder_dim_alpha = sibling.color.a
	expect(holder_dim_alpha <= 0.15, "Popup backdrop is translucent rather than a dark full-screen overlay")

	# 2. Empty tool previews full missing path (0 solved)
	var full_len: float = panel.path_length(panel.full_path)
	var q0_len: float = panel.path_length(panel.route)
	expect(panel.solved_path.is_empty() and is_equal_approx(panel.path_length(panel.missing_path), full_len),
		"Empty tool has zero solved path and full missing path")

	# 3. Operation 1 (SPIN — Cassette rotation ONLY on Ring): real angular drag validation
	button(panel, Vector2(20, 20), true)
	button(panel, Vector2(20, 20), false)
	expect(not panel.dragging and gear.stage(&"ring") == 0, "Starting outside spin ring does not start drag or award repair")
	trace(panel, [panel.route[0]])
	expect(gear.remaining(&"ring") == 0 and panel.trace_bad, "Short click on spin ring fails without free capacity")
	trace(panel, [panel.route[0], Vector2(360, 220)])
	expect(gear.remaining(&"ring") == 0 and panel.trace_bad, "Leaving spin ring annulus fails without free capacity")
	trace(panel, [panel.route[0], panel.route[1], panel.route[2]])
	expect(gear.remaining(&"ring") == 0 and panel.trace_bad, "Releasing early before completing spin angle fails")
	# Reverse direction mid-spin
	button(panel, panel.route[0], true)
	motion(panel, panel.route[1])
	motion(panel, panel.route[2])
	motion(panel, panel.route[0])
	button(panel, panel.route[0], false)
	expect(gear.remaining(&"ring") == 0 and panel.trace_bad, "Reversing spin direction mid-drag fails")

	# Valid continuous angular drag around cassette spin ring
	button(panel, panel.route[0], true)
	for point in panel.route.slice(1):
		motion(panel, point)
	expect(gear.remaining(&"ring") == 0 and panel.dragging, "Finishing spin motion alone waits for release")
	button(panel, panel.route[-1], false)
	expect(gear.stage(&"ring") == 1 and is_equal_approx(gear.remaining(&"ring"), gear.capacity(&"ring") / 4.0),
		"Valid cassette spin release restores first quarter (25%) and advances stage to 1")
	button(panel, panel.route[-1], false)
	expect(gear.stage(&"ring") == 1, "Duplicate release cannot repair the next operation")

	# 4. Hold-E flow: pressing E does NOT toggle/close; releasing E closes and preserves checkpoint
	expect(panel.active_op_index == 1 and panel.active_kind == &"connect",
		"After completing Operation 1 (Spin), panel advances to Operation 2 (Connect)")
	button(panel, panel.route[0], true)
	motion(panel, panel.route[1])
	key(KEY_E, false, true)
	key(KEY_E, true, true)
	await frames()
	expect(scenes.has_popup(&"Repair") and gear.repairing == &"ring",
		"Holding/pressing E does not toggle-close the repair panel")
	key(KEY_E, false, false)
	await frames()
	expect(not scenes.has_popup(&"Repair") and gear.repairing == &"",
		"Releasing E closes repair panel and releases its session")
	expect(gear.stage(&"ring") == 1 and gear.remaining(&"ring") == 8,
		"Releasing E mid-gesture discards only unfinished gesture and preserves completed checkpoint")

	# 5. Reopening resumes at Operation 2 (Connect) without redoing Operation 1 (Spin)
	panel = await open(scenes, gear, &"ring")
	expect(panel.active_op_index == 1 and panel.active_kind == &"connect" and panel.route[1] == panel.ROUTES[1][1] and not panel.dragging,
		"Reopening at 25% condition starts at Operation 2 (Connect) with a fresh gesture")

	# Real click-to-connect validation (shape + label matching ▲A and ■B)
	var pairs: Array = panel.active_op["pairs"]
	click_point(panel, Vector2(30, 30))
	expect(panel.trace_bad and panel.connected_pairs.is_empty(), "Clicking outside terminals fails without connecting")
	click_point(panel, pairs[0]["a"])
	expect(not panel.selected_terminal.is_empty() and String(panel.selected_terminal["label"]) == "A",
		"Clicking first ▲A terminal selects it")
	click_point(panel, pairs[0]["a"])
	expect(panel.connected_pairs.is_empty(), "Clicking the same terminal twice does not connect the pair")
	# Click mismatched shape/label terminal (■B instead of ▲A)
	click_point(panel, pairs[1]["a"])
	expect(panel.trace_bad and panel.selected_terminal.is_empty() and panel.connected_pairs.is_empty(),
		"Clicking mismatched terminal (▲A -> ■B) is rejected and clears selection")
	# Connect Pair A (▲A -> ▲A)
	click_connect_pair(panel, 0)
	expect(0 in panel.connected_pairs and gear.stage(&"ring") == 1,
		"Clicking matching ▲A terminals connects Pair A")
	# Miss while trying to connect Pair B preserves already-connected Pair A
	click_point(panel, pairs[1]["a"])
	click_point(panel, Vector2(30, 30))
	expect(panel.trace_bad and (0 in panel.connected_pairs) and gear.stage(&"ring") == 1,
		"Missing second terminal preserves already-connected Pair A")
	# Connect Pair B (■B -> ■B) to complete Operation 2
	click_connect_pair(panel, 1)
	expect(gear.stage(&"ring") == 2 and gear.remaining(&"ring") == 16 and panel.active_op_index == 2 and panel.active_kind == &"trace",
		"Connecting matching ■B terminals completes Operation 2 (50% capacity) and advances to Operation 3 (Trace)")

	# 6. WASD movement, PauseMenu interruption, focus loss, and lost button mask during Operation 3 (Trace)
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
	expect(not panel.dragging and paused and scenes.has_popup(&"PauseMenu"),
		"Opening Pause above Repair cancels only unfinished gesture")
	trace(panel, [], true)
	expect(gear.stage(&"ring") == 2 and gear.remaining(&"ring") == 16,
		"Even direct synthetic board events cannot progress a paused repair")
	state.resume()
	await frames()

	# Midpoint trace release at stage 2 saves Checkpoint 3 (75%, 24/32)
	var mid_path: Array[Vector2] = [panel.route[0], panel.route[1], panel.route[2]]
	trace(panel, mid_path)
	expect(gear.stage(&"ring") == 3 and gear.remaining(&"ring") == 24,
		"Releasing at midpoint of Operation 3 trace saves Checkpoint 3 (75%, 24/32)")

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
	expect(not panel.dragging and gear.stage(&"ring") == 3,
		"Focus loss discards current trace without erasing completed checkpoints")
	button(panel, panel.route[1], false)

	button(panel, panel.route[0], true)
	motion(panel, panel.route[1], false, false)
	expect(not panel.dragging and gear.stage(&"ring") == 3,
		"Lost mouse button mask releases trace without stuck input or progress loss")
	button(panel, panel.route[1], false)

	# 7. Escape cancels unfinished trace and closes Repair without opening PauseMenu
	button(panel, panel.route[0], true)
	motion(panel, panel.route[1])
	key(KEY_ESCAPE, false, true)
	await frames()
	expect(not scenes.has_popup() and not paused and state.is_playing() and gear.remaining(&"ring") == 24,
		"Escape cancels unfinished trace and closes Repair without opening PauseMenu")

	# 8. Finishing remaining short trace at stage 3 reaches full capacity and automatically closes Repair
	panel = await open(scenes, gear, &"ring")
	expect(panel.active_op_index == 2 and panel.active_kind == &"trace",
		"Reopening at 75% starts on the remaining tail of Operation 3 (Trace)")
	trace(panel)
	await frames()
	expect(gear.remaining(&"ring") == gear.capacity(&"ring") and gear.stage(&"ring") == 0
		and gear.repairing == &"" and not scenes.has_popup(&"Repair"),
		"Completing the remaining tail reaches full capacity, resets stage to 0, and closes Repair")

	# 9. Tiny / light wear vs heavy wear vs partial segment: never forces all 3 operations for small damage
	gear.reset_state()
	gear.spend(&"ring", 2.0) # 30/32 remaining (93.75% condition, tiny damage)
	panel = await open(scenes, gear, &"ring")
	var light_missing_len: float = panel.path_length(panel.missing_path)
	var light_route_len: float = panel.path_length(panel.route)
	expect(gear.stage(&"ring") == 3 and panel.active_op_index == 2 and light_missing_len < full_len * 0.15 and light_route_len < q0_len * 0.5,
		"Lightly worn ring skips Operations 1 & 2 and requires only a short tail trace in Operation 3")
	trace(panel)
	await frames()
	expect(gear.remaining(&"ring") == 32.0 and not scenes.has_popup(&"Repair") and gear.repairing == &"",
		"Tracing short missing section on lightly worn ring restores to full and closes panel")

	# Tiny damage on Orange (cone) at >75% condition: skips Spin & Trace, and Pair A is already connected; only Pair B needed!
	gear.reset_state()
	gear.spend(&"cone", 5.0) # 40/45 remaining (88.9% condition, stage 3)
	panel = await open(scenes, gear, &"cone")
	expect(gear.stage(&"cone") == 3 and panel.active_op_index == 2 and panel.active_kind == &"connect"
		and (0 in panel.connected_pairs) and not (1 in panel.connected_pairs),
		"Lightly worn Orange bellows skips Spin & Trace and starts with Pair A already connected")
	click_connect_pair(panel, 1)
	await frames()
	expect(is_equal_approx(gear.remaining(&"cone"), 45.0) and not scenes.has_popup(&"Repair") and gear.repairing == &"",
		"Clicking only the single remaining coil pair on lightly worn Orange bellows restores to full and closes")

	# Partial wear within Quarter 1 (4/32 = 12.5% condition) scales down Spin arc length to 50%
	gear.reset_state()
	gear.spend(&"ring", 28.0) # 4/32 remaining (12.5% condition)
	panel = await open(scenes, gear, &"ring")
	var heavy_missing_len: float = panel.path_length(panel.missing_path)
	var partial_q0_len: float = panel.path_length(panel.route)
	expect(gear.stage(&"ring") == 0 and heavy_missing_len > full_len * 0.80 and is_equal_approx(partial_q0_len, q0_len * 0.5),
		"Partially worn Quarter 1 (12.5%) requires only the missing half of the Spin arc")
	trace(panel)
	expect(gear.remaining(&"ring") == 8.0 and gear.stage(&"ring") == 1 and scenes.has_popup(&"Repair"),
		"Completing partial first quarter Spin restores to 25% boundary (8/32) and advances to Operation 2")
	scenes.close_popup(&"Repair")
	await frames()

	# 10. All four tools (ring, beam/Flash, cone, clock) complete full repair from 0% to 100% in 3 tool-specific operations!
	for tool: StringName in [&"ring", &"beam", &"cone", &"clock"]:
		gear.reset_state()
		gear.spend(tool, gear.capacity(tool))
		panel = await open(scenes, gear, tool)
		if tool == &"beam":
			expect(panel.heading.text.contains("Flash"), "Beam equipment ID is labeled Flash in repair UI")
		expect(panel.model_instances[String(tool)].visible, "Backdrop SubViewport displays %s 3D model" % String(tool))
		# Operation 1: Spin (0% -> 25%)
		expect(panel.active_op_index == 0 and panel.active_kind == &"spin", "%s Op 1 is Spin" % String(tool))
		trace(panel)
		expect(is_equal_approx(gear.remaining(tool), gear.capacity(tool) * 0.25) and gear.stage(tool) == 1,
			"%s Op 1 (Spin) restores to 25%%" % String(tool))
		# Operation 2: Connect on ring/beam, Trace on cone/clock (25% -> 50%)
		expect(panel.active_op_index == 1, "%s advances to Op 2" % String(tool))
		if panel.active_kind == &"connect":
			click_connect_pair(panel, 0)
			click_connect_pair(panel, 1)
		else:
			trace(panel)
		expect(is_equal_approx(gear.remaining(tool), gear.capacity(tool) * 0.50) and gear.stage(tool) == 2,
			"%s Op 2 (%s) restores to 50%%" % [String(tool), String(panel.active_kind)])
		# Operation 3: Trace on ring/beam, Connect on cone/clock (50% -> 100% Full)
		expect(panel.active_op_index == 2, "%s advances to Op 3" % String(tool))
		if panel.active_kind == &"connect":
			click_connect_pair(panel, 0)
			expect(is_equal_approx(gear.remaining(tool), gear.capacity(tool) * 0.75) and gear.stage(tool) == 3,
				"%s Op 3 first contact pair restores Checkpoint 3 (75%%)" % String(tool))
			click_connect_pair(panel, 1)
		else:
			trace(panel)
		await frames()
		expect(gear.is_full(tool) and not scenes.has_popup(&"Repair") and gear.repairing == &"",
			"Completing 3 tool-specific operations on %s reaches 100%% Full and auto-closes panel" % String(tool))

	# Clock cannot power itself while repairing clock, but can slow time while repairing another tool
	gear.reset_state()
	gear.spend(&"clock", 12.0) # 12.0 remaining
	gear.spend(&"ring", 16.0)  # 16.0 remaining
	panel = await open(scenes, gear, &"clock")
	player._step_slow(0.05, false)
	player._step_slow(0.5, true)
	expect(is_equal_approx(player.world_scale, 1.0) and is_equal_approx(gear.remaining(&"clock"), 12.0),
		"Repairing clock cannot power slow-time on itself")
	player._step_slow(0.05, false)
	scenes.close_popup(&"Repair")
	await frames()
	panel = await open(scenes, gear, &"ring")
	player._step_slow(0.05, false)
	player._step_slow(0.5, true)
	expect(player.world_scale < 1.0 and gear.remaining(&"clock") < 12.0,
		"Clock can slow world time while repairing another tool")
	player._step_slow(0.05, false)
	scenes.close_popup(&"Repair")
	await frames()

	# 11. Switching setup / stale panel token safety + Equipment.restore_state invalidation
	gear.reset_state()
	gear.spend(&"ring", 28)  # 4 remaining (stage 0)
	gear.spend(&"clock", 20) # 4 remaining (stage 0)
	panel = await open(scenes, gear, &"ring")
	trace(panel) # ring -> 8 (stage 1)
	panel.setup({"equipment": gear, "tool": &"clock"})
	expect(gear.repairing == &"clock" and gear.stage(&"ring") == 1 and gear.remaining(&"ring") == 8,
		"Switching setup to clock keeps ring checkpoint and replaces session")
	trace(panel) # clock -> 6 (stage 1)
	panel.setup({"equipment": gear, "tool": &"ring"})
	expect(gear.stage(&"clock") == 1 and gear.remaining(&"clock") == 6 and panel.route[1] == panel.ROUTES[1][1],
		"Switching back to ring resumes ring at stage 1 route")

	var old_panel: Control = panel
	var newer: Control = await open(scenes, gear, &"clock")
	trace(old_panel, [], true)
	expect(gear.stage(&"ring") == 1 and gear.remaining(&"ring") == 8,
		"Covered stale panel cannot finish an obsolete session")
	old_panel.queue_free()
	await frames()
	expect(gear.repairing == &"clock", "Old panel exit token cannot cancel the newer clock repair")
	trace(newer)
	expect(gear.stage(&"clock") == 2 and gear.remaining(&"clock") == 12,
		"Newer session remains playable after old panel destruction")
	scenes.close_popup(&"Repair")
	await frames()

	# Restore while panel is mid-gesture invalidates session and emits no completion effects
	gear.reset_state()
	gear.spend(&"ring", 24) # 8 remaining (stage 1)
	var snap_at_8: Dictionary = gear.capture_state()
	panel = await open(scenes, gear, &"ring")
	trace(panel) # 16 remaining (stage 2)
	button(panel, panel.route[0], true)
	for point in panel.route.slice(1):
		motion(panel, point)
	expect(panel.dragging, "Panel is mid-trace at final contact before restore_state")
	gear.restore_state(snap_at_8)
	expect(gear.repairing == &"" and gear.remaining(&"ring") == 8.0 and gear.stage(&"ring") == 1,
		"restore_state immediately clears active repair session and restores capacity to 8")
	button(panel, panel.route[-1], false, true)
	expect(gear.remaining(&"ring") == 8.0 and gear.stage(&"ring") == 1 and not panel.dragging,
		"Releasing trace on restored/stale panel does not complete a step or grant capacity")
	var post_restore_panel: Control = await open(scenes, gear, &"ring")
	panel.queue_free()
	await frames()
	expect(gear.repairing == &"ring", "Freeing pre-restore panel does not cancel post-restore repair session")
	trace(post_restore_panel)
	expect(gear.remaining(&"ring") == 16.0 and gear.stage(&"ring") == 2,
		"Post-restore repair panel completes checkpoint normally")
	scenes.close_popup(&"Repair")
	await frames()

	# 12. Enemy contact damage interruption and arena reset
	gear.reset_state()
	gear.spend(&"ring", 32)
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
	expect(player.health < health_before and not scenes.has_popup(&"Repair"),
		"Actual arena enemy contact damage closes the repair popup")
	expect(gear.stage(&"ring") == 1 and gear.remaining(&"ring") == 8 and gear.repairing == &"",
		"Damage interruption preserves completed checkpoint without leaving a lock")
	arena.director.clear()
	panel = await open(scenes, gear, &"ring")
	arena.reset_arena()
	await frames()
	expect(not scenes.has_popup() and gear.stage(&"ring") == 0 and gear.remaining(&"ring") == gear.capacity(&"ring"),
		"Explicit arena reset closes repair and fully resets equipment")
	expect(Engine.time_scale == 1.0, "Repair never changes global engine time or introduces its own clock")
	arena.queue_free()
	await frames()
	# Allow the audio server to release generated playback after scene removal.
	await create_timer(0.10).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
