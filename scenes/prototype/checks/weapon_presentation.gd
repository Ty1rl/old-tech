extends SceneTree
var arena: Node3D
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func expect(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func mouse(down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	return event
func run() -> void:
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	root.get_node("GameState").resume()
	arena.set_physics_process(false)
	arena.director.clear()
	var weapons: Node3D = arena.weapons
	var cues: Array = []
	weapons.combat_event.connect(func(kind, point, _strength): cues.append({"kind":kind,"point":point}))
	var player: Node3D = arena.player
	var aim := Vector3(0,0,-12)
	weapons.select_tool(2)
	player.set_visual_tool(2)
	var muzzle: Vector3 = player.visual.muzzle_position(2)
	expect(muzzle.y > 1.3 and muzzle.z < player.position.z, "Flash emitter is on raised modeled lens")
	weapons.handle_event(mouse(true),player,aim)
	weapons.step(.5,player,aim,[],0)
	expect(weapons.presentation.last_beam_start.is_equal_approx(muzzle), "Charge light begins on real lens")
	weapons.handle_event(mouse(false),player,aim)
	expect(cues.any(func(cue): return cue.kind == &"flash_fire" and cue.point.is_equal_approx(muzzle)), "Flash firing feedback is at lens, not feet")
	expect(weapons.beam_pulses.size() == 1 and weapons.beam_pulses[0].muzzle.is_equal_approx(muzzle), "Shot retains exact launch muzzle")
	weapons.step(.1,player,aim,[],.1)
	expect(weapons.presentation.last_beam_start.is_equal_approx(muzzle), "Traveling focused light begins at launch muzzle")
	expect(weapons.presentation.vertices > 0 and weapons.presentation.mesh.get_surface_count() == 1, "Light glow/core batched into one surface")
	var snapshot: Dictionary = weapons.capture_state()
	player.position.x += 3
	weapons.step(.1,player,aim,[],.1)
	expect(weapons.beam_pulses[0].muzzle.is_equal_approx(muzzle), "Moving after release never drags shot's launch point")
	weapons.restore_state(snapshot)
	expect(weapons.beam_pulses[0].muzzle.is_equal_approx(muzzle), "Rewind restores lens origin with pulse")
	var condition: float = arena.equipment.remaining(&"beam")
	for tick in range(10): weapons._rebuild_visuals(player,aim)
	expect(is_equal_approx(arena.equipment.remaining(&"beam"),condition), "Rendering never spends equipment or applies combat")
	arena.reset_arena()
	arena.director.clear()
	weapons.select_tool(3)
	player.set_visual_tool(3)
	weapons.handle_event(mouse(true),player,aim)
	weapons.step(.05,player,aim,[],.05)
	expect(cues.any(func(cue): return cue.kind == &"cone_pulse" and cue.point.is_equal_approx(player.visual.muzzle_position(3))), "Air blast feedback is at nozzle, not feet")
	expect(weapons.presentation.last_air_origin.is_equal_approx(player.visual.muzzle_position(3)), "Air begins at actual nozzle")
	expect(weapons.presentation.vertices > 200 and weapons.presentation.vertices < 1000 and weapons.presentation.mesh.get_surface_count() == 1, "Moving wisps and expanding air arcs use bounded batched geometry")
	var phase: float = weapons.presentation.phase
	weapons.step(.1,player,aim,[],0)
	expect(is_equal_approx(weapons.presentation.phase,phase), "Frozen world freezes air motion")
	weapons.step(.1,player,aim,[],.018)
	expect(is_equal_approx(weapons.presentation.phase-phase,.018), "Air motion follows slowed world clock")
	weapons.reset_state()
	expect(weapons.presentation.mesh.get_surface_count() == 0 and weapons.presentation.phase == 0, "Reset clears light and air")

	player.velocity = Vector3(6,0,0)
	player._input_dir = Vector2.ZERO
	player._update_velocity(.1)
	expect(Vector2(player.velocity.x,player.velocity.z).length() < .001, "Releasing movement brakes within a tenth of a second")
	player.velocity = Vector3(6,0,0)
	player._input_dir = Vector2(-1,0)
	player._update_velocity(.1)
	expect(player.velocity.x < 0, "Reversal crosses zero within a tenth of a second")
	player.velocity = Vector3.ZERO
	player._input_dir = Vector2(1,0)
	player._update_velocity(.5)
	expect(is_equal_approx(player.velocity.x,6), "Movement still caps at original maximum speed")
	player.visual.reset_pose()
	player.visual.step_visual(.1,6,6,Vector3.FORWARD*6)
	var forward: float = player.visual.animation.current_animation_position
	player.visual.reset_pose()
	player.visual.step_visual(.1,6,6,Vector3.BACK*6)
	var backward: float = player.visual.animation.current_animation_position
	expect(forward < .5 and backward > .5, "Backing away reverses the looping gait")
	for index in range(1,5):
		player.set_visual_tool(index)
		expect(player.visual.tool_attachments[player.visual.tool_id].scale.is_equal_approx(Vector3.ONE*1.25), "Tool is larger relative to player")
		expect(player.visual.grip_error("L") < .025 and player.visual.grip_error("R") < .025, "Enlarged tool retains two-hand grip")
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	await create_timer(.1).timeout
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
