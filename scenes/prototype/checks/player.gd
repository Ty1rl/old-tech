extends SceneTree

const Tuning = preload("res://scenes/prototype/tuning.gd")
const ACTIONS := [&"move_left", &"move_right", &"move_up", &"move_down"]
var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func release_actions() -> void:
	for action in ACTIONS:
		Input.action_release(action)


func space(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func ticks(player: CharacterBody3D, count: int, aim: Vector3) -> void:
	# Exercise the public arena delegate once per real engine physics tick.
	for index in range(count):
		await physics_frame
		player.step(1.0 / float(Engine.physics_ticks_per_second), aim)


func flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0, vector.z)


func resource_interval(player: CharacterBody3D, duration: float, delta: float, held: bool) -> float:
	var remaining := duration
	var world_seconds := 0.0
	while remaining > 0.00000001:
		var step := minf(remaining, delta)
		player._step_slow(step, held)
		world_seconds += step * player.world_scale
		remaining -= step
	return world_seconds


func run() -> void:
	space(false)
	release_actions()
	var arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	var player: CharacterBody3D = arena.player
	var state = root.get_node("GameState")
	var scenes = root.get_node("SceneManager")
	# The real arena integration is also checked separately by foundation.gd.
	# Here explicit public step() calls allow exact aim and delta scenarios.
	arena.set_physics_process(false)
	player.reset_state()
	expect(not player.is_physics_processing(), "Inherited automatic physics is disabled")
	var origin: Vector3 = player.position
	Input.action_press("move_up")
	await physics_frame
	await physics_frame
	expect(player.position == origin, "No delegate movement occurs without an arena step")
	await ticks(player, 12, Vector3(20, 1000, 0))
	var facing: Vector3 = -player.model.global_basis.z
	expect(player.position.z < origin.z - 0.5 and absf(player.position.x - origin.x) < 0.001, "W moves camera-forward while aim is sideways")
	expect(facing.dot(flat(Vector3(20, 0, 0) - player.position).normalized()) > 0.999, "Mouse-facing ignores height and follows world aim")
	var velocity_before := flat(player.velocity)
	await ticks(player, 1, Vector3(-20, 1000, 0))
	expect(flat(player.velocity).distance_to(velocity_before) < 0.001, "Changing aim does not change held movement velocity")
	expect((-player.model.global_basis.z).x < -0.98, "Facing updates immediately to a new mouse direction")
	var stable_facing: Basis = player.model.global_basis
	release_actions()
	player.reset_input()
	await ticks(player, 1, player.position + Vector3(0, 100, 0))
	expect(player.model.global_basis.is_equal_approx(stable_facing), "Aim directly above the player keeps a valid last facing")
	release_actions()
	player.reset_state()
	player.camera.global_rotation.y = PI * 0.5
	origin = player.position
	Input.action_press("move_up")
	await ticks(player, 12, Vector3(0, 0, 20))
	expect(player.position.x < origin.x - 0.5 and absf(player.position.z - origin.z) < 0.001, "Movement uses camera yaw rather than model facing")
	expect((-player.model.global_basis.z).dot(flat(Vector3(0, 0, 20) - player.position).normalized()) > 0.999, "Camera-relative motion still allows independent facing")
	release_actions()
	player.camera.global_rotation.y = 0.0
	player.reset_state()
	Input.action_press("move_up")
	Input.action_press("move_right")
	await ticks(player, 12, Vector3(20, 0, 0))
	expect(is_equal_approx(flat(player.velocity).length(), Tuning.PLAYER.speed), "Diagonal movement is normalized to configured speed")
	expect(player.velocity.x > 0.0 and player.velocity.z < 0.0, "Simultaneous W and D preserve both movement axes")
	release_actions()
	await ticks(player, 8, Vector3(20, 0, 0))
	expect(flat(player.velocity).is_zero_approx(), "Released movement decelerates to a stop")
	player.reset_state()
	await ticks(player, 1, Vector3.RIGHT * 20)
	space(true)
	expect(Input.is_physical_key_pressed(KEY_SPACE), "Engine Space injection exercises physical-key polling")
	Input.action_press("move_right")
	await ticks(player, 12, Vector3(0, 0, -20))
	expect(is_equal_approx(player.world_scale, Tuning.SLOW.scale), "Public step polls held Space and slows the enemy clock")
	expect(flat(player.velocity).length() > 0 and flat(player.velocity).length() <= Tuning.PLAYER.speed, "Slow-time acceleration remains bounded in world units")
	expect(absf(player.slow_charge - (arena.equipment.capacity(&"clock") - 12.0 / float(Engine.physics_ticks_per_second) * Tuning.SLOW.drain)) < 0.00001, "Live Space charge drains using real physics delta")
	expect((-player.model.global_basis.z).z < -0.99, "Mouse-facing remains independent during slow time")
	player.velocity = Vector3(Tuning.PLAYER.speed, 0, 0)
	origin = player.position
	var phase_before: float = player.visual.walk_phase
	await ticks(player, 12, Vector3(20, 0, player.position.z))
	var slowed_distance := flat(player.position - origin).length()
	var slowed_phase: float = player.visual.walk_phase - phase_before
	expect(absf(slowed_distance - Tuning.PLAYER.speed * (12.0 / Engine.physics_ticks_per_second) * Tuning.SLOW.scale) < .025, "Player displacement uses slowed world time: actual %.4f, expected %.4f" % [slowed_distance, Tuning.PLAYER.speed * (12.0 / Engine.physics_ticks_per_second) * Tuning.SLOW.scale])
	space(false)
	origin = player.position
	phase_before = player.visual.walk_phase
	await ticks(player, 12, Vector3(20, 0, player.position.z))
	var normal_distance := flat(player.position - origin).length()
	var normal_phase: float = player.visual.walk_phase - phase_before
	expect(absf(slowed_distance / normal_distance - Tuning.SLOW.scale) < .025, "Slow and normal walking cover the expected distance ratio")
	expect(absf(slowed_phase / normal_phase - Tuning.SLOW.scale) < .025, "Walking animation slows by the same ratio as movement")
	space(false)
	release_actions()
	var charge_before: float = player.slow_charge
	await ticks(player, 1, Vector3.RIGHT * 20)
	expect(player.world_scale == 1.0 and player.slow_charge == charge_before, "Space release restores normal time without passive regeneration")

	for delta in [1.0, 0.1, 1.0 / 60.0]:
		arena.equipment.reset_state()
		player.reset_state()
		player._step_slow(0.0, false)
		var world_seconds := resource_interval(player, 2.75, delta, true)
		var expected: float = arena.equipment.capacity(&"clock") - 2.75 * Tuning.SLOW.drain
		expect(absf(player.slow_charge - expected) < 0.00001, "Shared drain is delta-consistent at %.6f" % delta)
		expect(absf(world_seconds - 2.75 * Tuning.SLOW.scale) < 0.00001, "Enemy slow time is delta-consistent before exhaustion at %.6f" % delta)
		resource_interval(player, 1.25, delta, false)
		expect(absf(player.slow_charge - expected) < 0.00001, "Released clock never regenerates at %.6f" % delta)
	for delta in [31.0, 1.0, 0.03]:
		arena.equipment.reset_state()
		player.reset_state()
		player._step_slow(0.0, false)
		var slow_seconds: float = arena.equipment.capacity(&"clock") / Tuning.SLOW.drain
		var world_seconds := resource_interval(player, slow_seconds + 3.0, delta, true)
		expect(player.slow_charge < 0.000001 and player._slow_release_required, "Exhaustion latches at delta %.6f" % delta)
		expect(absf(world_seconds - (slow_seconds * Tuning.SLOW.scale + 3.0)) < 0.00001, "Partial exhaustion conserves enemy time at delta %.6f" % delta)
		var empty: float = player.slow_charge
		resource_interval(player, 2.0, delta, true)
		expect(player.slow_charge == empty and player.world_scale == 1.0, "Held Space cannot regenerate or strobe at delta %.6f" % delta)
		player._step_slow(0.5, false)
		expect(player.slow_charge == empty and not player._slow_release_required, "Release rearms but never refills at delta %.6f" % delta)
		arena.equipment.begin_repair(&"clock")
		arena.equipment.complete_step(&"clock")
		arena.equipment.end_repair()
		player._step_slow(0.0, false)
		player._step_slow(0.1, true)
		expect(is_equal_approx(player.world_scale, Tuning.SLOW.scale) and player.slow_charge > 0.0, "Repair and fresh hold reactivate slow at delta %.6f" % delta)
	var remaining_before: float = player.slow_charge
	player._step_slow(100.0, false)
	expect(player.slow_charge == remaining_before and player.world_scale == 1.0, "Long release cannot regenerate clock")
	player._step_slow(0.0, true)
	expect(player.slow_charge == remaining_before, "Zero delta consumes no charge")
	player._step_slow(-1.0, true)
	expect(player.slow_charge == remaining_before, "Negative delta cannot create or spend charge")
	arena.equipment.spend(&"clock", 0.5)
	expect(is_equal_approx(player.slow_charge, remaining_before - 0.5), "Slow charge mirrors external equipment changes immediately")
	player._step_slow(0.0, false)
	player._step_slow(0.1, true)
	arena.equipment.begin_repair(&"ring")
	remaining_before = player.slow_charge
	player._step_slow(0.1, true)
	expect(player.world_scale == 1.0 and player.slow_charge == remaining_before, "Opening repair cancels held slow activation")
	player._step_slow(0.0, false)
	player._step_slow(0.1, true)
	expect(is_equal_approx(player.world_scale, Tuning.SLOW.scale), "Fresh Space can slow during another item's repair")
	arena.equipment.end_repair()
	remaining_before = player.slow_charge
	player._step_slow(0.1, true)
	expect(player.world_scale == 1.0 and player.slow_charge == remaining_before, "Closing repair requires Space release")
	arena.equipment.begin_repair(&"clock")
	player._step_slow(0.0, false)
	player._step_slow(0.5, true)
	expect(player.world_scale == 1.0 and player.slow_charge == remaining_before, "Clock cannot slow or spend during its own repair")
	arena.equipment.end_repair()
	player._step_slow(0.1, true)
	expect(player.world_scale == 1.0, "Closing clock repair does not reactivate held Space")
	player._step_slow(0.0, false)

	player.take_damage(12.0)
	expect(is_equal_approx(player.health, Tuning.PLAYER.health - 12.0), "Contact damage subtracts actual health")
	player.take_damage(-10.0)
	expect(is_equal_approx(player.health, Tuning.PLAYER.health - 12.0), "Negative damage cannot heal the player")
	player.take_damage(1000.0)
	player.take_damage(12.0)
	expect(player.health == 0.0, "Repeated lethal damage stops at zero health")
	space(true)
	player.position = Vector3(5, 0.55, 5)
	player.velocity = Vector3(4, 0, 2)
	remaining_before = player.slow_charge
	arena.equipment.spend(&"ring", 24)
	arena.equipment.begin_repair(&"ring")
	arena.equipment.complete_step(&"ring")
	arena.equipment.end_repair()
	player.reset_state()
	expect(arena.equipment.remaining(&"ring") == 16 and arena.equipment.stage(&"ring") == 2, "Player reset preserves other gear and repair progress")
	expect(player.position == Vector3(0, 0.55, 0) and player.velocity == Vector3.ZERO and player.health == Tuning.PLAYER.health, "Reset restores player position, velocity and health")
	expect(player.slow_charge == remaining_before and player.world_scale == 1.0 and not player._slow_held, "Player reset preserves charge and clears held slow")
	await ticks(player, 2, Vector3.RIGHT * 20)
	expect(player.world_scale == 1.0 and player.slow_charge == remaining_before, "Reset with Space held cannot reactivate slow or refill clock")
	space(false)
	await ticks(player, 1, Vector3.RIGHT * 20)
	space(true)
	await ticks(player, 1, Vector3.RIGHT * 20)
	expect(is_equal_approx(player.world_scale, Tuning.SLOW.scale), "Reset rearms only after a release and fresh press")

	Input.action_press("move_up")
	await ticks(player, 2, Vector3.RIGHT * 20)
	state.pause()
	expect(paused and scenes.has_popup(&"PauseMenu"), "Existing pause flow opens the partner popup")
	expect(player.world_scale == 1.0 and player.velocity == Vector3.ZERO and not player._slow_held, "GameState pause immediately clears slow and movement")
	charge_before = player.slow_charge
	await create_timer(0.05).timeout
	expect(is_equal_approx(player.slow_charge, charge_before), "Paused tree does not drain or regenerate charge")
	Input.action_release("move_up")
	state.resume()
	await process_frame
	await ticks(player, 2, Vector3.RIGHT * 20)
	expect(not paused and not scenes.has_popup(), "Existing resume closes pause popup")
	expect(player.world_scale == 1.0 and is_equal_approx(player.slow_charge, charge_before), "Resume while Space remains held does not activate or refill slow")
	expect(flat(player.velocity).is_zero_approx(), "Movement released inside a popup is not stuck after resume")
	space(false)
	await ticks(player, 1, Vector3.RIGHT * 20)
	space(true)
	await ticks(player, 1, Vector3.RIGHT * 20)
	expect(is_equal_approx(player.world_scale, Tuning.SLOW.scale), "Pause rearm requires observed release and fresh press")
	arena._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(paused and player.world_scale == 1.0 and not player._slow_held, "Focus-loss callback pauses and cancels active slow")
	charge_before = player.slow_charge
	state.resume()
	await process_frame
	await ticks(player, 1, Vector3.RIGHT * 20)
	expect(player.world_scale == 1.0 and is_equal_approx(player.slow_charge, charge_before), "Focus-loss/resume also blocks an unreleased Space hold")
	space(false)
	await ticks(player, 1, Vector3.RIGHT * 20)
	space(true)
	await ticks(player, 1, Vector3.RIGHT * 20)
	expect(is_equal_approx(player.world_scale, Tuning.SLOW.scale), "Fresh Space reactivates after focus-loss release")
	expect(player.status_text().contains("Slow") and player.status_text().contains("slowing"), "Status exposes charge and active slow")
	player.reset_input()
	expect(player.status_text().contains("release Space"), "Status explains the release/rearm requirement")
	expect(Engine.time_scale == 1.0, "Player never changes the global engine clock")
	space(false)
	release_actions()
	state.resume()
	arena.queue_free()
	await process_frame
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
