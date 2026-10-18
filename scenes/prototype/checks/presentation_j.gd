extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func mouse(down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	return event
func run() -> void:
	var arena: Node3D = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	root.get_node("GameState").resume()
	arena.set_physics_process(false)
	arena.director.clear()
	var player: Node3D = arena.player
	var weapons: Node3D = arena.weapons
	var aim := Vector3(0,0,-10)
	expect(is_equal_approx(player.camera.size,22), "Default camera zooms back out")
	weapons.select_tool(2)
	player.set_visual_tool(2)
	weapons.handle_event(mouse(true),player,aim)
	weapons.step(.1,player,aim,[],0)
	var small: float = weapons.presentation.charge_glow_radius
	weapons.step(.6,player,aim,[],0)
	expect(weapons.presentation.charge_glow_radius > small and weapons.beam_pulses.is_empty(), "Charge grows aperture glow without firing")
	expect(weapons.presentation.mesh.get_aabb().size.length() < .8, "Charge geometry stays on aperture rather than extending as a beam")
	weapons.handle_event(mouse(false),player,aim)
	weapons.step(.15,player,aim,[],.15)
	expect(weapons.beam_pulses.size() == 1 and weapons.presentation.mesh.get_aabb().size.length() > 2, "Light beam appears only after release")
	arena.time_cue.update_state(.18,false)
	expect(arena.time_cue.caption.text == "TIME SLOW" and not arena.time_cue.frozen and arena.time_cue.target_amount > 0, "Slow time has blue tint and clear label")
	arena.time_cue.update_state(1,false)
	expect(arena.time_cue.target_amount == 0 and not arena.time_cue.caption.visible, "Normal time clears cue")

	arena.reset_arena()
	arena.director.clear()
	weapons.select_tool(3)
	player.set_visual_tool(3)
	weapons.handle_event(mouse(true),player,aim)
	weapons.step(.05,player,aim,[],.05)
	for tick in range(5): arena.history.record(.05,arena.capture_state)
	weapons.select_tool(4)
	arena._begin_inspection()
	arena._seek_inspection(.15)
	expect(arena.history.inspecting and weapons.selected_tool == 4, "Clock remains actual control tool during review")
	expect(player.visual_tool == 3 and arena.status_hud.selected == 2, "Historical gun and HUD overlay show recorded equipment")
	expect(weapons.preview_overlay.air and not weapons.cone_active and not weapons.beam_charging, "Recorded air is visual only, never restored held input")
	expect(weapons.presentation.vertices > 100, "Recorded cone effect renders during review")
	expect(weapons._draw_mesh.get_surface_count() > 0, "Recorded cone retains its floor footprint")
	expect(arena.time_cue.frozen and arena.time_cue.caption.text.begins_with("TIME FROZEN"), "Frozen review has distinct tint and label")
	var position: Vector3 = player.position
	var phase: float = player.visual.walk_phase
	var idle: float = player.visual.idle_phase
	Input.action_press("move_right")
	arena.set_physics_process(true)
	for tick in range(8): await physics_frame
	arena.set_physics_process(false)
	Input.action_release("move_right")
	expect(player.position.is_equal_approx(position), "Real engine ticks with movement held cannot move player while frozen")
	expect(player.visual.walk_phase == phase and player.visual.idle_phase == idle, "Skinned character animation remains frozen across real engine ticks")
	arena._finish_inspection(false)
	expect(weapons.preview_overlay.is_empty() and player.visual_tool == 4 and not weapons.cone_active, "Leaving review clears overlays and leaves clock equipped without firing")
	expect(not arena.time_cue.frozen and arena.time_cue.target_amount == 0, "Leaving freeze clears frozen cue")
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	await create_timer(.1).timeout
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
