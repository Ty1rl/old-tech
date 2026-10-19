extends "res://scenes/prototype/checks/repair_n.gd"
## Actual repair GUI input: shared time costs and stationary gesture targets.
func run() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	var arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await frames(4)
	arena.set_physics_process(false)
	arena.director.clear()
	var scenes := root.get_node("SceneManager")
	var tc: TimeController = arena.time_controller
	var gear: WeaponEquipment = arena.equipment
	for reserve: float in [100.0, 2.0]:
		gear.reset_state()
		gear.spend(&"cone", gear.capacity(&"cone") * 2.0 / 3.0)
		tc.begin_attempt()
		tc.try_spend(tc.capacity - reserve)
		var panel: WeaponRepair = scenes.push_popup(&"Repair", {"arena": arena, "equipment": gear, "tool": &"cone", "time_controller": tc})
		await frames()
		expect(panel.active_kind == &"trace", "Heat gun opens at leather trace")
		key(KEY_SPACE, true)
		arena._physics_process(.01)
		expect(tc.slow_active, "Holding Space slows world during repair")
		complete_active_operation(panel)
		if reserve > 6.0:
			expect(gear.stage(&"cone") == 2, "Heat-gun trace completes while holding slow with sufficient reserve")
		else:
			expect(gear.stage(&"cone") == 1 and panel.feedback.text.contains("Not enough time"), "Low reserve blocks checkpoint atomically rather than rejecting the traced shape")
		key(KEY_SPACE, false)
		scenes.close_popup(&"Repair")
		await frames()
	gear.reset_state()
	gear.spend(&"cone", gear.capacity(&"cone") * 2.0 / 3.0)
	tc.begin_attempt()
	var panel: WeaponRepair = scenes.push_popup(&"Repair", {"arena": arena, "equipment": gear, "tool": &"cone", "time_controller": tc})
	await frames(5)
	var before_click := gui_pos(panel, panel.route[0])
	var before_route := panel.route.duplicate()
	var before_model := panel.viewport_container.get_global_rect()
	mouse_button(panel, panel.route[0], true)
	if gui_pos(panel, panel.route[0]).distance_to(before_click) >= .01:
		print("click_route_before=", before_route, " after=", panel.route, " model_before=", before_model, " after=", panel.viewport_container.get_global_rect())
	expect(gui_pos(panel, panel.route[0]).distance_to(before_click) < .01, "First mouse press does not move the trace target")
	expect(panel.viewport_container.get_global_rect().is_equal_approx(before_model), "First mouse press does not move the weapon backdrop")
	expect(panel.dragging, "Trace begins before layout stability check")
	var target := gui_pos(panel, panel.route[0])
	var model := panel.viewport_container.get_global_rect()
	var labels_before := [panel.instructions.size, panel.feedback.size, panel.board.size, panel.board.global_position]
	panel.feedback.text = "Checkpoint complete. " .repeat(40)
	panel.instructions.text = "Trace the leather from the first contact to the last. ".repeat(12)
	await frames(5)
	if gui_pos(panel, panel.route[0]).distance_to(target) >= .01:
		print("layout_before=", labels_before, " after=", [panel.instructions.size, panel.feedback.size, panel.board.size, panel.board.global_position], " label_min=", [panel.instructions.get_minimum_size(), panel.feedback.get_minimum_size()], " line_height=", [panel.instructions.get_line_height(), panel.feedback.get_line_height()])
	expect(gui_pos(panel, panel.route[0]).distance_to(target) < .01, "Wrapping instruction/feedback text does not move an active trace target")
	expect(panel.viewport_container.get_global_rect().is_equal_approx(model), "Model stays aligned with trace while text changes")
	panel.feedback.text = "Ready"
	panel.instructions.text = "Trace"
	await frames(5)
	expect(gui_pos(panel, panel.route[0]).distance_to(target) < .01, "Shortening feedback does not move an active trace target")
	mouse_button(panel, panel.route[0], false)
	scenes.close_popup(&"Repair")
	for view_size: Vector2i in [Vector2i(1280,800), Vector2i(960,600)]:
		root.size = view_size
		await frames(3)
		for tool: StringName in [&"ring", &"beam", &"cone"]:
			gear.reset_state()
			var spec := Gestures.tool_spec(tool)
			var trace_step := 0
			for stage in 4:
				if spec.operations[Gestures.operation_index_for_stage(stage)].kind == &"trace":
					trace_step = stage
					break
			gear.spend(tool, gear.capacity(tool) * (1.0 - (float(trace_step) + .4) / 4.0))
			panel = scenes.push_popup(&"Repair", {"arena":arena,"equipment":gear,"tool":tool,"time_controller":tc})
			await frames(5)
			panel._start_switch_transition()
			var first_point := gui_pos(panel, panel.route[0])
			var weapon_rect := panel.viewport_container.get_global_rect()
			mouse_button(panel, panel.route[0], true)
			expect(panel.dragging and gui_pos(panel,panel.route[0]).distance_to(first_point) < .01, "%s trace stays at the clicked point at %s" % [tool,view_size])
			await frames(3)
			expect(gui_pos(panel,panel.route[0]).distance_to(first_point) < .01 and panel.viewport_container.get_global_rect().is_equal_approx(weapon_rect), "%s model and trace stay fixed during tool fade at %s" % [tool,view_size])
			mouse_button(panel,panel.route[0],false)
			scenes.close_popup(&"Repair")
			await frames(2)
	root.get_node("AudioManager").stop_dialogue()
	root.get_node("AudioManager").set_music_context(&"intro")
	call_group(&"world_audio", &"reset_state")
	arena.queue_free()
	await frames(4)
	await create_timer(.2).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
