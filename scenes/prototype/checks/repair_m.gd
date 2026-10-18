extends SceneTree

const Tuning = preload("res://scenes/prototype/tuning.gd")
const Gestures = preload("res://scenes/prototype/repair_gestures.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: " + description)


func frames(count: int = 2) -> void:
	for _i in range(count):
		await process_frame


func key(code: Key, pressed: bool = true, shift: bool = false, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	event.echo = echo
	root.push_input(event, true)


func gui_pos(panel: Control, board_point: Vector2) -> Vector2:
	var local: Vector2 = panel._board_offset() + board_point * panel._board_scale()
	return panel.board.get_global_transform_with_canvas() * local


func mouse_button(panel: Control, board_point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = gui_pos(panel, board_point)
	event.global_position = event.position
	root.push_input(event, true)


func mouse_motion(panel: Control, board_point: Vector2, held: bool = true) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	event.position = gui_pos(panel, board_point)
	event.global_position = event.position
	root.push_input(event, true)


func stroke_points(panel: Control, points: Array[Vector2]) -> void:
	if points.is_empty():
		return
	mouse_button(panel, points[0], true)
	for pt in points.slice(1):
		mouse_motion(panel, pt, true)
	mouse_button(panel, points[-1], false)


func click_connect_pair(panel: Control, pair_index: int) -> void:
	var pair: Dictionary = panel.active_op["pairs"][pair_index]
	mouse_button(panel, pair["a"], true)
	mouse_button(panel, pair["a"], false)
	mouse_button(panel, pair["b"], true)
	mouse_button(panel, pair["b"], false)


func run() -> void:
	root.size = Vector2i(1280, 800)
	var arena: Node3D = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	arena.director.clear()

	var gear: RefCounted = arena.equipment
	var weapons: Node3D = arena.weapons
	var player: CharacterBody3D = arena.player
	var scenes: Node = root.get_node("SceneManager")
	var state: Node = root.get_node("GameState")

	# 1. E-toggle open/close, release-E ignored, Escape close, and opening on a Full (Ready) item
	weapons.select_tool(1)
	expect(gear.is_full(&"ring"), "Ring starts at 100% full capacity")
	key(KEY_E, true)
	await frames()
	var panel: Control = arena._active_repair_panel()
	expect(scenes.has_popup(&"Repair") and panel != null and panel.tool == &"ring" and gear.repairing == &"",
		"Pressing E opens repair view even when equipped tool is full (Ready state)")
	expect(panel.progress.text.contains("Ready") and panel.feedback.text.contains("Ready"),
		"Full tool displays Ready status and switching hint inside repair")
	key(KEY_E, false)
	await frames()
	expect(scenes.has_popup(&"Repair"), "Releasing E does not close the toggled repair view")
	key(KEY_E, true)
	key(KEY_E, false)
	await frames()
	expect(not scenes.has_popup(&"Repair"), "Pressing E a second time closes the repair view")

	key(KEY_E, true)
	key(KEY_E, false)
	await frames()
	expect(scenes.has_popup(&"Repair"), "Pressing E reopens the repair view")
	key(KEY_ESCAPE, true)
	key(KEY_ESCAPE, false)
	await frames()
	expect(not scenes.has_popup(&"Repair") and state.is_playing(), "Pressing Escape closes repair without opening PauseMenu")

	# 2. Forgiving Spin via REAL transformed GUI mouse input across all 4 tools and 4 window sizes:
	#    - Permissive start (inside hub/lens and outer pad)
	#    - Both directions (CW and CCW)
	#    - Uneven / off-circle / wide oval paths + wrapped angles across +/-PI
	#    - Partial arcs / regrips banking progress across mouse releases
	#    - Center crossing through hub without polar angle spikes
	#    - Single-frame noise / teleport jump ignored without resetting honest turn
	var window_sizes: Array[Vector2i] = [Vector2i(1280, 800), Vector2i(960, 600), Vector2i(640, 480), Vector2i(1440, 720)]
	var tools: Array[StringName] = [&"ring", &"beam", &"cone", &"clock"]

	for idx in range(tools.size()):
		var tool_id: StringName = tools[idx]
		var win_size: Vector2i = window_sizes[idx]
		root.size = win_size
		await frames(3)

		# Case A: Counter-clockwise (CCW) uneven oval spin starting inside the central hub/lens, crossing +/-PI seam
		gear.reset_state()
		gear.spend(tool_id, gear.capacity(tool_id))
		weapons.select_tool(idx + 1)
		key(KEY_E, true)
		key(KEY_E, false)
		await frames()
		panel = arena._active_repair_panel()
		expect(panel != null and panel.tool == tool_id and panel.active_kind == &"spin",
			"%s opens on Spin operation at %s" % [String(tool_id), str(win_size)])

		var center: Vector2 = panel.active_op["center"]
		var radius: float = float(panel.active_op["radius"])
		var ccw_oval: Array[Vector2] = [center + Vector2(3.0, -2.0)] # Start right inside hub!
		var steps := 24
		for s in range(steps + 1):
			# Sweep from +2.4 rad backwards across +PI/-PI seam in CCW direction (-1.0) with oval distortion
			var ang: float = 2.4 - (Gestures.SPIN_FULL_RADIANS * 1.12) * (float(s) / float(steps))
			var rx: float = radius * 1.65 + sin(float(s) * 0.9) * 8.0
			var ry: float = radius * 0.62 + cos(float(s) * 0.7) * 6.0
			var shifted_center: Vector2 = center + Vector2(10.0, -7.0)
			ccw_oval.append(shifted_center + Vector2(cos(ang) * rx, sin(ang) * ry))

		mouse_button(panel, ccw_oval[0], true)
		for pt_idx in range(1, ccw_oval.size()):
			mouse_motion(panel, ccw_oval[pt_idx], true)
			if pt_idx == 8:
				expect(panel.spin_locked_dir < 0.0 and panel.feedback.text.contains("CCW"),
					"%s provides immediate CCW direction feedback during oval spin" % String(tool_id))
				# Inject a single-frame teleport noise spike (>170px jump) and verify it does not reset progress
				var accum_before_spike: float = panel.spin_accum
				mouse_motion(panel, center + Vector2(210.0, -160.0), true)
				expect(panel.dragging and is_equal_approx(panel.spin_accum, accum_before_spike),
					"%s ignores single-frame noise/teleport delta without resetting honest turn" % String(tool_id))
		mouse_button(panel, ccw_oval[-1], false)
		expect(gear.stage(tool_id) == 1 and is_equal_approx(gear.remaining(tool_id), gear.capacity(tool_id) * 0.25),
			"%s completes Spin via hub-start CCW uneven oval across +/-PI seam at %s" % [String(tool_id), str(win_size)])

		# Case B: Multi-stroke partial arcs with regrip, center-crossing, and outer-pad start (CW)
		gear.reset_state()
		gear.spend(tool_id, gear.capacity(tool_id))
		panel.switch_tool(tool_id)
		await frames()

		# Stroke 1: Start far out in outer pad (radius + 48), turn ~45% CW, then release early
		var stroke1: Array[Vector2] = []
		for s in range(10):
			var ang: float = -PI * 0.5 + (Gestures.SPIN_FULL_RADIANS * 0.45) * (float(s) / 9.0)
			var r_pad: float = radius + 48.0 - float(s) * 2.0
			stroke1.append(center + Vector2(cos(ang), sin(ang)) * r_pad)
		stroke_points(panel, stroke1)
		var banked_after_1: float = panel.spin_base_accum
		expect(gear.stage(tool_id) == 0 and banked_after_1 > Gestures.SPIN_FULL_RADIANS * 0.35,
			"%s banks partial arc progress (%.2f rad) on early mouse release" % [String(tool_id), banked_after_1])

		# Stroke 2: Regrip at a completely different angle, cross straight through the center hub (dist < 9), then continue CW to finish
		var stroke2: Array[Vector2] = [
			center + Vector2(-radius, 0.0),
			center + Vector2(-4.0, -2.0), # Inside hub deadzone!
			center + Vector2(2.0, 1.0),   # Crossing center!
		]
		for s in range(14):
			var ang: float = 0.0 + (Gestures.SPIN_FULL_RADIANS * 0.68) * (float(s) / 13.0)
			stroke2.append(center + Vector2(cos(ang), sin(ang)) * (radius * 0.95))
		stroke_points(panel, stroke2)
		expect(gear.stage(tool_id) == 1 and is_equal_approx(gear.remaining(tool_id), gear.capacity(tool_id) * 0.25),
			"%s regripped second stroke with center-crossing finishes Spin checkpoint at %s" % [String(tool_id), str(win_size)])

		key(KEY_E, true)
		key(KEY_E, false)
		await frames()

	root.size = Vector2i(1280, 800)
	await frames()

	# 3. Switching among ACQUIRED tools inside repair (Tab / Shift-Tab / 1-4), retaining checkpoints, and Ready display
	gear.reset_state()
	gear.spend(&"ring", gear.capacity(&"ring"))
	gear.spend(&"beam", gear.capacity(&"beam") * 0.10) # Lightly damaged (>75%, stage 3)
	gear.spend(&"cone", 0.0) # Full (Ready)
	gear.spend(&"clock", gear.capacity(&"clock"))
	var partial_loadout: Array[int] = [1, 2, 3] # Tool 4 (clock) not yet acquired
	weapons.set_loadout(partial_loadout, 1)

	key(KEY_E, true)
	key(KEY_E, false)
	await frames()
	panel = arena._active_repair_panel()
	expect(panel.tool == &"ring" and gear.repairing == &"ring", "Opens on equipped Ring (1)")

	# Complete Op 1 on Ring (25% checkpoint)
	stroke_points(panel, panel.route)
	expect(gear.stage(&"ring") == 1, "Ring reaches stage 1 (25%) before switching")

	# Pressing 4 for unacquired Clock inside repair is rejected
	key(KEY_4, true)
	key(KEY_4, false)
	await frames()
	expect(panel.tool == &"ring" and weapons.selected_tool == 1 and panel.feedback.text.contains("not yet collected"),
		"Unacquired tool 4 is rejected inside repair with clear feedback")

	# Tab switches Ring (1) -> Beam (2)
	key(KEY_TAB, true)
	key(KEY_TAB, false)
	await frames()
	expect(panel.tool == &"beam" and weapons.selected_tool == 2 and gear.repairing == &"beam" and gear.stage(&"ring") == 1,
		"Tab switches inside repair to Beam (2), updates equipped tool, and preserves Ring checkpoint")

	# Finish lightly damaged Beam to 100% Ready — panel must stay open in Ready state!
	stroke_points(panel, panel.route)
	await frames()
	expect(gear.is_full(&"beam") and gear.repairing == &"" and scenes.has_popup(&"Repair") and panel.progress.text.contains("Ready"),
		"Completing Beam repair keeps panel open in Ready state with cleared repair lock")

	# Tab switches Beam (2) -> Cone (3, already full Ready)
	key(KEY_TAB, true)
	key(KEY_TAB, false)
	await frames()
	expect(panel.tool == &"cone" and weapons.selected_tool == 3 and gear.repairing == &"" and panel.progress.text.contains("Ready"),
		"Tab switches to full Cone (3) and displays it as Ready")

	# Tab wraps Cone (3) -> Ring (1), skipping uncollected Clock (4)
	key(KEY_TAB, true)
	key(KEY_TAB, false)
	await frames()
	expect(panel.tool == &"ring" and weapons.selected_tool == 1 and gear.repairing == &"ring" and panel.active_op_index == 1,
		"Tab wraps among acquired tools back to Ring (1) at Operation 2")

	# Shift-Tab cycles backward Ring (1) -> Cone (3) -> Beam (2) -> Ring (1)
	key(KEY_TAB, true, true)
	key(KEY_TAB, false, true)
	await frames()
	expect(panel.tool == &"cone" and weapons.selected_tool == 3, "Shift-Tab cycles backward to Cone (3)")
	key(KEY_1, true)
	key(KEY_1, false)
	await frames()
	expect(panel.tool == &"ring" and weapons.selected_tool == 1, "Numeric key 1 switches directly back to Ring (1)")

	# 4. WASD movement during each operation (Spin, Connect, Trace) and no weapon attack leak
	var all_loadout: Array[int] = [1, 2, 3, 4]
	weapons.set_loadout(all_loadout, 1)
	gear.reset_state()
	gear.spend(&"ring", gear.capacity(&"ring"))
	panel.switch_tool(&"ring")
	await frames()

	# Verify opening/closing repair while moving does not zero player velocity
	key(KEY_E, true)
	key(KEY_E, false)
	await frames()
	player.position = Vector3(0, 0.55, 0)
	Input.action_press("move_right")
	await physics_frame
	arena._physics_process(0.1)
	var vel_before_open: float = player.velocity.x
	key(KEY_E, true)
	key(KEY_E, false)
	await frames()
	expect(vel_before_open > 1.0 and is_equal_approx(player.velocity.x, vel_before_open),
		"Toggling repair open does not reset active WASD velocity")

	panel = arena._active_repair_panel()
	# Move right during Operation 1 (Spin)
	var x0: float = player.position.x
	mouse_button(panel, panel.route[0], true)
	for pt in panel.route.slice(1):
		await physics_frame
		arena._physics_process(1.0 / 30.0)
		mouse_motion(panel, pt, true)
	mouse_button(panel, panel.route[-1], false)
	var x1: float = player.position.x
	expect(x1 > x0 + 0.5 and gear.stage(&"ring") == 1 and not weapons.ring_drawing,
		"Player moves with WASD during Spin without leaking ring draw input")

	# Move up during Operation 2 (Connect)
	Input.action_release("move_right")
	Input.action_press("move_up")
	var z0: float = player.position.z
	click_connect_pair(panel, 0)
	for _t in range(6):
		await physics_frame
		arena._physics_process(1.0 / 30.0)
	click_connect_pair(panel, 1)
	var z1: float = player.position.z
	expect(z1 < z0 - 0.3 and gear.stage(&"ring") == 2 and not weapons.ring_drawing,
		"Player moves with WASD during Connect without leaking weapon input")

	# Move left during Operation 3 (Trace)
	Input.action_release("move_up")
	Input.action_press("move_left")
	for _t in range(4):
		await physics_frame
		arena._physics_process(1.0 / 30.0)
	var x2: float = player.position.x
	mouse_button(panel, panel.route[0], true)
	for pt in panel.route.slice(1):
		await physics_frame
		arena._physics_process(1.0 / 30.0)
		mouse_motion(panel, pt, true)
	mouse_button(panel, panel.route[-1], false)
	Input.action_release("move_left")
	expect(player.position.x < x2 - 0.3 and gear.is_full(&"ring") and not weapons.ring_drawing,
		"Player moves with WASD during Trace and completes Ring repair without weapon leak")

	# 5. No automatic slow; manual Space slow across tool switches; no accidental rewind during repair
	gear.reset_state()
	gear.spend(&"ring", 4.0)
	gear.spend(&"beam", 4.0)
	gear.spend(&"clock", 2.0)
	key(KEY_1, true)
	key(KEY_1, false)
	await frames()
	var clock_start: float = gear.remaining(&"clock")
	arena._physics_process(0.1)
	expect(is_equal_approx(player.world_scale, 1.0) and is_equal_approx(gear.remaining(&"clock"), clock_start),
		"Repairing Ring does not automatically slow time or drain clock")

	key(KEY_SPACE, true)
	arena._physics_process(0.1)
	expect(is_equal_approx(player.world_scale, float(Tuning.SLOW.scale)) and gear.remaining(&"clock") < clock_start,
		"Holding Space manually slows time while repairing Ring")

	# Switch to Beam (2) while holding Space inside repair -> continues slowing seamlessly
	key(KEY_2, true)
	key(KEY_2, false)
	arena._physics_process(0.1)
	expect(panel.tool == &"beam" and is_equal_approx(player.world_scale, float(Tuning.SLOW.scale)) and not arena.history.inspecting,
		"Switching to Beam inside repair while holding Space maintains manual slow")

	# Switch to Clock (4) while holding Space inside repair -> disables slow and never starts rewind inspection
	var clock_before_self: float = gear.remaining(&"clock")
	key(KEY_4, true)
	key(KEY_4, false)
	arena._physics_process(0.1)
	expect(panel.tool == &"clock" and is_equal_approx(player.world_scale, 1.0)
		and is_equal_approx(gear.remaining(&"clock"), clock_before_self) and not arena.history.inspecting,
		"Switching to Clock inside repair stops slow and prevents accidental rewind")

	# Closing repair on Clock while Space is still held does not trigger accidental rewind
	key(KEY_E, true)
	key(KEY_E, false)
	await frames()
	arena._physics_process(0.1)
	expect(not scenes.has_popup(&"Repair") and not arena.history.inspecting,
		"Closing repair while holding Space on Clock requires fresh Space press before rewind")
	key(KEY_SPACE, false)

	# 6. Non-lethal damage keeps repair open; death, RunResult, PauseMenu, and focus-loss clean up safely
	gear.reset_state()
	gear.spend(&"cone", gear.capacity(&"cone"))
	key(KEY_3, true)
	key(KEY_3, false)
	key(KEY_E, true)
	key(KEY_E, false)
	await frames()
	panel = arena._active_repair_panel()
	stroke_points(panel, panel.route) # Op 1 (Spin) -> 25%
	expect(gear.stage(&"cone") == 1, "Cone reaches 25% before non-lethal damage")

	# Start Op 2 (Trace) mid-gesture, then take non-lethal contact damage
	mouse_button(panel, panel.route[0], true)
	mouse_motion(panel, panel.route[1], true)
	player.position = Vector3.ZERO
	arena.director.spawn(&"swarmer", Vector3.ZERO)
	var hp0: float = player.health
	arena._physics_process(0.1)
	expect(player.health < hp0 and player.health > 0.0 and scenes.has_popup(&"Repair") and gear.repairing == &"cone" and panel.dragging,
		"Non-lethal damage does not dismiss repair or cancel active drag")
	arena.director.clear()
	for pt in panel.route.slice(2):
		mouse_motion(panel, pt, true)
	mouse_button(panel, panel.route[-1], false)
	expect(gear.stage(&"cone") == 2, "In-progress trace finishes normally right after non-lethal damage")

	# Lethal damage closes repair and cleans up session while preserving stage 2
	player.take_damage(player.health)
	await frames()
	expect(player.health <= 0.0 and not scenes.has_popup(&"Repair") and gear.repairing == &"" and gear.stage(&"cone") == 2,
		"Player death closes repair and preserves completed checkpoints")

	# Revive, reopen repair, verify RunResult popup closes repair safely
	player.reset_state()
	key(KEY_E, true)
	key(KEY_E, false)
	await frames()
	expect(scenes.has_popup(&"Repair") and gear.repairing == &"cone", "Repair reopens after player reset")
	scenes.push_popup(&"RunResult")
	await frames()
	expect(not scenes.has_popup(&"Repair") and gear.repairing == &"", "RunResult popup closes active repair cleanly")
	scenes.close_popup(&"RunResult")
	await frames()

	# Reopen repair, verify focus-loss closes repair and pauses cleanly
	key(KEY_E, true)
	key(KEY_E, false)
	await frames()
	expect(scenes.has_popup(&"Repair"), "Repair open before focus-loss check")
	arena._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames()
	expect(not scenes.has_popup(&"Repair") and gear.repairing == &"" and state.state == state.State.PAUSED,
		"Focus loss closes repair, clears session, and pauses game")
	state.start_game()
	await frames()

	arena.queue_free()
	await frames()
	await create_timer(0.10).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
