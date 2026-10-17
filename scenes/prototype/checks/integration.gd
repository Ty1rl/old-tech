extends SceneTree

const Tuning = preload("res://scenes/prototype/tuning.gd")
var failures: Array[String] = []
var checks: int = 0
var arena: Node3D


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func mouse(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event


func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func fresh_enemy(kind: StringName, location: Vector3 = Vector3(0, 0, -3)) -> Node3D:
	arena.reset_arena()
	arena.director.clear()
	return arena.director.spawn(kind, location)


func weapon_tick(delta: float, aim: Vector3) -> void:
	arena.weapons.step(delta, arena.player, aim, arena.director.enemies)


func draw_ring(start: Vector3, finish: Vector3) -> void:
	arena.weapons.select_tool(1)
	arena.weapons.handle_event(mouse(true), arena.player, start)
	arena.weapons.handle_event(mouse(false), arena.player, finish)


func repair_tool(tool: StringName) -> void:
	var session: int = arena.equipment.begin_repair(tool)
	for section in range(Tuning.REPAIR_STEPS):
		arena.equipment.complete_step(tool)
	arena.equipment.end_repair(session)


func run() -> void:
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)

	# Exercise real weapon and enemy implementations together, including armor.
	for kind in [&"target", &"swarmer", &"brute", &"skirmisher"]:
		for tool in [1, 2, 3]:
			var enemy := fresh_enemy(kind)
			arena.weapons.select_tool(tool)
			var attempts := 0
			if tool == 3:
				arena.weapons.handle_event(mouse(true), arena.player, enemy.position)
			while enemy.health > 0.0 and attempts < 2000:
				attempts += 1
				if tool == 1:
					draw_ring(Vector3(-2, 0, -3), Vector3(2, 0, -3))
					weapon_tick(2.0, enemy.position)
				elif tool == 2:
					arena.weapons.handle_event(mouse(true), arena.player, enemy.position)
					arena.weapons.handle_event(mouse(false), arena.player, enemy.position)
					weapon_tick(1.0, enemy.position)
					arena.weapons.handle_event(mouse(false), arena.player, enemy.position)
				else:
					if not arena.equipment.can_use(&"cone"):
						arena.weapons.handle_event(mouse(false), arena.player, enemy.position)
						repair_tool(&"cone")
						arena.weapons.handle_event(mouse(true), arena.player, enemy.position)
					weapon_tick(0.1, enemy.position)
			arena.weapons.handle_event(mouse(false), arena.player, enemy.position)
			expect(enemy.health <= 0.0, "Tool %d can kill real %s" % [tool, kind])
			arena.director.step(0.0, arena.player)
			expect(arena.director.enemies.is_empty(), "Killed %s leaves live roster after tool %d" % [kind, tool])

	var brute := fresh_enemy(&"brute", Vector3(0, 0, -6))
	draw_ring(Vector3(-2.5, 0, -7.1), Vector3(2.5, 0, -7.1))
	weapon_tick(0.6, Vector3.ZERO)
	expect(is_equal_approx(brute.health, Tuning.ENEMIES.brute.health - Tuning.RING.damage),
		"Real brute takes full rear ring damage while player stands in front")
	expect(not brute.last_hit_result.armored, "Ring contact, rather than player position, decides armor")

	brute = fresh_enemy(&"brute")
	arena.weapons.select_tool(2)
	arena.weapons.handle_event(mouse(true), arena.player, brute.position)
	arena.weapons.handle_event(mouse(false), arena.player, brute.position)
	weapon_tick(0.2, brute.position)
	expect(brute.last_hit_result.armored and is_equal_approx(brute.last_hit_result.dealt,
		Tuning.BEAM.min_damage * Tuning.ARMOR.front_multiplier), "Real frontal flash reports reduced actual damage")

	var cone_damage: Array[float] = []
	for rate in [30, 120]:
		brute = fresh_enemy(&"brute")
		arena.weapons.select_tool(3)
		arena.weapons.handle_event(mouse(true), arena.player, brute.position)
		for tick in range(rate):
			weapon_tick(1.0 / rate, brute.position)
		cone_damage.append(Tuning.ENEMIES.brute.health - brute.health)
	expect(absf(cone_damage[0] - cone_damage[1]) < 0.001,
		"Cone armor damage agrees at 30 and 120 simulation steps per second")
	expect(absf(cone_damage[0] - Tuning.CONE.damage_per_second * Tuning.ARMOR.front_multiplier) < 0.001,
		"Cone uses real seconds and same frontal armor rule")

	var target := fresh_enemy(&"target")
	draw_ring(Vector3(-2, 0, -3), Vector3(2, 0, -3))
	var state = root.get_node("GameState")
	state.pause()
	expect(arena.weapons.ring_phase == "outbound", "Pause cancels held input but preserves launched ring")
	state.resume()
	await process_frame
	arena.player.position.x = 4
	weapon_tick(2, target.position)
	expect(arena.weapons.ring_phase == "idle" and arena.weapons.ring_pos.x == 4,
		"Resumed ring returns to moved player")

	fresh_enemy(&"swarmer", Vector3(0, 0, -8))
	var swarmer: Node3D = arena.director.enemies[0]
	arena.player._step_slow(0.5, false)
	arena.player._step_slow(0.5, true)
	var start: Vector3 = swarmer.position
	arena.director.step(0.5 * arena.player.world_scale, arena.player)
	expect(is_equal_approx(swarmer.position.distance_to(start), Tuning.ENEMIES.swarmer.speed * 0.5 * Tuning.SLOW.scale),
		"Arena timing policy slows real enemy movement")
	expect(is_equal_approx(arena.player.slow_charge, arena.equipment.capacity(&"clock") - 0.5 * Tuning.SLOW.drain), "Slow resource drains in real time")

	arena.weapons.select_tool(3)
	arena.weapons.handle_event(mouse(true), arena.player, swarmer.position)
	arena._unhandled_input(key(KEY_R))
	expect(not arena.weapons.cone_active and arena.weapons.ring_phase == "idle" and arena.player.world_scale == 1,
		"Reset key clears active attacks and restores world time")
	expect(arena.director.enemies.size() == 1 and arena.director.enemies[0].kind == &"target", "Reset key restores target encounter")
	arena._unhandled_input(key(KEY_F5))
	expect(arena.director.enemies.size() == 5, "Mixed debug key adds four real enemies")
	arena._unhandled_input(key(KEY_BACKSPACE))
	expect(arena.director.enemies.is_empty(), "Clear key empties encounter")

	var pushed := fresh_enemy(&"swarmer", Vector3(0, 0, -2))
	arena.weapons.select_tool(3)
	arena.weapons.handle_event(mouse(true), arena.player, pushed.position)
	weapon_tick(0.05, pushed.position)
	expect(pushed.is_staggered() and pushed.knockback_vel.length() > 0,
		"Actual cone burst staggers and displaces actual swarmer")
	var before_push: Vector3 = pushed.position
	arena.director.step(0.1, arena.player)
	expect(pushed.position.z < before_push.z and arena.player.health == Tuning.PLAYER.health,
		"Burst buys space while suppressing contact attacks")

	arena._unhandled_input(key(KEY_F6))
	expect(arena.equipment.remaining(&"clock") == arena.equipment.capacity(&"clock") and arena.director.encounter_active,
		"Encounter key resets equipment and starts bounded sequence")
	expect(arena.slow_bar.max_value == arena.equipment.capacity(&"clock"), "HUD meter matches shared clock capacity")

	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
