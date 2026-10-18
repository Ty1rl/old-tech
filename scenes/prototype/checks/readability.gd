extends SceneTree

const AimAssist = preload("res://scenes/prototype/aim_assist.gd")
var arena: Node3D
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	arena._unhandled_input(event)


func mouse(down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	return event


func fresh(kind: StringName, point: Vector3 = Vector3(0, 0, -4)) -> Node3D:
	arena.reset_arena()
	arena.director.clear()
	return arena.director.spawn(kind, point)


func fire_at_screen(screen: Vector2) -> void:
	arena.weapons.select_tool(2)
	var aim: Vector3 = arena.floor_aim(screen)
	arena.weapons.handle_event(mouse(true), arena.player, aim)
	arena.weapons.handle_event(mouse(false), arena.player, aim)
	arena.weapons.step(.4, arena.player, aim, arena.director.enemies)


func run() -> void:
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	root.get_node("GameState").resume()
	arena.set_physics_process(false)
	expect(is_equal_approx(arena.player.camera.size, 22), "Default view is closer")
	key(KEY_EQUAL)
	expect(is_equal_approx(arena.player.camera.size, 20), "Plus zooms in")
	key(KEY_MINUS)
	expect(is_equal_approx(arena.player.camera.size, 22), "Minus zooms out")
	key(KEY_F9)
	expect(is_equal_approx(arena.player.camera.size, 18), "Showcase uses closer view")
	key(KEY_R)
	expect(is_equal_approx(arena.player.camera.size, 22), "Reset restores default view")

	for facing in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var enemy := fresh(&"yellow")
		enemy.facing = facing
		var core: MeshInstance3D = enemy.part_visual.core
		expect(core.visible and enemy.core_world_position().y > 1.6, "Core is raised and visible facing " + str(facing))
		fire_at_screen(arena.player.camera.unproject_position(enemy.core_world_position()))
		expect(enemy.health <= 0 and enemy.core_broken, "Clicking visible core kills from facing " + str(facing))

	for route in [&"ring", &"cone"]:
		var enemy := fresh(&"front_guard")
		var saved: Dictionary = enemy.capture_state()
		expect(enemy.part_visual.plate.visible and not enemy.part_visual.core.visible, "Closed guard shows plate and hides core")
		if route == &"ring":
			var points: Array = enemy.cable_world_points()
			var middle: Vector3 = (points[0] + points[-1]) * .5
			enemy.receive_attack(route, 36, middle, {"segment_start": middle - Vector3.RIGHT, "segment_end": middle + Vector3.RIGHT, "radius": .1})
		else:
			for tick in range(90): enemy.receive_attack(route, 16.0/60, enemy.position, {"dt": 1.0/60})
		expect(not enemy.part_visual.plate.visible and enemy.part_visual.core.visible, "Opening removes orange geometry entirely via " + String(route))
		enemy.restore_state(saved)
		expect(enemy.part_visual.plate.visible and not enemy.part_visual.core.visible, "Rewind restores plate/core visibility via " + String(route))

	var blue := fresh(&"blue")
	arena.weapons.select_tool(1)
	var points: Array = blue.cable_world_points()
	var middle: Vector3 = (points[0] + points[-1]) * .5
	var screen: Vector2 = arena.player.camera.unproject_position(middle)
	var mapped: Vector3 = arena.floor_aim(screen)
	expect(Vector2(mapped.x-middle.x, mapped.z-middle.z).length() < .01, "Click on raised blue cable maps to cable rather than floor behind it")
	arena.weapons.handle_event(mouse(true), arena.player, mapped - Vector3.FORWARD)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	arena.weapons.handle_event(motion, arena.player, mapped)
	arena.weapons.handle_event(mouse(false), arena.player, mapped + Vector3.FORWARD)
	arena.weapons.step(.8, arena.player, mapped, arena.director.enemies)
	expect(blue.health <= 0 and blue.cable_cut, "Stroke through projected blue cable cuts real enemy")

	var enemy := fresh(&"front_guard")
	screen = arena.player.camera.unproject_position(enemy.core_world_position())
	expect(AimAssist.target(screen, arena.player.camera, [enemy], 2, arena.player.position) == null, "Closed core receives no aim assistance")
	enemy = fresh(&"yellow", Vector3(0, 0, -50))
	enemy.position.z = -50 # Bypass the normal spawn clamp to test range rejection.
	screen = arena.player.camera.unproject_position(enemy.core_world_position())
	expect(AimAssist.target(screen, arena.player.camera, [enemy], 2, arena.player.position) == null, "Out-of-range part receives no assistance")
	enemy = fresh(&"yellow")
	screen = arena.player.camera.unproject_position(enemy.core_world_position())
	for tool in [3, 4]:
		expect(AimAssist.target(screen, arena.player.camera, [enemy], tool, arena.player.position) == null, "Cone and clock retain floor aim")
	enemy.health = 0
	expect(AimAssist.target(screen, arena.player.camera, [enemy], 2, arena.player.position) == null, "Dead parts receive no assistance")
	enemy = fresh(&"yellow", Vector3(-5, 0, -7.5))
	arena.player.position = Vector3(-5, .55, -1)
	fire_at_screen(arena.player.camera.unproject_position(enemy.core_world_position()))
	expect(enemy.health == enemy.max_health, "Aiming at raised core still respects intervening cover")
	arena.director.clear()
	arena.weapons.select_tool(1)
	screen = arena.player.camera.unproject_position(Vector3(4, 0, -2))
	expect(arena.floor_aim(screen).distance_to(Vector3(4, 0, -2)) < .01, "Empty floor keeps ordinary free aim")

	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	await create_timer(.1).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
